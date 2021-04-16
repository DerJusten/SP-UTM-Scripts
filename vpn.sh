#!/bin/sh
###### Name von VPN_CA ###########
ca="CA_RW_VPN"
ca_exists="y"
####### Zertifikatseinstellungen für Proxy #########
bits="2048"
state="Deutschland"
location="Neuenhaus"
organization="maxbenedikt GmbH"
organization_unit="IT"
email="info@maxbenedikt.com"
############################################################
##Create new config
dtnow=$(date +"%m-%d-%Y_%T")
spcli system config save name "autovpn_$dtnow"

read -p "Ist eine CA für VPN vorhanden?:"$'\n' ca_exists

if [ "$ca_exists" = "n" ];then
    echo "CA wird erstellt"
    read -p "Name der CA:"$'\n' ca
    if [ -z "$ca" ];then
        echo "CA name can't be empty"
        exit 1
    fi
elif [ "$ca_exists" = "n" ];then
    read -p "Name der CA:"$'\n' ca
else
    echo "ungueltige Eingabe"
    exit 1
fi

ID=$(spcli cert get | awk 'BEGIN {FS = "|" }; {print $1 "\t" $2 "\t" $14}' |grep $ca | cut -f1 -d$'\t')
if [ -z "$ID" ];then
    echo "CA not found"
    exit 1
fi

input="x"
user=""
password=""
##rework?
while [ "true" = "true" ]; do
    read -n 1 -s -p "Soll ein VPN Benutzer hinzugefügt werden? (y/n):"$'\n' input

    if [ "$input" = "y" ];then

        while [ ${#user} -lt 4 ]; do
            read -p "Benutzername:"$'\n' user
        done

        while [ ${#password} -lt 6 ]; do
            read -s -p "Passwort (mindestens 6 Zeichen):"$'\n' password
        done

        if [ ${#user} -gt 3 ] && [ ${#password} -gt 5 ]; then
            ##echo "$password"
            echo -e "$user" '\t' "$password"
            spcli user new name "$user" password "$password"
            cn="CC_"$user
            spcli cert new bits $bits common_name "$cn" issuer_id "$ID" valid_since "2021-01-01-00-00-00" valid_till "2037-12-31-23-59-59" country "DE" state "$state" location "$location" organization "$organization" organization_unit "$organization_unit" email "$email" > /dev/null 2>&1 

            else
            echo "nope"
        fi
    else
        echo "Vorgang abgebrochen."
        break
    fi
fi
