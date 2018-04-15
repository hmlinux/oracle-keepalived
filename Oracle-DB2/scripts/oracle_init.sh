#!/bin/bash
# Oracle database instance configuration and management command.
# Executed by keepalived_notify.sh

ORACLE_BASE="/u01/app/oracle"
ORACLE_HOME="/u01/app/oracle/product/11.2.0/db_1"
ORACLE_SID="HMODB"

control_files="/oradata/HMODB/control01.ctl","/u01/app/oracle/flash_recovery_area/HMODB/control02.ctl","/home/oracle
/rman/HMODB/control03.ctl"

check_instance_status() {
    su - oracle << EOF
    export ORACLE_SID=$ORACLE_SID
    $ORACLE_HOME/bin/sqlplus -S "/ as sysdba"
    SELECT STATUS FROM V\$INSTANCE;
    exit
EOF
}

startup_instance() {
    su - oracle << EOF
    export ORACLE_SID=$ORACLE_SID
    $ORACLE_HOME/bin/sqlplus -S "/ as sysdba"
    startup;
    exit
EOF
}

shutdown_instance() {
    su - oracle << EOF
    export ORACLE_SID=$ORACLE_SID
    $ORACLE_HOME/bin/sqlplus -S "/ as sysdba"
    shutdown immediate;
    exit
EOF
}

shutdown_abort() {
    su - oracle << EOF
    export ORACLE_SID=$ORACLE_SID
    $ORACLE_HOME/bin/sqlplus -S "/ as sysdba"
    shutdown abort;
    exit
EOF
}

startup_nomount() {
    su - oracle << EOF
    export ORACLE_SID=$ORACLE_SID
    $ORACLE_HOME/bin/sqlplus -S "/ as sysdba"
    startup nomount;
    exit
EOF
}

startup_mount() {
    su - oracle << EOF
    export ORACLE_SID=$ORACLE_SID
    $ORACLE_HOME/bin/sqlplus -S "/ as sysdba"
    startup mount;
    exit
EOF
}

mount_instance() {
    su - oracle << EOF
    export ORACLE_SID=$ORACLE_SID
    $ORACLE_HOME/bin/sqlplus -S "/ as sysdba"
    alter database mount;
    exit
EOF
}

open_instance() {
    su - oracle << EOF
    export ORACLE_SID=$ORACLE_SID
    $ORACLE_HOME/bin/sqlplus -S "/ as sysdba"
    alter database open;
    exit
EOF
}


