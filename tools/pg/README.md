# Local PostgreSQL (user-space, no Docker/root)

Development database for the Uko? API. Production uses the PostGIS image in
`app/docker-compose.yml`.

- Binaries: `@embedded-postgres/linux-x64` 18.7 (installed under `node_modules`)
- Cluster data: `data/` (git-ignored)
- Port: `55432`, user `uko`, database `uko`, trust auth on 127.0.0.1 only

```bash
./start.sh          # initdb on first run, then start + create db
node migrate.mjs    # apply core schema (no PostGIS)
./stop.sh
```

The API connects with:

```bash
AUTH_STORE=postgres DATABASE_URL=postgres://uko@127.0.0.1:55432/uko npm run start:dev
```

For PostGIS zones/pricing, apply `app/db/migrations/0002_zones_postgis.sql`
against a PostGIS-enabled database (production compose or a real Postgres+PostGIS).


## Backup and restore

```bash
node backup.mjs                              # JSON backup + manifest into backups/
node restore.mjs backups/<file>.json uko_restore   # restore into a fresh database and verify counts
```

Restore applies the schema migrations, inserts the backed-up rows with FK checks relaxed,
and verifies every table count against the manifest. Add `backups/` to your ignore list
(already gitignored here).
