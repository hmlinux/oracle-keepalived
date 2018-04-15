#!/bin/bash
# 
interface="eth1"
virtual_ipaddress="172.16.10.130","172.16.10.131"

sharedisk="/dev/sdb1"
sharedisk_mount_point="/oradata"

STATE=()
IFS=","
for i in $virtual_ipaddress
do
    ip=$(ip addr | awk -F"[/ ]+" '(/inet /) {print $3}' | grep -Eio "\b$i\b")
    if [ "$ip" != "" ];then
        STATE=(1)
    else
        STATE=(0)
    fi
    break
done

to_primary() {
    echo primary
    scp /usr/local/keepalived/scripts/monitor_primary_oracle.sh /usr/local/keepalived/scripts/monitor.sh
    echo
}

to_standby() {
    echo standby
    scp /usr/local/keepalived/scripts/monitor_standby_oracle.sh /usr/local/keepalived/scripts/monitor.sh
    echo
}

ismount=$(df -h | grep $sharedisk | grep $sharedisk_mount_point | wc -l)
if [ ${STATE[0]} -eq 0 -a $ismount -eq 0 ];then
    to_standby
else
    to_primary
fi
