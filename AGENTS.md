# DDNS Shell Scripts

28 standalone Bash scripts for updating DNS records, converted from [ddns-go](https://github.com/jeensy2/ddns-go). No package manager, no build step, no tests, no CI — a flat collection of self-contained scripts.

## Requirements

- `bash` 4.0+, `curl`, `openssl`, `grep`, `sed`, `awk`
- `python3` required by: `alidns.sh`, `aliesa.sh`, `edgeone.sh`, `baidu.sh`, `traffic_route.sh` (URL encoding in HMAC signatures)

## Script pattern

Every provider script follows the same structure:

1. Strict mode: `set -o errexit/nounset/pipefail`
2. `getopts` parses `-k`/`-s`/`-z`/`-h`/`-t`/`-T` flags (exact flags vary per provider)
3. Fetches public IP from ipify (`api4.ipify.org` / `api6.ipify.org`)
4. Compares against cache in `$HOME/.<provider>-wan_ip_<host>.<domain>.txt`
5. If changed, queries existing records, then creates or updates via provider API
6. Saves new IP to cache file

`common.sh` provides `get_ipv4`, `get_ipv6`, `check_ip_changed`, `save_ip_cache`, `validate_ipv4`, `validate_ipv6` — but most scripts inline their own IP fetching and don't source it.

## Running

```bash
./cloudflare.sh -k "API_KEY" -u "email" -z "example.com" -h "home" -t A
```

Exit codes: `0` = success, `1` = failure, `2` = missing required argument.

## Provider quirks worth knowing

| Script | Quirk |
|--------|-------|
| `cloudflare.sh` | Uses `-u` for email (unique). Has `-f` force flag to skip IP-change check. |
| `namesilo.sh` | Uses `-s` for API key (not `-k`). Converts `@` host to `www`. |
| `namecheap.sh` | No `-t`/`-T` flags — IPv4 only. Uses `-k` for hostname. |
| `dnspod.sh` | Has `-l` for resolution line (default: `默认`). |
| `vercel.sh` | Has `-e` for optional Team ID. |
| `huawei.sh` | Pure Shell (no Python/SDK). Persists config to `.huawei_ddns.conf`. Supports `-reset`/`-help`. Uses region-specific endpoint `dns.{region}.myhuaweicloud.com`. |
| `callback.sh` | Supports `#{ip}`, `#{domain}`, `#{recordType}`, `#{ttl}`, `#{timestamp}` placeholders in URL and POST body. |

## Flag patterns

Most scripts: `-k` (key), `-s` (secret), `-z` (zone), `-h` (subdomain), `-t` (A/AAAA), `-T` (TTL).

Exceptions: `namesilo.sh`/`gcore.sh`/`nsone.sh`/`dynv6.sh`/`dynadot.sh` use `-s` for the single credential (no `-k`). `cloudflare.sh` uses `-u` for email. `callback.sh` uses `-u` for URL.

## Conventions

- Shebang: `#!/usr/bin/env bash`
- Credentials passed via flags or environment, never hardcoded
- IP cache: `$HOME/.<provider>-wan_ip_<subdomain>.<domain>.txt`
- Zone/ID cache: `$HOME/.<provider>-id_<subdomain>.<domain>.txt` (4-line format: zone_id, record_id, zone_name, record_name)
- README is in Chinese (Simplified)
- Git history is minimal (3 commits)

## Adding a new provider

Copy a script with a similar auth pattern. Follow the same getopts/variable structure. Add the provider table entry and CLI docs to `README.md`.

## Security

- Never hardcode credentials in scripts
- Don't commit API keys to version control
- Cache files in `$HOME/` may contain zone/record IDs — restrict permissions on shared systems
