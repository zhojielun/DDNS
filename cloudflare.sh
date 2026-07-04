#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Cloudflare DDNS script
# Usage: cloudflare.sh -k API_KEY -u EMAIL -z ZONE -h HOST -t A|AAAA -f false|true

CFKEY=""
CFUSER=""
CFZONE_NAME=""
CFRECORD_NAME=""
CFRECORD_TYPE="A"
CFTTL=1
FORCE=false
WANIPSITE="https://api4.ipify.org"

while getopts k:u:h:z:t:f: opts; do
    case ${opts} in
        k) CFKEY=${OPTARG} ;;
        u) CFUSER=${OPTARG} ;;
        h) CFRECORD_NAME=${OPTARG} ;;
        z) CFZONE_NAME=${OPTARG} ;;
        t) CFRECORD_TYPE=${OPTARG} ;;
        f) FORCE=${OPTARG} ;;
    esac
done

if [ "$CFRECORD_TYPE" = "AAAA" ]; then
    WANIPSITE="https://api6.ipify.org"
fi

if [ -z "$CFKEY" ]; then echo "Missing -k (API key)"; exit 2; fi
if [ -z "$CFUSER" ]; then echo "Missing -u (email)"; exit 2; fi
if [ -z "$CFRECORD_NAME" ]; then echo "Missing -h (hostname)"; exit 2; fi
if [ -z "$CFZONE_NAME" ]; then echo "Missing -z (zone)"; exit 2; fi

if [ "$CFRECORD_NAME" != "$CFZONE_NAME" ] && [[ "$CFRECORD_NAME" != *".$CFZONE_NAME" ]]; then
    CFRECORD_NAME="$CFRECORD_NAME.$CFZONE_NAME"
fi

WAN_IP=$(curl -s "${WANIPSITE}")
WAN_IP_FILE="$HOME/.cf-wan_ip_${CFRECORD_NAME}.txt"
OLD_WAN_IP=""
[ -f "$WAN_IP_FILE" ] && OLD_WAN_IP=$(cat "$WAN_IP_FILE")

if [ "$WAN_IP" = "$OLD_WAN_IP" ] && [ "$FORCE" = false ]; then
    echo "WAN IP unchanged ($WAN_IP)"
    exit 0
fi

# Get zone and record IDs
ID_FILE="$HOME/.cf-id_${CFRECORD_NAME}.txt"
if [ -f "$ID_FILE" ] && [ "$(wc -l < "$ID_FILE")" -eq 4 ] \
    && [ "$(sed -n '3p' "$ID_FILE")" = "$CFZONE_NAME" ] \
    && [ "$(sed -n '4p' "$ID_FILE")" = "$CFRECORD_NAME" ]; then
    CFZONE_ID=$(sed -n '1p' "$ID_FILE")
    CFRECORD_ID=$(sed -n '2p' "$ID_FILE")
else
    CFZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$CFZONE_NAME" \
        -H "Authorization: Bearer $CFKEY" -H "Content-Type: application/json" | \
        grep -Po '(?<="id":")[^"]*' | head -1)
    CFRECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records?name=$CFRECORD_NAME&type=$CFRECORD_TYPE" \
        -H "Authorization: Bearer $CFKEY" -H "Content-Type: application/json" | \
        grep -Po '(?<="id":")[^"]*' | head -1)
    echo "$CFZONE_ID" > "$ID_FILE"
    echo "$CFRECORD_ID" >> "$ID_FILE"
    echo "$CFZONE_NAME" >> "$ID_FILE"
    echo "$CFRECORD_NAME" >> "$ID_FILE"
fi

if [ -z "$CFZONE_ID" ] || [ -z "$CFRECORD_ID" ]; then
    echo "Failed to find zone or record"
    exit 1
fi

RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records/$CFRECORD_ID" \
    -H "Authorization: Bearer $CFKEY" \
    -H "Content-Type: application/json" \
    --data "{\"id\":\"$CFRECORD_ID\",\"type\":\"$CFRECORD_TYPE\",\"name\":\"$CFRECORD_NAME\",\"content\":\"$WAN_IP\",\"ttl\":$CFTTL,\"proxied\":false}")

if echo "$RESPONSE" | grep -q '"success":true'; then
    echo "$WAN_IP" > "$WAN_IP_FILE"
    echo "Updated $CFRECORD_NAME to $WAN_IP"
else
    echo "Update failed: $RESPONSE"
    exit 1
fi
