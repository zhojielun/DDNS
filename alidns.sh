#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Alibaba Cloud DNS (AliDNS) DDNS script
# Usage: alidns.sh -k ACCESS_KEY -s ACCESS_SECRET -z ZONE -h HOST -t A|AAAA

ALIDNS_ID=""
ALIDNS_SECRET=""
ALIDNS_ZONE=""
ALIDNS_HOST=""
ALIDNS_TYPE="A"
ALIDNS_TTL="600"

while getopts k:s:z:h:t:T: opts; do
    case ${opts} in
        k) ALIDNS_ID=${OPTARG} ;;
        s) ALIDNS_SECRET=${OPTARG} ;;
        z) ALIDNS_ZONE=${OPTARG} ;;
        h) ALIDNS_HOST=${OPTARG} ;;
        t) ALIDNS_TYPE=${OPTARG} ;;
        T) ALIDNS_TTL=${OPTARG} ;;
    esac
done

if [ -z "$ALIDNS_ID" ]; then echo "Missing -k (Access Key ID)"; exit 2; fi
if [ -z "$ALIDNS_SECRET" ]; then echo "Missing -s (Access Key Secret)"; exit 2; fi
if [ -z "$ALIDNS_ZONE" ]; then echo "Missing -z (zone/domain)"; exit 2; fi
if [ -z "$ALIDNS_HOST" ]; then echo "Missing -h (subdomain)"; exit 2; fi

# Get current IP
if [ "$ALIDNS_TYPE" = "AAAA" ]; then
    WAN_IP=$(curl -s "https://api6.ipify.org")
else
    WAN_IP=$(curl -s "https://api4.ipify.org")
fi

if [ -z "$WAN_IP" ]; then
    echo "Failed to get public IP"
    exit 1
fi

WAN_IP_FILE="$HOME/.alidns-wan_ip_${ALIDNS_HOST}.${ALIDNS_ZONE}.txt"
OLD_WAN_IP=""
[ -f "$WAN_IP_FILE" ] && OLD_WAN_IP=$(cat "$WAN_IP_FILE")

if [ "$WAN_IP" = "$OLD_WAN_IP" ]; then
    echo "WAN IP unchanged ($WAN_IP)"
    exit 0
fi

# AliDNS API signing function
ali_sign() {
    local params="$1"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local nonce=$(date +%s%N | cut -c1-19)

    # Build sorted query string
    local sorted_params=$(echo "$params&Timestamp=$timestamp&Format=JSON&Version=2015-01-09&SignatureMethod=HMAC-SHA1&SignatureNonce=$nonce&SignatureVersion=1.0&AccessKeyId=$ALIDNS_ID&Action=$2" | tr '&' '\n' | sort | tr '\n' '&' | sed 's/&$//')

    # URL encode
    local encoded_params=$(echo "$sorted_params" | sed 's/ /+/g' | sed 's/:/%3A/g')

    # Create signature
    local string_to_sign="GET&%2F&$(python3 -c "import urllib.parse; print(urllib.parse.quote('$encoded_params', safe=''))")"
    local signature=$(echo -n "$string_to_sign" | openssl dgst -sha1 -hmac "${ALIDNS_SECRET}&" -binary | base64)

    echo "$sorted_params&Signature=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$signature', safe=''))")"
}

# Query existing records
ACTION="DescribeSubDomainRecords"
QUERY="SubDomain=$ALIDNS_HOST&DomainName=$ALIDNS_ZONE&Type=$ALIDNS_TYPE"
SIGNED_QUERY=$(ali_sign "$QUERY" "$ACTION")

RESPONSE=$(curl -s "https://alidns.aliyuncs.com/?$SIGNED_QUERY")

RECORD_ID=$(echo "$RESPONSE" | grep -o '"RecordID":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -n "$RECORD_ID" ]; then
    # Update existing record
    ACTION="UpdateDomainRecord"
    QUERY="RecordId=$RECORD_ID&RR=$ALIDNS_HOST&Type=$ALIDNS_TYPE&Value=$WAN_IP&TTL=$ALIDNS_TTL"
    SIGNED_QUERY=$(ali_sign "$QUERY" "$ACTION")
    RESPONSE=$(curl -s "https://alidns.aliyuncs.com/?$SIGNED_QUERY")
    echo "Updated $ALIDNS_HOST.$ALIDNS_ZONE to $WAN_IP"
else
    # Create new record
    ACTION="AddDomainRecord"
    QUERY="DomainName=$ALIDNS_ZONE&RR=$ALIDNS_HOST&Type=$ALIDNS_TYPE&Value=$WAN_IP&TTL=$ALIDNS_TTL"
    SIGNED_QUERY=$(ali_sign "$QUERY" "$ACTION")
    RESPONSE=$(curl -s "https://alidns.aliyuncs.com/?$SIGNED_QUERY")
    echo "Created $ALIDNS_HOST.$ALIDNS_ZONE with $WAN_IP"
fi

echo "$WAN_IP" > "$WAN_IP_FILE"
