# Uko? — Foundation API contract v0.1 (Sprint 1)

**Status:** implemented in the walking skeleton; hardening tasks FND-4/FND-7 finalise persistence and conventions.
**Base URL:** `http://localhost:3000/v1` (dev) · `https://api.uko.example/v1` (production, TBD)
**Auth:** `Authorization: Bearer <accessToken>` for protected endpoints.
**Timestamps:** ISO-8601 UTC; business times displayed in EAT (Africa/Nairobi).
**Docs:** Swagger UI at `/docs` when the API runs.

---

## 1. Conventions

| Convention | Rule |
|---|---|
| Versioning | URL prefix `/v1`; breaking changes → `/v2` |
| Content type | `application/json; charset=utf-8` |
| Request ID | `X-Request-Id` returned on every response (generated if absent); logged with the request |
| Idempotency | writes accept `Idempotency-Key` (UUID) — enforced from Sprint 2 |
| Errors | `{ "statusCode", "code", "message", "requestId" }` — final envelope task FND-7 |
| Pagination | cursor-based `?cursor=&limit=` (Sprint 2+) |
| Rate limits | OTP request: 3/hour/phone + 10/hour/IP; auth verify: 10/10 min/phone (FND-3) |
| PII in logs | phone numbers masked (`+2547****678`); tokens never logged |

### Error codes (foundation)
`OTP_NOT_REQUESTED`, `OTP_EXPIRED`, `OTP_INVALID`, `OTP_TOO_MANY_ATTEMPTS`,
`REFRESH_INVALID`, `REFRESH_EXPIRED_OR_ROTATED`, `ACCESS_MISSING`, `ACCESS_INVALID`,
`VALIDATION_FAILED`, `RATE_LIMITED`, `INTERNAL_ERROR`.

---

## 2. Endpoints

### 2.1 `GET /health`
Public liveness probe.
```json
{ "status": "ok", "service": "uko-api", "version": "0.1.0", "time": "2026-11-22T11:18:57.245Z" }
```

`GET /health/db` → `{"database":"up"}` · `{"database":"down"}` (never exposed publicly).

### 2.2 `POST /auth/otp/request`
Request an OTP for a phone number.

Request:
```json
{ "phone": "+254712345678" }
```
Response `201`:
```json
{ "sent": true, "channel": "sms", "expiresInSeconds": 300 }
```
**Development only** (when `NODE_ENV != production` and `EXPOSE_DEV_OTP=true`):
```json
{ "sent": true, "channel": "sms", "expiresInSeconds": 300, "dev_code": "448549" }
```
Errors: `VALIDATION_FAILED` (not E.164), `RATE_LIMITED`.

### 2.3 `POST /auth/otp/verify`
Verify the OTP and create the user on first login.

Request:
```json
{ "phone": "+254712345678", "code": "448549" }
```
Response `201`:
```json
{
  "user": { "id": "dev_847388", "phone": "+254712345678", "name": null, "createdAt": "2026-11-22T11:20:00.000Z" },
  "tokens": {
    "accessToken": "eyJ...",
    "refreshToken": "eyJ...",
    "tokenType": "Bearer",
    "expiresIn": 900
  }
}
```
Errors: `OTP_NOT_REQUESTED`, `OTP_EXPIRED`, `OTP_INVALID`, `OTP_TOO_MANY_ATTEMPTS`.

### 2.4 `POST /auth/token/refresh`
Exchange a refresh token for a new pair. **Rotating:** the old refresh token is invalid immediately.

Request:
```json
{ "refreshToken": "eyJ..." }
```
Response `201`: same `tokens` object as verify.
Errors: `REFRESH_INVALID`, `REFRESH_EXPIRED_OR_ROTATED`.

### 2.5 `POST /auth/logout`
Revoke the session tied to the supplied refresh token.

Request:
```json
{ "refreshToken": "eyJ..." }
```
Response `201`:
```json
{ "loggedOut": true, "userId": "dev_847388" }
```

### 2.6 `GET /me` 🔒
Return the authenticated user.

Response `200`:
```json
{ "user": { "id": "dev_847388", "phone": "+254712345678", "name": null, "createdAt": "2026-11-22T11:20:00.000Z" } }
```
Errors: `ACCESS_MISSING`, `ACCESS_INVALID`.

### 2.7 `GET /zones` and `GET /zones/active`
Public zone/pricing config for client bootstrapping (pilot has one zone).

Response `200`:
```json
{
  "id": "zone_nairobi_pilot",
  "name": "Nairobi pilot zone",
  "city": "Nairobi",
  "currency": "KES",
  "category": "boda",
  "pricing": {
    "baseFare": 50,
    "perKm": 25,
    "perMinute": 3,
    "minimumFare": 80,
    "cancellationFee": 0,
    "commissionPercent": 20,
    "surge": { "enabled": false }
  }
}
```
Sprint 1 FND-6 replaces this in-memory stub with Postgres reads.

---

## 2a. Booking endpoints (walking skeleton, in-memory)

All booking endpoints require `Authorization: Bearer <accessToken>`.

### `POST /quotes` 🔒
Request:
```json
{
  "pickup":  { "lat": -1.2921, "lng": 36.8219, "address": "Kenyatta Avenue" },
  "dropoff": { "lat": -1.2648, "lng": 36.8031, "address": "Westlands" }
}
```
Response `201`:
```json
{ "quote": {
  "id": "q_…", "fare": 172, "currency": "KES",
  "distanceKm": 3.69, "durationMin": 10,
  "breakdown": { "baseFare": 50, "distanceFare": 92, "timeFare": 30, "minimumFareApplied": false },
  "pickup": { "lat": -1.2921, "lng": 36.8219, "address": "Kenyatta Avenue" },
  "dropoff": { "lat": -1.2648, "lng": 36.8031, "address": "Westlands" },
  "expiresAt": 1763820000000, "createdAt": "2026-11-22T16:24:00.000Z"
}}
```
Fare rule (Boda pilot): base **50**, **25/km**, **3/min**, minimum **80**, average city speed 22 km/h.

### `POST /rides` 🔒
```json
{ "quoteId": "q_…", "paymentMethod": "mpesa" }
```
Response `201`: `{ "ride": { "id": "r_…", "state": "SEARCHING", "fare": 172, "currency": "KES", "paymentMethod": "mpesa", … } }`

The ride is now matched with online drivers: it appears in their `GET /driver/offers` as a real offer. When a driver accepts, the same ride transitions to `ASSIGNED`, gains `driver` and `pickupCode`, and follows the driver’s trip actions (`ARRIVED → IN_PROGRESS → COMPLETED`). Ride states: `SEARCHING`, `ASSIGNED`, `ARRIVING`, `ARRIVED`, `IN_PROGRESS`, `COMPLETED`, `CANCELLED`.

### `GET /rides/{id}` 🔒
Returns the ride; the walking skeleton simulator transitions `SEARCHING → ASSIGNED` after ~5 s (mock driver) and `ASSIGNED → ARRIVING` after ~20 s.

### `POST /rides/{id}/cancel` 🔒
Cancels a `SEARCHING`/`ASSIGNED`/`ARRIVING` ride; returns `state: "CANCELLED"`.

### `GET /rides` 🔒
Lists the rider’s rides, newest first.

## 2b. Driver endpoints (walking skeleton, in-memory)

All driver endpoints require `Authorization: Bearer <accessToken>`.

| Endpoint | Purpose |
|---|---|
| `GET /driver/status` | online flag, active trip, pending offers |
| `POST /driver/online` `{ "online": true }` | go online/offline; going online generates one mock offer |
| `GET /driver/offers` | pending offers (expire after 60 s) |
| `POST /driver/offers/{id}/accept` | accept offer → creates trip `ACCEPTED` with 4-digit pickup code |
| `POST /driver/offers/{id}/reject` | decline and receive the next offer |
| `GET /driver/earnings` | today/lifetime trips, gross, 20% commission, net (Nairobi day boundary) |
| `GET /driver/shift` | online state, on-shift since, online minutes today, trips and net today |
| `GET /driver/trips/current` | active trip or null |
| `POST /driver/trips/{id}/arrived` | `ACCEPTED → ARRIVED` |
| `POST /driver/trips/{id}/start` | `ARRIVED → IN_PROGRESS` |
| `POST /driver/trips/{id}/complete` | `IN_PROGRESS → COMPLETED`; new offer generated if online |

Offers are built from real pending rider rides (`BookingService.pendingRides`); accepting assigns the driver to that ride and creates the driver trip with a shared pickup code. Postgres-backed matching and dispatch ranking arrive in the database sprint.

## 2c. Scheduling endpoints (walking skeleton, in-memory)

All endpoints require `Authorization: Bearer <accessToken>`.

| Endpoint | Purpose |
|---|---|
| `POST /scheduled-rides` | schedule a Boda: pickup/drop-off, `scheduledAt` ISO (45 min–90 days), optional payment method; returns fixed fare |
| `GET /scheduled-rides` | upcoming scheduled rides |
| `POST /scheduled-rides/{id}/cancel` | cancel a scheduled ride |
| `POST /scheduled-rides/{id}/repeat` | create a weekly series: `weekdays` (1=Mon…7=Sun), `endDate` ISO (max 8 weeks) |
| `GET /schedule-series` | rider’s recurring series |
| `PATCH /schedule-series/{id}` | `{ "status": "ACTIVE" \| "PAUSED" \| "CANCELLED" }` — pause/resume/cancel |

Series model: weekday pattern, time of day (EAT), start/end date, status `ACTIVE/PAUSED/CANCELLED/FINISHED`, occurrences generated for the next 14 days (max 100). Postgres repositories arrive in the database sprint.

## 2d. Calendar suggestions (on-device only)

Calendar suggestions have **no server API**: the rider app reads the next 7 days of calendar instances on the device (Android `READ_CALENDAR`, opt-in), keeps events with a location, dedupes and shows up to 3. Calendar events are never uploaded or stored server-side; only the destination/time the rider explicitly selects is sent through the existing scheduling endpoints.

## 2e. Payments endpoints (walking skeleton)

All endpoints require `Authorization: Bearer <accessToken>`. Payment is allowed only after the ride reaches `COMPLETED`, and only for the ride’s chosen method.

| Endpoint | Purpose |
|---|---|
| `POST /payments/mpesa/stk` `{ "rideId": "r_…" }` | start a simulated M-Pesa STK request; returns `PENDING` payment with `checkoutRequestId` and customer message |
| `GET /payments/ride/{rideId}` | latest payment for a ride (null before payment) |
| `GET /payments/{id}` | payment status; a pending STK auto-succeeds after ~4 s |
| `POST /payments/{id}/simulate` `{ "result": "SUCCESS" \| "FAILED" }` | force the outcome for tests |
| `POST /payments/cash/confirm` `{ "rideId": "r_…" }` | record a cash payment as `SUCCESS` |

Payment model: `id`, `rideId`, `amount`, `currency`, `method` (`mpesa`/`cash`), `status` (`PENDING`/`SUCCESS`/`FAILED`), `checkoutRequestId`, `customerMessage`, `receipt`, timestamps. Production will replace the simulator with Daraja STK push + callback verification and an immutable ledger.

## 2f. Safety endpoints (walking skeleton)

All endpoints require `Authorization: Bearer <accessToken>`.

| Endpoint | Purpose |
|---|---|
| `GET /safety/contacts` | rider’s emergency contacts |
| `POST /safety/contacts` `{ name, phone, relationship? }` | add an emergency contact |
| `DELETE /safety/contacts/{id}` | remove a contact |
| `POST /safety/sos` `{ rideId?, lat?, lng?, note? }` | raise SOS; copies emergency contacts onto the incident |
| `GET /safety/incidents` | rider’s incidents |
| `GET /safety/incidents/{id}` | incident state; simulated acknowledgement after ~5 s (`OPEN → ACKED`) |
| `POST /safety/incidents/{id}/cancel` | false-alarm cancel |

Incident model: `id`, `rideId?`, `type=SOS`, `state` (`OPEN`/`ACKED`/`RESOLVED`/`CANCELLED`), optional coordinates/note, notified contacts, event timeline. Pilot response model: Uko? ops on-call + private responder; production adds dispatch-console handling, responder SLA timers and immutable audit records.

## 2g. Auth persistence (Postgres)

Auth supports two stores, selected by `AUTH_STORE` (default `postgres` when `DATABASE_URL` is set, otherwise `memory`):

- **postgres** — users and refresh tokens persist in `users` / `refresh_tokens` (tokens stored as SHA-256 hashes). Access tokens remain stateless JWTs; `/me` and refresh validate against the database, so sessions survive API restarts.
- **memory** — walking skeleton for the tablet bench when no database is available.

Verified locally: OTP login → user row + hashed refresh row in Postgres → API restart → same access token works on `/me` and the refresh token still rotates successfully. Zone/pricing and the remaining ride domains still use in-memory stores; they move to Postgres next.

## 2h. Persistence (Postgres)

- **Auth** — relational tables (`users`, `refresh_tokens`) when `AUTH_STORE=postgres`.
- **Rides, quotes, driver trips/availability, payments, safety contacts/incidents, scheduled rides/series** — normalized Postgres tables (`0004_normalized_domains.sql`), loaded on API startup and upserted on mutation. The older `domain_documents` JSONB table is retained only as the backfill source.
- With no `DATABASE_URL`, all stores fall back to memory (tablet bench without a database).
- Verified: create ride → complete → pay → restart API → same ride/payment; safety contacts/incidents, scheduled rides and series also survive. Normalised relational tables for these domains are the next migration step.

## 2i. Dispatch endpoints

Authenticated ops endpoints (bearer token; role-based access is the next step):

| Endpoint | Purpose |
|---|---|
| `GET /dispatch/overview` | metrics (active rides, completed today + gross, open incidents, drivers online, scheduled upcoming) + recent rides/incidents |
| `GET /dispatch/rides` | all rides with rider phone, route, fare, state |
| `POST /dispatch/rides/{id}/cancel` | ops cancel for a non-terminal ride |
| `GET /dispatch/incidents` | all SOS incidents |
| `POST /dispatch/incidents/{id}/resolve` | mark an incident resolved |
| `GET /dispatch/scheduled` | all scheduled rides + weekly series |

Console: `app/apps/dispatch` (static prototype, served on port 8085).

## 2j. Security and operations baseline

- **Headers:** helmet defaults on API responses (HSTS, `X-Content-Type-Options`, `X-Frame-Options`); CSP disabled only for Swagger UI.
- **Request tracing:** every response carries `X-Request-Id`; structured JSON logs record method/path/status/duration (no bodies, no PII).
- **OTP rate limits:** 3 requests/hour/phone, 10/hour/IP, 10 verify attempts/10 min/phone → `429 RATE_LIMITED`. In-memory for the single-instance pilot; move to Redis when replicated.
- **SMS:** `SmsService` adapter — `dev` (logs code, dev responses include `dev_code`) or `africastalking` with `AT_USERNAME`/`AT_API_KEY`/`AT_SENDER_ID`.
- **Dispatch access:** `DISPATCH_PHONES` comma-separated allow-list; non-listed users get `403 DISPATCH_FORBIDDEN`. Dispatch actions are written to `audit_log` (actor, action, entity, detail) and exposed via `GET /dispatch/audit`.

## 2k. M-Pesa Daraja integration

`MPESA_PROVIDER=mock` (default) keeps the simulated STK flow used on the test bench.
`MPESA_PROVIDER=daraja` switches to the real gateway:

- **OAuth** — client-credentials token cached until expiry (`/oauth/v1/generate`).
- **STK push** — `/mpesa/stkpush/v1/processrequest` with Base64 shortcode+passkey+EAT timestamp,
  amount, `254…` phone, callback URL and ride id as account reference.
- **Callback** — `POST /payments/mpesa/callback?secret=…` (secret optional) accepts the Daraja
  `Body.stkCallback` shape, matches the pending payment by checkout request id, and stores
  SUCCESS + M-Pesa receipt or FAILED + result description.
- **Failure** — Daraja errors surface as `502 MPESA_UNAVAILABLE`; callbacks never throw to the gateway.
- Verified against a local fake Daraja gateway: success (receipt `MPESA-FAKE123`), failure
  (`Request cancelled by user`) and callback-secret rejection.

## 2l. Push notifications

- **Device registry** — `POST /notifications/devices` (token, platform) upserts to `device_tokens`;
  `GET /notifications/devices` lists them.
- **Outbox** — `notifications` rows are queued and marked `SENT`/`FAILED` with provider id or error;
  `GET /notifications` returns a user’s latest notifications.
- **Adapters** — `PUSH_PROVIDER=dev` logs deliveries; `fcm` sends per-device Firebase HTTP v1
  messages when `FCM_PROJECT_ID`/`FCM_CLIENT_EMAIL`/`FCM_PRIVATE_KEY` are set (OAuth2 JWT
  assertion → `messages:send`), or falls back to the legacy endpoint with `FCM_SERVER_KEY`.
  Both paths work against local fake gateways for tests.
- **Triggers** — ride assigned (“Boda on the way”), driver arrived, trip started, trip complete,
  ride cancelled. SMS fallback and per-user preferences are next.
- Verified end-to-end against `tools/fake-fcm.mjs` (legacy) and `tools/fake-fcm-v1.mjs` (HTTP v1);
  the rider and driver apps register real FCM tokens via `POST /notifications/devices`.

## 2m. Ratings

- `POST /ratings` — `{ rideId, rating 1..5, comment? }`; only for the rider’s completed rides; one rating per ride (upsert).
- `GET /ratings/ride/{rideId}` — the rider’s rating for a ride.
- `GET /ratings/driver/{driverId}` — `{ count, average }`.
- Stored in `ride_ratings` with the assigned driver id; a “New rating” notification is queued for the driver.

## 2n. Observability and analytics

- `GET /health/ready` — database check with latency, row counts (rides/users/notifications); `status: ok|degraded`.
- `GET /metrics` — request counters (total, failures, status mix, average latency, uptime), database counts, and 24-hour event counts.
- `analytics_events` (id, user_id, event, props, created_at) — server emits `ride_requested`, `ride_assigned`, `trip_completed`, `sos_triggered`, `rating_submitted`, `payment_started`/`payment_confirmed`; clients can post additional events with `POST /analytics/events`.
- Dispatch console **System** tab renders readiness, HTTP metrics and event counts.
- Crash reporting and external alerting are still to be wired in production.

## 2o. Driver documents

- `POST /driver/documents` — multipart (`type` = licence|insurance|vehicle_photo, `documentNumber`, `expiresAt`, `file` ≤5 MB) → stored as `PENDING` with file metadata.
- `GET /driver/documents` — the driver’s documents and statuses.
- Dispatch: `GET /dispatch/documents`, `POST /dispatch/documents/{id}/approve`, `POST /dispatch/documents/{id}/reject` (reason); each review is written to `audit_log`.
- `DOCUMENTS_REQUIRED=true` → `POST /driver/online` returns `403 DOCUMENTS_PENDING` until licence and insurance are approved.
- Approved documents expiring within 14 days generate an in-app notification (checked on startup and every 12 h; seven-day re-notify window).
- Driver app captures photos via the system camera/gallery (`image_picker`) and uploads them as documents; demo uploads remain for bench testing.

## 2p. Diagnostics and alerts

- `POST /diagnostics/client-errors` — `{ app, version?, platform?, message, stack? }`; authenticated when a bearer token is present, else anonymous; stored in `client_errors`.
- `GET /diagnostics/client-errors` — recent reports (internal).
- `GET /health/alerts` — evaluates database health, SOS incidents open >15 min, failed notifications, documents pending >24 h and client errors; returns `{ status: ok|warning|critical, alerts[] }`.
- Rider app reports Flutter/zone errors automatically and exposes **Report a problem**; dispatch **System** tab renders alerts.
- `ALERT_WEBHOOK_URL` delivers a Slack-compatible payload when the alert set changes (deduplicated); external paging providers can consume the same webhook.

## 2q. Payment reconciliation

`GET /dispatch/reconciliation?date=YYYY-MM-DD` (default today, Nairobi):

- Completed rides for the date with fare, payment method and latest payment status.
- Totals: `completedRides`, `grossFare`, `paidCount/paidAmount`, `unpaidCount/unpaidAmount`, `byMethod`.
- Commission: 20% of paid gross + driver payout.
- `mismatches[]`: unpaid completed rides, amount mismatches and duplicate successful payments.
- Dispatch **Money** tab renders the same data.

## 2r. Scheduled ride activation

- The API activates due schedules on startup and every minute: within 10 minutes ahead → quote + live `SEARCHING` ride, schedule status `ACTIVATED` with `activatedRideId`, rider notification; more than 60 minutes overdue → `MISSED`.
- `POST /scheduling/run-due` forces the activation check (authenticated, for tests/ops).
- Statuses: `SCHEDULED → ACTIVATED | MISSED | CANCELLED`.
- Weekly series: the occurrence window rolls to 14 days ahead; due occurrences activate into live rides (occurrence `ACTIVATED` + `rideId`, rider notification), overdue occurrences become `MISSED`.

## 3. Token model

| Property | Access token | Refresh token |
|---|---|---|
| TTL | 15 minutes | 30 days |
| Signed with | `JWT_ACCESS_SECRET` | `JWT_REFRESH_SECRET` |
| Claims | `sub`, `typ=access`, `jti`, `iat`, `exp` | `sub`, `typ=refresh`, `jti`, `iat`, `exp` |
| Storage (client) | memory / secure storage | secure storage (Keychain/Keystore) |
| Rotation | — | every refresh issues a new pair; old token revoked |
| Revocation | short TTL | logout + DB `revoked_at` (FND-4) |

**Production requirements:** refresh tokens stored hashed in `refresh_tokens` with device binding; reuse of a rotated token triggers session revocation and a security event.

---

## 4. Client behaviour

1. Start → read refresh token from secure storage → call `/auth/token/refresh`; on success keep in memory.
2. On `401 ACCESS_INVALID` → refresh once, replay the original request; second failure → logout to phone screen.
3. Never persist access tokens to disk in plaintext.
4. All requests send `X-Request-Id` (UUID v4) and accept `X-Request-Id` in responses for support.
5. OTP flow handles resend with a countdown; dev builds may display the `dev_code` only in debug mode.

---

## 5. What Sprint 1 delivers around this contract

- FND-3: SMS provider adapter + rate limits + attempt cap + OTP persistence.
- FND-4: refresh tokens in Postgres, device binding, revocation, reuse detection.
- FND-5: `/me` backed by database + profile updates + driver documents.
- FND-6: zones/pricing from database.
- FND-7: error envelope, request IDs, structured logs, security headers.
- FND-11: e2e tests for the auth contract (happy path, invalid code, rotation, reuse, logout).

Endpoint changes after Sprint 1 are additive; any breaking change requires a contract note and version bump.
