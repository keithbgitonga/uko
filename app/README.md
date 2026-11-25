# Uko? — application monorepo

Foundation scaffold for the Uko? MVP (Phase 3, Sprint 1).

## Services
- `services/api` — NestJS modular-monolith API (auth, booking, driver, scheduling, payments, safety, dispatch)
- `apps/rider` — Flutter rider app (bootstrap required; see its README)
- `apps/driver` — Flutter driver app (bootstrap required)
- `apps/dispatch` — Next.js dispatch console (bootstrap required)
- `db` — SQL-first schema, migrations and seeds (PostGIS)
- `docker-compose.yml` — local Postgres/PostGIS, Redis, EMQX

## Prerequisites
- Node.js 22+ and npm (present)
- Flutter 3.x SDK (not installed on this machine yet)
- Docker + Docker Compose (not installed on this machine yet)
- psql client for applying SQL migrations

## Persistence (2026-11-23)

Auth uses relational tables (`users`, `refresh_tokens`). Rides, quotes, driver
trips/availability, payments, safety and scheduling use normalized tables from
migration `0004_normalized_domains.sql`; the earlier `domain_documents` JSONB
store is kept only as the backfill source.

## Local database (no Docker required)

```bash
cd ../tools/pg && ./start.sh      # PostgreSQL 18 on 127.0.0.1:55432
cd ../tools/pg && node migrate.mjs  # core schema
cd ../app/services/api
AUTH_STORE=postgres DATABASE_URL=postgres://uko@127.0.0.1:55432/uko npm run start:dev
```

See `tools/pg/README.md`. Production uses PostGIS via `docker-compose.yml`.

## Quick start
```bash
cp .env.example .env
make install          # installs API dependencies
make db-up            # starts Postgres/PostGIS, Redis, EMQX (needs Docker)
make db-migrate       # applies db/migrations/*.sql
make db-seed          # seeds one Nairobi zone + Boda pricing
make api-dev          # http://localhost:3000/v1/health  ·  swagger at /docs
```

## Walking skeleton (validated)
`npm run build` passes. Smoke test executed end-to-end:
OTP request → verify → `GET /v1/me` → refresh-token rotation (old token rejected)
→ logout (session revoked). With `NODE_ENV=development`, `POST /v1/auth/otp/request`
returns a `dev_code` (never enabled in production).

The skeleton uses in-memory stores for identity until the Postgres repositories
land in Sprint 1 (FND-3/FND-4). This is deliberate: the API shape is real,
storage is a stub. Zone/Boda pricing is also in-memory until FND-6.

Contract: [`../spec/api-foundation-v0.1.md`](../spec/api-foundation-v0.1.md) · Sprint plan: [`../spec/sprint-1-plan.md`](../spec/sprint-1-plan.md)

## Sprint 1
See `../spec/sprint-1-plan.md` and `../spec/api-foundation-v0.1.md`.


## Production deployment

See [`deploy/README.md`](deploy/README.md): Docker Compose stack with PostGIS, a one-off
migration service, the API image and Caddy for automatic HTTPS. The API image also ships
`scripts/migrate.mjs` (`npm run migrate`) for applying `db/migrations/*.sql` with a
`schema_migrations` ledger.
