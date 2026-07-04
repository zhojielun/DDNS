#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Spaceship DDNS script
# Usage: spaceship.sh -k API_KEY -s API_SECRET -z ZONE -h HOST -t A|AAAA

SP_KEY=""
SP_SECRET=""
SP_ZONE=""
SP_HOST=""
SP_TYPE="A"
SP_TTL="600"

while getopts k:s:z:h:t:T: opts; do
    case ${opts} in
        k) SP_KEY=${OPTARG} ;;
        s) SP_SECRET=${OPTARG} ;;
        z) SP_ZONE=${OPTARG} ;;
        h) SP_HOST=${OPTARG} ;;
        t) SP_TYPE=${OPTARG} ;;
        T) SP_TTL=${OPTARG} ;;
    esac
done

if [ -z "$SP_KEY" ]; then echo "Missing -k (API Key)"; exit 2; fi
if [ -z "$SP_SECRET" ]; then echo "Missing -s (API Secret)"; exit 2; fi
if [ -z "$SP_ZONE" ]; then echo "Missing -z (zone/domain)"; exit 2; fi
if [ -z "$SP_HOST" ]; then echo "Missing -h (subdomain)"; exit 2; fi

if [ "$SP_TYPE" = "AAAA" ]; then
    WAN_IP=$(curl -s "https://api6.ipify.org")
else
    WAN_IP=$(curl -s "https://api4.ipify.org")
fi

if [ -z "$WAN_IP" ]; then
    echo "Failed to get public IP"
    exit 1
fi

WAN_IP_FILE="$HOME/.spaceship-wan_ip_${SP_HOST}.${SP_ZONE}.txt"
OLD_WAN_IP=""
[ -f "$WAN_IP_FILE" ] && OLD_WAN_IP=$(cat "$WAN_IP_FILE")

if [ "$WAN_IP" = "$OLD_WAN_IP" ]; then
    echo "WAN IP unchanged ($WAN_IP)"
    exit 0
fi

# Get existing records
RECORDS=$(curl -s -H "X-API-Key: ${SP_KEY}" -H "X-API-Secret: ${SP_SECRET}" \
    "https://spaceship.dev/api/v1/dns/records/${SP_ZONE}?take=500&skip=0")

EXISTING_IP=$(echo "$RECORDS" | grep -o "\"type\":\"${SP_TYPE}\"" -A10 | grep -o "\"address\":\"[^\"]*\"" | head -1 | cut -d'"' -f4)

if [ -n "$EXISTING_IP" ] && [ "$EXISTING_IP" = "$WAN_IP" ]; then
    echo "WAN IP unchanged ($WAN_IP)"
    echo "$WAN_IP" > "$WAN_IP_FILE"
    exit 0
fi

# Delete existing records of this type (using jq or grep)
if [ -n "$EXISTING_IP" ]; then
    # Try to extract record names and types using grep
    DELETE_PAYLOAD="["
    FIRST=true
    while IFS= read -r line; do
        ITEM_NAME=$(echo "$line" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
        ITEM_TYPE=$(echo "$line" | grep -o '"type":"[^"]*"' | cut -d'"' -f4)
        ITEM_ADDR=$(echo "$line" | grep -o '"address":"[^"]*"' | cut -d'"' -f4)
        if [ "$ITEM_TYPE" = "$SP_TYPE" ] && [ "$ITEM_NAME" = "$SP_HOST" ]; then
            if [ "$FIRST" = true ]; then
                FIRST=false
            else
                DELETE_PAYLOAD+=","
            fi
            DELETE_PAYLOAD+="{\"type\":\"${ITEM_TYPE}\",\"address\":\"${ITEM_ADDR}\",\"name\":\"${ITEM_NAME}\"}"
        fi
    done <<< "$(echo "$RECORDS" | grep -o '{[^}]*"type":"[^"]*"[^}]*}')"
    DELETE_PAYLOAD+="]"
    
    if [ "$DELETE_PAYLOAD" != "[]" ]; then
        curl -s -X DELETE -H "X-API-Key: ${SP_KEY}" -H "X-API-Secret: ${SP_SECRET}" -H "Content-Type: application/json" \
            "https://spaceship.dev/api/v1/dns/records/${SP_ZONE}" \
            --data "$DELETE_PAYLOAD" > /dev/null
    fi
fi

# Create new record
CREATE_PAYLOAD="{\"force\":true,\"items\":[{\"type\":\"${SP_TYPE}\",\"address\":\"${WAN_IP}\",\"name\":\"${SP_HOST}\",\"ttl\":${SP_TTL}}]}"

curl -s -X PUT -H "X-API-Key: ${SP_KEY}" -H "X-API-Secret: ${SP_SECRET}" -H "Content-Type: application/json" \
    "https://spaceship.dev/api/v1/dns/records/${SP_ZONE}" \
    --data "$CREATE_PAYLOAD" > /dev/null

echo "$WAN_IP" > "$WAN_IP_FILE"
echo "Updated $SP_HOST.$SP_ZONE to $WAN_IP"
