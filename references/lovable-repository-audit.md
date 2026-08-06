# Lovable repository audit

## What source control usually contains

A conventional Lovable repository often contains:

- React/Vite frontend and `@supabase/supabase-js`
- `supabase/migrations/*.sql`
- `supabase/functions/<name>/index.ts`
- browser-facing Supabase URL and anonymous/publishable key
- SQL for tables, triggers, functions, grants, RLS, and some seed/reference data

It normally does not contain existing Auth users, application rows, storage objects, generated service-role/database/JWT secrets, or dashboard-only changes.

## Inspect the real flow

Run the bundled audit, then inspect every hit rather than replacing strings blindly:

```sh
rg -n 'supabase\.co|VITE_SUPABASE|SUPABASE_' src supabase .env* package.json
rg -n 'storage\.from|getPublicUrl|createSignedUrl|functions/v1' src supabase
rg -n 'storage\.buckets|CREATE POLICY|ALTER TABLE.*ENABLE ROW LEVEL SECURITY' supabase/migrations
find supabase/functions -mindepth 2 -maxdepth 2 -name index.ts -print
```

Watch for frontend code that creates Edge Function URLs from `VITE_SUPABASE_PROJECT_ID`. Self-hosted projects need:

```ts
`${import.meta.env.VITE_SUPABASE_URL}/functions/v1/<function>`
```

## Dashboard-state gaps

A common clean-install failure is policies referencing a bucket that no migration creates. Policies can exist before the bucket row, so all SQL may apply successfully while uploads still fail. Compare each client `storage.from("bucket")` with `INSERT INTO storage.buckets` migrations.

Add a final corrective migration rather than altering historical SQL:

```sql
INSERT INTO storage.buckets (id, name, public)
VALUES ('private-files', 'private-files', false)
ON CONFLICT (id) DO UPDATE SET public = false;
```

Do the same for missing schema, grants, seed data, or policy cleanup. Dashboard-created state is not reproducible until represented in source control.

## Security review

For each table:

- confirm RLS is enabled
- list all policies and remember permissive policies combine with OR
- identify duplicate legacy policies left by Lovable refactors
- trace authorization through ownership relationships
- check admin role tables/functions cannot be modified by ordinary users

For each storage bucket:

- confirm sensitive buckets have `public = false`
- confirm `SELECT`, `INSERT`, `UPDATE`, and `DELETE` policies use ownership or control-chain checks
- do not assume signed URLs protect a bucket marked public

For each Edge Function:

- validate CORS deliberately
- validate JWTs and authorization inside the function where required
- never expose service-role keys to frontend code
- test unauthenticated, ordinary-user, and administrator behavior

## Environment cleanup

A Supabase anonymous key is browser-facing, but an old deployment `.env` should still be removed from tracking because it silently directs builds to the former project. Track only:

```dotenv
VITE_SUPABASE_URL=https://supabase.example.com
VITE_SUPABASE_PUBLISHABLE_KEY=replace-with-public-anon-key
```

Ignore `.env` and `*.local`. Scan staged changes for JWTs, service-role keys, passwords, private keys, and generated Supabase `.env` files before every commit.

## Data migration boundary

A clean install and a migration are different jobs. If users, database rows, storage objects, password hashes, or custom catalog data must survive, stop and design an export/import plan before creating production. Never claim migrations recreate data that is absent from SQL.
