#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Porkbun DDNS script
# Usage: porkbun.sh -k API_KEY -s SECRET_KEY -z ZONE -h HOST -t A|AAAA

PB_KEY=""
PB_SECRET=""
PB_ZONE=""
PB_HOST=""
PB_TYPE="A"
PB_TTL="600"

while getopts k:s:z:h:t:T: opts; do
    case ${opts} in
        k) PB_KEY=${OPTARG} ;;
        s) PB_SECRET=${OPTARG} ;;
        z) PB_ZONE=${OPTARG} ;;
        h) PB_HOST=${OPTARG} ;;
        t) PB_TYPE=${OPTARG} ;;
        T) PB_TTL=${OPTARG} ;;
    esac
done

if [ -z "$PB_KEY" ]; then echo "Missing -k (API key)"; exit 2; fi
if [ -z "$PB_SECRET" ]; then echo "Missing -s (Secret API key)"; exit 2; fi
if [ -z "$PB_ZONE" ]; then echo "Missing -z (zone/domain)"; exit 2; fi
if [ -z "$PB_HOST" ]; then echo "Missing -h (subdomain)"; exit 2; fi

if [ "$PB_TYPE" = "AAAA" ]; then
    WAN_IP=$(curl -s "https://api6.ipify.org")
else
    WAN_IP=$(curl -s "https://api4.ipify.org")
fi

if [ -z "$WAN_IP" ]; then
    echo "Failed to get public IP"
    exit 1
fi

WAN_IP_FILE="$HOME/.porkbun-wan_ip_${PB_HOST}.${PB_ZONE}.txt"
OLD_WAN_IP=""
[ -f "$WAN_IP_FILE" ] && OLD_WAN_IP=$(cat "$WAN_IP_FILE")

if [ "$WAN_IP" = "$OLD_WAN_IP" ]; then
    echo "WAN IP unchanged ($WAN_IP)"
    exit 0
fi

# Query existing records
RESPONSE=$(curl -s -X POST "https://api.porkbun.com/api/json/v3/dns/retrieveByNameType/${PB_ZONE}/${PB_TYPE}/${PB_HOST}" \
    -H "Content-Type: application/json" \
    --data "{\"apikey\":\"$PB_KEY\",\"secretapikey\":\"$PB_SECRET\"}")

STATUS=$(echo "$RESPONSE" | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ "$STATUS" = "SUCCESS" ]; then
    RECORD_COUNT=$(echo "$RESPONSE" | grep -o '"records":\[' | wc -l)
    if [ "$RECORD_COUNT" -gt 0 ] && [ "$(echo "$RESPONSE" | grep -o '"records":\[\]' | wc -l)" -eq 0 ]; then
        # Update existing record
        RESPONSE=$(curl -s -X POST "https://api.porkbun.com/api/json/v3/dns/editByNameType/${PB_ZONE}/${PB_TYPE}/${PB_HOST}" \
            -H "Content-Type: application/json" \
            --data "{\"apikey\":\"$PB_KEY\",\"secretapikey\":\"$PB_SECRET\",\"content\":\"$WAN_IP\",\"ttl\":\"$PB_TTL\"}")
        echo "Updated $PB_HOST.$PB_ZONE to $WAN_IP"
    else
        # Create new record
        RESPONSE=$(curl -s -X POST "https://api.porkbun.com/api/json/v3/dns/create/${PB_ZONE}" \
            -H "Content-Type: application/json" \
            --data "{\"apikey\":\"$PB_KEY\",\"secretapikey\":\"$PB_SECRET\",\"name\":\"$PB_HOST\",\"type\":\"$PB_TYPE\",\"content\":\"$WAN_IP\",\"ttl\":\"$PB_TTL\"}")
        echo "Created $PB_HOST.$PB_ZONE with $WAN_IP"
    fi
else
    echo "Failed to query records: $RESPONSE"
    exit 1
fi

echo "$WAN_IP" > "$WAN_IP_FILE"
