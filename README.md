# Uko? — rider tracking & scheduled rides

Working project folder for the **Uko?** platform: an original rider-tracking and scheduled-rides product benchmarked against Bolt Rider and Bolt Driver.

## Current status

**Step 0 — plan complete (2026-11-20).**
**Step 1 — Phase 0 evidence sprint: both reference builds pinned (2026-11-21).**
**Step 2 — Phase 1 + Spike A complete (2026-11-21): reference coverage 80.5%, evidence gate passed by acceptance.**
**Step 3 — Phase 2 specs drafted + MVP scope frozen v1.1 (2026-11-21): PRD + architecture delta updated with owner decisions; recurring schedules and calendar suggestions added to MVP.**
**Step 4 — Sprint 1 preparation complete (2026-11-22): repo scaffold, foundation SQL, walking-skeleton API (validated auth flow), sprint plan and foundation API contract.**
**Step 5 — First app on the test bench (2026-11-22): Flutter + Android SDK installed, rider APK built and installed on the Lenovo TB-J616X; OTP login verified end-to-end on-device.**
**Step 6 — Booking flow on-device (2026-11-22): quote → payment method → confirm → driver assigned (simulated) → cancel; rider APK rebuilt and verified on the tablet.**
**Step 7 — Driver app on-device (2026-11-22): driver login, online toggle, incoming offer, accept, pickup code, arrived → started → completed trip lifecycle verified on the tablet.**
**Step 8 — Rider + driver matching on-device (2026-11-22): a real rider booking becomes the driver’s offer; rider and driver share one ride with synchronised pickup code and lifecycle.**
**Step 9 — Scheduling + recurring series on-device (2026-11-22): schedule a Boda up to 90 days ahead, repeat weekly for up to 8 weeks, manage and pause/resume series; timezone-correct EAT display.**
**Step 10 — Calendar suggestions on-device (2026-11-22): opt-in read-only calendar access, on-device event filtering (next 7 days, location required), tap-to-prefill a scheduled ride; no server storage.**
**Step 11 — M-Pesa payment on-device (2026-11-22): completed-trip payment with simulated STK push, pending → paid receipt, plus cash confirmation; verified end-to-end on the tablet.**
**Step 12 — Safety & SOS on-device (2026-11-22): emergency contacts, SOS with simulated private-response acknowledgement, false-alarm cancel; in-trip SOS button added.**
**Step 13 — Postgres persistence (2026-11-23): user-space PostgreSQL 18 cluster, core schema migration, DB-backed auth verified across API restarts; app works against the DB-backed API.**
**Step 14 — Map-led UI pass (2026-11-23): new ride-hailing home with stylised map, floating header, bottom booking sheet and quick actions; trip screen with route map + driver marker.**
**Step 15 — Driver UI pass (2026-11-23): map-led driver home, 45 s offer countdown ring, route map and 4-step trip timeline.**
**Step 16 — Trips & receipts (2026-11-23): ride history with payment status and a receipt sheet (fare, method, receipt, ride id) verified on the tablet.**
**Step 17 — Driver earnings (2026-11-23): daily earnings endpoint and driver home summary (trips, gross, commission, net) verified on-device.**
**Step 18 — Domain persistence (2026-11-23): rides, driver trips/status, payments, safety and scheduling now survive API restarts via a Postgres JSONB snapshot layer; verified via API and on the tablet.**
**Step 19 — Normalized persistence (2026-11-23): those domains now live in proper Postgres tables (quotes, rides, driver_trips, driver_availability, payments, safety_*, scheduled_rides, schedule_series) with startup load + mutation upserts.**
**Step 20 — Booking sheet polish (2026-11-23): draggable Where-to sheet with saved and recent places, prefilled booking, and a route-map header on the booking page.**
**Step 21 — Dispatch console (2026-11-23): ops dashboard with live metrics, rides/incidents/scheduled views and cancel/resolve actions, verified in headless Chromium.**
**Step 22 — Driver shift + pilot readiness review (2026-11-23): shift tracking/summary in the driver app, and a 6-page readiness review with scorecard, blockers, risks and a go/no-go checklist.**
**Step 23 — Security hardening (2026-11-23): helmet headers, request IDs + structured logs, OTP rate limits, SMS provider adapter, dispatch phone allow-list and audit log.**
**Step 24 — Data durability & ops (2026-11-23): tested Postgres backup/restore drill, 15-check pilot smoke script, dispatch audit view and the pilot operations runbook.**
**Step 25 — Daraja STK integration (2026-11-23): real M-Pesa OAuth + STK push + callback behind `MPESA_PROVIDER=daraja`, verified success/failure against a local fake gateway.**
**Step 26 — Push notification outbox (2026-11-23): device registry + notification outbox with dev/FCM adapter, triggered by ride lifecycle events and verified against a fake FCM gateway.**
**Step 27 — SMS gateway test + rider inbox (2026-11-23): configurable SMS endpoint verified against a fake Africa’s Talking gateway, and the rider app now shows a notification inbox on the tablet.**
**Step 28 — Driver notifications inbox (2026-11-23): driver trip events generate notifications, and the driver app shows them in an in-app inbox on the tablet.**
**Step 29 — Ride ratings (2026-11-23): completed trips can be rated in the receipt sheet; ratings are stored per ride/driver and notify the driver.**
**Step 30 — Observability & analytics (2026-11-23): readiness/metrics endpoints, server-side analytics events and a dispatch System view.**
**Step 31 — Driver document vetting (2026-11-23): licence/insurance upload from the driver app, ops review in dispatch, approval gating for online status.**
**Step 32 — Pilot dry run & gate hardening (2026-11-23): 27-check end-to-end dry run passed and persisted online states are re-checked against document approval at startup.**
**Step 33 — Crash reporting & alerting (2026-11-23): client error intake from the apps, alert evaluation endpoint and dispatch System alerts.**
**Step 34 — Alert webhook + document expiry (2026-11-23): Slack-compatible alert delivery with dedupe, and driver document expiry reminders in the notification outbox.**
**Step 35 — Payment reconciliation (2026-11-23): dispatch Money view comparing completed rides to payments, with commission, payout and mismatch detection.**
**Step 36 — Device-level pilot dry run (2026-11-23): full rider booking → driver accept → trip → rider payment flow driven through the real apps on the Lenovo and verified.**
**Step 37 — Scheduled ride activation (2026-11-23): due scheduled rides become live SEARCHING rides with rider notification; overdue schedules marked missed.**
**Step 38 — Recurring series activation (2026-11-23): weekly occurrence window rolls to 14 days and due occurrences become live rides with notifications.**
**Step 39 — Driver crash reporting & readiness v0.3 (2026-11-23): driver app crash/report parity and the refreshed pilot review with five remaining blockers.**
**Step 40 — Camera document capture (2026-11-23): real photo capture from the driver app with type selector, uploaded as a pending document and verified on the tablet.**
**Step 41 — Gallery capture + final verification (2026-11-23): gallery document upload verified on the tablet; 27/27 dry run, 15/15 smoke and backup/restore drill all green.**
**Step 42 — Production deployment assets (2026-11-23): API Dockerfile, PostGIS + migrate + API + Caddy compose stack, secrets template and a migration runner tested on a fresh database.**
**Step 43 — Daily pilot check + pilot kit (2026-11-23): one-command daily ops check and the complete pilot onboarding/training/go-no-go pack.**
**Step 44 — Pilot readiness v0.4 (2026-11-23): final engineering assessment with definition of done, four external gates and pilot start plan.**
**Step 45 — Firebase/FCM integration (2026-11-23): both apps register real FCM tokens and the API sends HTTP v1 messages via service-account OAuth2 (verified against a fake gateway).**
**Step 46 — Google Maps scaffolding + credential setup (2026-11-23): Maps plugin, manifest key placeholder and fallback map widget, plus `tools/setup-google.mjs` for the remaining service-account and Maps-key steps.**
**Step 47 — OpenStreetMap in-app maps (2026-11-23): switched both apps to `flutter_map` + OSM tiles (no key/billing), with markers, route line and attribution; Google Maps scaffolding replaced.**
**Step 48 — Real FCM push verified (2026-11-23): service-account HTTP v1 live; outbox SENT with real message IDs and background notifications on the tablet.**
**Step 49 — Real pickup/drop-off + geocoding (2026-11-23): places search API (OSM Nominatim), rider suggestions + current location, coordinate-based quotes and map recenter (airport quote KES 459 / 12.3 km).**
**Step 50 — Driver live location + Navigate (2026-11-23): driver posts GPS every 10s, rider map shows a moving driver marker, and the driver trip page opens Google Maps navigation without any API key.**
**Step 51 — Accurate road routes (2026-11-23): OSRM route endpoint + road geometry on rider/driver maps; quotes priced on road distance (JKIA: 16.3 km / 22 min / KES 524).**
**Step 52 — Icon font, scheduled coordinates, notification deep links (2026-11-24): MaterialIcons bundled explicitly, scheduled rides use real coords, push taps open the ride/trip; rider verified.**
**Step 53 — Driver build recovery (2026-11-24): prepared host and built the driver directly with Gradle (17m 54s), installed it; icons/home verified.**
**Step 54 — Maximized maps + route preview (2026-11-24): OSRM turn-by-turn steps, full-screen map with ETA/directions/zoom, expand buttons, schedule place suggestions, Open in Google Maps.**
**Step 55 — Route camera fit (2026-11-25): preview and full-screen maps now fit the whole route with UI padding (`CameraFit.bounds`); rider verified, driver rebuilt/installed.**
**Step 56 — Saved places + live ETA (2026-11-25): persisted saved places with a save action, and a live driver ETA on the rider driver card; ETA verified 7 min → 1 min on an assigned ride.**
**Step 57 — Saved place edit/delete, driver ETA, offline fallback (2026-11-25): rename/remove menus, driver remaining-ETA, and runtime map fallback with automatic recovery.**
**Step 58 — Home map line fix (2026-11-25): removed the demo straight placeholder; polylines now appear only for real OSRM route geometry.**
**Step 66 — Cancellation rules, pickup verification, branded icons (2026-11-27): no default destination, driver pickup-code check, reasoned rider cancellation with arrived-state lock and dispatch visibility, new launcher icons.**
**Step 65 — Thika pilot zone + instant search (2026-11-27): Thika defaults across apps/API/dispatch; destination suggestions now start at the first character and stay visible above the keyboard.**
**Step 64 — Juja zone, GPS pickup, live search, mobile dispatch (2026-11-27): Juja defaults across apps/API/dispatch, live destination suggestions + reverse geocoding, GPS-first rider pickup, header-free UI and mobile dispatch layout.**
**Step 63 — Fixed test credentials (2026-11-25): rider/driver/dispatch test numbers with generic OTP 123456; removed one-tap test-login endpoints and cards.**
**Step 62 — One-tap test logins (2026-11-25): guarded test accounts for rider, driver, dispatch, safety and admin, with test-login cards in both apps and the dispatch console.**
**Step 61 — Live Render + Neon deployment (2026-11-25): API https://uko-pilot-api.onrender.com (health/ready ok, CORS to dispatch) and dispatch https://uko-pilot-dispatch.onrender.com; Neon schema migrated; OTP via SMS.**
**Step 60 — Render + Neon deployment prep (2026-11-25): Neon SSL, boot-time migrations, Render Blueprint for API + static dispatch, app build script and deployment guide.**
**Step 59 — Calculating route + public hosting + dispatch (2026-11-25): route spinner, free Cloudflare quick tunnels for API/dispatch, public API build for rider/driver, and dispatch access tooling.**

- Plan deliverable: [`docs/Uko-Product-Plan-v0.1.pdf`](docs/Uko-Product-Plan-v0.1.pdf) (11 pages); source [`docs/uko-plan-v0.1.html`](docs/uko-plan-v0.1.html)
- **MVP scope freeze (PDF, 3 pages): [`docs/Uko-MVP-Scope-Freeze-v1.1.pdf`](docs/Uko-MVP-Scope-Freeze-v1.1.pdf)** — decisions, frozen scope incl. recurring + calendar, launch gate, build sequence + sign-off block
- **PRD v0.1 (scope-freeze updated): [`spec/prd-v0.1.md`](spec/prd-v0.1.md)** — Boda-only, no cancellation fee, 20% commission, private emergency response, recurring schedules, calendar suggestions, Uko? brand
- **Architecture delta v0.1 (scope-freeze updated): [`spec/architecture-delta-v0.1.md`](spec/architecture-delta-v0.1.md)** — services, API contract, data model (series), state machines, M-Pesa flow, dispatch, ADRs, build sequence
- **Sprint 1 plan: [`spec/sprint-1-plan.md`](spec/sprint-1-plan.md)** — goal, backlog FND-0…FND-11, environment gaps, demo, exit criteria
- **Foundation API contract: [`spec/api-foundation-v0.1.md`](spec/api-foundation-v0.1.md)** — auth/token/me/zones endpoints, errors, client behaviour
- **Application scaffold: [`app/`](app/README.md)** — NestJS walking skeleton (builds; auth flow smoke-tested), SQL foundation + Boda seed, Docker Compose, CI, Makefile
- **Primary test device: [`spec/test-device-lenovo-tb-j616x.md`](spec/test-device-lenovo-tb-j616x.md)** — Lenovo TB-J616X, Android 12/API 31, arm64, 3.7 GB RAM, ≈800 dp wide, connected over adb · **first rider build + OTP login verified on-device**
- **Test bench: [`testbench/`](testbench/README.md)** — device-prep, install and evidence scripts; rider + driver builds and screenshots in `testbench/evidence/`
- **Pilot readiness review: [`docs/Uko-Pilot-Readiness-Review-v0.4.pdf`](docs/Uko-Pilot-Readiness-Review-v0.4.pdf)** (6 pages, latest) — final engineering assessment: definition of done, v0.4 scorecard, four external gates and pilot start plan; source [`docs/uko-pilot-readiness-v0.4.html`](docs/uko-pilot-readiness-v0.4.html). Previous: [`v0.3`](docs/Uko-Pilot-Readiness-Review-v0.3.pdf), [`v0.2`](docs/Uko-Pilot-Readiness-Review-v0.2.pdf), [`v0.1`](docs/Uko-Pilot-Readiness-Review-v0.1.pdf).
- **Pilot operations runbook: [`docs/Pilot-Operations-Runbook-v0.1.md`](docs/Pilot-Operations-Runbook-v0.1.md)** — daily checks, backup/restore, SOS handling, dispatch access, escalation
- **Pilot kit: [`docs/Pilot-Kit-v0.1.md`](docs/Pilot-Kit-v0.1.md)** — roles, daily cadence, rider/driver onboarding scripts, SOS drill, KPI tracker and go/no-go checklist
- **Production deployment: [`app/deploy/README.md`](app/deploy/README.md)** — Docker Compose stack (PostGIS, migrations, API, Caddy TLS), secrets template and operations notes
- **Firebase setup + maps status: [`docs/Google-Setup.md`](docs/Google-Setup.md)** — one remaining Firebase service-account step; in-app maps use OpenStreetMap with no key
- **Free hosting (Render + Neon): [`docs/Free-Hosting.md`](docs/Free-Hosting.md)** — permanent deploy blueprint, Neon SSL, migrations-on-boot and app rebuild script
- **Current status brief (PDF): [`docs/Uko-Phase1-Status-Brief.pdf`](docs/Uko-Phase1-Status-Brief.pdf)** (7 pages) — plain-language where-we-are + recommended path
- Evidence pack: [`recon/bolt-builds/bolt-builds.md`](recon/bolt-builds/bolt-builds.md)
- Parity matrix v0 + v1/v1.1 scoring: [`recon/parity-matrix-v0.md`](recon/parity-matrix-v0.md)
- **Phase 1 reference report v1.0: [`recon/phase1-reference-report-v0.md`](recon/phase1-reference-report-v0.md)**
- **Spike A gap closure: [`recon/spike-a-gap-closure.md`](recon/spike-a-gap-closure.md)** — 216 driver endpoints, offer/pricing/notification contracts; **reference coverage 80.5%**, remaining gaps accepted as non-blocking
- Rider build pinned: `ee.mtakso.client` **CA.234.0**, SHA-256 `c2475da3…ae7ee7`, signed v2+v3 by Mtakso OÜ
- Driver build pinned: `ee.mtakso.driver` **DA.157.0**, SHA-256 `13351bfe…86918c`, same signer, `ACCESS_BACKGROUND_LOCATION` + Mapbox navigation
- Investigation memory: `recon/bolt.cany/` (craft-anything project: brief, plan, handoff)

**Observed so far:** MQTT is the realtime transport in both apps; rider has a dedicated `scheduledrides/core` module and a `preorderflow` booking flow; driver has `ScheduledRideRequests`/`ScheduledRidesGroupRequest` models; calendar-based suggestions exist; masked calling uses Sinch; driver uses Mapbox, rider uses Google Maps.

**Code-level:** rider scheduled-ride API family is mapped — `order/createScheduled`, `getScheduledRideEta`, `getScheduledRidePickupTimeScreen`, `getFlightSuggestions`, `mobility/editScheduledRide`, `client/v1/cancelRide`; payments use dedicated 3-D Secure challenge endpoints + Google Pay token + instrument lifecycle; SOS calls `emergencyCall/register`. Driver: offer endpoints `driver/offers/accept|reject`, `POST /driver/acknowledgeRiderConfirmation`, full `OrderState` enum, `ScheduledRidesGroupRequest`, server-driven `ScheduledRideDetails`, and a third pricing model — **price bidding** (`rides/order/updateOffer`, `CounterOffer` with bid variants and `price_bands`).

The PDF covers: product concept and MVP boundary, the public Bolt capability baseline, the evidence-first reverse-engineering method for both Bolt apps, the four product surfaces, scheduling rules and ride lifecycle, system architecture, a 25-week delivery roadmap, quality gates, risks and decisions D1–D8.

## Quick facts from the plan

| Item | Value |
|---|---|
| Reference builds | Bolt Rider `ee.mtakso.client` CA.234.0 · Bolt Driver `ee.mtakso.driver` DA.157.0 (planning snapshot — re-pin and hash at acquisition) |
| Product surfaces | Rider app · Driver app · Dispatch console · public Track link |
| Stack | Flutter · NestJS · PostgreSQL/PostGIS · Redis · MQTT · M-Pesa Daraja · Next.js |
| Roadmap | ~26–27 weeks to single-zone pilot (25-week plan + recurring/calendar additions), seven-person team |
| Market | Kenya, one Nairobi pilot zone, **Boda only** |
| Primary test device | Lenovo TB-J616X tablet · Android 12 (API 31) · arm64 · 3.7 GB RAM · 1200×2000 @ 240 dpi |

## Frozen decisions

Boda-only pilot · no cancellation fee during pilot · ~20% commission (weekly manual payouts) · private emergency response · brand “Uko?” · recurring schedules and calendar suggestions in MVP. Assumptions to confirm: scheduling window 45 min–90 days; recurring 8-week horizon + per-occurrence payment; calendar suggestions next-7-days window.

## Next steps

1. Install Flutter + Docker on team machines (FND-0) and sign off the PRD assumptions.
2. Sprint 1: database-backed auth (OTP, rotating refresh, logout), profiles/documents, zones/pricing from Postgres, API conventions, Flutter shells, CI.
3. Sprint 2: quotes, on-demand booking, MQTT tracking skeleton, cash payment.
4. Prototype + technical design review before the first build PR.

## Folder layout

```
uko/
├── README.md
├── docs/                  # PDFs: plan, status brief, scope freeze
├── spec/                  # PRD, architecture delta, sprint plan, API contract
├── app/                   # application monorepo scaffold (Sprint 1)
│   ├── services/api/      # NestJS walking skeleton
│   ├── apps/              # rider, driver, dispatch (bootstrap pending Flutter/Next)
│   ├── db/                # SQL migrations + seeds (PostGIS)
│   └── docker-compose.yml # Postgres/PostGIS, Redis, EMQX
└── recon/                 # Bolt evidence pack, decompiled trees, investigation memory
```
