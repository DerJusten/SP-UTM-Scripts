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
##########################################
interface=$(spcli interface get | awk 'BEGIN {FS = "|" }; {print $1 "\t" $5 "\t" $2}' |grep $intZone |cut -f1 -d$'\t')
info=$(spcli interface address get | awk 'BEGIN {FS = "|" };  {print $1 "\t" $3 "\t" $4}' | grep $interface)
interfaceID=$(echo $info | cut -f1 -d$' ')
interfaceIpAddress=$(echo $info | cut -f3 -d$' ')
input="n"
read -n 1 -p "Soll das Interface $interface ($interfaceIpAddress) bearbeitet werden?" input
##user confirmed
if [ "$input" = "y" ];then
    ##Create new config
    dtnow=$(date +"%m-%d-%Y_%T")
    spcli system config save name "autorules_$dtnow" 
    ##Disable any rules to internet
    id=$(spcli rule get | awk 'BEGIN {FS = "|" };  {print $3 "\t" $4 "\t" $5 "\t" $6 "\t" $9}' | grep any| grep ACCEPT | grep $intInterface | grep $internetInterface |cut -f1 -d$'\t')
    while [ ! -z $id ];do
       spcli rule set id "$id" flags [ "DROP" "LOG" "HIDENAT" "DISABLED" ]
       id=$(spcli rule get | awk 'BEGIN {FS = "|" };  {print $3 "\t" $4 "\t" $5 "\t" $6 "\t" $9}' | grep any| grep ACCEPT |grep $intInterface | grep $internetInterface |cut -f1 -d$'\t')
    done
    spcli rule group new name "Interne Regeln"
    ##Default Internet
    spcli rule new group "Interne Regeln" src "$intInterface" dst "$internetInterface" service "default-internet" comment "" flags [ "LOG" "HIDENAT" "ACCEPT" ] nat_node "$extInterface"
    ##NTP
    spcli rule new group "Interne Regeln" src "$intInterface" dst "$internetInterface" service "network-time" comment "" flags [ "LOG" "HIDENAT" "ACCEPT" ] nat_node "$extInterface"
    ##Create Group
    spcli service group new name "dgrp_mails"
    ## 993
    spcli service group add name "dgrp_mails" services "imap-ssl"
    ## 25
    spcli service group add name "dgrp_mails" services "smtp"
    ## 465
    spcli service group add name "dgrp_mails" services "smtps"
    ## 587
    spcli service group add name "dgrp_mails" services "submission"
    ## Add Mailgroup
    spcli rule new group "Interne Regeln" src "$intInterface" dst "internet" service "dgrp_mails" comment "" flags [ "LOG" "HIDENAT" "ACCEPT" ] nat_node "$extInterface"
    
    ## Add ProxyCertificate
    spcli cert new bits $bits common_name CA_Proxy valid_since "2021-01-01-00-00-00" valid_till "2037-12-31-23-59-59" country "DE" state "$state" location "$location" organization "$organization" organization_unit "$organization_unit" email "$email"
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
else
    echo "Vorgang abgebrochen"
fi
