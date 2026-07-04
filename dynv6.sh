#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Dynv6 DDNS script
# Usage: dynv6.sh -s TOKEN -z ZONE -h HOST -t A|AAAA

DV6_TOKEN=""
DV6_ZONE=""
DV6_HOST=""
DV6_TYPE="A"
DV6_TTL="600"

while getopts s:z:h:t:T: opts; do
    case ${opts} in
        s) DV6_TOKEN=${OPTARG} ;;
        z) DV6_ZONE=${OPTARG} ;;
        h) DV6_HOST=${OPTARG} ;;
        t) DV6_TYPE=${OPTARG} ;;
        T) DV6_TTL=${OPTARG} ;;
    esac
done

if [ -z "$DV6_TOKEN" ]; then echo "Missing -s (API token)"; exit 2; fi
if [ -z "$DV6_ZONE" ]; then echo "Missing -z (zone/domain)"; exit 2; fi
if [ -z "$DV6_HOST" ]; then echo "Missing -h (subdomain)"; exit 2; fi

if [ "$DV6_TYPE" = "AAAA" ]; then
    WAN_IP=$(curl -s "https://api6.ipify.org")
else
    WAN_IP=$(curl -s "https://api4.ipify.org")
fi

if [ -z "$WAN_IP" ]; then
    echo "Failed to get public IP"
    exit 1
fi

WAN_IP_FILE="$HOME/.dynv6-wan_ip_${DV6_HOST}.${DV6_ZONE}.txt"
OLD_WAN_IP=""
[ -f "$WAN_IP_FILE" ] && OLD_WAN_IP=$(cat "$WAN_IP_FILE")

if [ "$WAN_IP" = "$OLD_WAN_IP" ]; then
    echo "WAN IP unchanged ($WAN_IP)"
    exit 0
fi

# Get zones
ZONES=$(curl -s -H "Authorization: Bearer ${DV6_TOKEN}" "https://dynv6.com/api/v2/zones")
ZONE_ID=$(echo "$ZONES" | grep -o "\"id\":[0-9]*" | head -1 | cut -d: -f2)

if [ -z "$ZONE_ID" ]; then
    echo "Zone not found"
    exit 1
fi

# Check if this is the main domain
FULL_DOMAIN="${DV6_HOST}.${DV6_ZONE}"
if [ "$DV6_HOST" = "@" ] || [ "$DV6_HOST" = "" ]; then
    FULL_DOMAIN="$DV6_ZONE"
fi

# Try to find existing record by type and name
RECORDS=$(curl -s -H "Authorization: Bearer ${DV6_TOKEN}" "https://dynv6.com/api/v2/zones/${ZONE_ID}/records")
# Find record matching type and name
RECORD_ID=""
for record in $(echo "$RECORDS" | grep -o '{[^}]*}'); do
    R_NAME=$(echo "$record" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
    R_TYPE=$(echo "$record" | grep -o '"type":"[^"]*"' | cut -d'"' -f4)
    R_ID=$(echo "$record" | grep -o '"id":[0-9]*' | cut -d: -f2)
    if [ "$R_NAME" = "$DV6_HOST" ] && [ "$R_TYPE" = "$DV6_TYPE" ]; then
        RECORD_ID="$R_ID"
        break
    fi
done

if [ -n "$RECORD_ID" ]; then
    # Update existing record
    RESPONSE=$(curl -s -X PATCH -H "Authorization: Bearer ${DV6_TOKEN}" -H "Content-Type: application/json" \
        "https://dynv6.com/api/v2/zones/${ZONE_ID}/records/${RECORD_ID}" \
        --data "{\"type\":\"${DV6_TYPE}\",\"data\":\"${WAN_IP}\",\"name\":\"${DV6_HOST}\"}")
    echo "Updated $DV6_HOST.$DV6_ZONE to $WAN_IP"
else
    # Create new record
    RESPONSE=$(curl -s -X POST -H "Authorization: Bearer ${DV6_TOKEN}" -H "Content-Type: application/json" \
        "https://dynv6.com/api/v2/zones/${ZONE_ID}/records" \
        --data "{\"type\":\"${DV6_TYPE}\",\"data\":\"${WAN_IP}\",\"name\":\"${DV6_HOST}\"}")
    echo "Created $DV6_HOST.$DV6_ZONE with $WAN_IP"
fi

echo "$WAN_IP" > "$WAN_IP_FILE"
