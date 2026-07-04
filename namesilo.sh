#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# NameSilo DDNS script
# Usage: namesilo.sh -s API_KEY -z ZONE -h HOST -t A|AAAA

NS_KEY=""
NS_ZONE=""
NS_HOST=""
NS_TYPE="A"
NS_TTL="3600"

while getopts s:z:h:t:T: opts; do
    case ${opts} in
        s) NS_KEY=${OPTARG} ;;
        z) NS_ZONE=${OPTARG} ;;
        h) NS_HOST=${OPTARG} ;;
        t) NS_TYPE=${OPTARG} ;;
        T) NS_TTL=${OPTARG} ;;
    esac
done

if [ -z "$NS_KEY" ]; then echo "Missing -s (API key)"; exit 2; fi
if [ -z "$NS_ZONE" ]; then echo "Missing -z (zone/domain)"; exit 2; fi
if [ -z "$NS_HOST" ]; then echo "Missing -h (subdomain)"; exit 2; fi

if [ "$NS_HOST" = "@" ]; then
    NS_HOST="www"
fi

if [ "$NS_TYPE" = "AAAA" ]; then
    WAN_IP=$(curl -s "https://api6.ipify.org")
else
    WAN_IP=$(curl -s "https://api4.ipify.org")
fi

if [ -z "$WAN_IP" ]; then
    echo "Failed to get public IP"
    exit 1
fi

WAN_IP_FILE="$HOME/.namesilo-wan_ip_${NS_HOST}.${NS_ZONE}.txt"
OLD_WAN_IP=""
[ -f "$WAN_IP_FILE" ] && OLD_WAN_IP=$(cat "$WAN_IP_FILE")

if [ "$WAN_IP" = "$OLD_WAN_IP" ]; then
    echo "WAN IP unchanged ($WAN_IP)"
    exit 0
fi

# List existing records
RECORDS=$(curl -s "https://www.namesilo.com/api/dnsListRecords?version=1&type=xml&key=${NS_KEY}&domain=${NS_ZONE}")

RECORD_ID=$(echo "$RECORDS" | grep -B5 "<host>${NS_HOST}</host>" | grep -o '<record_id>[^<]*</record_id>' | head -1 | sed 's/<[^>]*>//g')

if [ -n "$RECORD_ID" ]; then
    # Update existing record
    RESPONSE=$(curl -s "https://www.namesilo.com/api/dnsUpdateRecord?version=1&type=xml&key=${NS_KEY}&domain=${NS_ZONE}&rrhost=${NS_HOST}&rrid=${RECORD_ID}&rrvalue=${WAN_IP}&rrttl=${NS_TTL}")
    echo "Updated $NS_HOST.$NS_ZONE to $WAN_IP"
else
    # Create new record
    RESPONSE=$(curl -s "https://www.namesilo.com/api/dnsAddRecord?version=1&type=xml&key=${NS_KEY}&domain=${NS_ZONE}&rrhost=${NS_HOST}&rrtype=${NS_TYPE}&rrvalue=${WAN_IP}&rrttl=${NS_TTL}")
    echo "Created $NS_HOST.$NS_ZONE with $WAN_IP"
fi

if echo "$RESPONSE" | grep -q "<code>300</code>"; then
    echo "$WAN_IP" > "$WAN_IP_FILE"
    echo "Success"
else
    echo "Failed: $RESPONSE"
    exit 1
fi
