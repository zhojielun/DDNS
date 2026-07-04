#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Common DDNS helper functions

# Get public IPv4 address
get_ipv4() {
    local ip=""
    local sources=(
        "https://api4.ipify.org"
        "https://api.ipify.org"
        "https://bot.whatismyipaddress.com"
        "https://icanhazip.com"
        "https://checkip.amazonaws.com"
    )
    for url in "${sources[@]}"; do
        ip=$(curl -s -4 --max-time 10 "$url" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
        if [ -n "$ip" ]; then
            echo "$ip"
            return 0
        fi
    done
    echo ""
    return 1
}

# Get public IPv6 address
get_ipv6() {
    local ip=""
    local sources=(
        "https://api6.ipify.org"
        "https://api64.ipify.org"
        "https://icanhazip.com"
        "https://checkip.amazonaws.com"
    )
    for url in "${sources[@]}"; do
        ip=$(curl -s -6 --max-time 10 "$url" 2>/dev/null | grep -oE '([0-9a-fA-F:]+:)+[0-9a-fA-F]+' | head -1)
        if [ -n "$ip" ]; then
            echo "$ip"
            return 0
        fi
    done
    echo ""
    return 1
}

# Check if IP has changed compared to cached value
check_ip_changed() {
    local new_ip="$1"
    local cache_file="$2"

    if [ -z "$new_ip" ]; then
        return 1
    fi

    if [ -f "$cache_file" ]; then
        local old_ip
        old_ip=$(cat "$cache_file")
        if [ "$new_ip" = "$old_ip" ]; then
            return 1
        fi
    fi

    return 0
}

# Save IP to cache file
save_ip_cache() {
    local ip="$1"
    local cache_file="$2"
    echo "$ip" > "$cache_file"
}

# Validate IPv4 address
validate_ipv4() {
    local ip="$1"
    echo "$ip" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'
}

# Validate IPv6 address
validate_ipv6() {
    local ip="$1"
    echo "$ip" | grep -qE '([0-9a-fA-F:]+:)+[0-9a-fA-F]*'
}
