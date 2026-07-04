#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Rainyun DDNS script
# Usage: rainyun.sh -s API_KEY -z DOMAIN_ID -h HOST -t A|AAAA

RY_KEY=""
RY_DOMAIN=""
RY_HOST=""
RY_TYPE="A"
RY_TTL="600"

while getopts s:z:h:t:T: opts; do
    case ${opts} in
        s) RY_KEY=${OPTARG} ;;
        z) RY_DOMAIN=${OPTARG} ;;
        h) RY_HOST=${OPTARG} ;;
        t) RY_TYPE=${OPTARG} ;;
        T) RY_TTL=${OPTARG} ;;
    esac
done

if [ -z "$RY_KEY" ]; then echo "Missing -s (API Key)"; exit 2; fi
if [ -z "$RY_DOMAIN" ]; then echo "Missing -z (Domain ID)"; exit 2; fi
if [ -z "$RY_HOST" ]; then echo "Missing -h (subdomain)"; exit 2; fi

if [ "$RY_TYPE" = "AAAA" ]; then
    WAN_IP=$(curl -s "https://api6.ipify.org")
else
    WAN_IP=$(curl -s "https://api4.ipify.org")
fi

if [ -z "$WAN_IP" ]; then
    echo "Failed to get public IP"
    exit 1
fi

WAN_IP_FILE="$HOME/.rainyun-wan_ip_${RY_HOST}.${RY_DOMAIN}.txt"
OLD_WAN_IP=""
[ -f "$WAN_IP_FILE" ] && OLD_WAN_IP=$(cat "$WAN_IP_FILE")

if [ "$WAN_IP" = "$OLD_WAN_IP" ]; then
    echo "WAN IP unchanged ($WAN_IP)"
    exit 0
fi

# Get existing records
RECORDS=$(curl -s -H "x-api-key: ${RY_KEY}" \
    "https://api.v2.rainyun.com/product/domain/${RY_DOMAIN}/dns/?limit=100&page_no=1")

RECORD_ID=$(echo "$RECORDS" | grep -o "\"host\":\"${RY_HOST}\"" -B5 | grep -o "\"record_id\":[0-9]*" | head -1 | cut -d: -f2)

if [ -n "$RECORD_ID" ]; then
    # Update existing record
    RESPONSE=$(curl -s -X PATCH -H "x-api-key: ${RY_KEY}" -H "Content-Type: application/json" \
        "https://api.v2.rainyun.com/product/domain/${RY_DOMAIN}/dns" \
        --data "{\"host\":\"${RY_HOST}\",\"line\":\"DEFAULT\",\"level\":10,\"ttl\":${RY_TTL},\"type\":\"${RY_TYPE}\",\"value\":\"${WAN_IP}\",\"record_id\":${RECORD_ID}}")
    echo "Updated $RY_HOST.$RY_DOMAIN to $WAN_IP"
else
    # Create new record
    RESPONSE=$(curl -s -X POST -H "x-api-key: ${RY_KEY}" -H "Content-Type: application/json" \
        "https://api.v2.rainyun.com/product/domain/${RY_DOMAIN}/dns" \
        --data "{\"host\":\"${RY_HOST}\",\"line\":\"DEFAULT\",\"level\":10,\"ttl\":${RY_TTL},\"type\":\"${RY_TYPE}\",\"value\":\"${WAN_IP}\",\"record_id\":0}")
    echo "Created $RY_HOST.$RY_DOMAIN with $WAN_IP"
fi

echo "$WAN_IP" > "$WAN_IP_FILE"
