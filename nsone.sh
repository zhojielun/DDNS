#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# NS1 (IBM) DDNS script
# Usage: nsone.sh -s API_KEY -z ZONE -h HOST -t A|AAAA

NS1_KEY=""
NS1_ZONE=""
NS1_HOST=""
NS1_TYPE="A"
NS1_TTL="3600"

while getopts s:z:h:t:T: opts; do
    case ${opts} in
        s) NS1_KEY=${OPTARG} ;;
        z) NS1_ZONE=${OPTARG} ;;
        h) NS1_HOST=${OPTARG} ;;
        t) NS1_TYPE=${OPTARG} ;;
        T) NS1_TTL=${OPTARG} ;;
    esac
done

if [ -z "$NS1_KEY" ]; then echo "Missing -s (API Key)"; exit 2; fi
if [ -z "$NS1_ZONE" ]; then echo "Missing -z (zone/domain)"; exit 2; fi
if [ -z "$NS1_HOST" ]; then echo "Missing -h (subdomain)"; exit 2; fi

if [ "$NS1_TYPE" = "AAAA" ]; then
    WAN_IP=$(curl -s "https://api6.ipify.org")
else
    WAN_IP=$(curl -s "https://api4.ipify.org")
fi

if [ -z "$WAN_IP" ]; then
    echo "Failed to get public IP"
    exit 1
fi

WAN_IP_FILE="$HOME/.ns1-wan_ip_${NS1_HOST}.${NS1_ZONE}.txt"
OLD_WAN_IP=""
[ -f "$WAN_IP_FILE" ] && OLD_WAN_IP=$(cat "$WAN_IP_FILE")

if [ "$WAN_IP" = "$OLD_WAN_IP" ]; then
    echo "WAN IP unchanged ($WAN_IP)"
    exit 0
fi

# Build record name
if [ "$NS1_HOST" = "@" ] || [ -z "$NS1_HOST" ]; then
    RECORD_NAME="$NS1_ZONE"
else
    RECORD_NAME="${NS1_HOST}.${NS1_ZONE}"
fi

# Check if record exists
EXISTING=$(curl -s -H "X-NSONE-Key: ${NS1_KEY}" -H "Content-Type: application/json" \
    "https://api.nsone.net/v1/zones/${NS1_ZONE}/${RECORD_NAME}/${NS1_TYPE}?records=false" 2>/dev/null)

ANSWERS=$(echo "$EXISTING" | grep -o '"answers":\[' | head -1)

if [ -n "$ANSWERS" ]; then
    # Update existing record
    RESPONSE=$(curl -s -X POST -H "X-NSONE-Key: ${NS1_KEY}" -H "Content-Type: application/json" \
        "https://api.nsone.net/v1/zones/${NS1_ZONE}/${RECORD_NAME}/${NS1_TYPE}" \
        --data "{\"answers\":[{\"answer\":[\"${WAN_IP}\"]}],\"domain\":\"${RECORD_NAME}\",\"ttl\":${NS1_TTL},\"type\":\"${NS1_TYPE}\",\"zone\":\"${NS1_ZONE}\"}")
    echo "Updated $NS1_HOST.$NS1_ZONE to $WAN_IP"
else
    # Create new record
    RESPONSE=$(curl -s -X PUT -H "X-NSONE-Key: ${NS1_KEY}" -H "Content-Type: application/json" \
        "https://api.nsone.net/v1/zones/${NS1_ZONE}/${RECORD_NAME}/${NS1_TYPE}" \
        --data "{\"answers\":[{\"answer\":[\"${WAN_IP}\"]}],\"domain\":\"${RECORD_NAME}\",\"ttl\":${NS1_TTL},\"type\":\"${NS1_TYPE}\",\"zone\":\"${NS1_ZONE}\"}")
    echo "Created $NS1_HOST.$NS1_ZONE with $WAN_IP"
fi

echo "$WAN_IP" > "$WAN_IP_FILE"
