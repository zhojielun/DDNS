# DDNS Shell Scripts

基于 [ddns-go](https://github.com/jeessy2/ddns-go) 项目转换而来的 Shell 脚本集合，支持 28 个 DNS 服务商。

## 特性

- 支持 IPv4 (A记录) 和 IPv6 (AAAA记录)
- 自动检测 IP 变化，避免不必要的 API 调用
- 支持定时任务 (crontab)
- 每个脚本独立运行，无需额外依赖
- 部分复杂签名的服务商脚本使用纯 Shell 实现

## 支持的服务商

| 服务商 | 脚本 | 认证方式 |
|--------|------|----------|
| 华为云 DNS | `huawei.sh` | SDK-HMAC-SHA256 签名 |
| Cloudflare | `cloudflare.sh` | API Token |
| 阿里云 DNS | `alidns.sh` | Access Key (HMAC-SHA1) |
| 阿里云 ESA | `aliesa.sh` | Access Key (Aliyun 签名) |
| DNSPod/腾讯云 | `dnspod.sh` | Login Token |
| 腾讯云 DNS | `tencent_cloud.sh` | Login Token (via DNSPod) |
| 腾讯云 EdgeOne | `edgeone.sh` | TC3-HMAC-SHA256 签名 |
| 百度云 DNS | `baidu.sh` | BCE auth v1 签名 |
| 火山引擎 | `traffic_route.sh` | HMAC-SHA256 签名 |
| Porkbun | `porkbun.sh` | API Key + Secret |
| GoDaddy | `godaddy.sh` | sso-key |
| Namecheap | `namecheap.sh` | Dynamic DNS Password (仅IPv4) |
| NameSilo | `namesilo.sh` | API Key |
| Dynadot | `dynadot.sh` | Dynamic DNS Password |
| Dynv6 | `dynv6.sh` | Bearer Token |
| Vercel | `vercel.sh` | Bearer Token |
| Spaceship | `spaceship.sh` | API Key + Secret |
| DNSLA | `dnsla.sh` | Basic Auth |
| ClouDNS | `cloudns.sh` | Auth ID + Password |
| Gcore | `gcore.sh` | APIKey Token |
| Name.com | `name_com.sh` | Basic Auth |
| IBM NS1 | `nsone.sh` | X-NSONE-Key |
| 雨云 | `rainyun.sh` | x-api-key |
| 时代互联 | `nowcn.sh` | HMAC-SHA1 签名 |
| Eranet | `eranet.sh` | HMAC-SHA1 签名 |
| Tnet.hk | `tnethk.sh` | HMAC-SHA1 签名 |
| HiPM DNS | `hipmdnsmgr.sh` | API (占位) |
| Callback | `callback.sh` | 自定义 URL |

## 快速开始

### 1. 下载并配置脚本

选择你需要的服务商，在下方参数说明中找到下载命令，然后用命令行参数配置：

```bash
./huawei.sh -k "YOUR_AK" -s "YOUR_SK" -z "example.com" -h "home" -t A
```

### 2. 运行脚本

```bash
# 直接运行
./huawei.sh

# 或使用 crontab 定时运行
crontab -e
# 添加以下行（每1分钟执行一次）
*/1 * * * * /root/ddns/huawei.sh >/dev/null 2>&1
```

## 参数说明

### 通用参数

| 参数 | 说明 | 示例 |
|------|------|------|
| `-t` | 记录类型 (A=IPv4, AAAA=IPv6) | `-t A` |
| `-T` | TTL (秒) | `-T 600` |

### 华为云 DNS

```bash
curl -sO https://raw.githubusercontent.com/zhojielun/DDNS/refs/heads/master/huawei.sh && chmod +x huawei.sh
```

| 参数 | 说明 |
|------|------|
| `-k` | Access Key |
| `-s` | Secret Key |
| `-z` | 根域名 |
| `-h` | 子域名 |
| `-t` | 记录类型: A=IPv4, AAAA=IPv6 (默认: A) |
| `-T` | TTL 秒数 (默认: 300) |
| `-r` | 华为云区域 (默认: cn-north-1) |

> **注意**: 华为云 DNS 脚本为纯 Shell 实现，无需安装 Python 或任何 SDK，仅依赖 bash、curl、openssl、date（均为系统自带工具）。

#### 华为云 DNS 使用方法

**首次配置**（参数会自动保存，下次无需重复输入）：

```bash
./huawei.sh -k "YOUR_AK" -s "YOUR_SK" -z "ddns.cam" -h "test" -r "ap-southeast-1"
```

**之后直接运行**（自动使用已保存的配置）：

```bash
./huawei.sh
```

**清除所有保存的配置**：

```bash
./huawei.sh -reset
```

**查看帮助**：

```bash
./huawei.sh -help
```

#### 华为云 DNS 定时任务

配置完成后，可通过 crontab 设置定时更新：

```bash
crontab -e

# 每 1 分钟检查并更新 DNS（推荐）
*/1 * * * * /path/to/huawei.sh >/dev/null 2>&1
```

> **提示**: 脚本会自动检测 IP 是否变化，只有 IP 改变时才会调用 API，所以频繁执行不会产生多余的 API 调用。

### Cloudflare

```bash
curl -sO https://raw.githubusercontent.com/zhojielun/DDNS/refs/heads/master/cloudflare.sh && chmod +x cloudflare.sh
```

| 参数 | 说明 |
|------|------|
| `-k` | Global API Key |
| `-u` | 登录邮箱 |
| `-z` | 根域名 (如 example.com) |
| `-h` | 子域名前缀 (如 home) |
| `-f` | 强制更新 (true/false) |

### 阿里云 DNS

```bash
curl -sO https://raw.githubusercontent.com/zhojielun/DDNS/refs/heads/master/alidns.sh && chmod +x alidns.sh
```

| 参数 | 说明 |
|------|------|
| `-k` | Access Key ID |
| `-s` | Access Key Secret |
| `-z` | 根域名 |
| `-h` | 子域名 (如 www) |

### DNSPod/腾讯云

```bash
curl -sO https://raw.githubusercontent.com/zhojielun/DDNS/refs/heads/master/dnspod.sh && chmod +x dnspod.sh
```

| 参数 | 说明 |
|------|------|
| `-k` | Login Token ID |
| `-s` | Login Token |
| `-z` | 根域名 |
| `-h` | 子域名 |
| `-l` | 解析线路 (默认: 默认) |

### Porkbun

```bash
curl -sO https://raw.githubusercontent.com/zhojielun/DDNS/refs/heads/master/porkbun.sh && chmod +x porkbun.sh
```

| 参数 | 说明 |
|------|------|
| `-k` | API Key |
| `-s` | Secret API Key |
| `-z` | 根域名 |
| `-h` | 子域名 |

### GoDaddy

```bash
curl -sO https://raw.githubusercontent.com/zhojielun/DDNS/refs/heads/master/godaddy.sh && chmod +x godaddy.sh
```

| 参数 | 说明 |
|------|------|
| `-k` | API Key |
| `-s` | API Secret |
| `-z` | 根域名 |
| `-h` | 子域名 |

### Namecheap

```bash
curl -sO https://raw.githubusercontent.com/zhojielun/DDNS/refs/heads/master/namecheap.sh && chmod +x namecheap.sh
```

| 参数 | 说明 |
|------|------|
| `-k` | 主机名 (如 @, www, home) |
| `-s` | Dynamic DNS Password |
| `-z` | 根域名 |
| `-h` | 主机名 (同 -k) |

### NameSilo

```bash
curl -sO https://raw.githubusercontent.com/zhojielun/DDNS/refs/heads/master/namesilo.sh && chmod +x namesilo.sh
```

| 参数 | 说明 |
|------|------|
| `-s` | API Key |
| `-z` | 根域名 |
| `-h` | 子域名 |

### Dynadot

```bash
curl -sO https://raw.githubusercontent.com/zhojielun/DDNS/refs/heads/master/dynadot.sh && chmod +x dynadot.sh
```

| 参数 | 说明 |
|------|------|
| `-s` | Dynamic DNS Password |
| `-z` | 根域名 |
| `-h` | 子域名 (多个用逗号分隔) |

### Dynv6

```bash
curl -sO https://raw.githubusercontent.com/zhojielun/DDNS/refs/heads/master/dynv6.sh && chmod +x dynv6.sh
```

| 参数 | 说明 |
|------|------|
| `-s` | API Token |
| `-z` | 根域名 |
| `-h` | 子域名 |

### Vercel

```bash
curl -sO https://raw.githubusercontent.com/zhojielun/DDNS/refs/heads/master/vercel.sh && chmod +x vercel.sh
```

| 参数 | 说明 |
|------|------|
| `-s` | API Token |
| `-z` | 根域名 |
| `-h` | 子域名 |
| `-e` | Team ID (可选) |

### 百度云 DNS

```bash
curl -sO https://raw.githubusercontent.com/zhojielun/DDNS/refs/heads/master/baidu.sh && chmod +x baidu.sh
```

| 参数 | 说明 |
|------|------|
| `-k` | Access Key |
| `-s` | Secret Key |
| `-z` | 根域名 |
| `-h` | 子域名 |

### 腾讯云 EdgeOne

```bash
curl -sO https://raw.githubusercontent.com/zhojielun/DDNS/refs/heads/master/edgeone.sh && chmod +x edgeone.sh
```

| 参数 | 说明 |
|------|------|
| `-k` | Secret ID |
| `-s` | Secret Key |
| `-z` | 根域名 |
| `-h` | 子域名 |

### Callback (自定义回调)

```bash
curl -sO https://raw.githubusercontent.com/zhojielun/DDNS/refs/heads/master/callback.sh && chmod +x callback.sh
```

| 参数 | 说明 |
|------|------|
| `-u` | 回调 URL |
| `-s` | POST 请求体 (可选) |
| `-z` | 根域名 |
| `-h` | 子域名 |

支持的变量：
- `#{ip}` - 新的 IP 地址
- `#{domain}` - 完整域名
- `#{recordType}` - 记录类型 (A/AAAA)
- `#{ttl}` - TTL 值
- `#{timestamp}` - 当前时间戳

## 使用示例

### 华为云 DNS

```bash
./huawei.sh -k "your-access-key" -s "your-secret-key" -z "example.com" -h "home" -t A -r "ap-southeast-1"
```

### Cloudflare DDNS

```bash
./cloudflare.sh -k "your-api-key" -u "you@email.com" -z "example.com" -h "home" -t A
```

### 阿里云 DNS

```bash
./alidns.sh -k "your-access-key-id" -s "your-access-key-secret" -z "example.com" -h "home" -t A
```

### DNSPod

```bash
./dnspod.sh -k "your-token-id" -s "your-token" -z "example.com" -h "home" -t A
```

### 自定义回调

```bash
./callback.sh -u "https://your-api.com/update?domain=#{domain}&ip=#{ip}" -z "example.com" -h "home" -t A
```

### 定时任务示例

```bash
# 编辑 crontab
crontab -e

# 每1分钟更新 Cloudflare
*/1 * * * * /root/ddns/cloudflare.sh -k "key" -u "email" -z "example.com" -h "home" -t A >/dev/null 2>&1

# 每10分钟更新阿里云 DNS
*/10 * * * * /root/ddns/alidns.sh -k "key" -s "secret" -z "example.com" -h "home" -t A >/dev/null 2>&1
```

## 文件结构

```
/root/ddns/
├── common.sh          # 通用辅助函数
├── huawei.sh          # 华为云 DNS
├── cloudflare.sh      # Cloudflare
├── alidns.sh          # 阿里云 DNS
├── aliesa.sh          # 阿里云 ESA
├── dnspod.sh          # DNSPod
├── tencent_cloud.sh   # 腾讯云 DNS
├── edgeone.sh         # 腾讯云 EdgeOne
├── baidu.sh           # 百度云 DNS
├── traffic_route.sh   # 火山引擎
├── porkbun.sh         # Porkbun
├── godaddy.sh         # GoDaddy
├── namecheap.sh       # Namecheap
├── namesilo.sh        # NameSilo
├── dynadot.sh         # Dynadot
├── dynv6.sh           # Dynv6
├── vercel.sh          # Vercel
├── spaceship.sh       # Spaceship
├── dnsla.sh           # DNSLA
├── cloudns.sh         # ClouDNS
├── gcore.sh           # Gcore
├── name_com.sh        # Name.com
├── nsone.sh           # IBM NS1
├── rainyun.sh         # 雨云
├── nowcn.sh           # 时代互联
├── eranet.sh          # Eranet
├── tnethk.sh          # Tnet.hk
├── hipmdnsmgr.sh      # HiPM DNS
└── callback.sh        # 自定义回调
```

## 依赖

- `bash` 4.0+
- `curl`
- `openssl` (用于签名)
- `grep`, `sed`, `awk` (标准工具)
- `python3` (阿里云/百度云/火山引擎/腾讯云 EdgeOne 脚本需要)

## 注意事项

1. **IP 缓存**: 脚本会将当前 IP 缓存到 `$HOME/.<provider>-wan_ip_<domain>.txt`，只有 IP 变化时才会更新
2. **首次运行**: 首次运行会直接更新 DNS 记录
3. **错误处理**: 脚本会在 API 调用失败时返回非零退出码
4. **安全性**: 请勿将包含 API 密钥的脚本提交到版本控制系统

## License

MIT
