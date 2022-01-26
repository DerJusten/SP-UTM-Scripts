#!/bin/sh
####### Nicht anpassen #########
isVersion12="0"
isLicensed="0"
createConfigBackup=$1
####### Anpassen, wenn notwendig #########
####### Zertifikatseinstellungen für VPN #########
bits="2048"
state="Deutschland"
location="Musterstadt"
organization="Muster GmbH"
organization_unit="EDV"
email="mail@muster.com"
#####################################################
intNetwork="internal-network"
internetInterface="internet"

echo "######## Skript zur Proxy Ersteinrichtung #############"

version=$(spcli system info | awk 'BEGIN {FS = "|" }; {print $1 "\t" $2}' | grep -w version |cut -f2 -d$'\t' | cut -f1 -d ' ')
if case $version in "11"*) true;; *) false;; esac; then
    isVersion12="0"
else
    isVersion12="1"
fi

checkLicense=$(spcli system info |grep devicetype | awk 'BEGIN {FS = "|" }; {print $2}')
case $checkLicense in 
    *VPN*) echo "Keine Lizenz für Proxy gefunden. Proxy-Einrichtung wird übersprungen."
    exit 1;;
esac
aio_cfg=$dir"/aio.cfg"
if test -f "$aio_cfg"; then    
    source $aio_cfg
    inputProxy=$aio_inputProxy
fi

checkIntNetwork=$(spcli node get |grep $intNetwork | awk 'BEGIN {FS = "|" }; {print $1 "\t" $2}' | cut -f2 -d$'\t')

if [ -z $checkIntNetwork ]; then
    echo "Es konnte $intNetwork nicht gefunden werden"
    exit 1
fi

while [ "$inputProxy" != "n" ] && [ "$inputProxy" != "y" ];do
    read -s -n 1 -p "Quellnetzwerk: $intNetwork Zielnetzwerk: $internetInterface Ist dies korrekt(y/n)?"$'\n' inputProxy
done
##user confirmed
if [ "$inputProxy" = "y" ];then

    ##Create new config
    if [ -z $createConfigBackup ] || [ $createConfigBackup == 1 ];then
        dtnow=$(date +"%m-%d-%Y_%T")
        echo "Erstelle neue Konfigurationsdatei autorules_$dtnow"
        spcli system config save name "proxy_$dtnow" 
    fi
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
        intNetwork=$cfgIntNetwork
        internetInterface=$cfgInternetInterface
    else
        echo $cfg " wurde nicht gefunden"
    fi
    ################## SSL Proxy ########################
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

        ## Delete existing Rules
        Node_IDs=$(spcli rule transparent get |awk 'BEGIN {FS = "|" }; {print $3 "\t" $2 "\t" $5 "\t" $6}' |grep internal |grep -v pop |cut -f1 -d$'\t')
        if [ ! -z "$Node_IDs" ];then
            for i in $Node_IDs
            do
                spcli rule transparent delete node_id "$i"
            done   
        fi

        spcli rule transparent add id "2" type "INCLUDE" src "$intNetwork" dst "$internetInterface"
        spcli rule transparent add id "3" type "INCLUDE" src "$intNetwork" dst "$internetInterface"


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
        spcli webfilter rule new ruleset_oid "$webfilterID" expression "127.0.80.3" action "blacklist-cat" rank "$startRank" > /dev/null
        let startRank=$startRank+1
        # Unseriöses Geld verdienen
        spcli webfilter rule new ruleset_oid "$webfilterID" expression "127.0.15.35" action "blacklist-cat" rank "$startRank" > /dev/null
        let startRank=$startRank+1
        # Parked Websites
        spcli webfilter rule new ruleset_oid "$webfilterID" expression "127.0.80.4" action "blacklist-cat" rank "$startRank" > /dev/null
        let startRank=$startRank+1
              
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
        spcli appmgmt restart application "http_proxy"

        echo "HTTP Proxy Einstellungen abgeschlossen"
        ##########################################################################
    else
        echo "Vorgang abgebrochen"
fi



