#!/bin/bash
sharedisk="/dev/sdb1"
sharedisk_mount_point="/oradata"

. /usr/local/keepalived/scripts/oracle_init.sh

resources_status() {
    ismount=$(df -h | grep $sharedisk | grep $sharedisk_mount_point | wc -l)
    if [ $ismount -eq 0 ];then
        exit 0
    else
        ostatus=$(check_instance_status | grep -Eio -e "\bOPEN\b" -e "\bMOUNTED\b" -e "\bSTARTED\b")
        if [ "$ostatus" == "OPEN" -o "$ostatus" == "MOUNTED" ];then
            runuser -l oracle -c "$ORACLE_HOME/bin/lsnrctl status" &>/dev/null
            if [ $? -eq 0 ];then
                exit 0
            else
                runuser -l oracle -c "$ORACLE_HOME/bin/lsnrctl start" &>/dev/null
                if [ $? -eq 0 ];then
                    exit 0
                else
                    exit 0
                fi
            fi
        else
            exit 0
        fi
    fi
    }
    resources_status
