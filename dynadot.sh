#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Dynadot DDNS script
# Usage: dynadot.sh -s PASSWORD -z ZONE -h HOST -t A|AAAA

DD_PASSWORD=""
DD_ZONE=""
DD_HOST=""
DD_TYPE="A"
DD_TTL="600"

while getopts s:z:h:t:T: opts; do
    case ${opts} in
        s) DD_PASSWORD=${OPTARG} ;;
        z) DD_ZONE=${OPTARG} ;;
        h) DD_HOST=${OPTARG} ;;
        t) DD_TYPE=${OPTARG} ;;
        T) DD_TTL=${OPTARG} ;;
    esac
done

if [ -z "$DD_PASSWORD" ]; then echo "Missing -s (Dynamic DNS password)"; exit 2; fi
if [ -z "$DD_ZONE" ]; then echo "Missing -z (zone/domain)"; exit 2; fi
if [ -z "$DD_HOST" ]; then echo "Missing -h (subdomain, comma separated for multiple)"; exit 2; fi

if [ "$DD_TYPE" = "AAAA" ]; then
    WAN_IP=$(curl -s "https://api6.ipify.org")
else
    WAN_IP=$(curl -s "https://api4.ipify.org")
fi

if [ -z "$WAN_IP" ]; then
    echo "Failed to get public IP"
    exit 1
fi

# Check if root domain should be included
CONTAIN_ROOT="false"
if [ "$DD_HOST" = "@" ] || [ "$DD_HOST" = "" ]; then
    CONTAIN_ROOT="true"
fi

RESPONSE=$(curl -s "https://www.dynadot.com/set_ddns?domain=${DD_ZONE}&subDomain=${DD_HOST}&type=${DD_TYPE}&ip=${WAN_IP}&pwd=${DD_PASSWORD}&ttl=${DD_TTL}&containRoot=${CONTAIN_ROOT}")

ERROR_CODE=$(echo "$RESPONSE" | grep -o '"error_code":[0-9-]*' | cut -d: -f2)

if [ "$ERROR_CODE" != "-1" ] && [ -n "$ERROR_CODE" ]; then
    echo "Updated $DD_HOST.$DD_ZONE to $WAN_IP"
    echo "$WAN_IP" > "$HOME/.dynadot-wan_ip_${DD_HOST}.${DD_ZONE}.txt"
else
    echo "Update failed: $RESPONSE"
    exit 1
fi
