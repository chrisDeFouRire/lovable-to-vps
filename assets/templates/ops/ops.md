# Operations

Source of truth for {{APP_NAME}} infrastructure. Update this file and tracked `ops/` files with every operational change.

## Environment map

| Item | Staging | Production |
| --- | --- | --- |
| Git branch | `{{STAGING_BRANCH}}` | `{{PRODUCTION_BRANCH}}` |
| Source | `/opt/{{APP_SLUG}}-staging` | `/opt/{{APP_SLUG}}-production` |
| Static root | `/var/www/{{APP_SLUG}}-staging` | `/var/www/{{APP_SLUG}}-production` |
| Supabase config | `/opt/supabase-staging` | `/opt/supabase-production` |
| Supabase data | `{{DATA_ROOT}}/supabase-staging` | `{{DATA_ROOT}}/supabase-production` |
| App URL | `https://staging.{{BASE_DOMAIN}}` | `https://prod.{{BASE_DOMAIN}}` |
| Supabase URL | `https://supabase-staging.{{BASE_DOMAIN}}` | `https://supabase-prod.{{BASE_DOMAIN}}` |

SSH alias: `{{SSH_HOST}}`. Git remote: `{{GITHUB_REPO}}`. Supabase release: `{{SUPABASE_REF}}`.

## Tracked configuration

| Repository file | Installed path |
| --- | --- |
| `ops/docker/daemon.json` | `/etc/docker/daemon.json` |
| `ops/Caddyfile` | `/etc/caddy/Caddyfile` (both environments) |
| `ops/<environment>/supabase/docker-compose.yml` | `/opt/supabase-<environment>/docker-compose.yml` |
| `ops/<environment>/supabase/.supabase-version` | `/opt/supabase-<environment>/.supabase-version` |
| `ops/<environment>/supabase/.app-migrations` | `/opt/supabase-<environment>/.app-migrations` |
| `ops/<environment>/backup/supabase-db-backup` | `/etc/cron.daily/{{APP_SLUG}}-<environment>-db-backup` |

Never commit generated `.env`, credentials, keys, database files, storage objects, dumps, or certificates.

## Provider control plane

Record A, AAAA, CNAME, and network-firewall changes here, including actual addresses and verification dates. Public inbound ports are TCP 80 and 443 for IPv4 and IPv6. Keep Supabase gateway and database ports private.

## Installation log

Document the actual commands, versions, reviewed upstream setup-script SHA-256, generated paths, ownership, verification, and rollback as each phase is completed. Follow the `lovable-to-vps` user skill; do not leave this as a generic placeholder after deployment.

## Deployment

Staging updates use `git pull --ff-only origin {{STAGING_BRANCH}}`; production updates use `git pull --ff-only origin {{PRODUCTION_BRANCH}}`. Promote an accepted staging revision to `{{PRODUCTION_BRANCH}}` through a reviewed fast-forward merge or pull request, then deploy from the production checkout. Keep both environment configurations tracked on both branches so either checkout can perform drift checks.

Build Vite on a trusted workstation and atomically deploy `dist/` to the matching static root. Environment build files are independent and root-owned on the server:

- `/opt/{{APP_SLUG}}-staging/.env.staging.local`
- `/opt/{{APP_SLUG}}-production/.env.production.local`

Production uses its own Supabase secrets, migration marker, administrators, Edge Functions, database backup job, storage directory, previous static release, and rollback procedure. Never seed production by copying staging `.env`, database, storage, or credentials.

## Production acceptance

Before declaring production live, record the promoted Git commit and verify all production containers are healthy; public ports are loopback-only except Caddy; app and SPA fallback return `200` over IPv4/IPv6; Auth and unauthenticated protected functions return `401`; authenticated profile/RLS, private storage upload/download/delete, administrator function, and Realtime `101` pass; and the production dump is readable with `pg_restore -l`.

## Verification

Record app root, SPA fallback, Auth, RLS, private storage, protected Edge Function, Realtime, backup validation, IPv4/IPv6 TLS, and tracked-config drift results.

## Rollback

Static app: swap current and `.previous` directories. Database: use a tested compensating migration or verified restore. Supabase stack stop preserves data; never use `reset.sh` after data exists.
