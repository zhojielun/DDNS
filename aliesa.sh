#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Ali ESA (Edge Security Accelerator) DDNS script (Aliyun signing)
# Usage: aliesa.sh -k ACCESS_KEY -s ACCESS_SECRET -z ZONE -h HOST -t A|AAAA

ESA_KEY=""
ESA_SECRET=""
ESA_ZONE=""
ESA_HOST=""
ESA_TYPE="A"
ESA_TTL="600"

while getopts k:s:z:h:t:T: opts; do
    case ${opts} in
        k) ESA_KEY=${OPTARG} ;;
        s) ESA_SECRET=${OPTARG} ;;
        z) ESA_ZONE=${OPTARG} ;;
        h) ESA_HOST=${OPTARG} ;;
        t) ESA_TYPE=${OPTARG} ;;
        T) ESA_TTL=${OPTARG} ;;
    esac
done

if [ -z "$ESA_KEY" ]; then echo "Missing -k (Access Key ID)"; exit 2; fi
if [ -z "$ESA_SECRET" ]; then echo "Missing -s (Access Key Secret)"; exit 2; fi
if [ -z "$ESA_ZONE" ]; then echo "Missing -z (zone/domain)"; exit 2; fi
if [ -z "$ESA_HOST" ]; then echo "Missing -h (subdomain)"; exit 2; fi

if [ "$ESA_TYPE" = "AAAA" ]; then
    WAN_IP=$(curl -s "https://api6.ipify.org")
else
    WAN_IP=$(curl -s "https://api4.ipify.org")
fi

if [ -z "$WAN_IP" ]; then
    echo "Failed to get public IP"
    exit 1
fi

WAN_IP_FILE="$HOME/.aliesa-wan_ip_${ESA_HOST}.${ESA_ZONE}.txt"
OLD_WAN_IP=""
[ -f "$WAN_IP_FILE" ] && OLD_WAN_IP=$(cat "$WAN_IP_FILE")

if [ "$WAN_IP" = "$OLD_WAN_IP" ]; then
    echo "WAN IP unchanged ($WAN_IP)"
    exit 0
fi

# Aliyun signing function (HMAC-SHA1)
aliyun_sign() {
    local action="$1"
    local params="$2"
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local nonce=$(date +%s%N | cut -c1-19)
    
    # Add common parameters
    params="${params}&AccessKeyId=${ESA_KEY}&Action=${action}&Format=JSON&SignatureMethod=HMAC-SHA1&SignatureNonce=${nonce}&SignatureVersion=1.0&Timestamp=${timestamp}&Version=2015-01-09"
    
    # Sort parameters
    local sorted_params=$(echo "$params" | tr '&' '\n' | sort | tr '\n' '&' | sed 's/&$//')
    
    # URL encode for signing
    local encoded_params=$(echo "$sorted_params" | sed 's/=&//g' | sed 's/+/%20/g' | sed 's/[^&%=+]/\\x&/g' | xargs -0 -I {} echo -e "{}")
    
    # Build string to sign
    local string_to_sign="GET&%2F&$(python3 -c "import urllib.parse; print(urllib.parse.quote('${encoded_params}', safe=''))")"
    
    # Calculate signature
    local signature=$(echo -n "$string_to_sign" | openssl dgst -sha1 -hmac "${ESA_SECRET}&" -binary | base64)
    
    # URL encode signature
    local encoded_signature=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${signature}', safe=''))")
    
    echo "${sorted_params}&Signature=${encoded_signature}"
}

# Find site ID
SITE_RESULT=$(curl -s "https://esa.cn-hangzhou.aliyuncs.com/?$(aliyun_sign "ListSites" "SiteName=${ESA_ZONE}")")
SITE_ID=$(echo "$SITE_RESULT" | grep -o '"SiteId":[0-9]*' | head -1 | cut -d: -f2)

if [ -z "$SITE_ID" ]; then
    echo "Site not found"
    exit 1
fi

# Get record list
RECORD_RESULT=$(curl -s "https://esa.cn-hangzhou.aliyuncs.com/?$(aliyun_sign "ListOriginRecords" "SiteId=${SITE_ID}&RecordName=${ESA_HOST}.${ESA_ZONE}")")
RECORD_ID=$(echo "$RECORD_RESULT" | grep -o '"RecordId":[0-9]*' | head -1 | cut -d: -f2)

if [ -n "$RECORD_ID" ]; then
    # Update existing record
    RESPONSE=$(curl -s "https://esa.cn-hangzhou.aliyuncs.com/?$(aliyun_sign "UpdateOriginRecord" "RecordId=${RECORD_ID}&SiteId=${SITE_ID}&Content=${WAN_IP}&Type=${ESA_TYPE}&TTL=${ESA_TTL}")")
    echo "Updated $ESA_HOST.$ESA_ZONE to $WAN_IP"
else
    # Create new record
    RESPONSE=$(curl -s "https://esa.cn-hangzhou.aliyuncs.com/?$(aliyun_sign "CreateOriginRecord" "SiteId=${SITE_ID}&RecordName=${ESA_HOST}.${ESA_ZONE}&Content=${WAN_IP}&Type=${ESA_TYPE}&TTL=${ESA_TTL}")")
    echo "Created $ESA_HOST.$ESA_ZONE with $WAN_IP"
fi

echo "$WAN_IP" > "$WAN_IP_FILE"
