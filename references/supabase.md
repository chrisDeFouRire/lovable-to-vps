# Self-hosted Supabase

## Isolation model

Run one stack per environment, including one PostgreSQL container per stack. Sharing PostgreSQL couples roles, replication, upgrades, backup/restore, JWT secrets, and failures. The small resource saving is not worth the operational ambiguity.

Install staging first and leave production absent or stopped until launch. If resources are tight, stop staging when unused or disable optional services supported by the pinned upstream release; do not merge environments.

## Pin and preserve upstream

Use Supabase's official Docker setup script with an explicit `self-hosted/<version>` ref. The bundled installer first downloads the setup script and reports its SHA-256 without installing. Inspect it, then rerun with that reviewed hash; a changed download fails closed. The setup may print generated secrets, so the installer captures output in a root-only file, rotates generated keys before first start, and deletes the captured output after success.

Track:

- pinned `.supabase-version`
- customized `docker-compose.yml`
- Caddyfile
- applied application migration marker
- backup script
- runbook/TODO

Do not vendor the rest of the generated upstream bundle. Do not track generated `.env`.

## Required Compose changes

For each environment:

1. Give Compose a unique top-level project name.
2. Give containers unique environment-specific names.
3. Keep the Realtime environment-specific container name, but add network alias `realtime-dev.supabase-realtime` because upstream Kong routes may expect it.
4. Bind Kong HTTP/HTTPS and Supavisor session/transaction ports to `127.0.0.1`.
5. Move PostgreSQL and Storage bind mounts to the large data volume.
6. Use unique host ports and pooler tenant IDs.

The installer fails if expected upstream patterns are absent. Treat that as a request to inspect a newer upstream release, not as permission to apply approximate text edits.

### Installer-permission gotcha

Do not run the upstream generator under a persistent restrictive `umask`. Its database initialization SQL is bind-mounted into a non-root PostgreSQL container; mode `600` files can make first boot fail with errors such as `98-webhooks.sql: Permission denied`. Before the first start, normalize the generated tree with `chmod -R a+rX`, immediately restore generated `.env` to root-owned mode `600`, and verify every file under `volumes/db` is readable by the container.

If this is detected on a brand-new empty stack, stop it, remove the incomplete database directory and stack-owned named volumes, correct permissions, and initialize again:

```sh
cd /opt/supabase-<environment>
docker compose down -v
chmod -R a+rX /opt/supabase-<environment>
chmod 600 /opt/supabase-<environment>/.env
rm -rf /mnt/data/supabase-<environment>/db /mnt/data/supabase-<environment>/storage
install -d -m 755 /mnt/data/supabase-<environment>/db /mnt/data/supabase-<environment>/storage
docker compose config --quiet
sh run.sh start
```

Never use that reset procedure after any real data exists; restore a verified backup instead.

## Typical ports

| Service | Staging | Production |
| --- | ---: | ---: |
| Kong HTTP | 8001 | 8002 |
| Kong HTTPS | 8444 | 8445 |
| PostgreSQL/Supavisor session | 5433 | 5434 |
| Supavisor transaction | 6544 | 6545 |

All remain localhost-only. Caddy is the only public ingress.

## Environment values

Set environment-specific public URL, Auth external URL, site URL, redirect URLs, ports, pooler tenant ID, project labels, and proxy domain. Disable signup while SMTP and the account-creation flow are unfinished:

```dotenv
DISABLE_SIGNUP=true
ENABLE_EMAIL_AUTOCONFIRM=false
```

Do not copy staging secrets into production.

## Migrations

For a fresh database, apply non-empty SQL files in lexical order. Use:

```sh
psql -X -v ON_ERROR_STOP=1 -1 -U postgres -d postgres
```

Track filenames outside Supabase's internal schema because generic SQL execution does not populate CLI migration history. For later deployments, apply only files absent from the installed marker. If an application migration fails, leave it absent and investigate. Roll back with a tested compensating migration or restore, not manual deletion.

## Edge Functions

The default Docker setup discovers functions from its bind-mounted functions directory. Copy each tracked function directory under:

```text
/opt/supabase-<environment>/volumes/functions/<function>/
```

Do not copy local `.env` files. Test protected functions through Kong with the anonymous key and an anonymous bearer token; expected unauthorized response is generally `401`.

## Realtime gotcha

If `/realtime/v1/websocket` returns `503` while the Realtime container is healthy, inspect Kong logs and service DNS. Environment-specific renaming can break the upstream hostname `realtime-dev.supabase-realtime`. Add that network alias, recreate Realtime, and verify an HTTP `101` WebSocket upgrade. Include the anonymous key as required by the installed Supabase version.

## Production parity

Production is not a copy of staging data. Install the same pinned release independently with its own generated `.env`, Compose project, container names, loopback ports, database/storage mounts, migration marker, functions, administrators, static build environment, cron job, and backup directory. Apply the same migrations in order and rerun all authenticated tests. Keep production build configuration at `/opt/<app>-production/.env.production.local`; never reuse `.env.staging.local`.

After both stacks run, inspect listening sockets and memory/disk usage. Only Caddy should be public; both sets of Kong, PostgreSQL, and pooler ports remain loopback-only.

## Backups

A daily `pg_dump -Fc` protects PostgreSQL only. Validate with `pg_restore -l`. Also back up:

- `/opt/supabase-<environment>/.env` to protected encrypted storage
- `/mnt/data/supabase-<environment>/storage`
- database dumps to off-server storage

Never use Supabase `reset.sh` after data exists; it deletes database and storage state.
