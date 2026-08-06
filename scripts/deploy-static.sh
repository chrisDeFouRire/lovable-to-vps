#!/bin/sh
set -eu

[ "$#" -eq 5 ] || { echo "usage: $0 <ssh-host> <staging|production> <repository-directory> <app-slug> <base-domain>" >&2; exit 2; }
host=$1; env_name=$2; repo=$3; app=$4; base=$5
case "$env_name" in staging) label=staging;; production) label=prod;; *) echo "invalid environment" >&2; exit 2;; esac
case "$app" in *[!A-Za-z0-9._-]*) echo "unsafe app slug" >&2; exit 2;; esac
cd "$repo"
[ -f package-lock.json ] || { echo "package-lock.json required for npm ci" >&2; exit 1; }
local_env=".env.$env_name.local"
archive=$(mktemp /tmp/app-dist.XXXXXX.tar)
trap 'rm -f "$local_env" "$archive"' EXIT

ssh "$host" "cd /opt/supabase-$env_name && sudo sh -c 'key=\$(grep \"^ANON_KEY=\" .env | cut -d= -f2-); printf \"VITE_SUPABASE_URL=https://supabase-$label.$base\\nVITE_SUPABASE_PUBLISHABLE_KEY=%s\\n\" \"\$key\"'" > "$local_env"
chmod 600 "$local_env"
npm ci
npm test --if-present
npm run build -- --mode "$env_name"
[ -f dist/index.html ] || { echo "build did not create dist/index.html" >&2; exit 1; }
# supabase-js bundles harmless wildcard strings such as *.supabase.co; reject
# only a hard-coded hosted-project URL.
if grep -R -Eq 'https://[A-Za-z0-9.-]+\.supabase\.co' dist; then
  echo "build still contains a hosted Supabase project URL" >&2
  exit 1
fi
tar -cf "$archive" -C dist .
scp -q "$archive" "$host:/tmp/app-dist.tar"
ssh "$host" "set -eu
  root=/var/www/$app-$env_name
  sudo rm -rf \"\$root.new\"
  sudo install -d -m 755 \"\$root.new\"
  sudo tar -xf /tmp/app-dist.tar -C \"\$root.new\"
  sudo chown -R root:root \"\$root.new\"
  sudo rm -rf \"\$root.previous\"
  if [ -d \"\$root\" ]; then sudo mv \"\$root\" \"\$root.previous\"; fi
  sudo mv \"\$root.new\" \"\$root\"
  rm /tmp/app-dist.tar"

for path in / /nonexistent-spa-route; do
  code=$(curl -sS -o /dev/null -w '%{http_code}' "https://$label.$base$path")
  [ "$code" = 200 ] || { echo "unexpected HTTP $code for $path" >&2; exit 1; }
done
echo "Static $env_name deployment passed root and SPA-fallback checks."
