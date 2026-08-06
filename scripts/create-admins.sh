#!/bin/bash
set -euo pipefail

[[ $(id -u) -eq 0 ]] || { echo "run as root on the VPS" >&2; exit 1; }
[[ $# -ge 2 ]] || { echo "usage: $0 <staging|production> <email> [email ...]" >&2; exit 2; }
env_name=$1; shift
case "$env_name" in staging|production) ;; *) echo "invalid environment" >&2; exit 2;; esac
cd "/opt/supabase-$env_name"
credentials="/root/supabase-$env_name-admin-passwords"
[[ ! -e $credentials ]] || { echo "refusing to overwrite $credentials" >&2; exit 1; }
anon=$(grep '^ANON_KEY=' .env | cut -d= -f2-)
service=$(grep '^SERVICE_ROLE_KEY=' .env | cut -d= -f2-)
users=$(curl -fsS 'http://127.0.0.1:'"$(grep '^KONG_HTTP_PORT=' .env | cut -d= -f2-)"'/auth/v1/admin/users?page=1&per_page=1000' -H "apikey: $service" -H "Authorization: Bearer $service")
for email in "$@"; do
  jq -e --arg email "$email" 'all(.users[]; .email != $email)' >/dev/null <<<"$users" || { echo "user already exists; refusing password reset: $email" >&2; exit 1; }
done

umask 077
: > "$credentials"
port=$(grep '^KONG_HTTP_PORT=' .env | cut -d= -f2-)
for email in "$@"; do
  password=$(openssl rand -base64 24 | tr -d '\n')
  body=$(jq -nc --arg email "$email" --arg password "$password" '{email:$email,password:$password,email_confirm:true}')
  response=$(curl -fsS -X POST "http://127.0.0.1:$port/auth/v1/admin/users" -H "apikey: $service" -H "Authorization: Bearer $service" -H 'Content-Type: application/json' -d "$body")
  id=$(jq -er '.id' <<<"$response")
  role=$(jq -nc --arg id "$id" '[{user_id:$id,role:"admin"}]')
  curl -fsS -X POST "http://127.0.0.1:$port/rest/v1/user_roles?on_conflict=user_id,role" -H "apikey: $service" -H "Authorization: Bearer $service" -H 'Content-Type: application/json' -H 'Prefer: resolution=ignore-duplicates,return=minimal' -d "$role" >/dev/null
  printf '%s %s\n' "$email" "$password" >> "$credentials"

  login=$(jq -nc --arg email "$email" --arg password "$password" '{email:$email,password:$password}')
  token=$(curl -fsS -X POST "http://127.0.0.1:$port/auth/v1/token?grant_type=password" -H "apikey: $anon" -H 'Content-Type: application/json' -d "$login" | jq -er '.access_token')
  roles=$(curl -fsS "http://127.0.0.1:$port/rest/v1/user_roles?select=role" -H "apikey: $anon" -H "Authorization: Bearer $token")
  jq -e 'any(.[]; .role == "admin")' >/dev/null <<<"$roles"
  echo "$email: login and admin role verified"
done
chmod 600 "$credentials"
echo "Initial credentials are in $credentials (mode 600). Retrieve securely, require changes, then delete it."
