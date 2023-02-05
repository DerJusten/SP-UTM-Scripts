#!/bin/sh
####### Nicht anpassen #########
vpn_log="/tmp/fw-tool/access.txt"
createConfigBackup=$1
## VPN Einstellungen
VPN_Port="1194"
VPN_Name="RW-VPN-U"$VPN_Port
VPN_network_obj="vpn-c2s-network" 
CA_VPN="CA_RW_VPN"
CS_VPN="CS_RW_VPN"
VPN_Tun="10.8.0.0/24"
VPN_SupportUser="support"
VPN_SupportGrp="grpSupportVPN"
VPN_UserGrp="grpUserVPN"
VPN_RemoteHost=""
#### Interface #########
intInterface="internal-interface"
intNetwork="internal-network"
intZone="internal"
####### Zertifikatseinstellungen für VPN #########
bits="2048"
state="Deutschland"
location="Musterstadt"
organization="Muster GmbH"
organization_unit="EDV"
email="mail@muster.com"
####################################################

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
    intInterface=$cfgIntInterface
    intNetwork=$cfgIntNetwork
    intZone=$cfgIntZone
else
    echo $cfg " wurde nicht gefunden"
fi

aio_cfg=$dir"/aio.cfg"
if test -f "$aio_cfg"; then    
    source $aio_cfg
    VPN_Port=$aio_VPN_Port
    VPN_Name="RW-VPN-U"$VPN_Port
    VPN_RemoteHost=$aio_ddnsHost
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

##Workaround, replace last octect with 0 in /24 

netmask=$(echo $interfaceIpAddress | cut -d "." -f4 | cut -d "/" -f2)
if [ "$netmask" = "24" ];then

    LastOctet=$(echo $interfaceIpAddress | cut -d "." -f4 | cut -d "/" -f1)
    NetID=$(echo $s | sed "s/$LastOctet\//0\//g")
else
    NetID=$interfaceIpAddress
fi


echo "Current Subnet "$NetID
    ##Create new config
    if [ -z $createConfigBackup ] || [ $createConfigBackup == 1 ];then
        dtnow=$(date +"%m-%d-%Y_%H-%M-%S")
        echo "Erstelle neue Konfigurationsdatei autorules_$dtnow"
        spcli system config save name "vpn_$dtnow"  
    fi 
  
  ## Create CA VPN
        spcli cert new bits $bits common_name "$CA_VPN" valid_since "2021-01-01-00-00-00" valid_till "2037-12-31-23-59-59" country "DE" state "$state" location "$location" organization "$organization" organization_unit "$organization_unit" email "$email" > /dev/null
        CA_VPN_ID=$(spcli cert get | awk 'BEGIN {FS = "|" }; {print $1 "\t" $2 "\t" $14}' |grep "$CA_VPN" | cut -f1 -d$'\t')
    ##Create CS VPN
        spcli cert new bits $bits common_name "$CS_VPN" issuer_id "$CA_VPN_ID" valid_since "2021-01-01-00-00-00" valid_till "2037-12-31-23-59-59" country "DE" state "$state" location "$location" organization "$organization" organization_unit "$organization_unit" email "$email" > /dev/null
        CS_VPN_ID=$(spcli cert get | awk 'BEGIN {FS = "|" }; {print $1 "\t" $2 "\t" $14}' |grep "$CS_VPN" | cut -f1 -d$'\t')
        spcli cert extension add id "$CS_VPN_ID" ext_name "Netscape Cert Type" ext_value "SSL Server"
        spcli cert extension add id "$CS_VPN_ID" ext_name "X509v3 Extended Key Usage" ext_value "TLS Web Server Authentication" 
    ## Create User Certificate
        spcli cert new bits $bits common_name "VPN_Support" issuer_id "$CA_VPN_ID" valid_since "2021-01-01-00-00-00" valid_till "2037-12-31-23-59-59" country "DE" state "$state" location "$location" organization "$organization" organization_unit "$organization_unit" email "$email" > /dev/null

        ## Add VPN rules
        spcli interface new name "tun0" type "TUN" flags [ "DYNADDR" ] > /dev/null
        spcli openvpn new name "$VPN_Name" interface "tun0" proto "UDP" local_port "$VPN_Port" auth "LOCAL" cert "$CS_VPN" pool "$VPN_Tun" pool_ipv6 "" mtu "1500" push_subnet [ "$NetID" ] flags [ "MULTIHOME" ] cipher "AES-128-CBC" digest_algorithm "SHA256" > /dev/null
        spcli interface zone new name "vpn-ssl-$VPN_Name" interface "tun0" > /dev/null
        spcli node new name "$VPN_network_obj" address "$VPN_Tun" zone "vpn-ssl-$VPN_Name" > /dev/null

        ## Create VPN Group
        spcli user group new name "$VPN_SupportGrp" directory_name "" permission [ "WEB_USER" "VPN_OPENVPN" ] > /dev/null
        id_SupportGrp=$(spcli user group get | awk 'BEGIN {FS = "|" }; {print $1 "\t" $2}' |grep "$VPN_SupportGrp" |cut -f1)
        spcli user group set id "$id_SupportGrp" name "$VPN_SupportGrp" directory_name "" permission [ "WEB_USER" "VPN_OPENVPN" ] ibf_flags [ "SSLVPN" ] > /dev/null

        spcli user group new name "$VPN_UserGrp" directory_name "" permission [ "WEB_USER" "VPN_OPENVPN" ] > /dev/null
        id_UserGrp=$(spcli user group get | awk 'BEGIN {FS = "|" }; {print $1 "\t" $2}' |grep "$VPN_UserGrp" |cut -f1) 
        spcli user group set id "$id_UserGrp" name "$VPN_UserGrp" directory_name "" permission [ "WEB_USER" "VPN_OPENVPN" ] ibf_flags [ "SSLVPN" ] > /dev/null

        ## Create Rules
        spcli rule group new name "VPN Regeln" > /dev/null
        ##Gruppen temporär entfernt, da nicht funktional
        spcli rule new group "VPN Regeln" src "$VPN_network_obj" dst "$intInterface" service "icmp-echo-req" comment "" flags [ "LOG" "ACCEPT" ] > /dev/null
        spcli rule new group "VPN Regeln" src "$VPN_network_obj" dst "$intInterface" service "administration" comment "" flags [ "LOG" "ACCEPT" ] > /dev/null
        spcli rule new group "VPN Regeln" src "$VPN_UserGrp" dst "$intNetwork" service "ms-rdp" comment "" flags [ "LOG" "ACCEPT" ] > /dev/null
        
        
        ## Create Support User
        echo "Erstelle VPN User " $VPN_SupportUser
        vpn_support_pw=$(openssl rand -base64 24)
        vpn_support_pw=$vpn_support_pw"$"       
        spcli user new name "$VPN_SupportUser" password "$vpn_support_pw" groups [ "$VPN_SupportGrp" ] > /dev/null
        spcli user attribute set name "$VPN_SupportUser" attribute "vpn_l2tp_ip" value ""
        spcli user attribute set name "$VPN_SupportUser" attribute "vpn_openvpn_ip" value ""
        spcli user attribute set name "$VPN_SupportUser" attribute "vpn_openvpn_ipv6" value ""
        spcli user attribute set name "$VPN_SupportUser" attribute "password_length" value "8"
        spcli user attribute set name "$VPN_SupportUser" attribute "openvpn_name" value "$VPN_Name"
        spcli user attribute set name "$VPN_SupportUser" attribute "openvpn_certificate" value "VPN_Support"
        spcli user attribute set name "$VPN_SupportUser" attribute "openvpn_gateway" value "$VPN_RemoteHost"
        spcli user attribute set name "$VPN_SupportUser" attribute "language" value "DEFAULT"
        spcli user attribute set name "$VPN_SupportUser" attribute "password_change" value "0"
        spcli user attribute set name "$VPN_SupportUser" attribute "openvpn_client_download" value "1"
        spcli user attribute set name "$VPN_SupportUser" attribute "openvpn_redirectgateway" value "0"
        spcli user attribute set name "$VPN_SupportUser" attribute "mailfilter_download_attachments_filtered" value "0"
        spcli user attribute set name "$VPN_SupportUser" attribute "mailfilter_download_attachments_quarantine" value "0"
        spcli user attribute set name "$VPN_SupportUser" attribute "mailfilter_allow_resend_quarantined" value "1"
        spcli user attribute set name "$VPN_SupportUser" attribute "mailfilter_allow_resend_filtered" value "0"
        ## Overwrite file
        echo "######### VPN Zugaenge ##########" > $vpn_log
        echo "# Name:"$'\t' $VPN_SupportUser$'\t'"Passwort:"$'\t' $vpn_support_pw >> $vpn_log

        ## Create 5x Clients
        for i in 1 2 3 4 5
        do
            vpn_client_pw=$(openssl rand -base64 12)
            vpn_client_pw=$vpn_client_pw"#"
            vpn_client_name="Client0"$i
            echo "Erstelle VPN User " $vpn_client_name
            spcli user new name "$vpn_client_name" password "$vpn_client_pw" groups [ "$VPN_UserGrp" ] > /dev/null
             spcli cert new bits $bits common_name "CC_$vpn_client_name" issuer_id "$CA_VPN_ID" valid_since "2021-01-01-00-00-00" valid_till "2037-12-31-23-59-59" country "DE" state "$state" location "$location" organization "$organization" organization_unit "$organization_unit" email "$email" > /dev/null
            spcli user attribute set name "$vpn_client_name" attribute "vpn_l2tp_ip" value ""
            spcli user attribute set name "$vpn_client_name" attribute "vpn_openvpn_ip" value ""
            spcli user attribute set name "$vpn_client_name" attribute "vpn_openvpn_ipv6" value ""
            spcli user attribute set name "$vpn_client_name" attribute "password_length" value "8"
            spcli user attribute set name "$vpn_client_name" attribute "openvpn_name" value "$VPN_Name"
            spcli user attribute set name "$vpn_client_name" attribute "openvpn_certificate" value "CC_$vpn_client_name"
            spcli user attribute set name "$vpn_client_name" attribute "openvpn_gateway" value "$VPN_RemoteHost"
            spcli user attribute set name "$vpn_client_name" attribute "language" value "DEFAULT"
            spcli user attribute set name "$vpn_client_name" attribute "password_change" value "0"
            spcli user attribute set name "$vpn_client_name" attribute "openvpn_client_download" value "1"
            spcli user attribute set name "$vpn_client_name" attribute "openvpn_redirectgateway" value "0"
            spcli user attribute set name "$vpn_client_name" attribute "mailfilter_download_attachments_filtered" value "0"
            spcli user attribute set name "$vpn_client_name" attribute "mailfilter_download_attachments_quarantine" value "0"
            spcli user attribute set name "$vpn_client_name" attribute "mailfilter_allow_resend_quarantined" value "1"
            spcli user attribute set name "$vpn_client_name" attribute "mailfilter_allow_resend_filtered" value "0" 
            echo "# Name:"$'\t' $vpn_client_name $'\t'"Passwort:"$'\t' $vpn_client_pw >> $vpn_log
            ## Sleep script seems to skip sometimes user            
            sleep 0.5
        done
        #echo "##############################" >> $vpn_log
        echo "VPN Konfiguration abgeschlossen"
       ## cat $vpn_log

