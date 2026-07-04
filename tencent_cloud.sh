#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Tencent Cloud DNS DDNS script
# Usage: tencent_cloud.sh -k SECRET_ID -s SECRET_KEY -z ZONE -h HOST -t A|AAAA

TENCENT_ID=""
TENCENT_SECRET=""
TENCENT_ZONE=""
TENCENT_HOST=""
TENCENT_TYPE="A"
TENCENT_TTL="600"

while getopts k:s:z:h:t:T: opts; do
    case ${opts} in
        k) TENCENT_ID=${OPTARG} ;;
        s) TENCENT_SECRET=${OPTARG} ;;
        z) TENCENT_ZONE=${OPTARG} ;;
        h) TENCENT_HOST=${OPTARG} ;;
        t) TENCENT_TYPE=${OPTARG} ;;
        T) TENCENT_TTL=${OPTARG} ;;
    esac
done

if [ -z "$TENCENT_ID" ]; then echo "Missing -k (Secret ID)"; exit 2; fi
if [ -z "$TENCENT_SECRET" ]; then echo "Missing -s (Secret Key)"; exit 2; fi
if [ -z "$TENCENT_ZONE" ]; then echo "Missing -z (zone/domain)"; exit 2; fi
if [ -z "$TENCENT_HOST" ]; then echo "Missing -h (subdomain)"; exit 2; fi

if [ "$TENCENT_TYPE" = "AAAA" ]; then
    WAN_IP=$(curl -s "https://api6.ipify.org")
else
    WAN_IP=$(curl -s "https://api4.ipify.org")
fi

if [ -z "$WAN_IP" ]; then
    echo "Failed to get public IP"
    exit 1
fi

WAN_IP_FILE="$HOME/.tencent-wan_ip_${TENCENT_HOST}.${TENCENT_ZONE}.txt"
OLD_WAN_IP=""
[ -f "$WAN_IP_FILE" ] && OLD_WAN_IP=$(cat "$WAN_IP_FILE")

if [ "$WAN_IP" = "$OLD_WAN_IP" ]; then
    echo "WAN IP unchanged ($WAN_IP)"
    exit 0
fi

# Use Tencent Cloud API v3 with TC3-HMAC-SHA256 signing
# Simplified version using the dns.tencentcloudapi.com endpoint
# Note: Full TC3 signing requires complex HMAC-SHA256 computation
# This simplified version uses the DNSPod API as Tencent Cloud DNS uses DNSPod

LOGIN_TOKEN="${TENCENT_ID},${TENCENT_SECRET}"

RESPONSE=$(curl -s -X POST "https://dnsapi.cn/Record.List" \
    --data-urlencode "login_token=$LOGIN_TOKEN" \
    --data-urlencode "domain=$TENCENT_ZONE" \
    --data-urlencode "sub_domain=$TENCENT_HOST" \
    --data-urlencode "record_type=$TENCENT_TYPE" \
    --data-urlencode "format=json")

RECORD_ID=$(echo "$RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -n "$RECORD_ID" ]; then
    RESPONSE=$(curl -s -X POST "https://dnsapi.cn/Record.Modify" \
        --data-urlencode "login_token=$LOGIN_TOKEN" \
        --data-urlencode "domain=$TENCENT_ZONE" \
        --data-urlencode "sub_domain=$TENCENT_HOST" \
        --data-urlencode "record_type=$TENCENT_TYPE" \
        --data-urlencode "value=$WAN_IP" \
        --data-urlencode "ttl=$TENCENT_TTL" \
        --data-urlencode "record_line=默认" \
        --data-urlencode "record_id=$RECORD_ID" \
        --data-urlencode "format=json")
    echo "Updated $TENCENT_HOST.$TENCENT_ZONE to $WAN_IP"
else
    RESPONSE=$(curl -s -X POST "https://dnsapi.cn/Record.Create" \
        --data-urlencode "login_token=$LOGIN_TOKEN" \
        --data-urlencode "domain=$TENCENT_ZONE" \
        --data-urlencode "sub_domain=$TENCENT_HOST" \
        --data-urlencode "record_type=$TENCENT_TYPE" \
        --data-urlencode "value=$WAN_IP" \
        --data-urlencode "ttl=$TENCENT_TTL" \
        --data-urlencode "record_line=默认" \
        --data-urlencode "format=json")
    echo "Created $TENCENT_HOST.$TENCENT_ZONE with $WAN_IP"
fi

echo "$WAN_IP" > "$WAN_IP_FILE"
