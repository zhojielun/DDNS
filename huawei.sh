#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# ==========================================
# Huawei Cloud DNS DDNS 脚本 (纯 Shell 实现)
# 无需安装 Python、SDK 或任何额外依赖
# 仅需: bash, curl, openssl, date
# ==========================================

# 检查依赖
missing_deps=""
for cmd in bash curl openssl date; do
    if ! command -v "$cmd" &>/dev/null; then
        missing_deps="${missing_deps} ${cmd}"
    fi
done
if [ -n "$missing_deps" ]; then
    echo "缺少以下工具:${missing_deps}"
    echo "请先安装后再运行此脚本"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="${SCRIPT_DIR}/.huawei_ddns.conf"

load_config() {
    [ -f "$CONF_FILE" ] || return 0
    source "$CONF_FILE"
}

save_config() {
    cat > "$CONF_FILE" << EOF
HW_KEY='${HW_KEY}'
HW_SECRET='${HW_SECRET}'
HW_ZONE='${HW_ZONE}'
HW_HOST='${HW_HOST}'
HW_TYPE='${HW_TYPE}'
HW_TTL='${HW_TTL}'
HW_REGION='${HW_REGION}'
EOF
    echo "配置已保存到: $CONF_FILE"
}

reset_config() {
    rm -f "$CONF_FILE" 2>/dev/null
    rm -f "$HOME"/.huawei-wan_ip_*.txt 2>/dev/null || true
    echo "配置和缓存已清除"
}

usage() {
    echo "用法:"
    echo "  $0 -k AK -s SK -z 域名 -h 子域名    # 首次配置"
    echo "  $0                                    # 使用已保存的配置"
    echo "  $0 -reset                             # 清除配置"
    echo ""
    echo "参数: -k AK  -s SK  -z 根域名  -h 子域名  -t A|AAAA  -T TTL  -r 区域"
}

case "${1:-}" in
    -reset)  reset_config; exit 0 ;;
    -help|--help) usage; exit 0 ;;
esac

load_config

PARAM_PROVIDED=false
while getopts k:s:z:h:t:T:r: opts; do
    case ${opts} in
        k) HW_KEY=${OPTARG}; PARAM_PROVIDED=true ;;
        s) HW_SECRET=${OPTARG}; PARAM_PROVIDED=true ;;
        z) HW_ZONE=${OPTARG}; PARAM_PROVIDED=true ;;
        h) HW_HOST=${OPTARG}; PARAM_PROVIDED=true ;;
        t) HW_TYPE=${OPTARG}; PARAM_PROVIDED=true ;;
        T) HW_TTL=${OPTARG}; PARAM_PROVIDED=true ;;
        r) HW_REGION=${OPTARG}; PARAM_PROVIDED=true ;;
        ?) usage; exit 2 ;;
    esac
done

HW_KEY="${HW_KEY:-}"
HW_SECRET="${HW_SECRET:-}"
HW_ZONE="${HW_ZONE:-}"
HW_HOST="${HW_HOST:-}"
HW_TYPE="${HW_TYPE:-A}"
HW_TTL="${HW_TTL:-300}"
HW_REGION="${HW_REGION:-cn-north-1}"

missing=false
for var_name in HW_KEY HW_SECRET HW_ZONE HW_HOST; do
    eval val=\$$var_name
    [ -z "$val" ] && echo "错误: 参数 $var_name 未设置" && missing=true
done
[ "$missing" = true ] && exit 2
[[ "$HW_TYPE" != "A" && "$HW_TYPE" != "AAAA" ]] && echo "错误: 记录类型必须是 A 或 AAAA" && exit 1

if [ "$PARAM_PROVIDED" = true ]; then save_config; fi

# 获取公网 IP
if [ "$HW_TYPE" = "AAAA" ]; then
    WAN_IP=$(curl -s --max-time 10 "https://api6.ipify.org")
else
    WAN_IP=$(curl -s --max-time 10 "https://api4.ipify.org")
fi
[ -z "$WAN_IP" ] && echo "获取公网IP失败" && exit 1

# 检查 IP 变化
WAN_IP_FILE="$HOME/.huawei-wan_ip_${HW_HOST}.${HW_ZONE}.txt"
OLD_WAN_IP=""
[ -f "$WAN_IP_FILE" ] && OLD_WAN_IP=$(cat "$WAN_IP_FILE")
if [ "$WAN_IP" = "$OLD_WAN_IP" ]; then
    echo "${HW_HOST}.${HW_ZONE} IP未变化 (${WAN_IP})"
    exit 0
fi

echo "${HW_HOST}.${HW_ZONE} IP已变化 (${OLD_WAN_IP:-无} -> ${WAN_IP})，正在同步..."

# ==========================================
# 华为云 API 请求函数
# ==========================================
DNS_HOST="dns.${HW_REGION}.myhuaweicloud.com"

hw_api_req() {
    local method="$1" path="$2" query="$3" payload="$4"
    local timestamp=$(date -u +'%Y%m%dT%H%M%SZ')

    local canonical_uri="${path}"
    echo "${canonical_uri}" | grep -qE "/$" || canonical_uri="${canonical_uri}/"

    local canonical_headers="host:${DNS_HOST}\nx-sdk-date:${timestamp}\n"
    local signed_headers="host;x-sdk-date"

    [ -n "${payload}" ] || payload='""'
    local hashed_payload=$(printf -- "%b" "${payload}" | openssl dgst -sha256 -hex 2>/dev/null | sed 's/^.* //')

    local canonical_request="${method}\n${canonical_uri}\n${query}\n${canonical_headers}\n${signed_headers}\n${hashed_payload}"
    local cr_hash=$(printf -- "%b" "${canonical_request}" | openssl dgst -sha256 -hex 2>/dev/null | sed 's/^.* //')
    local string_to_sign="SDK-HMAC-SHA256\n${timestamp}\n${cr_hash}"
    local signature=$(printf -- '%b' "${string_to_sign}" | openssl dgst -sha256 -hmac "${HW_SECRET}" -hex 2>/dev/null | sed 's/^.* //')
    local authorization="SDK-HMAC-SHA256 Access=${HW_KEY}, SignedHeaders=${signed_headers}, Signature=${signature}"

    local url="https://${DNS_HOST}${path}"
    [ -z "$query" ] || url="${url}?${query}"

    curl -s --max-time 15 -X "${method}" \
        -H "X-Sdk-Date: ${timestamp}" \
        -H "host: ${DNS_HOST}" \
        -H "Content-Type: application/json" \
        -H "Authorization: ${authorization}" \
        -d "${payload}" \
        "${url}"
}

# 查询 Zone ID
RESP=$(hw_api_req "GET" "/v2/zones" "name=${HW_ZONE}.&search_mode=equal" "")
ZONE_ID=$(echo "$RESP" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ -z "$ZONE_ID" ]; then
    echo "域名 ${HW_ZONE} 未找到"
    exit 1
fi

# 查询现有记录
if [ "$HW_HOST" = "@" ] || [ -z "$HW_HOST" ]; then
    RECORD_NAME="${HW_ZONE}"
else
    RECORD_NAME="${HW_HOST}.${HW_ZONE}"
fi

RESP=$(hw_api_req "GET" "/v2/zones/${ZONE_ID}/recordsets" "name=${RECORD_NAME}.&search_mode=equal&type=${HW_TYPE}" "")
RECORD_ID=$(echo "$RESP" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

# 更新或创建记录
PAYLOAD="{\"name\":\"${RECORD_NAME}.\",\"type\":\"${HW_TYPE}\",\"records\":[\"${WAN_IP}\"],\"ttl\":${HW_TTL}}"

if [ -n "$RECORD_ID" ]; then
    RESP=$(hw_api_req "PUT" "/v2/zones/${ZONE_ID}/recordsets/${RECORD_ID}" "" "$PAYLOAD")
else
    RESP=$(hw_api_req "POST" "/v2/zones/${ZONE_ID}/recordsets" "" "$PAYLOAD")
fi

# 检查结果
ERR_CODE=$(echo "$RESP" | grep -o '"error_code":"[^"]*"' | head -1 | cut -d'"' -f4 || true)
if [ -n "$ERR_CODE" ]; then
    echo "同步失败: $RESP"
    exit 1
fi

echo "${HW_HOST}.${HW_ZONE} 已同步到 ${WAN_IP}"
echo "$WAN_IP" > "$WAN_IP_FILE"
