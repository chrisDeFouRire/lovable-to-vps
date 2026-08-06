# Security and operations

## Trust boundaries

- Verify the VPS SSH host-key fingerprint before accepting it.
- Verify GitHub's SSH host keys before deploy-key use.
- Download installers to a file and inspect them before execution.
- Keep generated Supabase `.env` root-owned with mode `600`.
- Keep deploy keys mode `600`; deploy key should be repository-specific and read-only.
- Do not add operators to the Docker group merely for convenience; it grants root-equivalent access.
- Never print service-role, database, JWT, private-key, or administrator secrets into chat or CI logs.

## Infomaniak control panel

Document manual provider actions because they are not represented on the VPS:

1. Base-domain A record to the server IPv4 address.
2. Base-domain AAAA record to the server IPv6 address.
3. CNAMEs for app/API staging and production names.
4. Network firewall TCP 80/443 inbound for IPv4 and IPv6.

Only Caddy should accept public traffic. Confirm database and gateway ports are loopback-bound:

```sh
sudo ss -lntup | grep -E ':(80|443|543[2-9]|654[3-9]|800[0-9]|844[3-9]) '
```

## Configuration ownership

The target repository's `ops/` directory should map tracked files to installed paths. After each approved change, update source control first or immediately reconcile it, install the tracked file, validate, and check drift with `diff -u`.

Record:

- exact commands and paths
- pinned versions
- manual Infomaniak actions
- verification output/expected status
- rollback procedure
- deferred SMTP, imports, off-server backup, and production work

## Static deployment rollback

Keep one previous static release. Deployment should create `<root>.new`, verify extraction, move current to `<root>.previous`, then atomically rename new to current. Rollback swaps current and previous. A Caddy reload is needed only if configuration changed.

## Database rollback

Do not improvise destructive SQL on a database containing data. Use a tested compensating migration or restore from a verified dump. Before upgrades, preserve `.env`, database dump, and storage objects off-server.

## Credential lifecycle

If administrator passwords are generated into a root-only VPS file:

1. retrieve through a trusted interactive SSH terminal
2. distribute out-of-band
3. require password changes
4. delete the temporary file

SMTP credentials and off-server backup credentials belong in protected server configuration or a secrets manager, never the repository.

## Minimum checks after changes

```sh
sudo docker compose config --quiet
sudo docker compose ps
sudo caddy validate --config /etc/caddy/Caddyfile
curl -4 -o /dev/null -w '%{http_code}\n' https://staging.example.com/
curl -6 -o /dev/null -w '%{http_code}\n' https://staging.example.com/
curl -o /dev/null -w '%{http_code}\n' https://supabase-staging.example.com/auth/v1/
```

Expected for a conventional deployment: app `200`, SPA fallback `200`, unauthenticated Auth `401`. Add authenticated tests for the actual authorization model rather than relying only on container health.
