# End-to-end workflow

## 1. Audit and decide

Run:

```sh
SKILL=~/.pi/agent/skills/lovable-to-infomaniak-vps
"$SKILL/scripts/audit-lovable-repo.sh" .
```

Confirm whether the app is static Vite, which npm command builds it, which environment names it reads, whether Supabase migrations/functions exist, and whether data must be migrated. A clean install reconstructs schema from SQL but does not recover users, rows, storage objects, dashboard-created buckets, or secrets.

## 2. Generate tracked operations files

Copy `assets/config.example.env`, fill non-secret values, then run:

```sh
cp "$SKILL/assets/config.example.env" /tmp/lovable-vps-config.env
$EDITOR /tmp/lovable-vps-config.env
"$SKILL/scripts/init-ops.py" --config /tmp/lovable-vps-config.env --repo .
```

Review and commit `ops/`, `.env.example`, and any required app fixes. Keep the generated runbook current after every operational change.

## 3. Configure Infomaniak

Create one A and one AAAA record for the base host, then CNAMEs for:

```text
staging
prod
supabase-staging
supabase-prod
```

Point each CNAME to the base host. In the Infomaniak network firewall allow inbound TCP 80 and 443 for IPv4 and IPv6. Do not expose 5432/5433, 6543/6544, 8000/8001, or 8443/8444.

Verify DNS before deployment:

```sh
dig +short A example.com
dig +short AAAA example.com
dig +short CNAME staging.example.com
```

## 4. GitHub and source checkouts

On the VPS, generate one read-only repository deploy key:

```sh
install -d -m 700 ~/.ssh
ssh-keygen -t ed25519 -N '' -C '<app> deploy key' -f ~/.ssh/<app>_deploy
chmod 600 ~/.ssh/<app>_deploy
chmod 644 ~/.ssh/<app>_deploy.pub
cat ~/.ssh/<app>_deploy.pub
```

Add only the public key in GitHub repository settings under **Deploy keys**, with write access disabled. Verify GitHub's host-key fingerprint before accepting it.

Create two independent clones:

```sh
GIT_SSH_COMMAND='ssh -i ~/.ssh/<app>_deploy -o IdentitiesOnly=yes' \
  git clone --branch staging --single-branch git@github.com:<owner>/<repo>.git /opt/<app>-staging
GIT_SSH_COMMAND='ssh -i ~/.ssh/<app>_deploy -o IdentitiesOnly=yes' \
  git clone --branch main --single-branch git@github.com:<owner>/<repo>.git /opt/<app>-production
```

Configure `core.sshCommand` in each clone and use `git pull --ff-only`. Never install `gh`, copy a personal key, or store a GitHub token merely to deploy one repository.

## 5. Bootstrap VPS

Copy and inspect the script, then run it on the VPS:

```sh
scp "$SKILL/scripts/bootstrap-vps.sh" <ssh-host>:/tmp/
ssh -t <ssh-host> 'sudo /tmp/bootstrap-vps.sh /mnt/data'
```

It installs Ubuntu-packaged Docker, Compose, and Caddy; moves Docker data to the data volume; adds log rotation; enables services; and runs a Docker smoke test. It deliberately does not add the login user to the root-equivalent `docker` group.

## 6. Install staging Supabase

Copy and inspect the script:

```sh
scp "$SKILL/scripts/install-supabase.sh" <ssh-host>:/tmp/
ssh -t <ssh-host> 'sudo /tmp/install-supabase.sh staging example.com /mnt/data self-hosted/<pinned-version>'
# The first run downloads setup.sh, prints its SHA-256, and exits.
ssh <ssh-host> 'sudo less /tmp/supabase-setup.sh'
ssh -t <ssh-host> 'sudo /tmp/install-supabase.sh staging example.com /mnt/data self-hosted/<pinned-version> <reviewed-sha256>'
```

Copy the generated non-secret Compose file and version marker back into `ops/staging/supabase/`. Install the single tracked Caddyfile containing all four staging/production app/API hosts before public checks:

```sh
scp ops/Caddyfile <ssh-host>:/tmp/app.Caddyfile
ssh <ssh-host> 'sudo install -m 644 /tmp/app.Caddyfile /etc/caddy/Caddyfile && sudo caddy validate --config /etc/caddy/Caddyfile && sudo systemctl reload caddy && rm /tmp/app.Caddyfile'
```

Start staging only. Verify all services are healthy and internal Auth returns `401`.

## 7. Reconcile application state

Fix audit findings before applying SQL:

- replace hard-coded `https://${projectId}.supabase.co/...` with `${VITE_SUPABASE_URL}/...`
- add corrective migrations for dashboard-created buckets or schema
- make sensitive buckets private and confirm ownership/control-chain policies
- remove tracked old `.env`; commit `.env.example`
- review stale tables, duplicate policies, and legacy Lovable migrations

Historical migrations that have been applied elsewhere should not be rewritten. Add corrective migrations at the end.

## 8. Apply migrations and functions

```sh
"$SKILL/scripts/apply-migrations.sh" <ssh-host> staging .
"$SKILL/scripts/deploy-functions.sh" <ssh-host> staging .
```

Review resulting table count, RLS coverage, policies, triggers, buckets, and function authorization. An unauthenticated protected function should return `401`, not `200`.

## 9. Deploy static staging app

Install the tracked Caddyfile first. Then:

```sh
"$SKILL/scripts/deploy-static.sh" <ssh-host> staging . <app-slug> <base-domain>
```

The script obtains the public anonymous key from the VPS without printing it, builds locally with the appropriate Vite mode, and atomically swaps the static directory while retaining one previous release.

## 10. Administrators, backups, and smoke tests

Run the admin helper on the VPS only after confirming the repository uses the conventional `public.user_roles(user_id, role)` model:

```sh
sudo /tmp/create-admins.sh staging admin1@example.com admin2@example.com
```

Retrieve generated passwords in a trusted terminal, distribute them securely, then delete the root-only credential file after password changes.

Install the generated cron script under `/etc/cron.daily`, run it once, and validate the newest dump using `pg_restore -l`. Database dumps do not include storage objects.

Run `verify-environment.sh`. For the conventional Lovable `profiles(user_id)` model, copy and run the bundled authenticated test with the real private bucket and protected function:

```sh
sudo /tmp/smoke-test-lovable.sh staging <private-bucket> <protected-function> profiles
```

Adapt or replace this check when the schema differs.

## 11. Promote the accepted revision

Do not deploy an arbitrary working tree. Ensure staging is clean and accepted, then merge its revision into the production branch through a reviewed pull request or an explicit fast-forward when branch history permits:

```sh
git fetch origin --prune
git switch main
git merge --ff-only origin/staging
git push origin main
```

If fast-forward is impossible, stop and review the divergent commits; do not force-push or create an unreviewed merge. Keep `ops/staging/` and `ops/production/` tracked on both branches. Update the production VPS clone independently:

```sh
ssh <ssh-host> 'cd /opt/<app>-production && git pull --ff-only origin main'
```

## 12. Install production Supabase

Repeat the reviewed-hash installer flow for `production`. It selects the production ports and paths:

```sh
ssh -t <ssh-host> 'sudo /tmp/install-supabase.sh production example.com /mnt/data self-hosted/<pinned-version>'
ssh <ssh-host> 'sudo less /tmp/supabase-setup.sh'
ssh -t <ssh-host> 'sudo /tmp/install-supabase.sh production example.com /mnt/data self-hosted/<pinned-version> <reviewed-sha256>'
```

Use fresh production secrets. Never copy staging `.env`, PostgreSQL data, Storage objects, JWT keys, administrator passwords, or migration marker. Copy the generated non-secret production Compose/version files into `ops/production/supabase/`, commit them, install the tracked copies, and check `docker compose config --quiet`.

If first boot reports unreadable database initialization SQL, follow the permission recovery in `references/supabase.md` only while the stack is provably empty.

## 13. Build all production state

Apply the same application migrations and functions to the independent production stack:

```sh
"$SKILL/scripts/apply-migrations.sh" <ssh-host> production .
"$SKILL/scripts/deploy-functions.sh" <ssh-host> production .
"$SKILL/scripts/deploy-static.sh" <ssh-host> production . <app-slug> <base-domain>
```

The static deploy creates `.env.production.local` from the production anonymous key, uses Vite mode `production`, and deploys to `/var/www/<app>-production`. Its hosted-Supabase check rejects only concrete `https://...supabase.co` URLs; dependency bundles legitimately contain wildcard text such as `*.supabase.co`.

Create administrators through the production Auth API independently, install the production cron script under its own name, run it once, and validate its dump with production `pg_restore -l`.

## 14. Production acceptance

Run basic and authenticated checks against production, not staging:

```sh
sudo /tmp/verify-environment.sh production <base-domain> /mnt/data <app-slug>
sudo /tmp/smoke-test-lovable.sh production <private-bucket> <protected-function> profiles
```

Also verify:

- all expected production containers are healthy
- production table/RLS/policy/trigger/bucket inventory matches the accepted schema
- app and SPA fallback return `200` over IPv4 and IPv6
- Auth and unauthenticated protected function return `401`
- authenticated own-profile RLS, private upload/download/delete, admin function, and Realtime `101` pass
- production Kong/PostgreSQL/pooler ports are bound only to `127.0.0.1`
- `/opt/<app>-production/.env.production.local` and `/opt/supabase-production/.env` are root-owned mode `600`
- production configuration has no drift from `ops/production/`
- production dump is non-empty, mode `600`, and readable with `pg_restore -l`
- memory and both root/data-volume free space remain acceptable with two stacks

Record the deployed Git commit and every result in `ops/ops.md`. Retrieve initial production passwords securely, require changes, then delete the root-only temporary credential file. Local database dumps still do not cover Storage objects or server loss.
