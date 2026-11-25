# Uko? — Lenovo tablet test bench

The **Lenovo TB-J616X** tablet is the primary Android test bench for Uko? builds.
Device profile and constraints: [`../spec/test-device-lenovo-tb-j616x.md`](../spec/test-device-lenovo-tb-j616x.md).

## One-time setup

```bash
# USB debugging on, device trusted, then:
./scripts/device-prep.sh
```

This will:
- keep the screen awake while charging and extend the screen timeout,
- disable animations (already 0 on this device) for stable screenshots,
- map device `localhost:3000` to the workstation API (`adb reverse`),
- clear logcat for a clean test run.

## Daily test loop

```bash
# 1. start the API on the workstation
cd ../app && make api-dev

# 2. build + install the rider app
cd ../app/apps/rider
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk

# 3. launch and capture evidence
adb shell am start -n ke.uko.rider/.MainActivity
./scripts/capture.sh rider-login
```

## Evidence

Screenshots, video and logcat excerpts go in `evidence/` (git-ignored).
Naming: `<app>-<flow>-<yyyy-mm-dd-hhmm>.<ext>`.

```bash
./scripts/capture.sh rider-login
# → evidence/rider-login-2026-11-22-1500.png
# → evidence/rider-login-2026-11-22-1500.log
```

## Verified runs

### 2026-11-22 — rider auth flow (first build on the bench)
- Build: `flutter build apk --debug --target-platform android-arm64` → 74 MB APK
- Install: `adb install -r` → success, package `ke.uko.rider`
- Flow verified on the Lenovo: launch → phone prefilled (+254712345678) → **Send code** → dev OTP auto-filled → **Verify and continue** → home screen “You are in, rider.” signed in as +254712345678
- API path: device `localhost:3000` → workstation `localhost:3100` via `adb reverse tcp:3000 tcp:3100`
- Evidence: `evidence/rider-launch-2.png`, `evidence/rider-otp.png`, `evidence/rider-home.png`

**Note:** the workstation port 3000 is occupied by another local app, so the Uko? API runs on **3100** and the device port 3000 is remapped. Keep that mapping when testing.

### 2026-11-22 — booking flow (quote → confirm → driver assigned → cancel)
- API additions: `POST /quotes`, `POST /rides`, `GET /rides/{id}`, `POST /rides/{id}/cancel`
- Flow verified on the Lenovo: Book a Boda → pickup “Kenyatta Avenue”, drop-off “Westlands” → **Get price** (KES 172 for 3.7 km / 10 min) → choose M-Pesa → **Confirm Boda** → “Finding your Boda…” → mock driver **Peter M. · Bajaj Boxer · KDA 123A · ★4.9 · 3 min** → **Cancel ride** returns to home and the ride becomes `CANCELLED` in the API.
- Evidence: `evidence/booking-01-home.png` … `booking-06-cancelled-home.png`

### 2026-11-22 — driver offer + trip flow
- API additions: `GET/POST /driver/status|online`, `GET /driver/offers`, `POST /driver/offers/{id}/accept|reject`, `GET /driver/trips/current`, `POST /driver/trips/{id}/arrived|start|complete`
- Flow verified on the Lenovo: driver login (dev OTP) → **Go online** → offer **Brian O. · Westlands → Kileleshwa · KES 150** → **Accept** → trip page with pickup code **3370** → **I've arrived** → **Start trip** → **Complete trip** → completion dialog → back online.
- Evidence: `evidence/driver-01-offline.png` … `driver-07-home-after.png`

### 2026-11-22 — rider + driver shared trip (matching)
- Backend now matches real rides: a rider booking appears as the driver’s offer; accepting assigns the same ride and the driver’s trip actions update what the rider sees.
- Verified on the Lenovo: rider books Kenyatta Avenue → Westlands (KES 172) → driver (online) receives the real offer → Accept → **rider sees Peter M. · Bajaj Boxer · KDA 123A and pickup code 1607** → driver I've arrived → rider “Driver has arrived” → Start trip → rider “On the way to your destination” → Complete trip → rider “Trip completed · KES 172 · MPESA”.
- Evidence: `evidence/integration-00-driver-online.png` … `integration-08-rider-completed.png`

### 2026-11-22 — scheduling + weekly series
- API additions: `POST/GET /scheduled-rides`, `POST /scheduled-rides/{id}/cancel|repeat`, `GET /schedule-series`, `PATCH /schedule-series/{id}`
- Flow verified on the Lenovo: rider logs in → **Schedule a ride** → date/time default +2h → **Schedule ride** (KES 172, Sun 22 Nov 2026 · 19:08) → **Create weekly series** (Sun, ends 20 Dec 2026, 3 upcoming occurrences) → **View scheduled rides** → **Pause** the series (ACTIVE → PAUSED).
- Evidence: `evidence/schedule-01-form.png`, `schedule-02-series-created.png`, `schedule-03-manage.png`, `schedule-04-paused.png`

### 2026-11-22 — calendar suggestions (opt-in, on-device)
- Native bridge: `ke.uko.rider/calendar` MethodChannel requests `READ_CALENDAR`, reads `CalendarContract.Instances` for the next 7 days, keeps events with a location, dedupes by title/time/location, returns up to 10 (Dart shows 3).
- Flow verified on the Lenovo: rider logs in → **Calendar suggestions** → privacy note → **Allow calendar access** → Android permission dialog → suggestion **Dentist · Mon 23 Nov 2026 · 09:00 · Westlands** → **Schedule a ride to this event** → Schedule screen prefilled with Westlands and Mon 23 Nov 09:00.
- Test data: a `Dentist` event (location Westlands) inserted into the tablet's local calendars for verification; no other next-7-day events with locations were present.
- Evidence: `evidence/calendar-01-suggestions.png`, `calendar-02-prefilled.png`

### 2026-11-22 — M-Pesa payment after trip
- API additions: `POST /payments/mpesa/stk`, `GET /payments/ride/{rideId}`, `GET /payments/{id}`, `POST /payments/{id}/simulate`, `POST /payments/cash/confirm`
- Flow verified on the Lenovo: driver completes the ride → rider sees **Trip completed · KES 172 · MPESA** → **Pay KES 172 with M-Pesa** → “Check your phone…” → **Payment received · KES 172 · MPESA-6bdf0324** → Done.
- Walking skeleton: STK auto-succeeds after ~4 s; `/simulate` can force SUCCESS/FAILED for tests; real Daraja integration waits on sandbox credentials.
- Evidence: `evidence/payment-00-driver-offer.png`, `payment-01-completed-unpaid.png`, `payment-02-pending.png`, `payment-03-paid.png`

### 2026-11-22 — safety & SOS
- API additions: `GET/POST /safety/contacts`, `DELETE /safety/contacts/{id}`, `POST /safety/sos`, `GET /safety/incidents`, `GET /safety/incidents/{id}`, `POST /safety/incidents/{id}/cancel`
- Flow verified on the Lenovo: rider opens **Safety & SOS** (Jane W. contact on file) → **Send SOS** → confirm → **SOS · OPEN** → after ~5 s **SOS · ACKED** (“private responder being dispatched and emergency contacts notified”) → **Cancel SOS — false alarm** → **SOS · CANCELLED**.
- Private-response wording is explicit: pilot uses Uko? ops on-call + a private responder, not 999.
- Evidence: `evidence/safety-01-page.png` … `safety-04-sos-cancelled.png`

### 2026-11-23 — map-led UI pass
- New rider home: full-screen stylised map, floating location/account header, bottom “Where to?” sheet, quick actions (Book a Boda / Schedule / Calendar / Safety), trips placeholder.
- Trip screen now shows a route map (pickup/drop-off pins, driver marker, ETA chip) above the driver card and pickup code.
- Verified on the Lenovo: login → map home → Book a Boda → driver accepts → rider sees the new map + Peter M. card + pickup code.
- Evidence: `evidence/ui-01-home.png`, `ui-02-trip-map.png`

### 2026-11-23 — driver UI pass
- Map-led driver home: full-bleed stylised map, online/offline pill, earnings chip, account avatar, bottom sheet with online switch and offer/waiting/active-trip states.
- Offer card now has a **45 s countdown ring**, rider name, pickup/drop-off, distance/fare, Decline/Accept.
- Trip screen: route map with pickup/drop-off pins, 4-step timeline (Accepted → Arrived → On trip → Done), pickup code and fare.
- Verified on the Lenovo: driver → online → rider books → offer with countdown (KES 172 · Rider 5678) → Accept → trip map + code 5282 + timeline.
- Evidence: `evidence/driver-ui-01-home.png`, `driver-ui-03-trip.png`

**Note:** the live countdown can make `uiautomator dump` flaky; tap by screenshot coordinates when needed.

### 2026-11-23 — trips & receipts history
- Rider home “Trips & receipts” now opens history: completed/cancelled rides, date/time, route, fare, Paid · receipt badge.
- Tapping a completed trip opens a receipt sheet: route, fare, payment method, payment status, receipt number, ride id.
- Verified on the Lenovo with two completed rides (M-Pesa + cash both paid): list and receipt screens render correctly.
- Evidence: `evidence/trips-01-list.png`, `trips-02-receipt.png`

### 2026-11-23 — driver earnings
- API: `GET /v1/driver/earnings` (today/lifetime trips, gross, 20% commission, net; Africa/Nairobi day boundary).
- Driver home shows the net earnings chip and a “Today’s earnings” card (trips · net · commission).
- Verified on the Lenovo with 2 completed trips: chip **KES 275 today**, card **2 trips · net KES 275 · commission 20%** (gross 344 − commission 69).
- Evidence: `evidence/driver-earnings.png`

### 2026-11-23 — persistence across API restarts
- New migration `0003_domain_documents.sql` (JSONB snapshot store) + `PersistenceService`; rides, driver trips/status, payments, safety contacts/incidents and scheduled rides/series are written to Postgres on mutation and reloaded on startup.
- Verified: seeded one completed+paid ride, an SOS incident, a scheduled ride and a weekly series; restarted the API; all endpoints returned the same records, and the tablet showed **Trips & receipts** with the persisted completed ride and **driver earnings KES 138** from the persisted trip.
- Evidence: `evidence/persist-01-trips-after-restart.png`, `persist-02-driver-earnings-after-restart.png`

### 2026-11-23 — normalized Postgres tables
- Migration `0004_normalized_domains.sql`: quotes, rides, driver_trips, driver_availability, driver_rejections, payments, safety_contacts, safety_incidents, scheduled_rides, schedule_series; backfilled from the interim JSONB store.
- `PersistenceService` now maps each domain to its table (loads on startup, upserts on mutation).
- Verified: restart loaded backfilled ride/payment/safety/scheduled/series; new ride+trip+payment+safety incident+series wrote rows to the tables; second restart returned all of it; tablet **Trips & receipts** shows both completed rides.
- Fixed: node-postgres serialises JS arrays as PG arrays, so JSONB columns now receive `JSON.stringify` values.
- Evidence: `evidence/normalized-01-trips.png`

### 2026-11-23 — booking sheet polish
- Home **Where to?** now opens a draggable bottom sheet with a destination field, **saved places** (Home/Work/Airport/Mall) and **recent destinations** from completed trips.
- Selecting a place opens **Book a Boda** prefilled; the booking page gained a route-map header and wider tablet layout.
- Verified on the Lenovo: sheet → **Home (Kileleshwa)** → prefilled booking → **Get price** (KES 172, 3.7 km / 10 min) with map header.
- Evidence: `evidence/booking-sheet-01.png`, `booking-sheet-02-prefilled.png`, `booking-sheet-03-quote.png`

### 2026-11-23 — driver shift summary
- API: `GET /driver/shift` (online state, on-shift since, online minutes today, trips, gross/commission/net today; Nairobi day boundary); driver shifts recorded on online/offline transitions and persisted.
- Driver home shows “On shift · 1h 17m online today · 2 trips” above the earnings card.
- Verified on the Lenovo: driver online → shift card with online time and trip count (`evidence/driver-shift.png`).

### 2026-11-23 — API security hardening
- Helmet security headers, `X-Request-Id` on every response, structured JSON request logs (method/path/status/duration).
- OTP rate limiting: 3 requests/hour/phone, 10/hour/IP, 10 verify attempts/10 min/phone (in-memory, single instance); 4th request returns `429 RATE_LIMITED`.
- SMS adapter: dev channel by default; Africa's Talking wired behind `SMS_PROVIDER=africastalking` + credentials. Dev responses include `dev_code`.
- Dispatch: `DISPATCH_PHONES` allow-list (non-listed account gets `403 DISPATCH_FORBIDDEN`) and DB-backed audit log for cancel/resolve; `GET /dispatch/audit`.
- Verified via API and on-device login after hardening (`evidence/security-01-login.png`).

### 2026-11-23 — backup drill and pilot smoke test
- `tools/pg/backup.mjs` writes a JSON snapshot of every table with counts and a SHA-256 manifest; `tools/pg/restore.mjs` restores into a fresh database and verifies counts.
- Drill: 21 tables / 99 rows backed up; sentinel contact added after; restore into `uko_restore` passed (94 rows, sentinel absent, live ride/payment counts matched).
- `tools/pilot-smoke.mjs` runs 15 API checks (auth, quote, ride + cancel, scheduled ride, safety contact/SOS/cancel, driver online/offers, dispatch overview/audit) — **15/15 passed**.
- Dispatch console gained an **Audit** tab backed by `/dispatch/audit` (`evidence/dispatch-03-audit.png`).
- Runbook: `docs/Pilot-Operations-Runbook-v0.1.md`.

### 2026-11-23 — Daraja STK integration (fake gateway)
- `MPESA_PROVIDER=daraja` uses a real Daraja OAuth + STK push client and callback endpoint; `mock` remains the default for the tablet demo.
- Tested against `tools/fake-daraja.mjs`: OAuth token request, STK body (shortcode/timestamp/password/phone/amount), callback → payment `SUCCESS` with receipt `MPESA-FAKE123`; failure callback → `FAILED` (“Request cancelled by user”); wrong callback secret → `401`; unknown checkout → accepted ack.
- Env: `DARAJA_BASE_URL`, `DARAJA_CONSUMER_KEY/SECRET`, `DARAJA_PASSKEY`, `DARAJA_SHORTCODE`, `DARAJA_CALLBACK_URL/SECRET`.

### 2026-11-23 — push notification outbox (fake FCM)
- Backend: `device_tokens` registry, `notifications` outbox and `PUSH_PROVIDER=dev|fcm` adapter; ride events create notifications (assigned, arrived, started, completed, cancelled).
- Tested against `tools/fake-fcm.mjs`: registered two rider device tokens, accepted a ride + arrived, outbox showed `SENT`, fake gateway received `registration_ids` with title/body/data payloads.
- Default provider stays `dev` for the tablet demo; real FCM credentials are the remaining step.

### 2026-11-23 — SMS gateway test + rider notification inbox
- SMS adapter endpoint is configurable (`SMS_BASE_URL`); tested against `tools/fake-sms.mjs`: OTP request returned `channel: "sms"` with no dev code, and the fake Africa’s Talking gateway received the API-key-authenticated form body (username, phone, message).
- Rider app gained a bell icon opening a **Notifications** inbox (`GET /notifications`), with pull-to-refresh, relative timestamps and empty/error states.
- Verified on the Lenovo: inbox showed persisted ride notifications (“Boda on the way” with pickup code, “Your Boda has arrived”) — `evidence/notifications-01-inbox.png`.

### 2026-11-23 — driver notifications inbox
- Driver trip events now create notifications for the driver: “Trip accepted”, “At pickup” (with pickup code), “Trip started”, “Trip completed” (net after commission).
- Driver app gained a bell icon opening a **Notifications** inbox with pull-to-refresh and relative timestamps.
- Verified on the Lenovo: completed a trip, opened the inbox and saw all four trip notifications — `evidence/driver-notifications-01-inbox.png`.

### 2026-11-23 — ride ratings
- Backend: `POST /ratings` (completed rides only, 1–5 stars, upsert per ride, optional comment), `GET /ratings/ride/:id`, `GET /ratings/driver/:id` summary; ratings table stores driver id when the ride was assigned through the current flow; driver receives a “New rating” notification.
- Rider app: receipt sheet now includes **Rate your driver** stars; tapping a star submits and shows a thank-you state.
- Verified on the Lenovo: opened a completed trip receipt, tapped 5 stars, saw the confirmation — `evidence/rating-01-sheet.png`, `rating-02-submitted.png`.

### 2026-11-23 — observability and analytics
- `GET /health/ready` checks the database and returns row counts; `GET /metrics` returns HTTP request metrics (total, failures, status mix, average latency, uptime), database counts and 24h event counts.
- `analytics_events` table + `POST /analytics/events` endpoint; server records `ride_requested`, `ride_assigned`, `trip_completed`, `sos_triggered`, `rating_submitted`, `payment_started/confirmed`.
- Dispatch console gained a **System** tab showing readiness, HTTP metrics and event counts (`evidence/dispatch-04-system.png`).

### 2026-11-23 — pilot readiness review v0.2
- Updated 6-page assessment: progress since v0.1, refreshed scorecard, seven remaining blockers, updated risk register and closed/open pilot gate.
- `docs/Uko-Pilot-Readiness-Review-v0.2.pdf` (source `docs/uko-pilot-readiness-v0.2.html`); v0.1 retained for history.

### 2026-11-23 — driver document vetting
- Backend: `driver_documents` table; `POST /driver/documents` (multipart upload), `GET /driver/documents`; dispatch list/approve/reject with audit entries; `DOCUMENTS_REQUIRED=true` blocks online until licence **and** insurance are approved.
- Driver app: account menu → **Documents**; demo upload buttons generate on-device files and submit them; status chips refresh to `PENDING`/`APPROVED`.
- Dispatch console: **Documents** tab with Approve/Reject.
- Verified: upload via tablet → pending; approve through dispatch API → approved on tablet; gate returned `403 DOCUMENTS_PENDING` before approval and online succeeded after. Evidence: `driver-documents-01-empty.png`, `driver-documents-02-pending.png`, `driver-documents-03-approved.png`, `dispatch-05-documents.png`.

### 2026-11-23 — pilot dry run (27/27) + document gate hardening
- `tools/pilot-dry-run.mjs` exercises the full pilot path in one pass: readiness, rider/driver auth, document upload + gate + dispatch approval, online, quote/ride/accept/arrive/start/complete, cash payment, rating, scheduled ride + weekly series, SOS acknowledge/cancel, notifications, dispatch overview/audit, analytics events. **27/27 checks passed** (`evidence/pilot-dry-run-report.json`).
- Document gate hardening: when `DOCUMENTS_REQUIRED=true`, an online state persisted in the DB is forced offline on API startup unless licence + insurance are approved (verified: DB online true → restart → driver status offline + `403 DOCUMENTS_PENDING`).

### 2026-11-23 — crash reporting + alerting
- Apps report crashes: rider `FlutterError.onError` + zone handler POST to `/diagnostics/client-errors`; account menu → **Report a problem** sends a diagnostic from the tablet.
- `client_errors` table + `GET /health/alerts` evaluating database health, unattended SOS (>15 min), failed notifications, stale pending documents and client errors; dispatch **System** tab renders alerts.
- Verified: diagnostic from the Rider app increased client errors, alerts showed `CLIENT_ERRORS`, and dispatch displayed a critical unattended-SOS alert plus the warning (`evidence/crash-report-01-rider.png`, `dispatch-06-alerts.png`). Test SOS incidents were resolved afterwards.

### 2026-11-23 — alert webhook + document expiry reminders
- Alert evaluation now forwards a Slack-compatible payload to `ALERT_WEBHOOK_URL` when the alert set changes (deduplicated). Verified with `tools/fake-webhook.mjs`: one POST containing the `DOCS_EXPIRING` and `CLIENT_ERRORS` warnings; repeat polls did not resend.
- Approved driver documents expiring within 14 days trigger an in-app notification (“Document expiring soon”, days left). Verified: uploaded a licence expiring 2026-12-03 → notification `SENT`, `expiry_notified_at` set, `DOCS_EXPIRING` alert raised.
- Migration `0012_document_expiry.sql`.

### 2026-11-23 — payment reconciliation
- `GET /dispatch/reconciliation?date=YYYY-MM-DD` (defaults to today, Nairobi) compares completed rides with their payments: gross/paid/unpaid, by method, 20% commission, driver payout, and mismatches (unpaid, amount mismatch, duplicate payment).
- Dispatch console gained a **Money** tab with the summary, method split, commission and mismatch table.
- Verified: 9 completed rides → KES 1548 gross, 4 paid (688), 5 unpaid (860), commission 138, payout 550; five mismatches listed (`evidence/dispatch-07-money.png`).

### 2026-11-23 — device-level pilot dry run (both apps)
- Cleaned ride/driver state, cleared both apps, then drove the real UI end-to-end:
  1. Rider logged in → Where-to sheet → Home (Kileleshwa) → Get price → **Confirm Boda** → searching.
  2. Driver logged in (online) → new offer card → **Accept** → trip page (pickup code 7644).
  3. Driver **I’ve arrived → Start trip → Complete trip**.
  4. Rider screen showed **Trip completed** → **Pay KES 172 with M-Pesa** → **Payment received · MPESA-8fb5c113**.
- Evidence: `dryrun-00-rider-home.png` … `dryrun-08-rider-paid.png`; payment row verified `SUCCESS` in Postgres.
- Notes: booking confirm needs a scroll on the tablet; driver offer/trip buttons are at the bottom of the sheet/page.

### 2026-11-23 — scheduled ride activation
- Scheduling now turns due rides into live bookings: on API startup and every minute, scheduled rides within 10 minutes (up to 60 minutes overdue) create a quote + SEARCHING ride, mark the schedule `ACTIVATED`, store `activatedRideId`, and notify the rider (“Scheduled Boda is ready”). Older schedules become `MISSED`.
- `POST /scheduling/run-due` forces the check (used for tests); migration `0013_scheduled_activation.sql`.
- Verified: created two scheduled rides, set one 1 min overdue and one 2 h overdue, restarted the API → due ride `ACTIVATED` with live `SEARCHING` ride + notification, overdue ride `MISSED`; live ride cancelled afterwards.

### 2026-11-23 — recurring series activation + rollover
- Weekly series occurrences are now kept rolling to 14 days ahead and activated into live rides just like single schedules: due occurrence → quote + `SEARCHING` ride, occurrence `ACTIVATED` with `rideId`, rider notification “Recurring Boda is ready”; overdue → `MISSED`.
- Verified: created a weekly series, set the first occurrence 3 minutes overdue in the DB, restarted the API → occurrence `ACTIVATED` with live `SEARCHING` ride and notification; truncated the occurrence list to one and restarted → window rolled forward to the 14-day horizon (`2026-11-30`, `2026-12-07`).

### 2026-11-23 — driver crash reporting + readiness v0.3
- Driver app now has the same crash hooks as the rider app plus account menu → **Report a problem**; verified a diagnostic from the tablet increased `client_errors` and showed the confirmation snackbar (`evidence/crash-report-02-driver.png`).
- Pilot readiness review v0.3 (`docs/Uko-Pilot-Readiness-Review-v0.3.pdf`): 27/27 API dry run, 9-step device dry run, driver vetting/scheduling/reconciliation/alerting closed; five blockers left (credentials, managed Postgres/TLS, safety responder, camera/gallery docs, legal).

### 2026-11-23 — camera document capture
- Driver Documents screen now has a document-type selector (Licence / Insurance / Vehicle) plus **Take photo** and **Gallery** actions using `image_picker`; demo buttons remain for bench testing.
- Verified on the Lenovo: tapped **Take photo** → system camera → captured a photo → **Done** → uploaded as a real JPEG (`scaled_…jpg`, 15.9 KB) and appeared as `PENDING` in the documents list (`evidence/camera-01-uploaded.png`).
- The server accepts image/JPEG/PNG/PDF/text uploads up to 5 MB.

### 2026-11-23 — gallery capture + final verification suite
- **Gallery** path verified on the Lenovo: Take photo / Gallery picker opened the system photo picker, selected a photo and uploaded it as a pending document alongside camera captures (`evidence/camera-02-gallery-uploaded.png`).
- Final verification run (log: `evidence/final-verification-2026-11-23.txt`): **27/27** API dry run (document gate on, fresh driver), **15/15** pilot smoke, backup of 27 tables / 434 rows, restore into a fresh DB inserted 422 rows with **verification PASSED**; alerts cleared to `ok` after removing test diagnostics.

### 2026-11-23 — production deployment assets
- `app/services/api/Dockerfile` (multi-stage, non-root, healthcheck), `app/deploy/docker-compose.production.yml` (PostGIS + migrate + API + Caddy), `Caddyfile` (automatic TLS + security headers), `.env.production.example`.
- `app/services/api/scripts/migrate.mjs` applies migrations in order with a `schema_migrations` ledger; tested on a fresh local database: **12 applied, 27 tables**, second run **idempotent (0 applied)**. `0002` is skipped locally without PostGIS and applies in the production image.
- Docker is not installed on the bench, so containers were validated statically (YAML parse, runner syntax + real migrations); the stack is ready for a real host once credentials/domain exist.

### 2026-11-23 — daily pilot check + pilot kit
- `tools/pilot-check.mjs` reports readiness, alerts, HTTP failures, money reconciliation, pending driver documents and audit activity; exits non-zero on failures and writes `evidence/pilot-check-report.json`.
- Pilot kit (`docs/Pilot-Kit-v0.1.md`): roles, daily cadence, rider/driver onboarding scripts, SOS drill, incident/refund policy, KPI tracker, go/no-go checklist.
- Verified on the bench: readiness ok, alerts ok, 0 failures, driver documents 0 pending, audit 18 entries; money check warned about 5 unpaid test rides (expected test data).

### 2026-11-23 — pilot readiness v0.4 (final engineering assessment)
- `docs/Uko-Pilot-Readiness-Review-v0.4.pdf`: engineering definition of done, v0.4 scorecard, four external gates (credentials, managed infrastructure, safety responder, legal/privacy) and the pilot start plan.
- Engineering scope declared complete; readiness is conditional on the external gates only.

### 2026-11-23 — Firebase/FCM client + HTTP v1 backend
- Firebase project `uko-pilot` configured for `ke.uko.rider` and `ke.uko.driver`; both apps now initialize Firebase, request notification permission, obtain an FCM token and register it with `POST /notifications/devices`.
- Backend sends Firebase **HTTP v1** messages using service-account OAuth2 (JWT assertion → token → `messages:send`); legacy `FCM_SERVER_KEY` path retained as fallback.
- Verified: both tablet apps registered real tokens (`evidence/fcm-device-tokens.txt`); HTTP v1 path tested against `tools/fake-fcm-v1.mjs` (OAuth + per-device sends, outbox SENT with provider ids). Real delivery awaits the project service-account JSON.

### 2026-11-23 — Google Maps scaffolding + credential helper
- Added `google_maps_flutter`, manifest API-key placeholder from `android/local.properties` (`MAPS_API_KEY`), and a `UkoMap` widget: real Google map when built with `--dart-define=UKO_REAL_MAPS=true`, otherwise the offline stylised map. Both apps rebuilt/installed with the fallback (evidence `maps-fallback-01-rider.png`, `maps-fallback-02-driver.png`).
- Added `tools/setup-google.mjs` (`firebase <service-account.json>` / `maps <key>` / `status`) plus root `.gitignore` for google-services.json, local.properties, .env, service accounts and keystores. Manual console steps and verification in `docs/Google-Setup.md`.
- Build note: driver Gradle build failed with the daemon OOM at `-Xmx8G` on the 6.7 GB host; rebuilding with `-Xmx2G`, `MaxMetaspaceSize=512m`, 2 workers succeeded (~8 min).

### 2026-11-23 — OpenStreetMap in-app maps verified
- Both apps now render real OSM tiles via `flutter_map` with pickup/drop-off markers, route line and attribution; no Google Maps key or billing required.
- Verified on the Lenovo over Wi-Fi: `evidence/osm-map-01-rider.png`, `evidence/osm-map-02-driver.png`, notes in `evidence/osm-map-notes.txt`.
- Offline fallback remains available with `--dart-define=UKO_REAL_MAPS=false` (stylised map).
- Note for public beta: OSM’s free tiles are best-effort under its usage policy; move to a provider/self-hosted tiles if usage grows.

### 2026-11-23 — real FCM push verified
- Firebase service account configured (`PUSH_PROVIDER=fcm`, HTTP v1). IAM role `Firebase Cloud Messaging API Admin` added; after propagation real sends returned 200.
- Outbox rows now **SENT** with real `projects/uko-pilot/messages/…` IDs; tablet logcat shows `FCM foreground: Trip accepted / Trip completed`.
- Background system notification verified on the Lenovo: `evidence/fcm-real-push-01-notification.png` (“At pickup — Rider has been notified…”), details in `evidence/fcm-real-push.txt`.
- Credentials: service-account JSON moved to `~/.config/uko/firebase-service-account.json` (mode 600); values live only in gitignored `.env` files.

### 2026-11-23 — real pickup/drop-off + OSM place search
- New auth API `GET /v1/places/search?q=` (Nominatim + seeded Nairobi fallback, 1h cache).
- Rider booking page: live suggestions, “Use my location”, selected coordinates sent to quotes; map recenters on chosen points.
- Verified: JKIA selected -> quote **KES 459 / 12.3 km** (real coordinates; old stub was ~2 km). Evidence: `places-01-booking.png`, `places-02-search.png`, `places-03-quote.png`, notes in `places-notes.txt`.
- Build note: geolocator needs Android CMake/Ninja; reinstall with `sdkmanager "cmake;3.22.1"` if missing.

### 2026-11-23 — driver live location + navigate
- Driver app shares its real GPS position every 10s (`POST /v1/driver/location`); rider app polls `GET /v1/rides/:id/driver-location` every 4s and shows a moving two-wheeler marker.
- Driver trip page shows real pickup/drop-off coordinates and a **Navigate** button that opens Google Maps directions (no API key).
- Verified: tablet location posted and readable by the rider API; driver trip screenshot `live-02-driver-trip.png`; notes `live-location-notes.txt`.

### 2026-11-23 — accurate road routes (OSRM)
- New auth API `GET /v1/routes` proxying OSRM with full road geometry, 1h cache and a straight-line fallback.
- Quotes now price on road distance/duration; rider booking and trip maps draw the road-following polyline.
- Verified Kenyatta Avenue → JKIA: **16.3 km / 22 min / KES 524**, 328 geometry points; screenshot `route-01-rider.png`; notes `routing-notes.txt`. Rider verified (`route-01-rider.png`); driver trip map verified after rebuilding (`route-02-driver.png`).
- Rider startup hardened: Firebase initializes after `runApp` so the splash can’t hang.

### 2026-11-24 — icons, scheduled coordinates, notification deep links
- Bundled MaterialIcons explicitly (Flutter 3.50/material_ui no longer copied the font despite `uses-material-design: true`); rider icons now render — `icons-02-home.png`.
- Scheduled rides now resolve/verify real pickup/drop-off coordinates instead of hardcoded stubs.
- Notification tap handlers added: rider opens the ride screen from `rideId`; driver opens the active trip.
- Rider rebuilt/installed; driver source updated but its APK rebuild kept getting OOM-killed on this host (Gradle 1.5G / Kotlin 768M / 1 worker). Notes: `icons-schedule-deeplink-notes.txt`.

### 2026-11-24 — driver build retry succeeded
- Prepared the host (no daemons, clean build dirs, CMake/Ninja verified, ~6.2G disk / 3.4G RAM) and built the driver directly with Gradle:
  `cd app/apps/driver/android && ./gradlew assembleDebug --console=plain` → **BUILD SUCCESSFUL in 17m 54s**.
- Driver APK installed; icons render and the online/offers/earnings home is intact (`icons-04-driver-home.png`).
- Notes: `driver-build-ready.txt`.

### 2026-11-24 — maximized maps + route preview
- Backend route API returns OSRM turn-by-turn steps; rider full-screen route page shows a large map, ETA (`16.3 km · about 22 min`), 25 directions, zoom controls and **Open in Google Maps**.
- Booking and trip maps have expand buttons; schedule page has live place suggestions; driver has the same full-screen route/preview code (rebuild in progress).
- Evidence: `maps-max-01-booking.png`, `maps-max-02-route-preview.png`, `maps-fit-01-route.png`, notes `map-ux-notes.txt`.
- Route bounds are fitted with `CameraFit.bounds` and UI padding so long routes are centred between the summary card and directions sheet.
- Driver route page verified on a live accepted trip: `driver-route-preview.png` (16.3 km / 22 min / 25 directions / Google Maps button).

### 2026-11-25 — saved places + live ETA
- Saved places persist locally (shared_preferences): seeded Home/Work/Airport/Mall; booking sheet lists them; booking page can save a place with a label and coordinates.
- Rider driver-card shows a live ETA (`Driver N min away` / `N min to destination`) from OSRM, refreshed at most every 10s from the driver-location feed.
- Saved places verified on the tablet: `saved-places-01-sheet.png`.
- Live ETA verified on a real ride: `Driver 7 min away` -> moved location -> `Driver 1 min away`, with rider map marker; evidence `live-eta-01-rider.png`, `live-eta-02-rider.png`.
- Saved places have Rename/Remove menus (`saved-places-02-menu.png`); driver trip page now shows its own ETA to pickup/drop-off (rebuild installed, visual test pending). Notes `saved-places-live-eta-notes.txt`.

### 2026-11-25 — runtime offline map fallback
- `UkoMap` probes OSM reachability every 15s; when offline it switches to the stylised map with an **Offline map** badge and recovers automatically when connectivity returns.
- Verified on the rider app with Wi-Fi/data disabled (`offline-01-rider.png`) and re-enabled (`offline-02-online.png`); driver rebuilt with the same fallback. Notes `offline-fallback-notes.txt`.

### 2026-11-25 — home map placeholder line removed
- The straight line on the home hero map was a demo placeholder between two hard-coded coordinates, not a route.
- Maps now draw a polyline only from real OSRM geometry; home maps with no active trip show no line/markers, and route previews never fall back to a straight line.
- Verified clean home map `home-map-no-line.png`; road route still `maps-fit-01-route.png`.

### 2026-11-25 — calculating route + public hosting + dispatch
- Maps show a “Calculating route…” pill while OSRM geometry is being fetched (rider/driver).
- Free public endpoints via Cloudflare Quick Tunnels: API and dispatch console (see `docs/Free-Hosting.md`, `docs/Dispatch-Setup.md`); rider APK rebuilt with the public API URL and tested without adb reverse.
- Dispatch console live through the tunnel with CORS confirmed; `tools/dispatch-link.mjs` generates a login URL.

### 2026-11-25 — live Render + Neon deployment
- API: `https://uko-pilot-api.onrender.com/v1` — `/v1/health` and `/v1/health/ready` ok (Neon database reachable); CORS allows the dispatch origin.
- Dispatch: `https://uko-pilot-dispatch.onrender.com/` — static site deployed.
- Rider + driver APKs rebuilt with `API_BASE_URL=https://uko-pilot-api.onrender.com/v1` and installed; login screens show the Render API (dev OTP disabled, SMS login).
- Notes: `render-live-notes.txt`; hosting guide `docs/Free-Hosting.md`.

## Device constraints (quick)

- Android **12 (API 31)**: no POST_NOTIFICATIONS runtime prompt; test that on API 33+ later.
- Tablet width ≈800 dp: check portrait and landscape; no layout break.
- SIM may be inactive: use dev OTP (`EXPOSE_DEV_OTP=true`) for automated flows.
- 3.7 GB RAM: watch cold start and map rendering on this low-end target.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `adb devices` empty | Re-plug USB, accept “Allow USB debugging”, check `lsusb` |
| App can't reach API | `adb reverse --list`; re-run `adb reverse tcp:3000 tcp:3000` |
| HTTP blocked in debug build | Debug manifest must allow cleartext to localhost (see rider `android/app/src/debug/AndroidManifest.xml`) |
| Install fails `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | `adb uninstall <package>` then install |
| Device sleeps during a test | `adb shell svc power stayon true` |

### Bench storage/build cleanup (2026-11-23)
- Deleted regenerable Gradle `transforms`/build cache (~3.2G) after repeated silent build kills; capped `kotlin.daemon.jvmargs=-Xmx1024m` and Gradle heap at 2G. Driver build then succeeded in ~5 min.
- Keep an eye on `/` free space; builds need roughly 1–2G headroom.
