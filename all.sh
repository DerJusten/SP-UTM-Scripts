#!/bin/sh
####### Nicht anpassen #########
isVersion12="0"
####### Anpassen, wenn notwendig #########
intZone="internal"
intNetwork="internal-network"
intInterface="internal-interface"
extInterface="external-interface"
internetInterface="internet"
## VPN Einstellungen
VPN_Name="RW-VPN-U1194"
VPN_network_obj="vpn-c2s-network" 
CA_VPN="CA_RW_VPN"
CS_VPN="CS_RW_VPN"
VPN_Tun="10.8.0.0/24"
VPN_SupportUser="vpn_support"
VPN_SupportGrp="grpVPN"
####### Zertifikatseinstellungen für Proxy & VPN #########
bits="2048"
state="Deutschland"
location="Musterstadt"
organization="Muster GmbH"
organization_unit="EDV"
email="mail@muster.com"
####################################################
############## Functions ######################
####################################################

echo "Skript zur Ersteinrichtung fuer SecurePoint UTM Version 11 & 12 | Version 0.11 by DerJusten"
# Get current directory and read conf.cfg
dir=$(cd `dirname $0` && pwd)
cfg=$dir"/conf.cfg"

if test -f "$cfg"; then
    echo "Lade Variablen von conf.cfg"
    source $dir/conf.cfg
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

##interface=$(spcli interface get | awk 'BEGIN {FS = "|" }; {print $1 "\t" $6 "\t" $2}' |grep $intZone |cut -f3 -d$'\t')
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
       spcli rule set id "$id" flags [ "ACCEPT" "LOG" "HIDENAT" "DISABLED" ]
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
    ## Add DNS Server
    spcli extc global set variable "GLOB_NAMESERVER" value [ "9.9.9.9" "149.112.112.112" ]
   
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


    ## VPN
    while [ "$inputVPN" != "n" ] && [ "$inputVPN" != "y" ];do
        read -s -n 1 -p "Soll VPN eingerichtet werden? Es darf keine VPN bereits existieren! (y/n)"$'\n' inputVPN
    done

    if [ "$inputVPN" = "y" ];then

        ## Add VPN Certificate
        spcli cert new bits $bits common_name "$CA_VPN" valid_since "2021-01-01-00-00-00" valid_till "2037-12-31-23-59-59" country "DE" state "$state" location "$location" organization "$organization" organization_unit "$organization_unit" email "$email" > /dev/null
        CA_VPN_ID=$(spcli cert get | awk 'BEGIN {FS = "|" }; {print $1 "\t" $2 "\t" $14}' |grep "$CA_VPN" | cut -f1 -d$'\t')
        spcli cert new bits $bits common_name "$CS_VPN" issuer_id "$CA_VPN_ID" valid_since "2021-01-01-00-00-00" valid_till "2037-12-31-23-59-59" country "DE" state "$state" location "$location" organization "$organization" organization_unit "$organization_unit" email "$email" > /dev/null
        CS_VPN_ID=$(spcli cert get | awk 'BEGIN {FS = "|" }; {print $1 "\t" $2 "\t" $14}' |grep "$CS_VPN" | cut -f1 -d$'\t')
        spcli cert extension add id "$CS_VPN_ID" ext_name "Netscape Cert Type" ext_value "SSL Server"
        spcli cert extension add id "$CS_VPN_ID" ext_name "X509v3 Extended Key Usage" ext_value "TLS Web Server Authentication" 
        spcli cert new bits $bits common_name "$CC_RW_Support" issuer_id "$CA_VPN_ID" valid_since "2021-01-01-00-00-00" valid_till "2037-12-31-23-59-59" country "DE" state "$state" location "$location" organization "$organization" organization_unit "$organization_unit" email "$email" > /dev/null
        spcli cert new bits $bits common_name "VPN_Client01" issuer_id "$CA_VPN_ID" valid_since "2021-01-01-00-00-00" valid_till "2037-12-31-23-59-59" country "DE" state "$state" location "$location" organization "$organization" organization_unit "$organization_unit" email "$email" > /dev/null
        spcli cert new bits $bits common_name "VPN_Client02" issuer_id "$CA_VPN_ID" valid_since "2021-01-01-00-00-00" valid_till "2037-12-31-23-59-59" country "DE" state "$state" location "$location" organization "$organization" organization_unit "$organization_unit" email "$email" > /dev/null
        spcli cert new bits $bits common_name "VPN_Client03" issuer_id "$CA_VPN_ID" valid_since "2021-01-01-00-00-00" valid_till "2037-12-31-23-59-59" country "DE" state "$state" location "$location" organization "$organization" organization_unit "$organization_unit" email "$email" > /dev/null
        spcli cert new bits $bits common_name "VPN_Client04" issuer_id "$CA_VPN_ID" valid_since "2021-01-01-00-00-00" valid_till "2037-12-31-23-59-59" country "DE" state "$state" location "$location" organization "$organization" organization_unit "$organization_unit" email "$email" > /dev/null
        spcli cert new bits $bits common_name "VPN_Client05" issuer_id "$CA_VPN_ID" valid_since "2021-01-01-00-00-00" valid_till "2037-12-31-23-59-59" country "DE" state "$state" location "$location" organization "$organization" organization_unit "$organization_unit" email "$email" > /dev/null
       

        ## Add VPN rules
        spcli interface new name "tun0" type "TUN" flags [ "DYNADDR" ] > /dev/null
        spcli openvpn new name "$VPN_Name" interface "tun0" proto "UDP" local_port "1194" auth "LOCAL" cert "$CS_VPN" pool "$VPN_Tun" pool_ipv6 "" mtu "1500" push_subnet [ "$interfaceIpAddress" ] flags [ "MULTIHOME" ] cipher "AES-128-CBC" digest_algorithm "SHA256" > /dev/null
        spcli interface zone new name "vpn-ssl-$VPN_Name" interface "tun0" > /dev/null
        spcli node new name "$VPN_network_obj" address "$VPN_Tun" zone "vpn-ssl-$VPN_Name" > /dev/null
        spcli rule group new name "VPN Regeln" > /dev/null
        spcli rule new group "VPN Regeln" src "$VPN_network_obj" dst "$intInterface" service "administration" comment "" flags [ "LOG" "ACCEPT" ] > /dev/null

        ## Create VPN Group
        spcli user group new name "$VPN_SupportGrp" directory_name "" permission [ "WEB_USER" "VPN_OPENVPN" ] > /dev/null
        vpn_support_pw=$(openssl rand -base64 24)
        spcli user new name "$VPN_SupportUser" password "$vpn_support_pw" groups [ "grpVPN" ] > /dev/null
        spcli user attribute set name "$VPN_SupportUser" attribute "vpn_l2tp_ip" value ""
        spcli user attribute set name "$VPN_SupportUser" attribute "vpn_openvpn_ip" value ""
        spcli user attribute set name "$VPN_SupportUser" attribute "vpn_openvpn_ipv6" value ""
        spcli user attribute set name "$VPN_SupportUser" attribute "password_length" value "8"
        spcli user attribute set name "$VPN_SupportUser" attribute "openvpn_name" value "$VPN_Name"
        spcli user attribute set name "$VPN_SupportUser" attribute "openvpn_certificate" value ""
        spcli user attribute set name "$VPN_SupportUser" attribute "openvpn_gateway" value ""
        spcli user attribute set name "$VPN_SupportUser" attribute "language" value "DEFAULT"
        spcli user attribute set name "$VPN_SupportUser" attribute "password_change" value "0"
        spcli user attribute set name "$VPN_SupportUser" attribute "openvpn_client_download" value "0"
        spcli user attribute set name "$VPN_SupportUser" attribute "openvpn_redirectgateway" value "0"
        spcli user attribute set name "$VPN_SupportUser" attribute "mailfilter_download_attachments_filtered" value "0"
        spcli user attribute set name "$VPN_SupportUser" attribute "mailfilter_download_attachments_quarantine" value "0"
        spcli user attribute set name "$VPN_SupportUser" attribute "mailfilter_allow_resend_quarantined" value "1"
        spcli user attribute set name "$VPN_SupportUser" attribute "mailfilter_allow_resend_filtered" value "0" 


        for i in 1 2 3 4 5
        do
            vpn_client_pw=$(openssl rand -base64 24)
            vpn_client_name="Client0"$i
            spcli user new name "$vpn_client_name" password "$vpn_client_pw" groups [ "grpVPN" ] > /dev/null
            spcli user attribute set name "$vpn_client_name" attribute "vpn_l2tp_ip" value ""
            spcli user attribute set name "$vpn_client_name" attribute "vpn_openvpn_ip" value ""
            spcli user attribute set name "$vpn_client_name" attribute "vpn_openvpn_ipv6" value ""
            spcli user attribute set name "$vpn_client_name" attribute "password_length" value "8"
            spcli user attribute set name "$vpn_client_name" attribute "openvpn_name" value "$VPN_Name"
            spcli user attribute set name "$vpn_client_name" attribute "openvpn_certificate" value ""
            spcli user attribute set name "$vpn_client_name" attribute "openvpn_gateway" value ""
            spcli user attribute set name "$vpn_client_name" attribute "language" value "DEFAULT"
            spcli user attribute set name "$vpn_client_name" attribute "password_change" value "0"
            spcli user attribute set name "$vpn_client_name" attribute "openvpn_client_download" value "0"
            spcli user attribute set name "$vpn_client_name" attribute "openvpn_redirectgateway" value "0"
            spcli user attribute set name "$vpn_client_name" attribute "mailfilter_download_attachments_filtered" value "0"
            spcli user attribute set name "$vpn_client_name" attribute "mailfilter_download_attachments_quarantine" value "0"
            spcli user attribute set name "$vpn_client_name" attribute "mailfilter_allow_resend_quarantined" value "1"
            spcli user attribute set name "$vpn_client_name" attribute "mailfilter_allow_resend_filtered" value "0" 
        done
    fi

    ################## SSL Proxy ########################
    while [ "$inputProxy" != "n" ] && [ "$inputProxy" != "y" ];do
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

        ## Delete existing http rule
        Node_ID=$(spcli rule transparent get |awk 'BEGIN {FS = "|" }; {print $3 "\t" $2}' |grep -w http | cut -f1 -d$'\t')
        if [ ! -z $Node_ID ];then
               spcli rule transparent delete node_id "$Node_ID"
        fi
         spcli rule transparent add id "2" type "INCLUDE" src "$intNetwork" dst "$internetInterface"
        spcli rule transparent add id "3" type "INCLUDE" src "$intNetwork" dst "$internetInterface"
        spcli appmgmt restart application "http_proxy"

        ## Webfilter Categories
        webfilterID=$(spcli webfilter ruleset get | awk 'BEGIN {FS="|" }; {print $1 "\t" $2}' | grep security |cut -f1 -d$'\t')
        startRank=0
        # Waffen
        spcli webfilter rule new ruleset_oid "$webfilterID" expression "127.0.5.3" action "blacklist-cat" rank "$startRank" > /dev/null
        let startRank=$startRank+1
        # Porno & Erotik
        spcli webfilter rule new ruleset_oid "$webfilterID" expression "127.0.4.2" action "blacklist-cat" rank "$startRank" > /dev/null
        let startRank=$startRank+1
        # Erotik möglich
        spcli webfilter rule new ruleset_oid "$webfilterID" expression "127.0.4.4" action "blacklist-cat" rank "$startRank" > /dev/null
        let startRank=$startRank+1
        # Abstoßend
        spcli webfilter rule new ruleset_oid "$webfilterID" expression "127.0.6.0" action "blacklist-cat" rank "$startRank" > /dev/null
        let startRank=$startRank+1
        # Spiele
        spcli webfilter rule new ruleset_oid "$webfilterID" expression "127.0.11.0" action "blacklist-cat" rank "$startRank" > /dev/null
        let startRank=$startRank+1
        # Spam Domains
        spcli webfilter rule new ruleset_oid "$webfilterID" expression "127.0.80.5" action "blacklist-cat" rank "$startRank" > /dev/null
        let startRank=$startRank+1
        # Social Media
        spcli webfilter rule new ruleset_oid "$webfilterID" expression "127.0.31.2" action "blacklist-cat" rank "$startRank" > /dev/null
        let startRank=$startRank+1
        # Tracking Strict
        spcli webfilter rule new ruleset_oid "$webfilterID" expression "127.0.08.3" action "blacklist-cat" rank "$startRank" > /dev/null
        let startRank=$startRank+1
        # Unseriöses Geld verdienen
        spcli webfilter rule new ruleset_oid "$webfilterID" expression "127.0.15.35" action "blacklist-cat" rank "$startRank" > /dev/null
        let startRank=$startRank+1
        # Parked Websites
        spcli webfilter rule new ruleset_oid "$webfilterID" expression "127.0.80.4" action "blacklist-cat" rank "$startRank" > /dev/null


                
        if [ "$isVersion12" = "0" ];then
            # Proxy (v11)
            spcli webfilter rule new ruleset_oid "$webfilterID" expression "127.0.28.8" action "blacklist-cat" rank "$startRank" > /dev/null
            let startRank=$startRank+1
            #Hacking (v11)
            spcli webfilter rule new ruleset_oid "$webfilterID" expression "127.0.28.1" action "blacklist-cat" rank "$startRank" > /dev/null
            let startRank=$startRank+1
                    # Thread (v11)
            spcli webfilter rule new ruleset_oid "$webfilterID" expression "127.0.28.2" action "blacklist-cat" rank "$startRank" > /dev/null
            let startRank=$startRank+1
        fi
        ##########################################################################

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
    fi

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

    echo "Vorgang abgeschlossen"
    echo ""
    echo "###################### Zusammenfassung #############################"
    echo "# Konnektor IP:"$'\t'$'\t'$konnektorIpAddress
    echo "# TK-Anlagen IP:"$'\t'$tkIpAddres
    echo "# Cloud Backup PW:"$'\t'$CloudPw
    echo "# Server URL:"$'\t'$'\t'$ServerAdminURL
    echo "# VPN Support Pw:"$'\t'$vpn_support_pw
    echo "####################################################################"

    logfile=log.txt
    echo "###################### Zusammenfassung #############################"
    echo "# Konnektor IP:"$'\t'$'\t'$konnektorIpAddress >> $logfile
    echo "# TK-Anlagen IP:"$'\t'$tkIpAddres >> $logfile
    echo "# Cloud Backup PW:"$'\t'$CloudPw >> $logfile
    echo "# Server URL:"$'\t'$'\t'$ServerAdminURL >> $logfile
    echo "# VPN Support Pw:"$'\t'$vpn_support_pw >> $logfile
    echo "####################################################################"

else
    echo "Vorgang abgebrochen"
fi
