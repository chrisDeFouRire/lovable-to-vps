#!/bin/sh
set -eu

[ "$#" -eq 3 ] || { echo "usage: $0 <ssh-host> <staging|production> <repository-directory>" >&2; exit 2; }
host=$1; env_name=$2; repo=$3
case "$env_name" in staging|production) ;; *) echo "invalid environment" >&2; exit 2;; esac
cd "$repo"
[ -d supabase/functions ] || { echo "no supabase/functions directory" >&2; exit 1; }
archive=$(mktemp /tmp/supabase-functions.XXXXXX.tar)
trap 'rm -f "$archive"' EXIT
tar --exclude='.env' --exclude='.env.*' -cf "$archive" -C supabase/functions .
scp -q "$archive" "$host:/tmp/supabase-functions.tar"
ssh "$host" "set -eu; dest=/opt/supabase-$env_name/volumes/functions; sudo install -d -m 755 \"\$dest\"; sudo tar -xf /tmp/supabase-functions.tar -C \"\$dest\"; sudo find \"\$dest\" -type d -exec chmod 755 {} +; sudo find \"\$dest\" -type f -exec chmod 644 {} +; rm /tmp/supabase-functions.tar"
echo "Edge Functions deployed to Supabase $env_name. Test authorization through Kong."
