#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# DnsPod (Tencent Cloud) DDNS script
# Usage: dnspod.sh -k LOGIN_TOKEN -s LOGIN_TOKEN_SECRET -z ZONE -h HOST -t A|AAAA

DNSPOD_TOKEN=""
DNSPOD_SECRET=""
DNSPOD_ZONE=""
DNSPOD_HOST=""
DNSPOD_TYPE="A"
DNSPOD_TTL="600"
DNSPOD_LINE="默认"

while getopts k:s:z:h:t:T:l: opts; do
    case ${opts} in
        k) DNSPOD_TOKEN=${OPTARG} ;;
        s) DNSPOD_SECRET=${OPTARG} ;;
        z) DNSPOD_ZONE=${OPTARG} ;;
        h) DNSPOD_HOST=${OPTARG} ;;
        t) DNSPOD_TYPE=${OPTARG} ;;
        T) DNSPOD_TTL=${OPTARG} ;;
        l) DNSPOD_LINE=${OPTARG} ;;
    esac
done

if [ -z "$DNSPOD_TOKEN" ]; then echo "Missing -k (login token)"; exit 2; fi
if [ -z "$DNSPOD_SECRET" ]; then echo "Missing -s (login secret)"; exit 2; fi
if [ -z "$DNSPOD_ZONE" ]; then echo "Missing -z (zone/domain)"; exit 2; fi
if [ -z "$DNSPOD_HOST" ]; then echo "Missing -h (subdomain)"; exit 2; fi

if [ "$DNSPOD_TYPE" = "AAAA" ]; then
    WAN_IP=$(curl -s "https://api6.ipify.org")
else
    WAN_IP=$(curl -s "https://api4.ipify.org")
fi

if [ -z "$WAN_IP" ]; then
    echo "Failed to get public IP"
    exit 1
fi

WAN_IP_FILE="$HOME/.dnspod-wan_ip_${DNSPOD_HOST}.${DNSPOD_ZONE}.txt"
OLD_WAN_IP=""
[ -f "$WAN_IP_FILE" ] && OLD_WAN_IP=$(cat "$WAN_IP_FILE")

if [ "$WAN_IP" = "$OLD_WAN_IP" ]; then
    echo "WAN IP unchanged ($WAN_IP)"
    exit 0
fi

LOGIN_TOKEN="${DNSPOD_TOKEN},${DNSPOD_SECRET}"

# Query existing records
RESPONSE=$(curl -s -X POST "https://dnsapi.cn/Record.List" \
    --data-urlencode "login_token=$LOGIN_TOKEN" \
    --data-urlencode "domain=$DNSPOD_ZONE" \
    --data-urlencode "sub_domain=$DNSPOD_HOST" \
    --data-urlencode "record_type=$DNSPOD_TYPE" \
    --data-urlencode "format=json")

RECORD_ID=$(echo "$RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -n "$RECORD_ID" ]; then
    RESPONSE=$(curl -s -X POST "https://dnsapi.cn/Record.Modify" \
        --data-urlencode "login_token=$LOGIN_TOKEN" \
        --data-urlencode "domain=$DNSPOD_ZONE" \
        --data-urlencode "sub_domain=$DNSPOD_HOST" \
        --data-urlencode "record_type=$DNSPOD_TYPE" \
        --data-urlencode "value=$WAN_IP" \
        --data-urlencode "ttl=$DNSPOD_TTL" \
        --data-urlencode "record_line=$DNSPOD_LINE" \
        --data-urlencode "record_id=$RECORD_ID" \
        --data-urlencode "format=json")
    echo "Updated $DNSPOD_HOST.$DNSPOD_ZONE to $WAN_IP"
else
    RESPONSE=$(curl -s -X POST "https://dnsapi.cn/Record.Create" \
        --data-urlencode "login_token=$LOGIN_TOKEN" \
        --data-urlencode "domain=$DNSPOD_ZONE" \
        --data-urlencode "sub_domain=$DNSPOD_HOST" \
        --data-urlencode "record_type=$DNSPOD_TYPE" \
        --data-urlencode "value=$WAN_IP" \
        --data-urlencode "ttl=$DNSPOD_TTL" \
        --data-urlencode "record_line=$DNSPOD_LINE" \
        --data-urlencode "format=json")
    echo "Created $DNSPOD_HOST.$DNSPOD_ZONE with $WAN_IP"
fi

echo "$WAN_IP" > "$WAN_IP_FILE"
