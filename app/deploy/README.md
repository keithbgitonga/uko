# Production deployment (pilot)

Docker Compose stack: PostGIS Postgres, one-off migration job, the API, and Caddy
for automatic HTTPS. Only Caddy is exposed (80/443); Postgres and the API stay on the
private network.

## Prerequisites

- A Linux host with Docker + Compose v2
- A domain/subdomain with an A record pointing at the host (`DOMAIN`)
- Accounts/credentials: Africa's Talking (SMS), Firebase (FCM), Daraja (M-Pesa)

## First deploy

```bash
cd app/deploy
cp .env.production.example .env
# edit .env: DOMAIN, DB password, JWT secrets, external credentials
docker compose -f docker-compose.production.yml build
docker compose -f docker-compose.production.yml up -d
docker compose -f docker-compose.production.yml logs -f caddy api migrate
```

Verify: `curl https://$DOMAIN/v1/health/ready` and `curl https://$DOMAIN/v1/health/alerts`.

## Migrations

The `migrate` service applies `app/db/migrations/*.sql` in order and records them in
`schema_migrations`; rerunning is safe (applied files are skipped). To run manually:

```bash
docker compose -f docker-compose.production.yml run --rm migrate
```

## Backups

```bash
docker compose -f docker-compose.production.yml exec postgres \
  pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" > backup-$(date +%F).sql
```

Restore into a scratch database first, verify counts, then restore live. Keep daily
backups off-host (object storage) and test a restore monthly. The bench also has
`tools/pg/backup.mjs` / `restore.mjs` for JSON snapshots.

## Secrets

Keep `.env` out of git (chmod 600), rotate JWT secrets and DB passwords on a schedule,
and never reuse the bench values. `ALERT_WEBHOOK_URL` should point at the ops channel.

## Ops after deploy

- Dispatch console: host `app/apps/dispatch` behind auth/allow-list; point it at `https://$DOMAIN/v1`.
- Daily: `GET /health/alerts`, dispatch Money tab, pilot smoke from a workstation.
- Driver documents: review pending uploads in the dispatch Documents tab.
