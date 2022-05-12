#!/bin/sh
aio_cfg=$dir"/aio.cfg"
if test -f "$aio_cfg"; then    
    source $aio_cfg
    ddns=$aio_ddns
fi
## Set DDNS
if [ "$ddns" = "y" ];then
    externalInterface="$(spcli interface get |grep external |awk 'BEGIN {FS = "|" }; {print $2}' | xargs)"
    externalFlagsArr="$(spcli interface get |grep external |awk 'BEGIN {FS = "|" }; {print $4}' | xargs)"
    externalFlags=""
    for i in ${externalFlagsArr//,/ }
    do
        if [ ! -z $i ];then
            externalFlags="$externalFlags\"$i\" "
        fi
    done
    ## Flags buggy :C
    spcli interface set name "$externalInterface" flags [ "$externalFlags"] options [ "dyndns_hostname=maxbenedikt-test.spdns.de" "dyndns_user=maxbenedikt-test.spdns.de" "dyndns_password=jafg-lumb-wyqv" "dyndns_server=update.spdyn.de" "dyndns_mx=" "dyndns_ipv4=1" "dyndns_ipv6=0" "dyndns_webresolver=http://checkip4.spdyn.de/" ]

fi



## Set DHCP


##Create Backup of current Config
echo "Erstelle Current Config"
ConfigName=$(spcli system config get |grep CURRENT |awk 'BEGIN {FS = "|" }; {print $1}' | xargs )
spcli system config export name "$ConfigName"  > "/tmp/fw-tool/"$ConfigName".utm"