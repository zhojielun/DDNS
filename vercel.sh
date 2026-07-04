#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Vercel DDNS script
# Usage: vercel.sh -s TOKEN -z ZONE -h HOST -t A|AAAA -e TEAM_ID

VC_TOKEN=""
VC_ZONE=""
VC_HOST=""
VC_TYPE="A"
VC_TTL="60"
VC_TEAM=""

while getopts s:z:h:t:T:e: opts; do
    case ${opts} in
        s) VC_TOKEN=${OPTARG} ;;
        z) VC_ZONE=${OPTARG} ;;
        h) VC_HOST=${OPTARG} ;;
        t) VC_TYPE=${OPTARG} ;;
        T) VC_TTL=${OPTARG} ;;
        e) VC_TEAM=${OPTARG} ;;
    esac
done

if [ -z "$VC_TOKEN" ]; then echo "Missing -s (API token)"; exit 2; fi
if [ -z "$VC_ZONE" ]; then echo "Missing -z (zone/domain)"; exit 2; fi
if [ -z "$VC_HOST" ]; then echo "Missing -h (subdomain)"; exit 2; fi

if [ "$VC_TTL" -lt 60 ]; then VC_TTL=60; fi

if [ "$VC_TYPE" = "AAAA" ]; then
    WAN_IP=$(curl -s "https://api6.ipify.org")
else
    WAN_IP=$(curl -s "https://api4.ipify.org")
fi

WAN_IP=$(echo "$WAN_IP" | tr '[:upper:]' '[:lower:]')

if [ -z "$WAN_IP" ]; then
    echo "Failed to get public IP"
    exit 1
fi

TEAM_PARAM=""
if [ -n "$VC_TEAM" ]; then
    TEAM_PARAM="?teamId=${VC_TEAM}"
fi

WAN_IP_FILE="$HOME/.vercel-wan_ip_${VC_HOST}.${VC_ZONE}.txt"
OLD_WAN_IP=""
[ -f "$WAN_IP_FILE" ] && OLD_WAN_IP=$(cat "$WAN_IP_FILE")

if [ "$WAN_IP" = "$OLD_WAN_IP" ]; then
    echo "WAN IP unchanged ($WAN_IP)"
    exit 0
fi

# List existing records
RECORDS=$(curl -s -H "Authorization: Bearer ${VC_TOKEN}" "https://api.vercel.com/v4/domains/${VC_ZONE}/records${TEAM_PARAM}")
RECORD_ID=$(echo "$RECORDS" | grep -o "\"id\":\"[^\"]*\"" | head -1 | cut -d'"' -f4)

if [ -n "$RECORD_ID" ]; then
    # Update existing record
    curl -s -X PATCH -H "Authorization: Bearer ${VC_TOKEN}" -H "Content-Type: application/json" \
        "https://api.vercel.com/v1/domains/records/${RECORD_ID}${TEAM_PARAM}" \
        --data "{\"type\":\"${VC_TYPE}\",\"value\":\"${WAN_IP}\",\"ttl\":${VC_TTL}}" > /dev/null
    echo "Updated $VC_HOST.$VC_ZONE to $WAN_IP"
else
    # Create new record
    curl -s -X POST -H "Authorization: Bearer ${VC_TOKEN}" -H "Content-Type: application/json" \
        "https://api.vercel.com/v2/domains/${VC_ZONE}/records${TEAM_PARAM}" \
        --data "{\"name\":\"${VC_HOST}\",\"type\":\"${VC_TYPE}\",\"value\":\"${WAN_IP}\",\"ttl\":${VC_TTL}}" > /dev/null
    echo "Created $VC_HOST.$VC_ZONE with $WAN_IP"
fi

echo "$WAN_IP" > "$WAN_IP_FILE"
