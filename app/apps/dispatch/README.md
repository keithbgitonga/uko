# Uko? Dispatch console

Operations console for the pilot: live rides, incidents and scheduled rides, with
cancel-ride and resolve-incident actions.

## Run

```bash
cd app/apps/dispatch
node serve.mjs            # http://localhost:8085
```

Requires the API on `http://localhost:3100/v1` (see `tools/pg/README.md` and the
API quick-start). Sign in with a pilot phone (dev OTP is shown in the console).
For quick testing you can pass a token: `http://localhost:8085/?token=<accessToken>`.

## Views

- **Overview** — active rides, completed today + gross, open incidents, drivers online, scheduled upcoming, recent rides/incidents.
- **Rides** — all rides with state, route, fare and Cancel for active ones.
- **Incidents** — SOS incidents with state and Resolve.
- **Scheduled** — scheduled rides and weekly series.

Auto-refreshes every 5 s.

## Notes

- This is a dependency-free static console prototype. Production will use Next.js
  with role-based auth (`DISPATCH_PHONES`/ops role), proper layout and keyboard
  shortcuts; the API contract (`/dispatch/*`) is already in place.
- The temporary token-in-URL shortcut is for local testing only.
