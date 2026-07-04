#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# DNSLA DDNS script
# Usage: dnsla.sh -k ACCESS_KEY -s ACCESS_SECRET -z ZONE -h HOST -t A|AAAA

DLA_KEY=""
DLA_SECRET=""
DLA_ZONE=""
DLA_HOST=""
DLA_TYPE="A"
DLA_TTL="600"

while getopts k:s:z:h:t:T: opts; do
    case ${opts} in
        k) DLA_KEY=${OPTARG} ;;
        s) DLA_SECRET=${OPTARG} ;;
        z) DLA_ZONE=${OPTARG} ;;
        h) DLA_HOST=${OPTARG} ;;
        t) DLA_TYPE=${OPTARG} ;;
        T) DLA_TTL=${OPTARG} ;;
    esac
done

if [ -z "$DLA_KEY" ]; then echo "Missing -k (Access Key)"; exit 2; fi
if [ -z "$DLA_SECRET" ]; then echo "Missing -s (Access Secret)"; exit 2; fi
if [ -z "$DLA_ZONE" ]; then echo "Missing -z (zone/domain)"; exit 2; fi
if [ -z "$DLA_HOST" ]; then echo "Missing -h (subdomain)"; exit 2; fi

if [ "$DLA_TYPE" = "AAAA" ]; then
    WAN_IP=$(curl -s "https://api6.ipify.org")
    RECORD_TYPE_INT="28"
else
    WAN_IP=$(curl -s "https://api4.ipify.org")
    RECORD_TYPE_INT="1"
fi

if [ -z "$WAN_IP" ]; then
    echo "Failed to get public IP"
    exit 1
fi

WAN_IP_FILE="$HOME/.dnsla-wan_ip_${DLA_HOST}.${DLA_ZONE}.txt"
OLD_WAN_IP=""
[ -f "$WAN_IP_FILE" ] && OLD_WAN_IP=$(cat "$WAN_IP_FILE")

if [ "$WAN_IP" = "$OLD_WAN_IP" ]; then
    echo "WAN IP unchanged ($WAN_IP)"
    exit 0
fi

AUTH="Basic $(echo -n "${DLA_KEY}:${DLA_SECRET}" | base64)"

# Query existing records
RECORDS=$(curl -s -H "Authorization: ${AUTH}" \
    "http://api.dns.la/api/recordList?domain=${DLA_ZONE}&host=${DLA_HOST}&type=${RECORD_TYPE_INT}&pageIndex=1&pageSize=999")

RECORD_ID=$(echo "$RECORDS" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -n "$RECORD_ID" ]; then
    # Update existing record
    RESPONSE=$(curl -s -X PUT -H "Authorization: ${AUTH}" -H "Content-Type: application/json;charset=utf-8" \
        "http://api.dns.la/api/record" \
        --data "{\"Id\":\"${RECORD_ID}\",\"Host\":\"${DLA_HOST}\",\"Type\":${RECORD_TYPE_INT},\"Data\":\"${WAN_IP}\",\"TTL\":${DLA_TTL}}")
    echo "Updated $DLA_HOST.$DLA_ZONE to $WAN_IP"
else
    # Create new record
    RESPONSE=$(curl -s -X POST -H "Authorization: ${AUTH}" -H "Content-Type: application/json;charset=utf-8" \
        "http://api.dns.la/api/record" \
        --data "{\"Domain\":\"${DLA_ZONE}\",\"Host\":\"${DLA_HOST}\",\"Type\":${RECORD_TYPE_INT},\"Data\":\"${WAN_IP}\",\"TTL\":${DLA_TTL}}")
    echo "Created $DLA_HOST.$DLA_ZONE with $WAN_IP"
fi

echo "$WAN_IP" > "$WAN_IP_FILE"
