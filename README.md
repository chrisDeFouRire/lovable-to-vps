# Lovable to VPS

A Pi user skill for migrating a conventional Lovable React/Vite/Supabase application to a self-managed Ubuntu or Debian VPS.

The workflow is provider-independent. It was developed on Infomaniak, but uses standard Linux, DNS, firewall, SSH, Docker, Caddy, and GitHub features that also apply to providers such as Hetzner, DigitalOcean, OVHcloud, Scaleway, Linode, and generic virtual or dedicated servers.

## What it covers

- auditing Lovable repositories and finding dashboard-only Supabase state
- GitHub `staging`/`main` promotion and read-only deploy keys
- separate staging and production source checkouts
- Docker data and persistent application data on a large volume
- two isolated self-hosted Supabase/PostgreSQL stacks
- Caddy reverse proxy, static SPA hosting, DNS, TLS, and firewall rules
- SQL migrations, storage buckets, RLS, and Edge Functions
- administrator creation without exposing credentials
- atomic Vite deployments and static rollback
- local database backups and restore-list validation
- authenticated RLS, Storage, function, and Realtime smoke tests
- tracked operations configuration and drift checks

## Requirements

- Pi coding agent
- an Ubuntu or Debian VPS with `sudo`
- a persistent data volume or sufficiently large root filesystem
- a domain whose DNS records you can change
- inbound TCP ports 80 and 443
- GitHub repository access
- local Git, SSH/SCP, Python 3, Node.js, and npm

Provider terminology varies. An Infomaniak “network firewall” may be called a cloud firewall, security group, network ACL, or firewall policy elsewhere. The required outcome is the same: expose only HTTP/HTTPS publicly and keep Supabase and database ports loopback-only.

## Install

```sh
git clone https://github.com/chrisDeFouRire/lovable-to-vps.git \
  ~/.pi/agent/skills/lovable-to-vps
```

Restart Pi if the skill is not discovered in the current session.

## Use

Ask Pi to migrate or deploy a Lovable application to a VPS. The skill first audits the repository and collects the repository, SSH alias, domain, data-volume path, migration decision, administrator emails, SMTP decision, and backup destination.

For direct use of the bundled scaffold:

```sh
SKILL=~/.pi/agent/skills/lovable-to-vps
cp "$SKILL/assets/config.example.env" /tmp/lovable-vps-config.env
$EDITOR /tmp/lovable-vps-config.env
"$SKILL/scripts/init-ops.py" --config /tmp/lovable-vps-config.env --repo /path/to/app
```

Review generated files and downloaded installers before execution. The scripts deliberately fail when an upstream Supabase template differs from the expected pinned structure.

## Repository layout

- `SKILL.md` — triggering metadata and operating rules
- `references/` — migration, Supabase, security, staging, and production runbooks
- `scripts/` — deployment and verification helpers
- `assets/` — parameterized operations templates

## Provider assumptions

The bundled bootstrap script uses APT and systemd. Adapt package installation and service commands for non-Debian distributions. DNS and perimeter-firewall changes are manual because provider APIs and control panels differ. Servers without IPv6 can omit IPv6 records and checks after documenting that decision.

## Security

This repository contains placeholders only: no application IDs, customer domains, server addresses, credentials, generated Supabase environments, or customer data. Never commit generated `.env` files, private keys, administrator passwords, database dumps, storage objects, or certificates.

## License

[MIT](LICENSE)
