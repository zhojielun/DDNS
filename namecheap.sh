#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Namecheap DDNS script (IPv4 only)
# Usage: namecheap.sh -k HOST -s PASSWORD -z ZONE -h HOST

NC_HOST=""
NC_PASSWORD=""
NC_ZONE=""
NC_HOSTNAME=""

while getopts k:s:z:h: opts; do
    case ${opts} in
        k) NC_HOST=${OPTARG} ;;
        s) NC_PASSWORD=${OPTARG} ;;
        z) NC_ZONE=${OPTARG} ;;
        h) NC_HOSTNAME=${OPTARG} ;;
    esac
done

if [ -z "$NC_HOST" ]; then echo "Missing -k (host)"; exit 2; fi
if [ -z "$NC_PASSWORD" ]; then echo "Missing -s (Dynamic DNS password)"; exit 2; fi
if [ -z "$NC_ZONE" ]; then echo "Missing -z (zone/domain)"; exit 2; fi
if [ -z "$NC_HOSTNAME" ]; then echo "Missing -h (hostname)"; exit 2; fi

# Namecheap only supports IPv4
WAN_IP=$(curl -s "https://api4.ipify.org")

if [ -z "$WAN_IP" ]; then
    echo "Failed to get public IP"
    exit 1
fi

WAN_IP_FILE="$HOME/.namecheap-wan_ip_${NC_HOSTNAME}.${NC_ZONE}.txt"
OLD_WAN_IP=""
[ -f "$WAN_IP_FILE" ] && OLD_WAN_IP=$(cat "$WAN_IP_FILE")

if [ "$WAN_IP" = "$OLD_WAN_IP" ]; then
    echo "WAN IP unchanged ($WAN_IP)"
    exit 0
fi

RESPONSE=$(curl -s "https://dynamicdns.park-your-domain.com/update?host=${NC_HOST}&domain=${NC_ZONE}&password=${NC_PASSWORD}&ip=${WAN_IP}")

if echo "$RESPONSE" | grep -q "<ErrCount>0</ErrCount>"; then
    echo "$WAN_IP" > "$WAN_IP_FILE"
    echo "Updated $NC_HOST.$NC_ZONE to $WAN_IP"
else
    echo "Update failed: $RESPONSE"
    exit 1
fi
