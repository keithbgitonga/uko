# Free hosting — Render + Neon (recommended permanent path)

The repository is prepared for Render: `render.yaml` defines the API (Docker) and the static
dispatch console. Neon provides free managed Postgres. You need accounts on Neon, Render and
GitHub; I cannot create those for you.

## 1. Neon Postgres

1. <https://neon.tech> → create a project (e.g. `uko-pilot`) in a region near your users
   (Frankfurt pairs with the Render `frankfurt` region).
2. Copy the **connection string** (direct connection, not the pooled one) — it looks like:
   `postgresql://user:password@ep-xxx.eu-central-1.aws.neon.tech/neondb?sslmode=require`
3. Optional: in Neon SQL editor run `CREATE EXTENSION IF NOT EXISTS postgis;`. If that works,
   later set `SKIP_POSTGIS=0` and redeploy so the zones/pricing migration applies. Otherwise
   keep `SKIP_POSTGIS=1` (the current pilot API does not use those tables yet).

## 2. Push the repository to GitHub

A local git repository has been created and committed:

```bash
cd uko
git remote add origin git@github.com:<you>/uko.git
git push -u origin main
```

Secrets are excluded by `.gitignore` (`.env`, google-services.json, local.properties,
service-account JSON, keystores, uploads, recon/evidence). Verify with `git status` before
pushing.

## 3. Render Blueprint

1. <https://dashboard.render.com> → **New → Blueprint**.
2. Connect the GitHub repository; Render reads `render.yaml`.
3. Fill the prompted secrets:
   - `DATABASE_URL` — Neon connection string
   - `DISPATCH_PHONES` — comma-separated ops numbers, e.g. `+254712345678`
   - `AFRICASTALKING_USERNAME`, `AFRICASTALKING_API_KEY`, `AFRICASTALKING_SENDER_ID` (SMS)
   - `FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL`, `FCM_PRIVATE_KEY` (push)
4. Apply/deploy. The API image runs migrations on boot (`node scripts/migrate.mjs`) then starts.
5. Confirm:
   - `https://<api-service>.onrender.com/v1/health`
   - `https://<api-service>.onrender.com/v1/health/ready`
6. The static dispatch console deploys as `https://<dispatch-service>.onrender.com`.

If the service names are taken, Render adds suffixes; update `CORS_ORIGINS` in the API env
(and the dispatch URL) to match the actual dispatch URL, then redeploy.

## 4. Point the apps at Render

Once the API URL is known (e.g. `https://uko-api.onrender.com/v1`):

```bash
./tools/build-public-apps.sh https://uko-api.onrender.com/v1
```

Install the APKs:

```bash
adb -s HA1JE58L install -r app/apps/rider/build/app/outputs/flutter-apk/app-debug.apk
adb -s HA1JE58L install -r app/apps/driver/build/app/outputs/flutter-apk/app-debug.apk
```

## 5. Dispatch console

Open:

```text
https://<dispatch-service>.onrender.com/?api=https://<api-service>.onrender.com/v1
```

Log in with an ops phone number / OTP (SMS must be configured). Alternatively generate a
token link (development only):

```bash
API_BASE=https://<api-service>.onrender.com/v1 \
DISPATCH_WEB=https://<dispatch-service>.onrender.com/ \
node tools/dispatch-link.mjs +254712345678
```

## Free-tier caveats

- Render free web services **sleep after inactivity**; the first request after sleep is slow.
  Neon free also scales to zero/limited compute.
- Render free has **ephemeral disk**: uploaded driver documents are lost on redeploy/restart.
  For a real pilot move uploads to Cloudflare R2 / S3 / Supabase Storage, then set
  `DOCUMENTS_REQUIRED=true`.
- `render.yaml` sets `DOCUMENTS_REQUIRED=false` so drivers can use the free deployment before
  object storage is added. Change this when storage is ready.
- Free tiers have monthly hours/limits; check Render/Neon current terms.
- Keep `EXPOSE_DEV_OTP=false` for any public URL. Use real SMS.
- Rotate `JWT_SECRET`, FCM keys and dispatch tokens before onboarding real riders.

## Alternative: named Cloudflare Tunnel (free, stable URL, this machine)

If you have a domain on Cloudflare, `cloudflared tunnel login` + a named tunnel mapping
`api.yourdomain` → `localhost:3100` gives a stable URL with this machine as host. Keep the
machine powered/online; use Render for resilience instead.

## Live deployment (2026-11-25)

- API: `https://uko-pilot-api.onrender.com/v1`
- Dispatch: `https://uko-pilot-dispatch.onrender.com/`
- Neon project: eu-central-1 (Frankfurt), schema migrated (12 migrations, 27 tables, PostGIS skipped).
- API `/v1/health/ready` reports database ok; CORS allows the dispatch origin.
- Login: OTP sent by SMS (dev OTP disabled).

Cloudflare Quick Tunnels from the bench remain as an emergency local fallback:
API `https://trains-referred-morris-phd.trycloudflare.com/v1` and dispatch
`https://greetings-cruise-stayed-opinions.trycloudflare.com/`.
