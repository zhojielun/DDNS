#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# ClouDNS DDNS script
# Usage: cloudns.sh -k AUTH_ID -s AUTH_PASSWORD -z ZONE -h HOST -t A|AAAA

CL_ID=""
CL_SECRET=""
CL_ZONE=""
CL_HOST=""
CL_TYPE="A"
CL_TTL="3600"

while getopts k:s:z:h:t:T: opts; do
    case ${opts} in
        k) CL_ID=${OPTARG} ;;
        s) CL_SECRET=${OPTARG} ;;
        z) CL_ZONE=${OPTARG} ;;
        h) CL_HOST=${OPTARG} ;;
        t) CL_TYPE=${OPTARG} ;;
        T) CL_TTL=${OPTARG} ;;
    esac
done

if [ -z "$CL_ID" ]; then echo "Missing -k (Auth ID)"; exit 2; fi
if [ -z "$CL_SECRET" ]; then echo "Missing -s (Auth Password)"; exit 2; fi
if [ -z "$CL_ZONE" ]; then echo "Missing -z (zone/domain)"; exit 2; fi
if [ -z "$CL_HOST" ]; then echo "Missing -h (subdomain)"; exit 2; fi

if [ "$CL_TYPE" = "AAAA" ]; then
    WAN_IP=$(curl -s "https://api6.ipify.org")
else
    WAN_IP=$(curl -s "https://api4.ipify.org")
fi

if [ -z "$WAN_IP" ]; then
    echo "Failed to get public IP"
    exit 1
fi

WAN_IP_FILE="$HOME/.cloudns-wan_ip_${CL_HOST}.${CL_ZONE}.txt"
OLD_WAN_IP=""
[ -f "$WAN_IP_FILE" ] && OLD_WAN_IP=$(cat "$WAN_IP_FILE")

if [ "$WAN_IP" = "$OLD_WAN_IP" ]; then
    echo "WAN IP unchanged ($WAN_IP)"
    exit 0
fi

# Query existing records
RECORDS=$(curl -s -X POST "https://api.cloudns.net/dns/records.json" \
    --data-urlencode "auth-id=${CL_ID}" \
    --data-urlencode "auth-password=${CL_SECRET}" \
    --data-urlencode "domain-name=${CL_ZONE}" \
    --data-urlencode "host=${CL_HOST}" \
    --data-urlencode "type=${CL_TYPE}")

RECORD_ID=$(echo "$RECORDS" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -n "$RECORD_ID" ]; then
    # Update existing record
    RESPONSE=$(curl -s -X POST "https://api.cloudns.net/dns/modify-record.json" \
        --data-urlencode "auth-id=${CL_ID}" \
        --data-urlencode "auth-password=${CL_SECRET}" \
        --data-urlencode "domain-name=${CL_ZONE}" \
        --data-urlencode "record-id=${RECORD_ID}" \
        --data-urlencode "host=${CL_HOST}" \
        --data-urlencode "record=${WAN_IP}" \
        --data-urlencode "ttl=${CL_TTL}")
    echo "Updated $CL_HOST.$CL_ZONE to $WAN_IP"
else
    # Create new record
    RESPONSE=$(curl -s -X POST "https://api.cloudns.net/dns/add-record.json" \
        --data-urlencode "auth-id=${CL_ID}" \
        --data-urlencode "auth-password=${CL_SECRET}" \
        --data-urlencode "domain-name=${CL_ZONE}" \
        --data-urlencode "host=${CL_HOST}" \
        --data-urlencode "type=${CL_TYPE}" \
        --data-urlencode "record=${WAN_IP}" \
        --data-urlencode "ttl=${CL_TTL}")
    echo "Created $CL_HOST.$CL_ZONE with $WAN_IP"
fi

if echo "$RESPONSE" | grep -q '"status":"Success"'; then
    echo "$WAN_IP" > "$WAN_IP_FILE"
else
    echo "Failed: $RESPONSE"
    exit 1
fi
