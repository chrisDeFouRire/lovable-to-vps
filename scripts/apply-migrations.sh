#!/bin/sh
set -eu

[ "$#" -eq 3 ] || { echo "usage: $0 <ssh-host> <staging|production> <repository-directory>" >&2; exit 2; }
host=$1; env_name=$2; repo=$3
case "$env_name" in staging|production) ;; *) echo "invalid environment" >&2; exit 2;; esac
cd "$repo"
[ -d supabase/migrations ] || { echo "missing supabase/migrations" >&2; exit 1; }
marker="ops/$env_name/supabase/.app-migrations"
mkdir -p "$(dirname "$marker")"; touch "$marker"
remote_dir="/opt/supabase-$env_name"

for migration in $(find supabase/migrations -maxdepth 1 -type f -name '*.sql' -size +0 -print | LC_ALL=C sort); do
  name=$(basename "$migration")
  case "$name" in *[!A-Za-z0-9._-]*) echo "unsafe migration filename: $name" >&2; exit 1;; esac
  if ssh "$host" "sudo test -f '$remote_dir/.app-migrations' && sudo grep -Fxq '$name' '$remote_dir/.app-migrations'"; then
    grep -Fxq "$name" "$marker" || printf '%s\n' "$name" >> "$marker"
    continue
  fi
  echo "Applying $name"
  scp -q "$migration" "$host:/tmp/app-migration.sql"
  ssh "$host" "set -eu; cd '$remote_dir'; sudo docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -1 -U postgres -d postgres < /tmp/app-migration.sql; rm /tmp/app-migration.sql; printf '%s\\n' '$name' | sudo tee -a '$remote_dir/.app-migrations' >/dev/null; sudo sort -u -o '$remote_dir/.app-migrations' '$remote_dir/.app-migrations'; sudo chmod 644 '$remote_dir/.app-migrations'"
  printf '%s\n' "$name" >> "$marker"
done
LC_ALL=C sort -u -o "$marker" "$marker"
echo "Migration marker updated: $marker"
