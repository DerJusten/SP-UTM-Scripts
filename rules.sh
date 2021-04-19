#!/bin/sh
####### Anpassen, wenn notwendig #########
intZone="internal"
intInterface="internal-network"
extInterface="external-interface"
internetInterface="internet"
####### Zertifikatseinstellungen für Proxy #########
bits="2048"
state="Deutschland"
location="Neuenhaus"
organization="maxbenedikt GmbH"
organization_unit="IT"
email="info@maxbenedikt.com"
############## Functions ######################

##########################################
interface=$(spcli interface get | awk 'BEGIN {FS = "|" }; {print $1 "\t" $5 "\t" $2}' |grep $intZone |cut -f1 -d$'\t')
info=$(spcli interface address get | awk 'BEGIN {FS = "|" };  {print $1 "\t" $3 "\t" $4}' | grep $interface)
interfaceID=$(echo $info | cut -f1 -d$' ')
interfaceIpAddress=$(echo $info | cut -f3 -d$' ')

while [ "$input" != "n" ] && [ "$input" != "y" ];do
    read -s -n 1 -p "Soll das Interface $interface ($interfaceIpAddress) bearbeitet werden (y/n)?"$'\n' input
done
##user confirmed
if [ "$input" = "y" ];then
    ##Create new config
    dtnow=$(date +"%m-%d-%Y_%T")
    echo "Erstelle neue Konfigurationsdatei autorules_$dtnow"
    spcli system config save name "autorules_$dtnow" 
    echo "Deaktiviere alle ANY Regeln von '$intInterface' nach '$internetInterface'"
    ## Disable any rules from internal network to internet
    id=$(spcli rule get | awk 'BEGIN {FS = "|" };  {print $3 "\t" $4 "\t" $5 "\t" $6 "\t" $9}' | grep any| grep ACCEPT | grep -v DISABLED | grep $intInterface | grep $internetInterface |cut -f1 -d$'\t')
    while [ ! -z $id ];do
       spcli rule set id "$id" flags [ "ACCEPT" "LOG" "HIDENAT" "DISABLED" ]
       id=$(spcli rule get | awk 'BEGIN {FS = "|" };  {print $3 "\t" $4 "\t" $5 "\t" $6 "\t" $9}' | grep any| grep ACCEPT | grep -v DISABLED |grep $intInterface | grep $internetInterface |cut -f1 -d$'\t')
    done
    echo "Erstelle interne Regeln"
    spcli rule group new name "Interne Regeln"
    ##Default Internet
    spcli rule new group "Interne Regeln" src "$intInterface" dst "$internetInterface" service "default-internet" comment "" flags [ "LOG" "HIDENAT" "ACCEPT" ] nat_node "$extInterface"
    ##NTP
    spcli rule new group "Interne Regeln" src "$intInterface" dst "$internetInterface" service "network-time" comment "" flags [ "LOG" "HIDENAT" "ACCEPT" ] nat_node "$extInterface"
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
    ## Add Mailgroup
    spcli rule new group "Interne Regeln" src "$intInterface" dst "internet" service "dgrp_mails" comment "" flags [ "LOG" "HIDENAT" "ACCEPT" ] nat_node "$extInterface"
    ##Create Group Teamviewer
    spcli service group new name "dgrp_teamviewer"
    ## Add teamviewer ports TCP + UDP
    spcli service group add name "dgrp_teamviewer" services "teamviewer_tcp"
    spcli service group add name "dgrp_teamviewer" services "teamviewer_udp"
    ## Add TeamviewerGroup to rules
    spcli rule new group "Interne Regeln" src "$intInterface" dst "internet" service "dgrp_teamviewer" comment "" flags [ "LOG" "HIDENAT" "ACCEPT" ] nat_node "$extInterface"

    ## TerraCloud Abfrage
    while [ "$inputTerraCloud" != "n" ] && [ "$inputTerraCloud" != "y" ];do
        read -s -n 1 -p "Wird Terra Cloud Backup verwendet?"$'\n' inputTerraCloud
    done
    if [ "$inputTerraCloud" = "y" ];then
        ## TerraCloud
        spcli service new name "TerraCloud 8086" proto "tcp" ct_helper "" dst-ports [ "8086" ] src-ports [ ]
        spcli service new name "TerraCloud 8087" proto "tcp" ct_helper "" dst-ports [ "8087" ] src-ports [ ]
        spcli service new name "TerraCloud 2546" proto "tcp" ct_helper "" dst-ports [ "2546" ] src-ports [ ]

        spcli service group new name "dgrp_terracloud"
        spcli service group add name "dgrp_terracloud" services "TerraCloud 8086"
        spcli service group add name "dgrp_terracloud" services "TerraCloud 8087"
        spcli service group add name "dgrp_terracloud" services "TerraCloud 2546"
    fi
    else
    echo "Vorgang abgebrochen"
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
    spcli rule group new name "Konnektor"
    spcli rule new group "Konnektor" src "TI-Konnektor" dst "$internetInterface" service "ipsec" comment "" flags [ "LOG" "HIDENAT" "ACCEPT" ] nat_node "$extInterface" > /dev/null 2>&1
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
    spcli rule group new name "TK-Anlage Regeln"
    spcli rule new group "TK-Anlage Regeln" src "TK-Anlage" dst "$internetInterface" service "any" comment "" flags [ "LOG" "HIDENAT" "ACCEPT" ] nat_node "$extInterface" > /dev/null 2>&1
fi

################## SSL Proxy ########################
while [ "$inputProxy" != "n" ] && [ "$input" != "y" ];do
    read -s -n 1 -p "Soll der HTTP Proxy aktiviert werden? (y/n)"$'\n' inputProxy
done

if [ "$inputProxy" = "y" ];then
    ## Add ProxyCertificate
    spcli cert new bits $bits common_name CA_Proxy valid_since "2021-01-01-00-00-00" valid_till "2037-12-31-23-59-59" country "DE" state "$state" location "$location" organization "$organization" organization_unit "$organization_unit" email "$email" > /dev/null 2>&1
    CA_ID=$(spcli cert get | awk 'BEGIN {FS = "|" }; {print $1 "\t" $2 "\t" $14}' |grep "CA_Proxy" | cut -f1 -d$'\t')
    
    ## Enable SSL Proxy
    spcli extc value set application "http_proxy" variable "SSLPROXY" value "1"
    spcli extc value set application "http_proxy" variable "SSLPROXY_BUMP_ON_BLOCK_ONLY" value "1"
    spcli extc value set application "http_proxy" variable "SSLPROXY_CERT_ID" value [ "$CA_ID" ]
    spcli extc value set application "http_proxy" variable "SSLPROXY_NOVERIFY_LIST_ENABLED" value "0"
    spcli extc value set application "http_proxy" variable "SSLPROXY_EXCEPTION_LIST_ENABLED" value "0"
    spcli extc value set application "http_proxy" variable "SSLPROXY_VERIFY_PEER" value "0"
    spcli extc value set application "http_proxy" variable "ENABLE_TRANSPARENT" value "1"
    spcli rule transparent add id "2" type "INCLUDE" src "$intInterface" dst "$internetInterface"
    spcli rule transparent add id "3" type "INCLUDE" src "$intInterface" dst "$internetInterface"
    spcli appmgmt restart application "http_proxy"

    ## Webfilter Categories
    webfilterID=$(spcli webfilter ruleset get | awk 'BEGIN {FS="|" }; {print $1 "\t" $2}' | grep security |cut -f1 -d$'\t')
    startRank=0
    # Waffen
    spcli webfilter rule new ruleset_oid "$webfilterID" expression "127.0.5.3" action "blacklist-cat" rank "$startRank"
    let $startRank=$startRank+1
    # Porno & Erotik
    spcli webfilter rule new ruleset_oid "$webfilterID" expression "127.0.4.2" action "blacklist-cat" rank "$startRank"
    let $startRank=$startRank+1
    # Erotik möglich
    spcli webfilter rule new ruleset_oid "$webfilterID" expression "127.0.4.4" action "blacklist-cat" rank "$startRank"
    let $startRank=$startRank+1
    # Thread
    spcli webfilter rule new ruleset_oid "$webfilterID" expression "127.0.28.2" action "blacklist-cat" rank "$startRank"
    let $startRank=$startRank+1
    # Abstoßend
    spcli webfilter rule new ruleset_oid "$webfilterID" expression "127.0.6.0" action "blacklist-cat" rank "$startRank"
    let $startRank=$startRank+1
    # Proxy
    spcli webfilter rule new ruleset_oid "$webfilterID" expression "127.0.28.8" action "blacklist-cat" rank "$startRank"
    let $startRank=$startRank+1
    #Hacking
    spcli webfilter rule new ruleset_oid "$webfilterID" expression "127.0.28.1" action "blacklist-cat" rank "$startRank"
    let $startRank=$startRank+1
    # Spiele
    spcli webfilter rule new ruleset_oid "$webfilterID" expression "127.0.11.0" action "blacklist-cat" rank "$startRank"
    let $startRank=$startRank+1
    # Spam Domains
    spcli webfilter rule new ruleset_oid "$webfilterID" expression "127.0.80.5" action "blacklist-cat" rank "$startRank"
    let $startRank=$startRank+1
    # Social Media
    spcli webfilter rule new ruleset_oid "$webfilterID" expression "127.0.31.2" action "blacklist-cat" rank "$startRank"
    let $startRank=$startRank+1
    # Tracking Strict
    spcli webfilter rule new ruleset_oid "$webfilterID" expression "127.0.08.3" action "blacklist-cat" rank "$startRank"
    let $startRank=$startRank+1
    # Unseriöses Geld verdienen
    spcli webfilter rule new ruleset_oid "$webfilterID" expression "127.0.15.35" action "blacklist-cat" rank "$startRank"
    let $startRank=$startRank+1
    # Parked Websites
    spcli webfilter rule new ruleset_oid "$webfilterID" expression "127.0.80.4" action "blacklist-cat" rank "$startRank"
    ##########################################################################

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
echo "Vorgang abgeschlossen"
