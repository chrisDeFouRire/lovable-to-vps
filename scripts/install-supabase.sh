#!/bin/sh
set -eu

[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }
[ "$#" -ge 2 ] || { echo "usage: $0 <staging|production> <base-domain> [data-root] [supabase-ref] [reviewed-setup-sha256]" >&2; exit 2; }
env_name=$1
base_domain=$2
data_root=${3:-/mnt/data}
ref=${4:-}
setup_hash=${5:-}
case "$env_name" in staging) app_label=staging; kong_http=8001; kong_https=8444; postgres=5433; pooler=6544;; production) app_label=prod; kong_http=8002; kong_https=8445; postgres=5434; pooler=6545;; *) echo "environment must be staging or production" >&2; exit 2;; esac
[ -n "$ref" ] || { echo "pin an explicit Supabase ref, e.g. self-hosted/vX.Y.Z" >&2; exit 2; }
[ -d "$data_root" ] || { echo "missing data root: $data_root" >&2; exit 1; }

project_dir="/opt/supabase-$env_name"
[ ! -e "$project_dir" ] || { echo "refusing to overwrite $project_dir" >&2; exit 1; }
setup=/tmp/supabase-setup.sh
log="/root/supabase-$env_name-setup.log"
curl -fsSL https://raw.githubusercontent.com/supabase/supabase/refs/heads/master/docker/setup.sh -o "$setup"
chmod 755 "$setup"
actual_hash=$(sha256sum "$setup" | awk '{print $1}')
if [ -z "$setup_hash" ]; then
  echo "Downloaded $setup with SHA-256 $actual_hash" >&2
  echo "Inspect it, then rerun with that hash as the fifth argument." >&2
  exit 2
fi
[ "$actual_hash" = "$setup_hash" ] || { echo "setup script hash mismatch: expected $setup_hash, got $actual_hash" >&2; exit 1; }
install -m 600 /dev/null "$log"
if ! (cd /opt && sh "$setup" --skip-deps -y --ref "$ref" --project-dir "supabase-$env_name") >"$log" 2>&1; then
  echo "setup failed; root-only diagnostic log retained at $log" >&2
  exit 1
fi
# The generated SQL and configuration are bind-mounted into non-root containers.
# Normalize readability before first start; a restrictive caller umask otherwise
# causes PostgreSQL initialization failures such as unreadable 98-webhooks.sql.
chmod -R a+rX "$project_dir"
chmod 600 "$project_dir/.env"
(cd "$project_dir" && sh utils/generate-keys.sh --update-env >/dev/null && sh utils/add-new-auth-keys.sh --update-env >/dev/null)
chmod 600 "$project_dir/.env"
if find "$project_dir/volumes/db" -type f ! -perm -004 -print | grep -q .; then
  echo "database initialization files are not world-readable" >&2
  exit 1
fi
rm -f "$log"

export ENV_NAME="$env_name" APP_LABEL="$app_label" BASE_DOMAIN="$base_domain" DATA_ROOT="$data_root"
export KONG_HTTP="$kong_http" KONG_HTTPS="$kong_https" POSTGRES_PORT="$postgres" POOLER_PORT="$pooler" PROJECT_DIR="$project_dir"
python3 - <<'PY'
import os
from pathlib import Path

env_name=os.environ['ENV_NAME']; label=os.environ['APP_LABEL']; base=os.environ['BASE_DOMAIN']
p=Path(os.environ['PROJECT_DIR'])/'.env'
values={
 'SUPABASE_PUBLIC_URL':f'https://supabase-{label}.{base}',
 'API_EXTERNAL_URL':f'https://supabase-{label}.{base}/auth/v1',
 'SITE_URL':f'https://{label}.{base}',
 'ADDITIONAL_REDIRECT_URLS':f'https://{label}.{base}/**',
 'DISABLE_SIGNUP':'true', 'ENABLE_EMAIL_AUTOCONFIRM':'false',
 'POSTGRES_PORT':os.environ['POSTGRES_PORT'],
 'POOLER_PROXY_PORT_TRANSACTION':os.environ['POOLER_PORT'],
 'POOLER_TENANT_ID':env_name,
 'KONG_HTTP_PORT':os.environ['KONG_HTTP'], 'KONG_HTTPS_PORT':os.environ['KONG_HTTPS'],
 'PROXY_DOMAIN':f'supabase-{label}.{base}',
}
lines=p.read_text().splitlines(); seen=set()
for i,line in enumerate(lines):
    key=line.split('=',1)[0]
    if key in values:
        lines[i]=f'{key}={values[key]}'; seen.add(key)
missing=values.keys()-seen
if missing: raise SystemExit(f'upstream .env changed; missing keys: {sorted(missing)}')
p.write_text('\n'.join(lines)+'\n'); p.chmod(0o600)

p=Path(os.environ['PROJECT_DIR'])/'docker-compose.yml'; s=p.read_text()
def one(old,new):
    global s
    if s.count(old)!=1: raise SystemExit(f'upstream Compose changed; expected one occurrence: {old!r}, got {s.count(old)}')
    s=s.replace(old,new,1)
def some(old,new,minimum=1):
    global s
    if s.count(old)<minimum: raise SystemExit(f'upstream Compose changed; missing: {old!r}')
    s=s.replace(old,new)
one('name: supabase\n',f'name: supabase-{env_name}\n')
some('container_name: supabase-',f'container_name: supabase-{env_name}-')
one('container_name: realtime-dev.supabase-realtime',f'container_name: realtime-{env_name}.supabase-realtime')
one(f'    container_name: realtime-{env_name}.supabase-realtime\n',f'    container_name: realtime-{env_name}.supabase-realtime\n    networks:\n      default:\n        aliases:\n          - realtime-dev.supabase-realtime\n')
one('- ${KONG_HTTP_PORT}:8000/tcp','- 127.0.0.1:${KONG_HTTP_PORT}:8000/tcp')
one('- ${KONG_HTTPS_PORT}:8443/tcp','- 127.0.0.1:${KONG_HTTPS_PORT}:8443/tcp')
one('- ${POSTGRES_PORT}:5432','- 127.0.0.1:${POSTGRES_PORT}:5432')
one('- ${POOLER_PROXY_PORT_TRANSACTION}:6543','- 127.0.0.1:${POOLER_PROXY_PORT_TRANSACTION}:6543')
some('./volumes/db/data:/var/lib/postgresql/data:Z',f"{os.environ['DATA_ROOT']}/supabase-{env_name}/db:/var/lib/postgresql/data:Z")
some('./volumes/storage:/var/lib/storage:z',f"{os.environ['DATA_ROOT']}/supabase-{env_name}/storage:/var/lib/storage:z")
p.write_text(s)
PY

install -d -m 755 "$data_root/supabase-$env_name/db" "$data_root/supabase-$env_name/storage"
cd "$project_dir"
docker compose config --quiet
sh run.sh start
docker compose ps
code=000
for _ in $(seq 1 60); do
  code=$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:$kong_http/auth/v1/" || true)
  [ "$code" = 401 ] && break
  sleep 2
done
[ "$code" = 401 ] || { echo "unexpected internal Auth status after startup: $code" >&2; exit 1; }
echo "Supabase $env_name installed; internal Auth HTTP 401."
echo "Copy non-secret docker-compose.yml and .supabase-version into the repository ops/$env_name/supabase/."
