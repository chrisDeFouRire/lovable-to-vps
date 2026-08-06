#!/bin/bash
set -euo pipefail

[[ $(id -u) -eq 0 ]] || { echo "run as root on the VPS" >&2; exit 1; }
[[ $# -ge 1 && $# -le 4 ]] || { echo "usage: $0 <staging|production> [private-bucket] [protected-function] [profile-table]" >&2; exit 2; }
env_name=$1
bucket=${2:-private-files}
function_name=${3:-admin-users}
profile_table=${4:-profiles}
case "$env_name" in staging|production) ;; *) echo "invalid environment" >&2; exit 2;; esac
cd "/opt/supabase-$env_name"
credentials="/root/supabase-$env_name-admin-passwords"
[[ -f $credentials ]] || { echo "missing root-only test credentials: $credentials" >&2; exit 1; }
port=$(grep '^KONG_HTTP_PORT=' .env | cut -d= -f2-)
anon=$(grep '^ANON_KEY=' .env | cut -d= -f2-)
read -r email password < "$credentials"
login=$(jq -nc --arg email "$email" --arg password "$password" '{email:$email,password:$password}')
auth=$(curl -fsS -X POST "http://127.0.0.1:$port/auth/v1/token?grant_type=password" -H "apikey: $anon" -H 'Content-Type: application/json' -d "$login")
token=$(jq -er '.access_token' <<<"$auth")
user=$(jq -er '.user.id' <<<"$auth")

echo 'authentication: passed'
profile=$(curl -fsS "http://127.0.0.1:$port/rest/v1/$profile_table?select=user_id&user_id=eq.$user" -H "apikey: $anon" -H "Authorization: Bearer $token")
jq -e --arg user "$user" 'any(.[]; .user_id == $user)' >/dev/null <<<"$profile"
echo 'own-profile RLS read: passed'

path="$user/smoke-$(date +%s).txt"
cleanup() {
  curl -fsS -X DELETE "http://127.0.0.1:$port/storage/v1/object/$bucket/$path" -H "apikey: $anon" -H "Authorization: Bearer $token" >/dev/null 2>&1 || true
}
trap cleanup EXIT
upload=$(printf smoke | curl -sS -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$port/storage/v1/object/$bucket/$path" -H "apikey: $anon" -H "Authorization: Bearer $token" -H 'Content-Type: text/plain' --data-binary @-)
[[ $upload == 200 ]]
download=$(curl -sS -o /tmp/supabase-smoke-download -w '%{http_code}' "http://127.0.0.1:$port/storage/v1/object/authenticated/$bucket/$path" -H "apikey: $anon" -H "Authorization: Bearer $token")
[[ $download == 200 ]] && grep -qx smoke /tmp/supabase-smoke-download
rm -f /tmp/supabase-smoke-download
cleanup
trap - EXIT
echo 'private storage upload/download/delete: passed'

function_auth=$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/functions/v1/$function_name?action=list" -H "apikey: $anon" -H "Authorization: Bearer $token")
[[ $function_auth == 200 ]]
function_unauth=$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/functions/v1/$function_name?action=list" -H "apikey: $anon" -H "Authorization: Bearer $anon")
[[ $function_unauth == 401 ]]
echo 'protected function authorization: passed'

realtime=$(curl --http1.1 -sS -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:$port/realtime/v1/websocket?apikey=$anon&vsn=1.0.0" -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' || true)
[[ $realtime == 101 ]]
echo 'Realtime WebSocket upgrade: passed'
