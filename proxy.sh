#!/bin/sh
####### Nicht anpassen #########
isVersion12="0"
####### Anpassen, wenn notwendig #########
intZone="internal"
intNetwork="internal-network"
intInterface="internal-interface"
extInterface="external-interface"
internetInterface="internet"

echo "Skript zur Proxy Ersteinrichtung"

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

    ##Create new config
    dtnow=$(date +"%m-%d-%Y_%T")
    echo "Erstelle neue Konfigurationsdatei autorules_$dtnow"
    spcli system config save name "proxy_$dtnow" 

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




