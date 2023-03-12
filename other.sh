#!/bin/sh
vpn_log="/tmp/fw-tool/access.txt"
credCsv="/tmp/fw-tool/access.csv"
dir="/tmp/fw-tool"
###################################################

aio_cfg=$dir"/aio.cfg"
if test -f "$aio_cfg"; then    
    source $aio_cfg
    ddns=$aio_ddns
    ddnsHost=$aio_ddnsHost
    ddnsToken=$aio_ddnsToken
fi

## Set DDNS
if [ "$ddns" = "y" ];then
    echo "Set DynDNS"
    externalInterface="$(spcli interface get |grep external |awk 'BEGIN {FS = "|" }; {print $2}' | xargs)"
    externalFlagsArr="$(spcli interface get |grep external |awk 'BEGIN {FS = "|" }; {print $4}' | xargs)"
    externalFlags=""
    externalFlagOptionsArr="$(spcli interface get |grep external |awk 'BEGIN {FS = "|" }; {print $7}' | xargs)"
    externalOptions=""
    #[ "dyndns_hostname=" "dyndns_user=" "dyndns_password=*******" "dyndns_server=update.spdyn.de" "dyndns_mx=" "dyndns_ipv4=" "dyndns_ipv6=" "dyndns_webresolver=" 
    #"mtu=1500" "autonegotiation=on" 
    ## Necessary Options
    optDynDnsHost="\"dyndns_hostname=$ddnsHost\""
    optDynDnsUser="\"dyndns_user=$ddnsHost\""
    optDynDnsPw="\"dyndns_password=$ddnsToken\""
    optDynDnsServer="\"dyndns_server=update.spdyn.de\""
    optDynDnsMx="\"dyndns_mx=\""
    optDynDnsIpv4="\"dyndns_ipv4=1\""
    optDynDnsIpv6="\"dyndns_ipv6=0\""
    optDynDnsWebresolver="\"dyndns_webresolver=http://checkip4.spdyn.de/\""
    optMtu="\"mtu=1500\""
    optAutonegotiation="\"autonegotiation=on\""
    optSpeed="\"speed=\""
    optDuplex="\"duplex=\""
    optFallback_dev="\"fallback_dev=\""
    optPingCheckHost="\"ping_check_host=\""
    optPingCheckInt="\"ping_check_interval=\""
    optPingCheckThres="\"ping_check_threshold=\""
    optRouteHint="\"route_hint=\"" 

    if [ -z $externalFlagsArr ];then
        externalFlags="$externalFlags\"DYNDNS\" "
    else
        for i in ${externalFlagsArr//,/ }
        do
            if [ ! -z $i ];then
            dyndnsAlreadyEnabled="false"
                case $i in
                    "DYNDNS"*) dyndnsAlreadyEnabled="true"  ;;
                    *)  externalFlags="$externalFlags\"$i\" " ;;
                esac
                externalFlags="$externalFlags\"DYNDNS\" "
            fi
            if [ "$dyndnsAlreadyEnabled" = "true" ];then
                echo  "DynDNS Already exists"
            #    exit
            fi
        done
    fi
    ##Split options
    for i in ${externalFlagOptionsArr//,/ }
    do
        if [ ! -z $i ];then
            case $i in
            "mtu="*) optMtu="\"$i\""  ;;
            "autonegotiation="*) optAutonegotiation="\"$i\""  ;;
            "speed="*) optSpeed="\"$i\""  ;;
            "duplex="*) optDuplex="\"$i\""  ;;
            "fallback_dev="*) optFallback_dev="\"$i\""  ;;
            "ping_check_host="*) optPingCheckHost="\"$i\""  ;;
            "ping_check_interval="*) optPingCheckInt="\"$i\""  ;;
            "ping_check_threshold="*) optPingCheckThres="\"$i\""  ;;
            "route_hint="*) optRouteHint="\"$i\""  ;;
            #*)    externalOptions="$externalOptions\"$i\" " ;;
            esac
        fi  
    done
    externalOptions="$optDynDnsHost $optDynDnsUser $optDynDnsPw $optDynDnsServer $optDynDnsMx $optDynDnsIpv4 $optDynDnsIpv6 $optDynDnsWebresolver $optMtu $optAutonegotiation $optSpeed $optDuplex $optFallback_dev $optPingCheckHost $optPingCheckInt $optPingCheckThres $optRouteHint"
    interfaceCmd="spcli interface set name "$externalInterface" flags [ $externalFlags] options [ $externalOptions ]"
    eval $interfaceCmd
    spcli appmgmt restart application "named"
fi

##Create rootUser
rootExists=$(spcli user get name "root" | grep "root")
if [ -z $rootExists ];then
    echo "Erstelle root User"
    root_pw=$(openssl rand -base64 24)
    root_pw=$root_pw"$"       
    spcli user new name "root" password "$root_pw" groups [ "administrator" ] > /dev/null
    echo "# Name:"$'\t'"root"$'\t'"Passwort:"$'\t' $root_pw>> $vpn_log
    echo "root;"$root_pw";" >> $credCsv
else
    echo "Benutzer root existiert bereits"
fi

## Set DHCP
## 

##Create Backup of current Config
echo "Erstelle Current Config"
ConfigName=$(spcli system config get |grep CURRENT |awk 'BEGIN {FS = "|" }; {print $1}' | xargs )
spcli system config export name "$ConfigName"  > "/tmp/fw-tool/"$ConfigName".utm"