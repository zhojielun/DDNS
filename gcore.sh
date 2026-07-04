#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Gcore DNS DDNS script
# Usage: gcore.sh -s API_TOKEN -z ZONE -h HOST -t A|AAAA

GC_TOKEN=""
GC_ZONE=""
GC_HOST=""
GC_TYPE="A"
GC_TTL="120"

while getopts s:z:h:t:T: opts; do
    case ${opts} in
        s) GC_TOKEN=${OPTARG} ;;
        z) GC_ZONE=${OPTARG} ;;
        h) GC_HOST=${OPTARG} ;;
        t) GC_TYPE=${OPTARG} ;;
        T) GC_TTL=${OPTARG} ;;
    esac
done

if [ -z "$GC_TOKEN" ]; then echo "Missing -s (API Token)"; exit 2; fi
if [ -z "$GC_ZONE" ]; then echo "Missing -z (zone/domain)"; exit 2; fi
if [ -z "$GC_HOST" ]; then echo "Missing -h (subdomain)"; exit 2; fi

if [ "$GC_TYPE" = "AAAA" ]; then
    WAN_IP=$(curl -s "https://api6.ipify.org")
else
    WAN_IP=$(curl -s "https://api4.ipify.org")
fi

if [ -z "$WAN_IP" ]; then
    echo "Failed to get public IP"
    exit 1
fi

WAN_IP_FILE="$HOME/.gcore-wan_ip_${GC_HOST}.${GC_ZONE}.txt"
OLD_WAN_IP=""
[ -f "$WAN_IP_FILE" ] && OLD_WAN_IP=$(cat "$WAN_IP_FILE")

if [ "$WAN_IP" = "$OLD_WAN_IP" ]; then
    echo "WAN IP unchanged ($WAN_IP)"
    exit 0
fi

# Build record name
if [ "$GC_HOST" = "@" ] || [ -z "$GC_HOST" ]; then
    RECORD_NAME="$GC_ZONE"
else
    RECORD_NAME="${GC_HOST}.${GC_ZONE}"
fi

# Check if record exists
EXISTING=$(curl -s -H "Authorization: APIKey ${GC_TOKEN}" -H "Content-Type: application/json" \
    "https://api.gcore.com/dns/v2/zones/${GC_ZONE}/rrsets" 2>/dev/null)

RECORD_EXISTS=$(echo "$EXISTING" | grep -o "\"name\":\"${RECORD_NAME}\"" | head -1)

if [ -n "$RECORD_EXISTS" ]; then
    # Update existing record
    RESPONSE=$(curl -s -X PUT -H "Authorization: APIKey ${GC_TOKEN}" -H "Content-Type: application/json" \
        "https://api.gcore.com/dns/v2/zones/${GC_ZONE}/${RECORD_NAME}/${GC_TYPE}" \
        --data "{\"ttl\":${GC_TTL},\"resource_records\":[{\"content\":[\"${WAN_IP}\"],\"enabled\":true}]}")
    echo "Updated $GC_HOST.$GC_ZONE to $WAN_IP"
else
    # Create new record
    RESPONSE=$(curl -s -X POST -H "Authorization: APIKey ${GC_TOKEN}" -H "Content-Type: application/json" \
        "https://api.gcore.com/dns/v2/zones/${GC_ZONE}/${RECORD_NAME}/${GC_TYPE}" \
        --data "{\"ttl\":${GC_TTL},\"resource_records\":[{\"content\":[\"${WAN_IP}\"],\"enabled\":true}]}")
    echo "Created $GC_HOST.$GC_ZONE with $WAN_IP"
fi

echo "$WAN_IP" > "$WAN_IP_FILE"
