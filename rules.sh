#!/bin/sh
####### Nicht anpassen #########
isVersion12="0"
createConfigBackup=$1
####### Anpassen, wenn notwendig #########
intZone="internal"
intNetwork="internal-network"
intInterface="internal-interface"
extInterface="external-interface"
internetInterface="internet"
############## Functions ######################
####################################################

# Get current directory and read conf.cfg
dir=$(cd `dirname $0` && pwd)
cfg=$dir"/conf.cfg"

if test -f "$cfg"; then
    
    source $dir/conf.cfg
    location=$cfgLoc
    organization=$cfgOrg
    organization_unit=$cfgOrgUnit
    email=$cfgEmail
    ServerAdminURL=$cfgServerUrl
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
    inputDelRules =$aio_inputDelRules 
    inputTerraCloud=$aio_inputTerraCloud
    inputWhatsapp=$aio_inputWhatsapp
    input_konnektor=$aio_input_konnektor
    input_TK=$aio_input_TK
fi

version=$(spcli system info | awk 'BEGIN {FS = "|" }; {print $1 "\t" $2}' | grep -w version |cut -f2 -d$'\t' | cut -f1 -d ' ')
if case $version in "11"*) true;; *) false;; esac; then
    interface=$(spcli interface get | awk 'BEGIN {FS = "|" }; {print $1 "\t" $5 "\t" $2}' |grep $intZone |cut -f1 -d$'\t')
else
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

    ##Create new config
    if [ -z $createConfigBackup ] || [ $createConfigBackup == 1 ];then
        dtnow=$(date +"%m-%d-%Y_%T")
        echo "Erstelle neue Konfigurationsdatei autorules_$dtnow"
        spcli system config save name "autorules_$dtnow"  
    fi

    ## Delete default rules
    ## Abfrage
    while [ "$inputDelRules" != "n" ] && [ "$inputDelRules" != "y" ];do
        read -s -n 1 -p "Sollen die 'Default rules' gelöscht werden? (y/n)"$'\n' inputDelRules
    done

    if [ "$inputDelRules" = "y" ];then
        id_rule1=$(spcli rule group get | awk 'BEGIN {FS = "|" }; {print $2 "\t" $3}' | grep -w "internal-network ~auto-generated~" |cut -f1 -d$'\t')
        if [ ! -z $id_rule1 ];then
            spcli rule group delete id "$id_rule1"
        fi

        id_rule2=$(spcli rule group get | awk 'BEGIN {FS = "|" }; {print $2 "\t" $3}' | grep -w "dmz1-network ~auto-generated~" |cut -f1 -d$'\t')
        if [ ! -z $id_rule2 ];then
            spcli rule group delete id "$id_rule2"
        fi

        id_rule3=$(spcli rule group get | awk 'BEGIN {FS = "|" }; {print $2 "\t" $3}' | grep -w "default" |cut -f1 -d$'\t')
        if [ ! -z $id_rule3 ];then
            spcli rule group delete id "$id_rule3"
        fi
    fi

    ## Disable any rules from internal network to internet
    echo "Deaktiviere alle ANY Regeln von '$intNetwork' nach '$internetInterface'"
    id=$(spcli rule get | awk 'BEGIN {FS = "|" };  {print $3 "\t" $4 "\t" $5 "\t" $6 "\t" $9}' | grep any| grep ACCEPT | grep -v DISABLED | grep $intNetwork | grep $internetInterface |cut -f1 -d$'\t') 
    while [ ! -z $id ];do
       spcli rule set id "$id" flags [ "ACCEPT" "LOG" "HIDENAT" "DISABLED" ] > /dev/null 2>&1
       id=$(spcli rule get | awk 'BEGIN {FS = "|" };  {print $3 "\t" $4 "\t" $5 "\t" $6 "\t" $9}' | grep any| grep ACCEPT | grep -v DISABLED |grep $intNetwork | grep $internetInterface |cut -f1 -d$'\t')
    done
    echo "Erstelle interne Regeln (Internet, NTP, E-Mails und TeamViewer)"
    
    spcli rule group new name "Interne Regeln" > /dev/null
    ##Default Internet
    spcli rule new group "Interne Regeln" src "$intNetwork" dst "$internetInterface" service "default-internet" comment "" flags [ "LOG" "HIDENAT" "ACCEPT" ] nat_node "$extInterface" > /dev/null 2>&1
    ##NTP
    spcli rule new group "Interne Regeln" src "$intNetwork" dst "$internetInterface" service "network-time" comment "" flags [ "LOG" "HIDENAT" "ACCEPT" ] nat_node "$extInterface" > /dev/null 2>&1
    ##Create Group Mails
    spcli service group new name "dgrp_mails"
    ## 993
    spcli service group add name "dgrp_mails" services "imap-ssl" 
    ## 25
    spcli service group add name "dgrp_mails" services "smtp"
    ## 465
    spcli service group add name "dgrp_mails" services "smtps"
    ## 587
    spcli service group add name "dgrp_mails" services "submission"
    ## 143
    spcli service group add name "dgrp_mails" services "imap"
    ## 110
    spcli service group add name "dgrp_mails" services "pop3"
    ## 995
    spcli service group add name "dgrp_mails" services "pop3s"
    ## Add Mailgroup
    spcli rule new group "Interne Regeln" src "$intNetwork" dst "$internetInterface" service "dgrp_mails" comment "" flags [ "LOG" "HIDENAT" "ACCEPT" ] nat_node "$extInterface" > /dev/null 2>&1

 
    ##Create Group Teamviewer
    spcli service group new name "dgrp_teamviewer"
    ## Add teamviewer ports TCP + UDP
    spcli service group add name "dgrp_teamviewer" services "teamviewer_tcp"
    spcli service group add name "dgrp_teamviewer" services "teamviewer_udp"
    ## Add TeamviewerGroup to rules
    spcli rule new group "Interne Regeln" src "$intNetwork" dst "$internetInterface" service "dgrp_teamviewer" comment "" flags [ "LOG" "HIDENAT" "ACCEPT" ] nat_node "$extInterface" > /dev/null 2>&1
    
    ## Create TerraCloud Backup ports
    spcli service new name "TerraCloud 8086" proto "tcp" ct_helper "" dst-ports [ "8086" ] src-ports [ ]
    spcli service new name "TerraCloud 8087" proto "tcp" ct_helper "" dst-ports [ "8087" ] src-ports [ ]
    spcli service new name "TerraCloud 2546" proto "tcp" ct_helper "" dst-ports [ "2546" ] src-ports [ ]

    ## Create TerraCloud Group
    spcli service group new name "dgrp_terracloud"
    spcli service group add name "dgrp_terracloud" services "TerraCloud 8086"
    spcli service group add name "dgrp_terracloud" services "TerraCloud 8087"
    spcli service group add name "dgrp_terracloud" services "TerraCloud 2546"

    ## Create Whatsapp Group
    spcli service group new name "dgrp_whatsapp"
    spcli service group add name "dgrp_whatsapp" services "xmpp"
    spcli service group add name "dgrp_whatsapp" services "xmpp-ssl"

    ## Add DNS Rule
    spcli rule new group "Interne Regeln" src "$intNetwork" dst "$intInterface" service "dns" comment "" flags [ "LOG" "ACCEPT" ] > /dev/null

    ## TerraCloud Abfrage
    while [ "$inputTerraCloud" != "n" ] && [ "$inputTerraCloud" != "y" ];do
        read -s -n 1 -p "Wird Terra Cloud Backup verwendet? (y/n)"$'\n' inputTerraCloud
    done
    if [ "$inputTerraCloud" = "y" ];then
        spcli rule new group "Interne Regeln" src "$intNetwork" dst "$internetInterface" service "dgrp_terracloud" comment "" flags [ "LOG" "HIDENAT" "ACCEPT" ] nat_node "$extInterface" > /dev/null 2>&1
    fi

    ## Whatsapp Abfrage
    while [ "$inputWhatsapp" != "n" ] && [ "$inputWhatsapp" != "y" ];do
        read -s -n 1 -p "Soll WhatsApp freigegeben werden? (y/n)"$'\n' inputWhatsapp
    done
    if [ "$inputWhatsapp" = "y" ];then
        spcli rule new group "Interne Regeln" src "$intNetwork" dst "$internetInterface" service "dgrp_whatsapp" comment "" flags [ "LOG" "HIDENAT" "ACCEPT" ] nat_node "$extInterface" > /dev/null 2>&1
    fi

    ## Konnektor
    while [ "$input_konnektor" != "n" ] && [ "$input_konnektor" != "y" ];do
        read -n 1 -s -p "Ist ein Konnektor vorhanden? (y/n):"$'\n' input_konnektor
    done 

    if [ "$input_konnektor" = "y" ];then
        read -p "IP-Adresse:" konnektorIpAddress
        ip route get "$konnektorIpAddress" > /dev/null 2>&1

        while [ $? != "0" ] || [ -z "$konnektorIpAddress" ];do
            read -p"Konnektor IP ungueltig, wiederholen Sie ihre Eingabe:"$'\n' konnektorIpAddress
            ip route get "$konnektorIpAddress" > /dev/null 2>&1
        done
        spcli node new name "TI-Konnektor" address "$konnektorIpAddress/32" zone "$intZone" > /dev/null 2>&1
        spcli rule group new name "Konnektor" > /dev/null
        spcli service new name "Konnektor TCP 8443" proto "tcp" ct_helper "" dst-ports [ "8443" ] src-ports [ ]
        spcli rule new group "Konnektor" src "TI-Konnektor" dst "$internetInterface" service "ipsec" comment "" flags [ "LOG" "HIDENAT" "ACCEPT" ] nat_node "$extInterface" > /dev/null 2>&1
        spcli rule new group "Konnektor" src "TI-Konnektor" dst "$internetInterface" service "Konnektor TCP 8443" comment "" flags [ "LOG" "HIDENAT" "ACCEPT" ] nat_node "$extInterface" > /dev/null 2>&1
        spcli rule new group "Konnektor" src "TI-Konnektor" dst "$internetInterface" service "domain-tcp" comment "" flags [ "LOG" "HIDENAT" "ACCEPT" ] nat_node "$extInterface" > /dev/null 2>&1
    fi

    ## TK Anlage
    while [ "$input_TK" != "n" ] && [ "$input_TK" != "y" ];do
        read -n 1 -s -p "Ist eine TK Anlage vorhanden? (y/n):"$'\n' input_TK
    done 

    if [ "$input_TK" = "y" ];then
        read -p "IP-Adresse:" tkIpAddress
        ip route get "$tkIpAddress" > /dev/null 2>&1

        while [ $? != "0" ] || [ -z "$tkIpAddress" ];do
            read -p"TK-Anlagen IP ungueltig, wiederholen Sie ihre Eingabe:"$'\n' tkIpAddress
            ip route get "$tkIpAddress" > /dev/null 2>&1
        done
        spcli node new name "TK-Anlage" address "$tkIpAddress/32" zone "$intZone" > /dev/null 2>&1
        spcli rule group new name "TK-Anlage Regeln" > /dev/null
        spcli rule new group "TK-Anlage Regeln" src "TK-Anlage" dst "$internetInterface" service "any" comment "" flags [ "LOG" "HIDENAT" "ACCEPT" ] nat_node "$extInterface" > /dev/null 2>&1
    fi
    spcli rule group new name "Portweiterleitung" > /dev/null
    spcli rule group new name "Test" > /dev/null
    spcli rule new group "Test" src "$intNetwork" dst "$internetInterface" service "any" comment "" flags [ "LOG" "HIDENAT" "ACCEPT" "DISABLED" ] nat_node "$extInterface" > /dev/null 2>&1

