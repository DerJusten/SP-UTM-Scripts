#!/bin/sh
####### Zertifikatseinstellungen für Proxy #########
bits="2048"
state="Deutschland"
location="Neuenhaus"
organization="maxbenedikt GmbH"
organization_unit="IT"
email="info@maxbenedikt.com"
############################################################
ID="176"
CertName="CC_cx"
spcli cert new bits $bits common_name "$CertName" issuer_id "$ID" valid_since "2021-01-01-00-00-00" valid_till "2037-12-31-23-59-59" country "DE" state "$state" location "$location" organization "$organization" organization_unit "$organization_unit" email "$email"
