#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Eranet DDNS script (HMAC-SHA1 signing)
# Usage: eranet.sh -k ACCESS_KEY -s SECRET_KEY -z ZONE -h HOST -t A|AAAA

ER_KEY=""
ER_SECRET=""
ER_ZONE=""
ER_HOST=""
ER_TYPE="A"
ER_TTL="600"

while getopts k:s:z:h:t:T: opts; do
    case ${opts} in
        k) ER_KEY=${OPTARG} ;;
        s) ER_SECRET=${OPTARG} ;;
        z) ER_ZONE=${OPTARG} ;;
        h) ER_HOST=${OPTARG} ;;
        t) ER_TYPE=${OPTARG} ;;
        T) ER_TTL=${OPTARG} ;;
    esac
done

if [ -z "$ER_KEY" ]; then echo "Missing -k (Access Key)"; exit 2; fi
if [ -z "$ER_SECRET" ]; then echo "Missing -s (Secret Key)"; exit 2; fi
if [ -z "$ER_ZONE" ]; then echo "Missing -z (zone/domain)"; exit 2; fi
if [ -z "$ER_HOST" ]; then echo "Missing -h (subdomain)"; exit 2; fi

if [ "$ER_TYPE" = "AAAA" ]; then
    WAN_IP=$(curl -s "https://api6.ipify.org")
else
    WAN_IP=$(curl -s "https://api4.ipify.org")
fi

if [ -z "$WAN_IP" ]; then
    echo "Failed to get public IP"
    exit 1
fi

WAN_IP_FILE="$HOME/.eranet-wan_ip_${ER_HOST}.${ER_ZONE}.txt"
OLD_WAN_IP=""
[ -f "$WAN_IP_FILE" ] && OLD_WAN_IP=$(cat "$WAN_IP_FILE")

if [ "$WAN_IP" = "$OLD_WAN_IP" ]; then
    echo "WAN IP unchanged ($WAN_IP)"
    exit 0
fi

# URL percent encode (RFC 3986)
percent_encode() {
    local input="$1"
    local length=${#input}
    local encoded=""
    local i c
    
    for (( i=0; i<length; i++ )); do
        c="${input:$i:1}"
        case "$c" in
            [a-zA-Z0-9.~_-]) encoded+="$c" ;;
            ' ') encoded+="%20" ;;
            *) encoded+=$(printf '%%%02X' "'$c") ;;
        esac
    done
    echo "$encoded"
}

# HMAC-SHA1 signing (same as Aliyun)
eranet_sign() {
    local action="$1"
    local params="$2"
    local method="GET"
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local nonce=$(date +%s%N | cut -c1-19)
    
    # Add common parameters
    params="${params}&AccessInstanceID=${ER_KEY}&SignatureMethod=HMAC-SHA1&SignatureNonce=${nonce}&Timestamp=${timestamp}"
    
    # Sort parameters
    local sorted_params=$(echo "$params" | tr '&' '\n' | sort | tr '\n' '&' | sed 's/&$//')
    
    # Build string to sign
    local string_to_sign="${method}&$(percent_encode "/")&$(percent_encode "${sorted_params}")"
    
    # Calculate signature
    local signature=$(echo -n "$string_to_sign" | openssl dgst -sha1 -hmac "${ER_SECRET}&" -binary | base64)
    
    # Add signature to params
    local final_params="${sorted_params}&Signature=$(percent_encode "${signature}")"
    
    # Sort final params
    echo "$final_params" | tr '&' '\n' | sort | tr '\n' '&' | sed 's/&$//'
}

# Query existing records
QUERY_STRING=$(eranet_sign "DescribeRecordIndex" "Domain=${ER_ZONE}&Type=${ER_TYPE}&Host=${ER_HOST}")

RECORD_RESULT=$(curl -s "https://www.eranet.com/api/Dns/DescribeRecordIndex?${QUERY_STRING}")

RECORD_ID=$(echo "$RECORD_RESULT" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)

if [ -n "$RECORD_ID" ]; then
    # Update existing record
    QUERY_STRING=$(eranet_sign "UpdateDomainRecord" "Id=${RECORD_ID}&Domain=${ER_ZONE}&Host=${ER_HOST}&Type=${ER_TYPE}&Value=${WAN_IP}&Ttl=${ER_TTL}")
    RESPONSE=$(curl -s "https://www.eranet.com/api/Dns/UpdateDomainRecord?${QUERY_STRING}")
    echo "Updated $ER_HOST.$ER_ZONE to $WAN_IP"
else
    # Create new record
    QUERY_STRING=$(eranet_sign "AddDomainRecord" "Domain=${ER_ZONE}&Host=${ER_HOST}&Type=${ER_TYPE}&Value=${WAN_IP}&Ttl=${ER_TTL}")
    RESPONSE=$(curl -s "https://www.eranet.com/api/Dns/AddDomainRecord?${QUERY_STRING}")
    echo "Created $ER_HOST.$ER_ZONE with $WAN_IP"
fi

echo "$WAN_IP" > "$WAN_IP_FILE"
