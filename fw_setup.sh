#!/bin/sh
####### Nicht anpassen #########
isVersion12="0"
####### Anpassen, wenn notwendig #########
intZone="internal"
intNetwork="internal-network"
intInterface="internal-interface"
extInterface="external-interface"
internetInterface="internet"
############## Functions ######################
####################################################

echo "Skript zur Ersteinrichtung fuer SecurePoint UTM Version 11 & 12 | Version 0.11 by DerJusten"
# Get current directory and read conf.cfg
dir=$(cd `dirname $0` && pwd)
cfg=$dir"/conf.cfg"

if test -f "$cfg"; then
    echo "Lade Variablen von conf.cfg"
    source $dir/conf.cfg
    location=$cfgLoc
    organization=$cfgOrg
    organization_unit=$cfgOrgUnit
    email=$cfgEmail
    ServerAdminURL=$cfgServerUrl
else
    echo $cfg " wurde nicht gefunden"
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


while [ "$input" != "n" ] && [ "$input" != "y" ];do
    read -s -n 1 -p "Ist das Interface $interface ($interfaceIpAddress) das interene Interface(y/n)?"$'\n' input
done

##user confirmed
if [ "$input" = "y" ];then
    ##Create new config
    dtnow=$(date +"%m-%d-%Y_%T")
    echo "Erstelle neue Konfigurationsdatei autorules_$dtnow"
    spcli system config save name "autorules_$dtnow" 

    #### Abfrage Rules Script ####
    while [ "$inputRules" != "n" ] && [ "$inputRules" != "y" ];do
        read -s -n 1 -p "Sollen die Regeln angepasst werden? (y/n)"$'\n' inputRules
    done

    if [ "$inputRules" = "y" ];then
        if test -f "/tmp/rules.sh"; then
            chmod +x /tmp/rules.sh
            sh /tmp/rules.sh
        else
            echo "Script für die Regeln wurde nicht gefunden"
        fi
    fi

    #### Abfrage VPN Script ####
    while [ "$inputVPN" != "n" ] && [ "$inputVPN" != "y" ];do
        read -s -n 1 -p "Soll VPN eingerichtet werden? Es darf keine VPN bereits existieren! (y/n)"$'\n' inputVPN
    done

    if [ "$inputVPN" = "y" ];then
        if test -f "/tmp/vpn.sh"; then
            chmod +x /tmp/vpn.sh
            sh /tmp/vpn.sh 0
        else
            echo "Script für die Einrichtung von VPN wurde nicht gefunden"
        fi
    fi

    #### Abfrage VPN Script ####
    while [ "$inputProxy" != "n" ] && [ "$inputProxy" != "y" ];do
        read -s -n 1 -p "Soll der transparente Proxy eingerichtet werden? (y/n)"$'\n' inputProxy
    done

    if [ "$inputProxy" = "y" ];then
        if test -f "/tmp/vpn.sh"; then
            chmod +x /tmp/proxy.sh
            sh /tmp/proxy.sh 0
        else
            echo "Script für die Einrichtung des transparenten Proxys wurde nicht gefunden"
        fi
    fi

    ## Config Cloud Backup
    echo "Erstelle Config Cloud Backup"
    CloudPw=$(openssl rand -base64 24)
    spcli system cloudbackup set password "$CloudPw"
    spcli extc global set variable "GLOB_CLOUDBACKUP_TIME" value [ "00 00 * * *" ]

    if [ -z $ServerAdminURL ];then
        read -p "Administrativen Zugriff von folgender URL zulassen:"$'\n' ServerAdminURL
    fi

    if [ ! -z $ServerAdminURL ];then
        spcli extc value set application "spresolverd" variable [ "MANAGER_HOST_LIST" ] value [ "$ServerAdminURL" ]
    fi

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
    
    ## Autostart Konfig
    while [ "$inputAutostart" != "n" ] && [ "$inputAutostart" != "y" ];do
        read -s -n 1 -p "Soll die Konfiguration beim Neustart geladen werden? (y/n)"$'\n' inputAutostart
    done

    if [ "$inputAutostart" = "y" ];then
 	    spcli system config set name "autorules_$dtnow" 
    fi
    spcli system config save name "autorules_$dtnow" 
    spcli appmgmt restart application "named"
    spcli appmgmt restart application "openvpn"
    spcli appmgmt restart application "webfilter"
    spcli appmgmt restart application "http_proxy"
    spcli appmgmt restart application "ntpd"

else
    echo "Vorgang abgebrochen"
fi
