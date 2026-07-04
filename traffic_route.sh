#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Traffic Route (Volcano Engine) DDNS script
# Usage: traffic_route.sh -k ACCESS_KEY -s SECRET_KEY -z ZONE -h HOST -t A|AAAA

TR_KEY=""
TR_SECRET=""
TR_ZONE=""
TR_HOST=""
TR_TYPE="A"
TR_TTL="600"

while getopts k:s:z:h:t:T: opts; do
    case ${opts} in
        k) TR_KEY=${OPTARG} ;;
        s) TR_SECRET=${OPTARG} ;;
        z) TR_ZONE=${OPTARG} ;;
        h) TR_HOST=${OPTARG} ;;
        t) TR_TYPE=${OPTARG} ;;
        T) TR_TTL=${OPTARG} ;;
    esac
done

if [ -z "$TR_KEY" ]; then echo "Missing -k (Access Key)"; exit 2; fi
if [ -z "$TR_SECRET" ]; then echo "Missing -s (Secret Key)"; exit 2; fi
if [ -z "$TR_ZONE" ]; then echo "Missing -z (zone/domain)"; exit 2; fi
if [ -z "$TR_HOST" ]; then echo "Missing -h (subdomain)"; exit 2; fi

if [ "$TR_TYPE" = "AAAA" ]; then
    WAN_IP=$(curl -s "https://api6.ipify.org")
else
    WAN_IP=$(curl -s "https://api4.ipify.org")
fi

if [ -z "$WAN_IP" ]; then
    echo "Failed to get public IP"
    exit 1
fi

WAN_IP_FILE="$HOME/.trafficroute-wan_ip_${TR_HOST}.${TR_ZONE}.txt"
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

# SHA256 hex function
sha256_hex() {
    echo -n "$1" | sha256sum | awk '{print $1}'
}

# Volcano Engine signing (similar to AWS Signature V4)
volcengine_sign() {
    local method="$1"
    local service="dns"
    local action="$2"
    local payload="$3"
    
    local timestamp=$(date +%s)
    local date_str=$(date -u -d "@${timestamp}" +"%Y%m%d")
    local datetime=$(date -u -d "@${timestamp}" +"%Y%m%dT%H%M%SZ")
    
    # Step 1: Build canonical request
    local canonical_uri="/"
    local canonical_query=""
    local content_type="application/json"
    local host="dns.volcengineapi.com"
    local canonical_headers="content-type:${content_type}\nhost:${host}\nx-content-sha256:$(sha256_hex "$payload")\nx-date:${datetime}\nx-tc-action:$(echo "$action" | tr '[:upper:]' '[:lower:]')\n"
    local signed_headers="content-type;host;x-content-sha256;x-date;x-tc-action"
    
    local canonical_request="${method}\n${canonical_uri}\n${canonical_query}\n${canonical_headers}\n${signed_headers}\n$(sha256_hex "$payload")"
    
    # Step 2: Build string to sign
    local credential_scope="${date_str}/${service}/request"
    local string_to_sign="HMAC-SHA256\n${datetime}\n${credential_scope}\n$(sha256_hex "$canonical_request")"
    
    # Step 3: Calculate signature
    local k_date=$(hmac_sha256_hex "HMAC-SHA256${TR_SECRET}" "$date_str")
    local k_service=$(hmac_sha256_hex "$k_date" "$service")
    local k_signing=$(hmac_sha256_hex "$k_service" "request")
    local signature=$(hmac_sha256_hex "$k_signing" "$string_to_sign")
    
    # Step 4: Build authorization
    echo "HMAC-SHA256 Credential=${TR_KEY}/${credential_scope}, SignedHeaders=${signed_headers}, Signature=${signature}"
}

# Find zone ID
PAYLOAD="{\"Key\":\"${TR_ZONE}\"}"
AUTH_HEADER=$(volcengine_sign "GET" "ListZones" "$PAYLOAD")

ZONE_RESULT=$(curl -s -X GET "https://dns.volcengineapi.com/?Action=ListZones&Key=${TR_ZONE}" \
    -H "Authorization: ${AUTH_HEADER}" \
    -H "Content-Type: application/json" \
    -H "Host: dns.volcengineapi.com" \
    -H "X-Date: $(date -u +"%Y%m%dT%H%M%SZ")")

ZID=$(echo "$ZONE_RESULT" | grep -o '"ZID":[0-9]*' | head -1 | cut -d: -f2)

if [ -z "$ZID" ]; then
    echo "Zone not found"
    exit 1
fi

# Query existing records
PAYLOAD="{\"ZID\":${ZID},\"Host\":\"${TR_HOST}\",\"Type\":\"${TR_TYPE}\"}"
AUTH_HEADER=$(volcengine_sign "GET" "ListRecords" "$PAYLOAD")

RECORD_RESULT=$(curl -s -X GET "https://dns.volcengineapi.com/?Action=ListRecords&ZID=${ZID}&Host=${TR_HOST}&Type=${TR_TYPE}" \
    -H "Authorization: ${AUTH_HEADER}" \
    -H "Content-Type: application/json" \
    -H "Host: dns.volcengineapi.com" \
    -H "X-Date: $(date -u +"%Y%m%dT%H%M%SZ")")

RECORD_ID=$(echo "$RECORD_RESULT" | grep -o '"RecordID":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -n "$RECORD_ID" ]; then
    # Update existing record
    PAYLOAD="{\"ZID\":${ZID},\"RecordID\":\"${RECORD_ID}\",\"Host\":\"${TR_HOST}\",\"Type\":\"${TR_TYPE}\",\"Value\":\"${WAN_IP}\",\"TTL\":${TR_TTL},\"Line\":\"default\"}"
    AUTH_HEADER=$(volcengine_sign "POST" "UpdateRecord" "$PAYLOAD")
    
    RESPONSE=$(curl -s -X POST "https://dns.volcengineapi.com/?Action=UpdateRecord" \
        -H "Authorization: ${AUTH_HEADER}" \
        -H "Content-Type: application/json" \
        -H "Host: dns.volcengineapi.com" \
        -H "X-Date: $(date -u +"%Y%m%dT%H%M%SZ")" \
        --data "$PAYLOAD")
    echo "Updated $TR_HOST.$TR_ZONE to $WAN_IP"
else
    # Create new record
    PAYLOAD="{\"ZID\":${ZID},\"Host\":\"${TR_HOST}\",\"Type\":\"${TR_TYPE}\",\"Value\":\"${WAN_IP}\",\"TTL\":${TR_TTL},\"Line\":\"default\"}"
    AUTH_HEADER=$(volcengine_sign "POST" "CreateRecord" "$PAYLOAD")
    
    RESPONSE=$(curl -s -X POST "https://dns.volcengineapi.com/?Action=CreateRecord" \
        -H "Authorization: ${AUTH_HEADER}" \
        -H "Content-Type: application/json" \
        -H "Host: dns.volcengineapi.com" \
        -H "X-Date: $(date -u +"%Y%m%dT%H%M%SZ")" \
        --data "$PAYLOAD")
    echo "Created $TR_HOST.$TR_ZONE with $WAN_IP"
fi

echo "$WAN_IP" > "$WAN_IP_FILE"
