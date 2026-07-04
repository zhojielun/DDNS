#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Callback DDNS script
# Usage: callback.sh -u URL -s POST_BODY -z ZONE -h HOST -t A|AAAA -T TTL

CB_URL=""
CB_POST=""
CB_ZONE=""
CB_HOST=""
CB_TYPE="A"
CB_TTL="600"

while getopts u:s:z:h:t:T: opts; do
    case ${opts} in
        u) CB_URL=${OPTARG} ;;
        s) CB_POST=${OPTARG} ;;
        z) CB_ZONE=${OPTARG} ;;
        h) CB_HOST=${OPTARG} ;;
        t) CB_TYPE=${OPTARG} ;;
        T) CB_TTL=${OPTARG} ;;
    esac
done

if [ -z "$CB_URL" ]; then echo "Missing -u (callback URL)"; exit 2; fi
if [ -z "$CB_ZONE" ]; then echo "Missing -z (zone/domain)"; exit 2; fi
if [ -z "$CB_HOST" ]; then echo "Missing -h (subdomain)"; exit 2; fi

if [ "$CB_TYPE" = "AAAA" ]; then
    WAN_IP=$(curl -s "https://api6.ipify.org")
else
    WAN_IP=$(curl -s "https://api4.ipify.org")
fi

if [ -z "$WAN_IP" ]; then
    echo "Failed to get public IP"
    exit 1
fi

# Build domain string
if [ "$CB_HOST" = "@" ] || [ -z "$CB_HOST" ]; then
    FULL_DOMAIN="$CB_ZONE"
else
    FULL_DOMAIN="${CB_HOST}.${CB_ZONE}"
fi

# Replace placeholders
TIMESTAMP=$(date +%s)
REQUEST_URL=$(echo "$CB_URL" | sed \
    -e "s/#{ip}/${WAN_IP}/g" \
    -e "s/#{domain}/${FULL_DOMAIN}/g" \
    -e "s/#{recordType}/${CB_TYPE}/g" \
    -e "s/#{ttl}/${CB_TTL}/g" \
    -e "s/#{timestamp}/${TIMESTAMP}/g")

if [ -n "$CB_POST" ]; then
    # POST request
    POST_BODY=$(echo "$CB_POST" | sed \
        -e "s/#{ip}/${WAN_IP}/g" \
        -e "s/#{domain}/${FULL_DOMAIN}/g" \
        -e "s/#{recordType}/${CB_TYPE}/g" \
        -e "s/#{ttl}/${CB_TTL}/g" \
        -e "s/#{timestamp}/${TIMESTAMP}/g")
    
    # Check if body is JSON
    if echo "$POST_BODY" | grep -q '^{' 2>/dev/null; then
        curl -s -X POST "$REQUEST_URL" -H "Content-Type: application/json" --data "$POST_BODY"
    else
        curl -s -X POST "$REQUEST_URL" -d "$POST_BODY"
    fi
else
    # GET request
    curl -s "$REQUEST_URL"
fi

echo "Callback executed for $FULL_DOMAIN with IP $WAN_IP"
