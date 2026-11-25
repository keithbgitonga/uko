# Free hosting — current status and permanent options

## Working now (free, temporary)

Two Cloudflare Quick Tunnels expose the local bench without an account:

| Service | URL |
|---|---|
| API | `https://trains-referred-morris-phd.trycloudflare.com/v1` |
| Dispatch console | `https://greetings-cruise-stayed-opinions.trycloudflare.com/` |

The rider app has been rebuilt with `--dart-define=API_BASE_URL=https://trains-referred-morris-phd.trycloudflare.com/v1`
and works over the internet (no `adb reverse`). The driver app is built the same way.

**Important limitations**
- Quick-tunnel URLs are **ephemeral**: they change if cloudflared restarts, and only work while
  this machine is on and the tunnel processes are running.
- The API was started with `EXPOSE_DEV_OTP=true` for testing, so OTP codes are returned by the
  API. Do not share these URLs widely; switch to real SMS (`SMS_PROVIDER=africastalking`) before
  letting real riders in.
- Uploaded driver documents live on the local disk; they are not part of this tunnel backup.

Restart the tunnels if needed:

```bash
cloudflared tunnel --url http://localhost:3100 --no-autoupdate   # API
node app/apps/dispatch/serve.mjs                                # dispatch UI :8085
cloudflared tunnel --url http://localhost:8085 --no-autoupdate   # dispatch UI
```

Generate a fresh dispatch login link:

```bash
API_BASE=https://<api-host>/v1 \
DISPATCH_WEB=https://<dispatch-host>/ \
node tools/dispatch-link.mjs +254712345678
```

The dispatch token is short-lived; the console also supports logging in with an OTP.

## Permanent free-ish options

### Option A — Render (API) + Neon (Postgres)

1. Create a free Neon Postgres project and copy its pooled connection string.
2. Push this repo to GitHub, then create a **Render Blueprint** from `render.yaml`.
3. Set `DATABASE_URL` to the Neon string and the other secrets in Render.
4. Deploy; Render runs the API Docker image. Free instances sleep when idle (first request is slow).
5. Point the apps at the Render URL and rebuild:
   `flutter build apk --dart-define=API_BASE_URL=https://<service>.onrender.com/v1`.
6. Host the dispatch console on Cloudflare Pages/Netlify (static) and open it with
   `?api=https://<service>.onrender.com/v1`.

Caveats:
- Free Render services **sleep** and have ephemeral disk (uploaded documents are lost on restart).
  For real documents use Cloudflare R2 / S3 free tier, or Supabase Storage.
- Neon free has a storage/compute cap but is fine for a pilot.
- No card? Some free tiers require one; check current provider terms.

### Option B — keep the machine online with a named Cloudflare Tunnel (free)

If you have a domain on Cloudflare:
1. `cloudflared tunnel login`, create a named tunnel, and map `api.yourdomain` → `localhost:3100`.
2. Run it as a service so it reconnects automatically.
3. The API stays on this machine/Postgres; URLs are stable.

This is the lowest-effort free path if the bench can stay powered and online; it is not resilient
to power/internet loss.

### Option C — Oracle Cloud Always Free / Google Cloud free tier

More setup and a payment method may be required, but gives a real VM or Cloud Run instance with
stable URL and managed Postgres (Neon free) for a small pilot.

## Before public use

- Set `EXPOSE_DEV_OTP=false` and configure SMS.
- Rotate `JWT_SECRET`, FCM key and dispatch token; use HTTPS only (tunnels already provide it).
- Restrict `CORS_ORIGINS` to the dispatch host.
- Move document uploads to object storage.
- Keep `/v1/health/alerts` monitored.
