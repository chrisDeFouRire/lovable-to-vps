# Lovable to Infomaniak VPS

A reusable Pi user skill for migrating a conventional Lovable React/Vite/Supabase application to an Infomaniak Ubuntu VPS.

It covers repository auditing, GitHub staging/production branches, read-only deploy keys, Docker on a data volume, isolated self-hosted Supabase stacks, Caddy/DNS/TLS, migrations, Edge Functions, static deployments, administrators, backups, verification, and rollback.

## Install

```sh
git clone https://github.com/chrisDeFouRire/lovable-to-vps.git \
  ~/.pi/agent/skills/lovable-to-infomaniak-vps
```

Restart Pi if the skill is not discovered in the current session.

## Contents

- `SKILL.md` — triggering metadata and operating rules
- `references/` — migration, Supabase, security, and production workflow documentation
- `scripts/` — audited deployment helpers
- `assets/` — parameterized operations templates

## Safety

The repository contains placeholders only: no application IDs, server addresses, credentials, generated Supabase environments, or customer data. Review downloaded installers and generated configuration before execution, pin Supabase releases, and never commit deployment secrets.

## Status

Private while the workflow is being hardened. Choose and add a license before making the repository public.
