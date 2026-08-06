---
name: lovable-to-infomaniak-vps
description: Migrate and operate Lovable.dev/Lovable.io Vite applications on an Infomaniak Ubuntu VPS, including GitHub staging/production branches and deploy keys, Docker on a data volume, two isolated self-hosted Supabase stacks, Caddy/DNS/TLS, migrations, Edge Functions, static deployments, administrators, backups, verification, and rollback. Use this skill whenever a user wants to leave Lovable hosting, self-host a Lovable app or Supabase, deploy a Lovable GitHub repository to Infomaniak, or build staging/production VPS infrastructure for a typical Lovable React/Vite/Supabase project—even if only one part of that migration is requested.
compatibility: Requires bash, Python 3, SSH/SCP, Git, curl, and an Ubuntu VPS with sudo. Local Vite builds require Node.js/npm.
---

# Lovable to Infomaniak VPS

Move a typical Lovable React/Vite/Supabase repository to an Infomaniak VPS with reproducible, isolated staging and production environments.

## First response

Do not start installing until the repository and server are understood. Ask only for missing items:

- repository URL and staging/production branch names (`staging` and `main` by default)
- local SSH alias for the VPS
- base domain and ability to change Infomaniak DNS/firewall settings
- whether this is a clean Supabase install or a data migration
- VPS data-volume path (`/mnt/data` by default)
- administrator emails
- SMTP details, or approval to postpone email
- off-server backup destination, or approval to postpone it

Never ask users to paste secrets into chat. Generate secrets on the VPS or enter them in a trusted terminal.

## Required reading

Read resources only when their phase is reached:

- Start with [references/workflow.md](references/workflow.md).
- Before changing the app or applying SQL, read [references/lovable-repository-audit.md](references/lovable-repository-audit.md).
- Before installing Supabase, read [references/supabase.md](references/supabase.md).
- Before touching DNS, firewall, keys, credentials, or backups, read [references/security-and-operations.md](references/security-and-operations.md).

## Bundled tools

Resolve all paths relative to this skill directory.

```sh
scripts/audit-lovable-repo.sh [repository-directory]
scripts/init-ops.py --config config.env --repo /path/to/repo
scripts/bootstrap-vps.sh [data-root]
scripts/install-supabase.sh <staging|production> <base-domain> [data-root] [supabase-ref] [reviewed-setup-sha256]
scripts/apply-migrations.sh <ssh-host> <staging|production> <repository-directory>
scripts/deploy-functions.sh <ssh-host> <staging|production> <repository-directory>
scripts/deploy-static.sh <ssh-host> <staging|production> <repository-directory> <app-slug> <base-domain>
scripts/rollback-static.sh <app-slug> <staging|production>
scripts/create-admins.sh <staging|production> <email> [email ...]
scripts/smoke-test-lovable.sh <staging|production> [private-bucket] [protected-function] [profile-table]
scripts/verify-environment.sh <staging|production> <base-domain> [data-root] [app-slug]
```

Execution location matters:

- Run `audit-lovable-repo.sh`, `init-ops.py`, `apply-migrations.sh`, `deploy-functions.sh`, and `deploy-static.sh` on the trusted workstation.
- Copy and run `bootstrap-vps.sh`, `install-supabase.sh`, `create-admins.sh`, `smoke-test-lovable.sh`, and `verify-environment.sh` on the VPS.
- Review every generated file and every downloaded installer before execution.

## Environment model

Use independent resources rather than application-level tenancy:

| Resource | Staging | Production |
| --- | --- | --- |
| Git branch | `staging` | `main` |
| Source | `/opt/<app>-staging` | `/opt/<app>-production` |
| Static root | `/var/www/<app>-staging` | `/var/www/<app>-production` |
| Supabase config | `/opt/supabase-staging` | `/opt/supabase-production` |
| Supabase data | `/mnt/data/supabase-staging` | `/mnt/data/supabase-production` |
| App hostname | `staging.<base-domain>` | `prod.<base-domain>` |
| API hostname | `supabase-staging.<base-domain>` | `supabase-prod.<base-domain>` |

Do not share checkouts, `.env` files, databases, storage, JWT secrets, Compose projects, containers, ports, or backups. A self-hosted Supabase deployment is one project; do not simulate staging/production with tenant IDs or a shared PostgreSQL container.

## Working rules

1. Inspect before changing. Run the audit and trace all Supabase URL construction, storage buckets, migrations, functions, auth roles, and RLS.
2. Create `ops/` in the target repository as the source of truth for non-secret configuration. Use the bundled initializer and adapt the generated runbook.
3. Keep secrets and runtime data server-only. Commit templates and exact non-secret configuration, never generated `.env`, keys, database files, objects, or certificates.
4. Pin the Supabase self-hosted release. Do not deploy an unrepeatable `master` snapshot.
5. Bind Kong, PostgreSQL, and Supavisor to `127.0.0.1`. Expose only Caddy on TCP 80/443.
6. Put Docker, PostgreSQL, storage, and backups on the large data volume.
7. Build static Vite apps on a trusted workstation. Caddy serves the output; no Node process is needed at runtime.
8. Apply each SQL migration in its own transaction with `ON_ERROR_STOP`. Track applied filenames. Never replay the full directory against a populated database.
9. Verify every phase and write exact commands, installed paths, versions, results, and rollback steps into `ops/ops.md`.
10. Deploy staging first. Promote the accepted revision into `main`, then repeat every stateful step for production with fresh secrets and distinct resources. Track both environment configurations on both branches so drift checks work from either checkout.

## Expected completion checks

Do not call the migration complete until these pass:

- repository has no tracked deployment secrets or old production `.env`
- frontend and functions no longer construct `*.supabase.co` URLs from a project ID
- every referenced storage bucket is created by a migration and sensitive buckets are private
- all intended tables have RLS and policies are reviewed for duplicate or world-readable access
- app root and SPA fallback return `200`
- unauthenticated Auth and protected Edge Function probes return the expected `401`
- authenticated login, own-row RLS, private upload/download/delete, admin function, and Realtime WebSocket checks pass
- daily database dump exists, is mode `600`, and `pg_restore -l` can read it
- tracked server configuration has no drift
- IPv4 and IPv6 TLS probes pass after Infomaniak firewall changes
- production repeats migration, function, administrator, backup, authenticated smoke, port-binding, and rollback checks independently; staging success is not production evidence

## Scope boundaries

The default scripts cover clean installs for conventional Lovable Vite + Supabase repositories. Existing Supabase data migration, custom backend runtimes, SSR, Dockerized app servers, unusual auth schemas, and zero-downtime database upgrades need project-specific work. Do not pretend the generic scripts cover those cases; preserve the same isolation, security, verification, and rollback principles.
