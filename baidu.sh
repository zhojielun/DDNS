#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Baidu Cloud DNS DDNS script (BCE auth v1 signing)
# Usage: baidu.sh -k ACCESS_KEY -s SECRET_KEY -z ZONE -h HOST -t A|AAAA

BD_KEY=""
BD_SECRET=""
BD_ZONE=""
BD_HOST=""
BD_TYPE="A"
BD_TTL="300"

while getopts k:s:z:h:t:T: opts; do
    case ${opts} in
        k) BD_KEY=${OPTARG} ;;
        s) BD_SECRET=${OPTARG} ;;
        z) BD_ZONE=${OPTARG} ;;
        h) BD_HOST=${OPTARG} ;;
        t) BD_TYPE=${OPTARG} ;;
        T) BD_TTL=${OPTARG} ;;
    esac
done

if [ -z "$BD_KEY" ]; then echo "Missing -k (Access Key)"; exit 2; fi
if [ -z "$BD_SECRET" ]; then echo "Missing -s (Secret Key)"; exit 2; fi
if [ -z "$BD_ZONE" ]; then echo "Missing -z (zone/domain)"; exit 2; fi
if [ -z "$BD_HOST" ]; then echo "Missing -h (subdomain)"; exit 2; fi

if [ "$BD_TYPE" = "AAAA" ]; then
    WAN_IP=$(curl -s "https://api6.ipify.org")
else
    WAN_IP=$(curl -s "https://api4.ipify.org")
fi

if [ -z "$WAN_IP" ]; then
    echo "Failed to get public IP"
    exit 1
fi

WAN_IP_FILE="$HOME/.baidu-wan_ip_${BD_HOST}.${BD_ZONE}.txt"
OLD_WAN_IP=""
[ -f "$WAN_IP_FILE" ] && OLD_WAN_IP=$(cat "$WAN_IP_FILE")

if [ "$WAN_IP" = "$OLD_WAN_IP" ]; then
    echo "WAN IP unchanged ($WAN_IP)"
    exit 0
fi

# HMAC-SHA256 hex function
hmac_sha256_hex() {
    echo -n "$2" | openssl dgst -sha256 -hmac "$1" | awk '{print $2}'
}

# Baidu Cloud signing
baidu_sign() {
    local method="$1"
    local path="$2"
    
    local date_str=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local auth_prefix="bce-auth-v1/${BD_KEY}/${date_str}/1800"
    
    local canonical_request="${method}\n${path}\n\nhost:bcd.baidubce.com"
    
    local signing_key=$(hmac_sha256_hex "$BD_SECRET" "$auth_prefix")
    local signature=$(hmac_sha256_hex "$signing_key" "$canonical_request")
    
    echo "${auth_prefix}/host/${signature}"
}

# Query existing records
AUTH_HEADER=$(baidu_sign "POST" "/v1/domain/resolve/list")

RESPONSE=$(curl -s -X POST "https://bcd.baidubce.com/v1/domain/resolve/list" \
    -H "Authorization: ${AUTH_HEADER}" \
    -H "Content-Type: application/json" \
    --data "{\"domain\":\"${BD_ZONE}\",\"pageNum\":1,\"pageSize\":1000}")

RECORD_ID=$(echo "$RESPONSE" | grep -o "\"domain\":\"${BD_HOST}\"" -B10 | grep -o '"recordId":[0-9]*' | head -1 | cut -d: -f2)

if [ -n "$RECORD_ID" ]; then
    # Update existing record
    AUTH_HEADER=$(baidu_sign "POST" "/v1/domain/resolve/edit")
    RESPONSE=$(curl -s -X POST "https://bcd.baidubce.com/v1/domain/resolve/edit" \
        -H "Authorization: ${AUTH_HEADER}" \
        -H "Content-Type: application/json" \
        --data "{\"recordId\":${RECORD_ID},\"domain\":\"${BD_HOST}\",\"rdType\":\"${BD_TYPE}\",\"ttl\":${BD_TTL},\"rdata\":\"${WAN_IP}\",\"zoneName\":\"${BD_ZONE}\"}")
    echo "Updated $BD_HOST.$BD_ZONE to $WAN_IP"
else
    # Create new record
    AUTH_HEADER=$(baidu_sign "POST" "/v1/domain/resolve/add")
    RESPONSE=$(curl -s -X POST "https://bcd.baidubce.com/v1/domain/resolve/add" \
        -H "Authorization: ${AUTH_HEADER}" \
        -H "Content-Type: application/json" \
        --data "{\"domain\":\"${BD_HOST}\",\"rdType\":\"${BD_TYPE}\",\"ttl\":${BD_TTL},\"rdata\":\"${WAN_IP}\",\"zoneName\":\"${BD_ZONE}\"}")
    echo "Created $BD_HOST.$BD_ZONE with $WAN_IP"
fi

echo "$WAN_IP" > "$WAN_IP_FILE"
