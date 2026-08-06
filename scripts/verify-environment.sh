#!/bin/sh
set -eu

[ "$(id -u)" -eq 0 ] || { echo "run as root on the VPS" >&2; exit 1; }
[ "$#" -ge 2 ] && [ "$#" -le 4 ] || { echo "usage: $0 <staging|production> <base-domain> [data-root] [app-slug]" >&2; exit 2; }
env_name=$1; base=$2; data_root=${3:-/mnt/data}; app=${4:-}
case "$env_name" in staging) label=staging;; production) label=prod;; *) echo "invalid environment" >&2; exit 2;; esac
cd "/opt/supabase-$env_name"
docker compose config --quiet
docker compose ps
unhealthy=$(docker compose ps --format json | python3 -c 'import json,sys; print(sum(1 for l in sys.stdin if (x:=json.loads(l)).get("Health") not in ("healthy", "")))')
[ "$unhealthy" -eq 0 ] || { echo "$unhealthy unhealthy containers" >&2; exit 1; }

kong_http=$(grep '^KONG_HTTP_PORT=' .env | cut -d= -f2-)
kong_https=$(grep '^KONG_HTTPS_PORT=' .env | cut -d= -f2-)
postgres=$(grep '^POSTGRES_PORT=' .env | cut -d= -f2-)
pooler=$(grep '^POOLER_PROXY_PORT_TRANSACTION=' .env | cut -d= -f2-)
[ "$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:$kong_http/auth/v1/")" = 401 ]
for port in "$kong_http" "$kong_https" "$postgres" "$pooler"; do
  ss -H -lnt | awk '{print $4}' | grep -Fqx "127.0.0.1:$port" || { echo "port is missing or not IPv4-loopback-bound: $port" >&2; exit 1; }
done

families='4 6'
[ "${SKIP_IPV6:-0}" = 1 ] && families=4
for family in $families; do
  [ "$(curl -"$family" -sS -o /dev/null -w '%{http_code}' "https://$label.$base/")" = 200 ]
  [ "$(curl -"$family" -sS -o /dev/null -w '%{http_code}' "https://$label.$base/nonexistent-spa-route")" = 200 ]
  [ "$(curl -"$family" -sS -o /dev/null -w '%{http_code}' "https://supabase-$label.$base/auth/v1/")" = 401 ]
done

[ "$(stat -c '%U:%G %a' .env)" = 'root:root 600' ] || { echo "Supabase .env ownership/mode must be root:root 600" >&2; exit 1; }
if [ -n "$app" ]; then
  build_env="/opt/$app-$env_name/.env.$env_name.local"
  [ "$(stat -c '%U:%G %a' "$build_env")" = 'root:root 600' ] || { echo "build environment ownership/mode must be root:root 600: $build_env" >&2; exit 1; }
fi

latest=$(find "$data_root/backups/supabase-$env_name" -type f -name 'postgres-*.dump' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2- || true)
if [ -n "$latest" ]; then
  test -s "$latest"
  sh -c "docker compose exec -T db pg_restore -l < '$latest' >/dev/null"
  [ "$(stat -c '%U:%G %a' "$latest")" = 'root:root 600' ] || { echo "backup ownership/mode must be root:root 600" >&2; exit 1; }
  stat -c 'backup=%n size=%s mode=%a owner=%U:%G' "$latest"
else
  echo "warning: no local database backup found" >&2
fi
free -h
df -h / "$data_root"
echo "Basic address-family, port-binding, permission, backup, and resource checks passed for $env_name."
