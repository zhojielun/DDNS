#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# GoDaddy DDNS script
# Usage: godaddy.sh -k API_KEY -s API_SECRET -z ZONE -h HOST -t A|AAAA

GD_KEY=""
GD_SECRET=""
GD_ZONE=""
GD_HOST=""
GD_TYPE="A"
GD_TTL="600"

while getopts k:s:z:h:t:T: opts; do
    case ${opts} in
        k) GD_KEY=${OPTARG} ;;
        s) GD_SECRET=${OPTARG} ;;
        z) GD_ZONE=${OPTARG} ;;
        h) GD_HOST=${OPTARG} ;;
        t) GD_TYPE=${OPTARG} ;;
        T) GD_TTL=${OPTARG} ;;
    esac
done

if [ -z "$GD_KEY" ]; then echo "Missing -k (API Key)"; exit 2; fi
if [ -z "$GD_SECRET" ]; then echo "Missing -s (API Secret)"; exit 2; fi
if [ -z "$GD_ZONE" ]; then echo "Missing -z (zone/domain)"; exit 2; fi
if [ -z "$GD_HOST" ]; then echo "Missing -h (subdomain)"; exit 2; fi

if [ "$GD_TYPE" = "AAAA" ]; then
    WAN_IP=$(curl -s "https://api6.ipify.org")
else
    WAN_IP=$(curl -s "https://api4.ipify.org")
fi

if [ -z "$WAN_IP" ]; then
    echo "Failed to get public IP"
    exit 1
fi

WAN_IP_FILE="$HOME/.godaddy-wan_ip_${GD_HOST}.${GD_ZONE}.txt"
OLD_WAN_IP=""
[ -f "$WAN_IP_FILE" ] && OLD_WAN_IP=$(cat "$WAN_IP_FILE")

if [ "$WAN_IP" = "$OLD_WAN_IP" ]; then
    echo "WAN IP unchanged ($WAN_IP)"
    exit 0
fi

# GoDaddy uses PUT to update (creates if not exists)
RESPONSE=$(curl -s -X PUT "https://api.godaddy.com/v1/domains/${GD_ZONE}/records/${GD_TYPE}/${GD_HOST}" \
    -H "Authorization: sso-key ${GD_KEY}:${GD_SECRET}" \
    -H "Content-Type: application/json" \
    --data "[{\"data\":\"${WAN_IP}\",\"name\":\"${GD_HOST}\",\"ttl\":${GD_TTL},\"type\":\"${GD_TYPE}\"}]")

if [ -z "$RESPONSE" ]; then
    echo "$WAN_IP" > "$WAN_IP_FILE"
    echo "Updated $GD_HOST.$GD_ZONE to $WAN_IP"
else
    echo "Update failed: $RESPONSE"
    exit 1
fi
