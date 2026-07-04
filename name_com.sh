#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Name.com DDNS script
# Usage: name_com.sh -k USERNAME -s API_TOKEN -z ZONE -h HOST -t A|AAAA

NC_USER=""
NC_TOKEN=""
NC_ZONE=""
NC_HOST=""
NC_TYPE="A"
NC_TTL="300"

while getopts k:s:z:h:t:T: opts; do
    case ${opts} in
        k) NC_USER=${OPTARG} ;;
        s) NC_TOKEN=${OPTARG} ;;
        z) NC_ZONE=${OPTARG} ;;
        h) NC_HOST=${OPTARG} ;;
        t) NC_TYPE=${OPTARG} ;;
        T) NC_TTL=${OPTARG} ;;
    esac
done

if [ -z "$NC_USER" ]; then echo "Missing -k (Username)"; exit 2; fi
if [ -z "$NC_TOKEN" ]; then echo "Missing -s (API Token)"; exit 2; fi
if [ -z "$NC_ZONE" ]; then echo "Missing -z (zone/domain)"; exit 2; fi
if [ -z "$NC_HOST" ]; then echo "Missing -h (subdomain)"; exit 2; fi

if [ "$NC_TYPE" = "AAAA" ]; then
    WAN_IP=$(curl -s "https://api6.ipify.org")
else
    WAN_IP=$(curl -s "https://api4.ipify.org")
fi

if [ -z "$WAN_IP" ]; then
    echo "Failed to get public IP"
    exit 1
fi

WAN_IP_FILE="$HOME/.namecom-wan_ip_${NC_HOST}.${NC_ZONE}.txt"
OLD_WAN_IP=""
[ -f "$WAN_IP_FILE" ] && OLD_WAN_IP=$(cat "$WAN_IP_FILE")

if [ "$WAN_IP" = "$OLD_WAN_IP" ]; then
    echo "WAN IP unchanged ($WAN_IP)"
    exit 0
fi

AUTH="Basic $(echo -n "${NC_USER}:${NC_TOKEN}" | base64)"

# Get existing records
RECORDS=$(curl -s -H "Authorization: ${AUTH}" "https://api.name.com/core/v1/domains/${NC_ZONE}/records")

RECORD_ID=$(echo "$RECORDS" | grep -o "\"host\":\"${NC_HOST}\"" -B5 | grep -o "\"id\":[0-9]*" | head -1 | cut -d: -f2)

if [ -n "$RECORD_ID" ]; then
    # Update existing record
    RESPONSE=$(curl -s -X PUT -H "Authorization: ${AUTH}" -H "Content-Type: application/json" \
        "https://api.name.com/core/v1/domains/${NC_ZONE}/records/${RECORD_ID}" \
        --data "{\"type\":\"${NC_TYPE}\",\"answer\":\"${WAN_IP}\",\"ttl\":${NC_TTL},\"host\":\"${NC_HOST}\"}")
    echo "Updated $NC_HOST.$NC_ZONE to $WAN_IP"
else
    # Create new record
    RESPONSE=$(curl -s -X POST -H "Authorization: ${AUTH}" -H "Content-Type: application/json" \
        "https://api.name.com/core/v1/domains/${NC_ZONE}/records" \
        --data "{\"type\":\"${NC_TYPE}\",\"answer\":\"${WAN_IP}\",\"ttl\":${NC_TTL},\"host\":\"${NC_HOST}\"}")
    echo "Created $NC_HOST.$NC_ZONE with $WAN_IP"
fi

echo "$WAN_IP" > "$WAN_IP_FILE"
