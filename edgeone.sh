#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# EdgeOne (Tencent Cloud) DDNS script (TC3-HMAC-SHA256 signing)
# Usage: edgeone.sh -k SECRET_ID -s SECRET_KEY -z ZONE -h HOST -t A|AAAA

EO_ID=""
EO_SECRET=""
EO_ZONE=""
EO_HOST=""
EO_TYPE="A"
EO_TTL="600"
EO_SERVICE="teo"
EO_VERSION="2022-09-01"

while getopts k:s:z:h:t:T: opts; do
    case ${opts} in
        k) EO_ID=${OPTARG} ;;
        s) EO_SECRET=${OPTARG} ;;
        z) EO_ZONE=${OPTARG} ;;
        h) EO_HOST=${OPTARG} ;;
        t) EO_TYPE=${OPTARG} ;;
        T) EO_TTL=${OPTARG} ;;
    esac
done

if [ -z "$EO_ID" ]; then echo "Missing -k (Secret ID)"; exit 2; fi
if [ -z "$EO_SECRET" ]; then echo "Missing -s (Secret Key)"; exit 2; fi
if [ -z "$EO_ZONE" ]; then echo "Missing -z (zone/domain)"; exit 2; fi
if [ -z "$EO_HOST" ]; then echo "Missing -h (subdomain)"; exit 2; fi

if [ "$EO_TYPE" = "AAAA" ]; then
    WAN_IP=$(curl -s "https://api6.ipify.org")
else
    WAN_IP=$(curl -s "https://api4.ipify.org")
fi

if [ -z "$WAN_IP" ]; then
    echo "Failed to get public IP"
    exit 1
fi

WAN_IP_FILE="$HOME/.edgeone-wan_ip_${EO_HOST}.${EO_ZONE}.txt"
OLD_WAN_IP=""
[ -f "$WAN_IP_FILE" ] && OLD_WAN_IP=$(cat "$WAN_IP_FILE")

if [ "$WAN_IP" = "$OLD_WAN_IP" ]; then
    echo "WAN IP unchanged ($WAN_IP)"
    exit 0
fi

# SHA256 hash function
sha256_hex() {
    echo -n "$1" | sha256sum | awk '{print $1}'
}

# HMAC-SHA256 hex function
hmac_sha256_hex() {
    echo -n "$2" | openssl dgst -sha256 -hmac "$1" | awk '{print $2}'
}

# Tencent Cloud TC3 signing
tencent_sign() {
    local action="$1"
    local payload="$2"
    
    local timestamp=$(date +%s)
    local date_str=$(date -u -d "@${timestamp}" +"%Y-%m-%d")
    local host="${EO_SERVICE}.tencentcloudapi.com"
    
    # Step 1: Build canonical request
    local canonical_request="POST\n/\n\ncontent-type:application/json\nhost:${host}\nx-tc-action:$(echo "$action" | tr '[:upper:]' '[:lower:]')\n\ncontent-type;host;x-tc-action\n$(sha256_hex "$payload")"
    
    # Step 2: Build string to sign
    local credential_scope="${date_str}/${EO_SERVICE}/tc3_request"
    local string_to_sign="TC3-HMAC-SHA256\n${timestamp}\n${credential_scope}\n$(sha256_hex "$canonical_request")"
    
    # Step 3: Calculate signature
    local secret_date=$(hmac_sha256_hex "TC3${EO_SECRET}" "$date_str")
    local secret_service=$(hmac_sha256_hex "$secret_date" "$EO_SERVICE")
    local secret_signing=$(hmac_sha256_hex "$secret_service" "tc3_request")
    local signature=$(hmac_sha256_hex "$secret_signing" "$string_to_sign")
    
    # Step 4: Build authorization
    echo "TC3-HMAC-SHA256 Credential=${EO_ID}/${credential_scope}, SignedHeaders=content-type;host;x-tc-action, Signature=${signature}"
}

# First, get zone ID
ZONE_PAYLOAD="{\"Filters\":[{\"Name\":\"zone-name\",\"Values\":[\"${EO_ZONE}\"]}]}"
AUTH_HEADER=$(tencent_sign "DescribeZones" "$ZONE_PAYLOAD")
TIMESTAMP=$(date +%s)

ZONE_RESULT=$(curl -s -X POST "https://teo.tencentcloudapi.com" \
    -H "Authorization: ${AUTH_HEADER}" \
    -H "Content-Type: application/json" \
    -H "Host: teo.tencentcloudapi.com" \
    -H "X-TC-Action: DescribeZones" \
    -H "X-TC-Timestamp: ${TIMESTAMP}" \
    -H "X-TC-Version: ${EO_VERSION}" \
    --data "$ZONE_PAYLOAD")

ZONE_ID=$(echo "$ZONE_RESULT" | grep -o '"ZoneId":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -z "$ZONE_ID" ]; then
    echo "Zone not found"
    exit 1
fi

# Build record name
if [ "$EO_HOST" = "@" ] || [ -z "$EO_HOST" ]; then
    RECORD_NAME="$EO_ZONE"
else
    RECORD_NAME="${EO_HOST}.${EO_ZONE}"
fi

# Query existing records
RECORD_PAYLOAD="{\"ZoneId\":\"${ZONE_ID}\",\"Filters\":[{\"Name\":\"name\",\"Values\":[\"${RECORD_NAME}\"]},{\"Name\":\"type\",\"Values\":[\"${EO_TYPE}\"]}]}"
AUTH_HEADER=$(tencent_sign "DescribeDnsRecords" "$RECORD_PAYLOAD")
TIMESTAMP=$(date +%s)

RECORD_RESULT=$(curl -s -X POST "https://teo.tencentcloudapi.com" \
    -H "Authorization: ${AUTH_HEADER}" \
    -H "Content-Type: application/json" \
    -H "Host: teo.tencentcloudapi.com" \
    -H "X-TC-Action: DescribeDnsRecords" \
    -H "X-TC-Timestamp: ${TIMESTAMP}" \
    -H "X-TC-Version: ${EO_VERSION}" \
    --data "$RECORD_PAYLOAD")

RECORD_ID=$(echo "$RECORD_RESULT" | grep -o '"RecordId":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -n "$RECORD_ID" ]; then
    # Update existing record
    RECORD_PAYLOAD="{\"ZoneId\":\"${ZONE_ID}\",\"DnsRecords\":[{\"RecordId\":\"${RECORD_ID}\",\"Name\":\"${RECORD_NAME}\",\"Type\":\"${EO_TYPE}\",\"Content\":\"${WAN_IP}\",\"TTL\":${EO_TTL},\"Location\":\"Default\"}]}"
    AUTH_HEADER=$(tencent_sign "ModifyDnsRecords" "$RECORD_PAYLOAD")
    TIMESTAMP=$(date +%s)
    
    RESPONSE=$(curl -s -X POST "https://teo.tencentcloudapi.com" \
        -H "Authorization: ${AUTH_HEADER}" \
        -H "Content-Type: application/json" \
        -H "Host: teo.tencentcloudapi.com" \
        -H "X-TC-Action: ModifyDnsRecords" \
        -H "X-TC-Timestamp: ${TIMESTAMP}" \
        -H "X-TC-Version: ${EO_VERSION}" \
        --data "$RECORD_PAYLOAD")
    echo "Updated $EO_HOST.$EO_ZONE to $WAN_IP"
else
    # Create new record
    RECORD_PAYLOAD="{\"ZoneId\":\"${ZONE_ID}\",\"Name\":\"${RECORD_NAME}\",\"Type\":\"${EO_TYPE}\",\"Content\":\"${WAN_IP}\",\"TTL\":${EO_TTL},\"Location\":\"Default\"}"
    AUTH_HEADER=$(tencent_sign "CreateDnsRecord" "$RECORD_PAYLOAD")
    TIMESTAMP=$(date +%s)
    
    RESPONSE=$(curl -s -X POST "https://teo.tencentcloudapi.com" \
        -H "Authorization: ${AUTH_HEADER}" \
        -H "Content-Type: application/json" \
        -H "Host: teo.tencentcloudapi.com" \
        -H "X-TC-Action: CreateDnsRecord" \
        -H "X-TC-Timestamp: ${TIMESTAMP}" \
        -H "X-TC-Version: ${EO_VERSION}" \
        --data "$RECORD_PAYLOAD")
    echo "Created $EO_HOST.$EO_ZONE with $WAN_IP"
fi

echo "$WAN_IP" > "$WAN_IP_FILE"
