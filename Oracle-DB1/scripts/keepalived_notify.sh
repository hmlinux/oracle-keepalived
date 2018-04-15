#!/bin/bash
# author: hm@huangming.org
# keepalived notify script

#bind vip interface
interface="eth1"

#keepalived virtual_ipaddress
virtual_ipaddress="172.16.10.130","172.16.10.131"

MASTER_HOSTNAME="hmdg-db1"    #DB1
BACKUP_HOSTNAME="hmdg-db2"    #DB2

LOGDIR="/usr/local/keepalived/log"
LOGFILE="$LOGDIR/keepalived_haswitch.log"
TMPLOG=/tmp/notify_.log

sharedisk="/dev/sdb1"
sharedisk_mount_point="/oradata"

# oracle_datadir="/oradata/path/HMODB"
oracle_datadir="/oradata"

# Source oracle database instance startup/shutdown script
. /usr/local/keepalived/scripts/oracle_init.sh

control_files="/$oracle_datadir/$ORACLE_SID/control01.ctl","/u01/app/oracle/flash_recovery_area/$ORACLE_SID/control02.ctl","/home/oracle/rman/$ORACLE_SID/control03.ctl"

RETVAL=0

OLD_IFS="$IFS"
IFS=","

[ -d $LOGDIR ] || mkdir $LOGDIR

controlfile_backpath="/backup/oracle/control"
controlfile_back=$controlfile_backpath/control_$(date '+%Y%d%m%H%M%S')
[ -d $controlfile_backpath ] || mkdir -p $controlfile_backpath && chown -R oracle:oinstall $controlfile_backpath

info_log() {
    printf "$(date '+%b  %d %T %a') $HOSTNAME [keepalived_notify]: $1"
}

control01_ctl=`printf ${control_files[0]}`

backup_controlfile() {
    su - oracle << EOF
    export ORACLE_SID=$ORACLE_SID
    $ORACLE_HOME/bin/sqlplus -S "/ as sysdba"
    alter database backup controlfile to '$controlfile_back';
    exit
EOF
}

#runuser -l oracle -c "export ORACLE_SID=$ORACLE_SID;rman target / cmdfile=/usr/scripts/ControlfileRestore.sql"
restore_controlfile() {
    su - oracle << EOF
    export ORACLE_SID=$ORACLE_SID
    $ORACLE_HOME/bin/rman target / nocatalog
    RESTORE CONTROLFILE FROM '$control01_ctl';
    exit
EOF
}

ssh_p=$(netstat -ntp | awk '/sshd/{print $4}' | awk -F':' '{print $2}' | head -1)
chk_remote_node_sharedisk() {
    if [ $(hostname) == $MASTER_HOSTNAME ];then
        if ping -c1 -w2 $BACKUP_HOSTNAME &>/dev/null;then
            runuser -l oracle -c "ssh -p$ssh_p $BACKUP_HOSTNAME 2>/dev/null df | grep $sharedisk | wc -l"
        fi
    fi
    if [ $(hostname) == $BACKUP_HOSTNAME ];then
        if ping -c1 -w2 $MASTER_HOSTNAME &>/dev/null;then
            runuser -l oracle -c "ssh -p$ssh_p $MASTER_HOSTNAME 2>/dev/null df | grep $sharedisk | wc -l"
        fi
    fi
}

master() {
    info_log "Database Switchover To MASTER\n"
    info_log "Check remote node sharedisk mounted.\n"
    i=1
    while (($i<=30))
    do
        chk_status=$(chk_remote_node_sharedisk)
        if [ $chk_status -ge 1 ];then
            info_log "$sharedisk is already mounted on remote node or busy. checking [$i]...\n"
        else
            info_log "$sharedisk check passed.\n"
            break
        fi
        if [ $i -eq 20 ];then
            info_log "Disk status abnormal.\n"
            exit 1
        fi
        sleep 1
        i=$(($i+1))
    done
    ismount=$(df -h | grep $sharedisk | grep $sharedisk_mount_point | wc -l)
    if [ $ismount -eq 0 ];then
        info_log "mount $sharedisk on $sharedisk_mount_point\n"
        mount $sharedisk $sharedisk_mount_point
        RETVAL=$?
        if [ $RETVAL -eq 0 ];then
            #shutdown_instance
            info_log "restore controlfile 1\n"
            startup_nomount
            restore_controlfile
        else
            info_log "Error: $sharedisk cannot mount or $sharedisk_mount_point busy\n"
            exit $RETVAL
        fi
    else
        disk=$(df -h | grep $sharedisk_mount_point | awk '{print $1}')
        if [ $disk == $sharedisk ];then
            info_log "mount: $sharedisk is already mounted on $sharedisk_mount_point\n"
        else
            info_log "Warning: $sharedisk already mounted on $disk\n"
        fi
    fi

    status=$(check_instance_status | grep -Eio -e "\bOPEN\b" -e "\bMOUNTED\b" -e "\bSTARTED\b")
    if [ "$status" == "OPEN" ];then
        info_log "a database already open by the instance.\n"
    elif [ "$status" == "MOUNTED" ];then
        info_log "re-open database instance\n"
        open_instance | tee $TMPLOG
        opened=$(cat $TMPLOG | grep -Eio "\bDatabase altered\b")
        if [ "$opened" != "Database altered" ];then
            info_log "Error: database instance open fail!\n"
            exit 2
        fi
    elif [ "$status" == "STARTED" ];then
        info_log "alter database to mount\n"
        mount_instance | tee $TMPLOG
        mounted=$(cat $TMPLOG | grep -Eio "\bDatabase altered\b")
        if [ "$mounted" == "Database altered" ];then
            info_log "alter database to open\n"
            open_instance | tee $TMPLOG
            opened=$(cat $TMPLOG | grep -Eio "\bDatabase altered\b")
            if [ "$opened" == "Database altered" ];then
                info_log "Database opened.\n"
            else
                info_log "Database open failed\n"
                exit 4
            fi
        else
            info_log "Database mount failed\n"
            exit 3
        fi
    else
        info_log "Startup database and open instance\n"
        shutdown_instance &>/dev/null
        startup_instance | tee $TMPLOG
        started=$(cat $TMPLOG | grep -Eio "\bDatabase opened\b")
        if [ "$started" != "Database opened" ];then
            info_log "Database instance open fail.\n"
            info_log "restore controlfile 2\n"
            shutdown_instance | tee $TMPLOG
            startup_nomount | tee $TMPLOG
            restore_controlfile
            shutdown_instance | tee $TMPLOG
            startup_instance | tee $TMPLOG
            started=$(cat $TMPLOG | grep -Eio "\bDatabase opened\b")
            if [ "$started" != "Database opened" ];then
                info_log "Database restore fail!\n"
                exit 5
            else
                info_log "Database opened.\n"
            fi
        else
            info_log "Database opened.\n"
        fi
    fi

    info_log "Startup listener\n"
    runuser -l oracle -c "lsnrctl status &>/dev/null"
    if [ $? -eq 0 ];then
        info_log "listener already started.\n"
    else
        info_log "starting listener...\n"
        runuser -l oracle -c "lsnrctl start &>/dev/null"
        if [ $? -eq 0 ];then
            info_log "The listener startup successfully\n"
        else
            info_log "Listener start failure!\n"
        fi
    fi
    echo
}

backup() {
    info_log "Database Switchover To BACKUP\n"
    ismount=$(df -h | grep $sharedisk | grep $sharedisk_mount_point | wc -l)
    if [ $ismount -ge 1 ];then
        disk=$(df -h | grep $sharedisk_mount_point | awk '{print $1}')
        if [ $disk == $sharedisk ];then
            status=$(check_instance_status | grep -Eio -e "\bOPEN\b" -e "\bMOUNTED\b" -e "\bSTARTED\b")
            if [ "$status" == "OPEN" -o "$status" == "MOUNTED" ];then
                info_log "Database instance state is mounted\n"
                info_log "Backup current controlfile.\n"
                echo -e "\nSQL> alter database backup controlfile to '$controlfile_back';\n"
                backup_controlfile
                info_log "Shutdown database instance, please wait...\n"
                shutdown_instance | tee $TMPLOG
                shuted=$(cat $TMPLOG | grep -Eio "\binstance shut down\b")
                if [ "$shuted" == "instance shut down" ];then
                    info_log "Database instance shutdown successfully.\n"
                else
                    info_log "Database instance shutdown failed.\n"
                    info_log "shutdown abort.\n"
                    shutdown_abort
                fi
            elif [ "$status" == "STARTED" ];then
                info_log "Database instance state is STARTED\n"
                info_log "Shutdown database instance, please wait...\n"
                shutdown_instance | tee $TMPLOG
                shuted=$(cat $TMPLOG | grep -Eio "\binstance shut down\b")
                if [ "$shuted" == "instance shut down" ];then
                    info_log "Database instance shutdown successfully.\n"
                else
                    info_log "Database instance shutdown failed.\n"
                    info_log "shutdown abort.\n"
                    shutdown_abort
                fi
            else
                shutdown_instance | tee $TMPLOG
                info_log "Database instance not available.\n"
            fi
    
            echo
            info_log "umount sharedisk\n"
            echo
            umount $sharedisk_mount_point && RETVAL=$?
            if [ $RETVAL -eq 0 ];then
                info_log "umount $sharedisk_mount_point success.\n"
            else
                info_log "umount $sharedisk_mount_point fail!\n"
            fi
        else
            info_log "$sharedisk is not mount on $sharedisk_mount_point or busy.\n"
        fi
    else
        info_log "$sharedisk_mount_point is no mount\n"
    fi

    info_log "stopping listener...\n"
    runuser -l oracle -c "lsnrctl status" &>/dev/null
    RETVAL=$?
    if [ $RETVAL -eq 0 ];then
        runuser -l oracle -c "lsnrctl stop" &>/dev/null
        RETVAL=$?
        if [ $RETVAL -eq 0 ];then
            info_log "The listener stop successfully\n"
        else
            info_log "Listener stop failure!\n"
       fi
    else
        info_log "listener is not started.\n"
    fi
    echo
}

notify_master() {
    echo -e "\n-------------------------------------------------------------------------------" 
    echo "`date '+%b  %d %T %a'` $(hostname) [keepalived_notify]: Transition to $1 STATE";
    echo "`date '+%b  %d %T %a'` $(hostname) [keepalived_notify]: Setup the VIP on $interface $virtual_ipaddress";
}

notify_backup() {
    echo -e "\n-------------------------------------------------------------------------------" 
    echo "`date '+%b  %d %T %a'` $HOSTNAME [keepalived_notify]: Transition to $1 STATE";
    echo "`date '+%b  %d %T %a'` $HOSTNAME [keepalived_notify]: removing the VIP on $interface for $virtual_ipaddress";
}

case $1 in
        master)
                notify_master MASTER | tee -a $LOGFILE
                master | tee -a $LOGFILE
        ;;
        backup)
                notify_backup BACKUP | tee -a $LOGFILE
                backup | tee -a $LOGFILE
        ;;
        fault)
                notify_backup FAULT | tee -a $LOGFILE
	        backup | tee -a $LOGFILE
        ;;
        stop)
                notify_backup STOP | tee -a $LOGFILE
                /etc/init.d/keepalived start
                #sleep 6 && backup | tee -a $LOGFILE
        ;;
        *)
                echo "Usage: `basename $0` {master|backup|fault|stop}"
                RETVAL=1
        ;;
esac
exit $RETVAL
