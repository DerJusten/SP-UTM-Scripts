#!/bin/sh
## Set DDNS



## Set DHCP


##Create Backup of current Config
echo "Erstelle Current Config"
ConfigName=$(spcli system config get |grep CURRENT |awk 'BEGIN {FS = "|" }; {print $1}' | xargs )
spcli system config export name "$ConfigName"  > "/tmp/fw-tool/"$ConfigName".utm"