# Firebase setup + maps status

The apps use **OpenStreetMap via `flutter_map`** for in-app maps — no Google Maps key,
billing account or API key is required. Firebase/FCM needs only the service account.

## A. Firebase / FCM

1. <https://console.firebase.google.com> → project **uko-pilot** → ⚙ **Project settings**.
2. **Service accounts** tab → **Generate new private key** → download JSON.
3. Run (keep the JSON outside the repo):
   ```bash
   node tools/setup-google.mjs firebase /path/to/uko-pilot-firebase-adminsdk-*.json
   ```
   This writes `PUSH_PROVIDER=fcm` + `FCM_PROJECT_ID/CLIENT_EMAIL/PRIVATE_KEY` to
   `app/deploy/.env` and `app/services/api/.env` (mode 600, gitignored).
4. Grant the service account **Firebase Cloud Messaging API Admin** on the project
   (IAM & Admin → Grant access → service account principal → role). Without it FCM returns
   `403 PERMISSION_DENIED` for `cloudmessaging.messages.create`.
5. Restart the API and trigger a ride; the push arrives on the paired device.

Verified on 2026-11-23: outbox SENT with real `projects/uko-pilot/messages/…` IDs and
background notification on the tablet (`testbench/evidence/fcm-real-push.txt`).
`google-services.json` is in place for both apps; both have registered real FCM tokens.

## B. Maps — OpenStreetMap (already implemented)

- `flutter_map` + OSM raster tiles (`https://tile.openstreetmap.org/{z}/{x}/{y}.png`).
- No key, no billing. The map widget shows:
  - pickup and drop-off markers,
  - a route line,
  - “© OpenStreetMap contributors” attribution.
- Builds use OSM by default; `--dart-define=UKO_REAL_MAPS=false` keeps the offline
  stylised map (useful if the tablet has no internet).
- OSM’s free tile service is best-effort and subject to the
  [tile usage policy](https://operations.osmfoundation.org/policies/tiles/). For public
  beta, move to a free-tier tile provider (MapTiler/Stadia/OpenFreeMap) or self-host.
  Keep usage light; no bulk tile prefetching.

## Status check

```bash
node tools/setup-google.mjs status
```

Expected once FCM is configured:

```
ok   rider: Firebase project uko-pilot (ke.uko.rider)
ok   rider: maps use OpenStreetMap (no API key required)
ok   driver: Firebase project uko-pilot (ke.uko.driver, ke.uko.rider)
ok   driver: maps use OpenStreetMap (no API key required)
ok   FCM service account configured for uko-pilot
```

## Security

Never commit `google-services.json`, `local.properties`, `.env`, service-account JSON or
keystores — the repo `.gitignore` covers them.
