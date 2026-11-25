# Dispatch console — setup and access

## Current public access (free quick tunnels)

- Dispatch UI: `https://greetings-cruise-stayed-opinions.trycloudflare.com/`
- API: `https://trains-referred-morris-phd.trycloudflare.com/v1`
- Ops allow-list: `+254712345678` (DISPATCH_PHONES)

Open the console with the API URL (the UI reads `?api=` and `?token=`):

```bash
API_BASE=https://trains-referred-morris-phd.trycloudflare.com/v1 \
DISPATCH_WEB=https://greetings-cruise-stayed-opinions.trycloudflare.com/ \
node tools/dispatch-link.mjs +254712345678
```

The generated URL logs you in immediately. Access tokens are short-lived; the console can also
log in with an OTP on its login screen (dev OTP is exposed on this test API).

## What the console covers

- Overview (online drivers, active rides, alerts)
- Rides, incidents/SOS, scheduled rides
- Money/reconciliation
- Driver documents (approve/reject)
- Audit log
- System health and alerts

## Local fallback

```bash
node app/apps/dispatch/serve.mjs        # http://localhost:8085
# then open http://localhost:8085/?api=http://localhost:3100/v1&token=<token>
```

## Production notes

- Replace quick tunnels with a stable host (see `docs/Free-Hosting.md`).
- Set `CORS_ORIGINS` to the dispatch domain only.
- Set `EXPOSE_DEV_OTP=false`, configure SMS, and rotate `JWT_SECRET`.
- Use a separate dispatch account/phone from riders and drivers if possible.
- The console is static; host it on Cloudflare Pages/Netlify or behind the same proxy.
