#!/bin/sh
####### Nicht anpassen #########
isVersion12="0"
vpn_log="/tmp/fw-tool/access.txt"
script_version="1.1 [31.03.2022]"
####### Anpassen, wenn notwendig #########
intZone="internal"
intNetwork="internal-network"
intInterface="internal-interface"
extInterface="external-interface"
internetInterface="internet"
dnsServer1="9.9.9.9"
dnsServer2="149.112.112.112"
################################################################
echo "Skript zur Ersteinrichtung fuer SecurePoint UTM Version 11 & 12 | Version "$script_version" by DerJusten"
# Get current directory and read conf.cfg
dir=$(cd `dirname $0` && pwd)
cfg=$dir"/conf.cfg"

if test -f "$cfg"; then    
    source $dir/conf.cfg
    location=$cfgLoc
    organization=$cfgOrg
    organization_unit=$cfgOrgUnit
    email=$cfgEmail
    ServerAdminURL01=$cfgServerUrl01
    ServerAdminURL02=$cfgServerUrl02
    intZone=$cfgIntZone
    intNetwork=$cfgIntNetwork
    intInterface=$cfgIntInterface
    extInterface=$cfgExtInterface
    internetInterface=$cfgInternetInterface
else
    echo $cfg " wurde nicht gefunden"
fi

aio_cfg=$dir"/aio.cfg"
if test -f "$aio_cfg"; then    
    source $aio_cfg
    useAio="y"
    inputInterface=$aio_interface
    inputRules=$aio_inputRules
    inputVPN=$aio_inputVPN
    inputProxy=$aio_inputProxy
    inputDS=$aio_inputDS
    inputReboot=$aio_inputReboot 
    backup_conf=$aio_backup
fi

version=$(spcli system info | awk 'BEGIN {FS = "|" }; {print $1 "\t" $2}' | grep -w version |cut -f2 -d$'\t' | cut -f1 -d ' ')
if case $version in "11"*) true;; *) false;; esac; then
    echo "Version 11 wurde ermittelt"
    interface=$(spcli interface get | awk 'BEGIN {FS = "|" }; {print $1 "\t" $5 "\t" $2}' |grep $intZone |cut -f1 -d$'\t')
else
    echo "Version 12 wurde ermittelt"
    interface=$(spcli interface get | awk 'BEGIN {FS = "|" }; {print $1 "\t" $6 "\t" $2}' |grep $intZone |cut -f3 -d$'\t')
    isVersion12="1"
fi

info=$(spcli interface address get | awk 'BEGIN {FS = "|" };  {print $1 "\t" $3 "\t" $4}' | grep $interface)
interfaceID=$(echo $info | cut -f1 -d$' ')
interfaceIpAddress=$(echo $info | cut -f3 -d$' ')

if [ -z $interfaceID ]; then
    echo "Es konnte die interne IP-Adresse nicht ermittelt werden. Bitte überprüfen Sie ob die Zonennamen von der Firewall mit dem Skript übereinstimmen."
    exit 1
fi


while [ "$inputInterface" != "n" ] && [ "$inputInterface" != "y" ];do
    read -s -n 1 -p "Ist das Interface $interface ($interfaceIpAddress) das interene Interface(y/n)?"$'\n' inputInterface
done

##user confirmed
if [ "$inputInterface" = "y" ];then

    if [ "$backup_conf" = "y" ];then
        ConfigName=$(spcli system config get |grep CURRENT |awk 'BEGIN {FS = "|" }; {print $1}' | xargs )
        spcli system config export name "$ConfigName"  > "/tmp/fw-tool/"$ConfigName".utm"
    fi
    ##Create new config
    dtnow=$(date +"%m-%d-%Y_%H-%M-%S")
    echo "Erstelle neue Konfigurationsdatei autorules_$dtnow"
    spcli system config save name "autorules_$dtnow" 

    #### Abfrage Rules Script ####
    while [ "$inputRules" != "n" ] && [ "$inputRules" != "y" ];do
        read -s -n 1 -p "Sollen die Regeln angepasst werden? (y/n)"$'\n' inputRules
    done

    if [ "$inputRules" = "y" ];then
        if test -f "/tmp/fw-tool/rules.sh"; then
            chmod +x /tmp/fw-tool/rules.sh
            sh /tmp/fw-tool/rules.sh 0
        else
            echo "Script für die Regeln wurde nicht gefunden"
        fi
    fi
    ##################################################################################
    #### Abfrage VPN Script ####
    while [ "$inputVPN" != "n" ] && [ "$inputVPN" != "y" ];do
        read -s -n 1 -p "Soll VPN eingerichtet werden? Es darf keine VPN bereits existieren! (y/n)"$'\n' inputVPN
    done

    if [ "$inputVPN" = "y" ];then
        if test -f "/tmp/fw-tool/vpn.sh"; then
            chmod +x /tmp/fw-tool/vpn.sh
            sh /tmp/fw-tool/vpn.sh 0
        else
            echo "Script für die Einrichtung von VPN wurde nicht gefunden"
        fi
    fi
    ##################################################################################
    #### Abfrage VPN Script ####
    while [ "$inputProxy" != "n" ] && [ "$inputProxy" != "y" ];do
        read -s -n 1 -p "Soll der transparente Proxy eingerichtet werden? (y/n)"$'\n' inputProxy
    done

    if [ "$inputProxy" = "y" ];then
        if test -f "/tmp/fw-tool/vpn.sh"; then
            chmod +x /tmp/fw-tool/proxy.sh
            sh /tmp/fw-tool/proxy.sh 0
        else
            echo "Script für die Einrichtung des transparenten Proxys wurde nicht gefunden"
        fi
    fi
    ##################################################################################
    ## Config Cloud Backup
    echo "Erstelle Config Cloud Backup"
    CloudPw=$(openssl rand -base64 12)
    spcli system cloudbackup set password "$CloudPw"
    spcli extc global set variable "GLOB_CLOUDBACKUP_TIME" value [ "00 00 * * *" ]
    echo "# Konfig Cloud Backup PW:"$'\t'$'\t' $CloudPw$ >> $vpn_log

    if [ -z $ServerAdminURL01 ];then
        read -p "Administrativen Zugriff von folgender URL zulassen:"$'\n' ServerAdminURL01
    fi

    if [ ! -z $ServerAdminURL02 ];then
        spcli extc value set application "spresolverd" variable [ "MANAGER_HOST_LIST" ] value [ "$ServerAdminURL01" "$ServerAdminURL02" ]
    elif [ ! -z $ServerAdminURL01 ];then
        spcli extc value set application "spresolverd" variable [ "MANAGER_HOST_LIST" ] value [ "$ServerAdminURL01" ]
    fi


    while [ "$inputDS" != "n" ] && [ "$inputDS" != "y" ];do
        read -s -n 1 -p "Sollen die Logs anonymisiert werden(y/n)?"$'\n' inputDS
    done

    if [ "$inputDS" = "y" ];then
        ##Datenschutz Anonymisierung aktivieren
        spcli extc value set application "syslog" variable "ANONYMIZELOGS_SMTP" value [ "1" ]
        spcli extc value set application "syslog" variable "ANONYMIZELOGS_OPEN_VPN" value [ "1" ]
        spcli extc value set application "spibfd" variable "ANONYMIZELOGS" value [ "1" ]
        spcli extc value set application "syslog" variable "ANONYMIZELOGS_IPSEC" value [ "1" ]
        spcli extc value set application "syslog" variable "ANONYMIZELOGS_DHCP" value [ "1" ]
        spcli extc value set application "syslog" variable "ANONYMIZELOGS_ULOG" value [ "1" ]
        spcli extc value set application "wap" variable "ANONYMIZELOGS" value [ "1" ]
        spcli extc value set application "sshd" variable "ANONYMIZELOGS" value [ "1" ]
        spcli extc value set application "squid-reverse" variable "ANONYMIZELOGS" value [ "1" ]
        spcli extc value set application "spf2bd" variable "ANONYMIZELOGS" value [ "1" ]
        spcli extc value set application "spcgi" variable "ANONYMIZELOGS" value [ "1" ]
        spcli extc value set application "smtpd" variable "ANONYMIZELOGS" value [ "1" ]
        spcli extc value set application "securepoint_firewall" variable "ANONYMIZELOGS" value [ "1" ]
        spcli extc value set application "openvpn" variable "ANONYMIZELOGS" value [ "1" ]
        spcli extc value set application "mailfilter" variable "ANONYMIZELOGS" value [ "1" ]
        spcli extc value set application "l2tpd" variable "ANONYMIZELOGS" value [ "1" ]
        spcli extc value set application "ipsec" variable "ANONYMIZELOGS" value [ "1" ]
        spcli extc value set application "http_proxy" variable "ANONYMIZELOGS" value [ "1" ]
        spcli extc value set application "cvpn" variable "ANONYMIZELOGS" value [ "1" ]
    fi
    ## Add DNS Server
    echo "Setze DNS Server"
    spcli extc global set variable "GLOB_NAMESERVER" value [ "$dnsServer1" "$dnsServer2" ]
    

    ## Autostart Konfig
    #while [ "$inputAutostart" != "n" ] && [ "$inputAutostart" != "y" ];do
    #    read -s -n 1 -p "Soll die Konfiguration beim Neustart geladen werden? (y/n)"$'\n' inputAutostart
    #done

    ##Move Testgroup to end of Rules
    testGroup=$(spcli rule group get | awk 'BEGIN {FS = "|" }; {print $3}' | grep "Test")
    if [ ! -z $testGroup ];then
        ruleID=$(spcli rule group get | awk 'BEGIN {FS = "|" }; {print $2}' | sort -nrk1,1 |head -n 1)
        spcli rule group move name "Test" pos "$ruleID"
    fi 

    echo "Konfiguration wird beim Neustart geladen"
 	spcli system config set name "autorules_$dtnow" 

    if [ "$useAio" = "y" ];then
        chmod +x /tmp/fw-tool/other.sh
        sh /tmp/fw-tool/other.sh
    fi

    echo "Starte Dienste neu"
    spcli system config save name "autorules_$dtnow" 
    spcli appmgmt restart application "named"
    spcli appmgmt restart application "openvpn"
    spcli appmgmt restart application "webfilter"
    spcli appmgmt restart application "http_proxy"
    spcli appmgmt restart application "ntpd"
    echo "####################################" >> $vpn_log
    echo "########### Zugaenge ################"
    cat $vpn_log

    ## Exit scripts when using AIO / reboot wird per Tool ausgeführt
    if [ "$useAio" = "y" ];then
        exit
    fi

    while [ "$inputReboot" != "n" ] && [ "$inputReboot" != "y" ];do
        read -s -n 1 -p "Die Firewall muss neugestartet werden. Soll dies nun durchgeführt werden?(y/n)"$'\n' inputReboot
    done
    if [ "$inputReboot" = "y" ];then
        reboot
    fi

else
    echo "Vorgang abgebrochen"
fi
