#!/bin/sh
set -eu

repo=${1:-.}
cd "$repo"

echo '== repository =='
git status --short --branch 2>/dev/null || true
git remote -v 2>/dev/null || true

echo '== app =='
[ -f package.json ] && python3 - <<'PY'
import json
p=json.load(open('package.json'))
print('name:', p.get('name','unknown'))
print('scripts:', ', '.join(f'{k}={v}' for k,v in p.get('scripts',{}).items()))
print('supabase-js:', p.get('dependencies',{}).get('@supabase/supabase-js','not found'))
PY

echo '== tracked environment files =='
git ls-files 2>/dev/null | grep -E '(^|/)\.env($|\.)' || true

echo '== environment variable names =='
for f in .env .env.*; do
  [ -f "$f" ] || continue
  printf '%s: ' "$f"
  awk -F= '/^[A-Za-z_][A-Za-z0-9_]*=/{printf "%s ",$1} END{print ""}' "$f"
done

echo '== hard-coded Supabase/project-ID URLs =='
rg -n 'supabase\.co|VITE_SUPABASE_PROJECT_ID|functions/v1' src supabase 2>/dev/null || true

echo '== client bucket references =='
rg -o "storage\\.from\\(['\"][^'\"]+" src supabase/functions 2>/dev/null | sort -u || true

echo '== migrated buckets =='
rg -n "storage\\.buckets|VALUES[[:space:]]*\\(['\"]" supabase/migrations 2>/dev/null || true

echo '== RLS and policies =='
rg -n 'ENABLE ROW LEVEL SECURITY|CREATE POLICY|DROP POLICY' supabase/migrations 2>/dev/null | tail -100 || true

echo '== migrations/functions =='
find supabase/migrations -maxdepth 1 -type f -name '*.sql' -size +0 -print 2>/dev/null | sort || true
find supabase/functions -mindepth 2 -maxdepth 2 -name index.ts -print 2>/dev/null | sort || true

echo '== potential secrets in tracked files (review every hit) =='
git grep -nE 'SERVICE_ROLE_KEY=|POSTGRES_PASSWORD=|JWT_SECRET=|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|sb_secret_' 2>/dev/null || true
