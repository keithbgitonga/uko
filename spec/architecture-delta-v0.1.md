# Uko? — Architecture Delta (MVP v0.1)

**Status:** scope freeze v1.0 · **Date:** 2026-11-21 · **Companion:** `prd-v0.1.md`
**Purpose:** update the architecture in `Uko-Product-Plan-v0.1.pdf` with what Phase 1 evidence changed.

---

## 1. What changed versus the plan

| Plan assumption | Evidence finding | Delta |
|---|---|---|
| Scheduling rules can be client-side | Bolt asks the server for valid times/ETA/prerequisites | **Scheduling service owns all policy**; client renders server decisions |
| Scheduled ride = ride with future timestamp | Separate API family + driver scheduled surface | **`Booking` resource separate from `Ride`** |
| One pricing model | Fixed, surge **and** bid/counter-offer | Data model reserves `Offer`/`PriceBand`/`CounterOffer`; UI deferred |
| Card/cash/M-Pesa integration | 3-D Secure challenge endpoints, instrument lifecycle | Payment = **state machine + provider adapter**, not a single charge call |
| Pickup = driver taps start | Rider-confirmation/pickup-code gate exists | Add `CONFIRMATION_PENDING` + pickup-code verification |
| MQTT maybe | MQTT is realtime in both apps, polling fallback | **MQTT primary + polling fallback** with server-provided interval |
| Driver permissions light | Background location, overlay, usage access, recording | Driver app needs a policy decision before build |

---

## 2. Principles

1. **Server-owned policy** — prices, time windows, cancellation rules, offer timeouts, poll intervals and feature flags are server decisions. The client renders them.
2. **Durable ride events** — every state change is an append-only event; pings are ephemeral.
3. **Separate booking and ride** — a scheduled booking activates into a ride exactly once.
4. **Bid-ready, not bid-first** — schema supports offers/bids but MVP uses fixed price + surge.
5. **Provider adapters** — M-Pesa, SMS, maps and calls behind interfaces so providers can change.
6. **Failure-first realtime** — MQTT primary, polling fallback, idempotent clients, reconciliation on resume.
7. **One identity, two apps** — shared auth/session and deep-link contract; separate permission models.

**Pilot policy defaults (frozen):** Boda-only category; no cancellation fee (policy field = 0, still configurable); 20% commission; weekly manual payouts; private emergency response; scheduling 45 min–90 days ahead. **Recurring schedules** use weekly patterns, max 8-week horizon, occurrences generated 14 days ahead, billed per occurrence at activation. **Calendar suggestions** are read-only, on-device and opt-in.

---

## 3. Logical architecture

```
                       ┌──────────────────────────── clients ────────────────────────────┐
                       │ Rider app (Flutter)  Driver app (Flutter)  Dispatch (Next.js)   │
                       │                              public Track link                  │
                       └───────────────┬──────────────────────┬─────────────────────────┘
                                       │ HTTPS/JSON           │ MQTT (WSS) / polling
                               ┌───────▼──────────────────────▼───────┐
                               │ API Gateway: auth, rate limit, WS hub│
                               └───────┬──────────────────────────────┘
        ┌──────────────────────────────┼───────────────────────────────────────────────┐
        │                    modular monolith (NestJS)                                  │
        │  Identity/KYC │ Quote/Pricing │ Booking │ Scheduling │ Matching/Dispatch      │
        │  Ride/State   │ Tracking      │ Payments/Ledger │ Notifications │ Safety/Support│
        └──────────────────────────────┬───────────────────────────────────────────────┘
                                       │
     ┌───────────────┬───────────────┬─▼──────────────┬───────────────┬─────────────────┐
     │ PostgreSQL    │ Redis         │ MQTT broker    │ Object store  │ Analytics/events│
     │ + PostGIS     │ geo/locks/cache│ (EMQX)        │ docs/receipts │ (warehouse)     │
     └───────────────┴───────────────┴────────────────┴───────────────┴─────────────────┘
              integrations: M-Pesa Daraja · card provider (0.2) · Google Maps · FCM · SMS · CPaaS
```

---

## 4. Service responsibilities

### 4.1 Identity & KYC
- Phone OTP (SMS, WhatsApp autofill), tokens (access + rotating refresh), device binding, logout/deletion.
- Driver documents, vehicle, approval state, expiry jobs.
- RBAC for ops users; audit log for every privileged action.

### 4.2 Quote & pricing
- **Boda-only pilot:** one category, one fare rule set.
- Zone-based fare rules (base, distance, time, minimum, surge, promos).
- Returns quote id + breakdown; quote frozen for booking.
- Reserves bid contracts: `offer`, `counter_offer`, `price_band` (no UI).
- Feature flag: `pricing.bidding.enabled` (false in MVP).

### 4.3 Booking (scheduled rides)
- Owns `Booking` aggregate and its lifecycle.
- Calls Scheduling for time options and validation; calls Payments for prepayment.
- Emits `BookingActivated` → Ride service creates ride exactly once (idempotency key = booking id).
- Parent of `ScheduleSeries`; occurrence bookings carry `series_id` + `occurrence_index`.

### 4.4 Scheduling engine
- `POST /v1/scheduled-rides/time-options`: validates pickup/drop-off distance/area and returns valid slots, ETA, prerequisites, banners, errors.
- Persists booking; runs T-minus jobs (BullMQ delayed jobs + outbox):
  - T-24h: pre-assign candidate driver; T-45m: broadcast; T-15m: re-broadcast + escalate; T-20m: online-by check.
- Conflict checks: no overlapping bookings/shifts for a driver; travel buffer by zone (15–30 min).
- Reminders, activation, cancellation, no-show and refund orchestration.
- Manual assignment/reassignment API for dispatch.
- **Recurring series:** owns `ScheduleSeries` lifecycle (`ACTIVE/PAUSED/CANCELLED/FINISHED`); daily expansion job generates occurrence bookings 14 days ahead (idempotent by `series_id + occurrence_date`); pause/resume affects future generation only; per-occurrence payment collected at activation; auto-pauses series after 2 consecutive payment failures.

### 4.5 Matching & dispatch
- Driver eligibility/geo search (PostGIS/Redis GEO), offer fan-out with server timeout.
- Offer state machine; scheduled bookings use pre-assignment lists.
- Dispatch commands: assign, reassign, cancel, refund, suspend driver (all audited).

### 4.6 Ride & state
- Canonical ride state machine; immutable `ride_events`.
- Pickup-code generation/verification; wait timers; fare finalisation; receipt trigger.
- Reconciliation jobs for stale rides (app killed, network loss).

### 4.7 Tracking
- Location ingest (MQTT), last-known position, ETA computation (maps provider), geofence triggers.
- Publishes trip state to riders/drivers/dispatch/track link; polling fallback endpoint.
- Public track token: signed, expiring, scoped to a ride.

### 4.8 Payments & ledger
- Provider adapter: M-Pesa (Daraja), cash, card (0.2).
- Payment intent state machine; idempotent callbacks; double-entry ledger.
- **20% commission**, cash debt, refunds, manual weekly payouts (0.1), automated payouts (0.2).
- Receipts and reconciliation reports.

### 4.9 Notifications
- Event taxonomy and templates; push (FCM) + SMS fallback; separate Android channels.
- Deeplink registry (typed), delivery lifecycle queue; retries.

### 4.10 Safety & support
- SOS/emergency call registration, incident cases, share-trip tokens, masked-call session creation.
- Support cases with ride reference; dispatch incident queue.
- V0.2: ride-check anomaly detection and audio recording.

### 4.11 Calendar suggestions (client-side)
- Rider app reads the device calendar only after explicit opt-in (Android `READ_CALENDAR`); no server-side calendar storage.
- On-device mapping: event title/start/time/location → suggestion item; only events with a usable address are eligible.
- Tapping a suggestion pre-fills the normal quote/schedule flow; only the selected pickup/drop-off/time is sent to the backend.
- Suggestions limited to the next 7 days (max 3 shown); revoking permission clears the local cache and hides suggestions.
- No calendar write-back in MVP (V0.2 candidate).

---

## 5. API contract (v1)

Base: `https://api.uko.example/v1`; auth `Authorization: Bearer <access>`; idempotency header for writes; EAT timestamps ISO-8601.

### 5.1 Auth
| Method | Path | Purpose |
|---|---|---|
| POST | `/auth/otp/request` | send OTP (channel: sms/whatsapp) |
| POST | `/auth/otp/verify` | verify OTP → tokens |
| POST | `/auth/token/refresh` | rotate refresh token |
| POST | `/auth/logout` | revoke session |
| GET/PATCH | `/me` | profile |

### 5.2 Quotes and rides
| Method | Path | Purpose |
|---|---|---|
| POST | `/quotes` | quote for pickup/drop-off/category |
| POST | `/rides` | create on-demand ride (`quote_id`, payment method) |
| GET | `/rides/{id}` | ride + state + ETA |
| POST | `/rides/{id}/cancel` | cancel with reason |
| POST | `/rides/{id}/rate` | rating |
| GET | `/rides/{id}/receipt` | receipt |
| GET | `/rides/{id}/share-link` | public track token |
| POST | `/rides/{id}/confirmation-code/verify` | driver verifies pickup code |

### 5.3 Scheduled rides
| Method | Path | Purpose |
|---|---|---|
| POST | `/scheduled-rides/time-options` | server-validated slots, ETA, prerequisites, banners |
| POST | `/scheduled-rides` | create booking (prepaid) |
| GET | `/scheduled-rides/{id}` | booking detail |
| PATCH | `/scheduled-rides/{id}` | edit date/address (pre-activation) |
| POST | `/scheduled-rides/{id}/cancel` | cancel with reason/refund policy |
| GET | `/scheduled-rides` | upcoming bookings |
| POST | `/scheduled-rides/{id}/repeat` | create a recurring series from a booking |
| GET | `/schedule-series` | list rider's series |
| GET | `/schedule-series/{id}` | series detail + upcoming occurrences |
| PATCH | `/schedule-series/{id}` | pause/resume or edit future pattern/time/address |
| POST | `/schedule-series/{id}/cancel` | cancel series (future occurrences) |
| POST | `/schedule-series/{id}/occurrences/{date}/cancel` | cancel one occurrence |

**`POST /scheduled-rides/time-options` example**
```json
{
  "pickup": {"lat": -1.2921, "lng": 36.8219, "address": "Kenyatta Ave"},
  "dropoff": {"lat": -1.2648, "lng": 36.8031, "address": "Westlands"},
  "category": "boda",
  "payment_method_id": "pm_123",
  "requested_time": "2026-11-24T07:00:00+03:00"
}
```
```json
{
  "valid": true,
  "options": [
    {"time": "2026-11-24T07:00:00+03:00", "dropoff_eta": "2026-11-24T07:35:00+03:00"},
    {"time": "2026-11-24T07:15:00+03:00", "dropoff_eta": "2026-11-24T07:50:00+03:00"}
  ],
  "prerequisites": ["prepayment_required"],
  "banners": [{"id":"b1","title":"Airport? Add your flight for a smarter pickup","dismissible":true}],
  "errors": []
}
```
Errors: `AREA_NOT_SUPPORTED`, `DISTANCE_TOO_LONG`, `TIME_FRAME_INVALID`, `PAYMENT_METHOD_REQUIRED`, `CATEGORY_UNAVAILABLE`.

### 5.4 Driver
| Method | Path | Purpose |
|---|---|---|
| POST | `/driver/status` | online/offline, vehicle |
| GET | `/driver/offers/next` | long-poll next offer (server timeout) |
| POST | `/driver/offers/{id}/accept` | accept |
| POST | `/driver/offers/{id}/decline` | decline |
| GET | `/driver/scheduled-rides` | scheduled requests (accepted/available) |
| POST | `/driver/scheduled-rides/{id}/accept` | accept scheduled job |
| POST | `/driver/trips/{id}/arrive` | arrived at pickup |
| POST | `/driver/trips/{id}/start` | start trip (after code verification) |
| POST | `/driver/trips/{id}/complete` | complete + cash collected flag |
| GET | `/driver/poll` | polling fallback (`include_orders`, `app_state`) |
| GET | `/driver/earnings/summary` | daily/weekly summary |

**`GET /driver/poll` response (shape)**
```json
{
  "driver_state": "online",
  "interval_sec": 5,
  "take_new_orders_during_order": true,
  "order_summaries": [],
  "messages": [],
  "pending_busy_state": false,
  "is_bidding_enabled": false
}
```
The **server supplies `interval_sec`** — no client constant.

### 5.5 Payments
| Method | Path | Purpose |
|---|---|---|
| POST | `/payments/mpesa/stk` | initiate STK for ride/booking |
| GET | `/payments/{id}` | payment state |
| POST | `/webhooks/mpesa/callback` | Daraja callback (signed/validated) |
| GET/POST | `/payment-methods` | saved methods (0.2) |
| POST | `/ops/payments/{id}/refund` | ops refund |

### 5.6 Safety, ops and misc
| Method | Path | Purpose |
|---|---|---|
| POST | `/safety/sos` | create emergency event + call registration |
| POST | `/safety/incidents` | incident report |
| GET | `/ops/live` | live map snapshot |
| GET | `/ops/bookings` | booking board/filter |
| POST | `/ops/bookings/{id}/assign` | manual assign/reassign |
| POST | `/ops/rides/{id}/cancel` | ops cancel/refund |
| GET | `/ops/drivers` | roster + document status |
| GET | `/ops/analytics/summary` | KPIs |

---

## 6. Data model

Key tables (PostgreSQL; all have `id uuid`, `created_at`, `updated_at`; `zone_id`, `status` where relevant):

| Entity | Key fields | Notes |
|---|---|---|
| `users` | phone, name, language, status | one identity for rider/driver |
| `rider_profiles` | user_id, home/work places, emergency contacts | |
| `driver_profiles` | user_id, rating, acceptance, status, vehicle_id | |
| `vehicles` | make, model, plate, category (boda at pilot), capacity | |
| `documents` | driver_id, type, number, expires_at, status | expiry jobs |
| `zones` | name, polygon (PostGIS), pricing_rules | per-zone policy |
| `pricing_rules` | zone_id, category (boda), base, per_km, per_min, minimum, surge_rules, **cancellation_fee=0 (pilot)**, commission_pct (20), active | |
| `quotes` | rider_id, pickup, dropoff, category, price_breakdown, expires_at | frozen |
| `schedule_series` | rider_id, weekdays, pickup_time, start_date, end_date/occurrence_count, pickup, dropoff, category, payment_method, state, generated_until | **recurring parent** |
| `bookings` | rider_id, quote_id, series_id?, occurrence_index?, pickup, dropoff, scheduled_at, price, payment_id, state | **separate resource**; series occurrences reference parent |
| `booking_events` | booking_id, type, actor, payload, at | immutable |
| `rides` | rider_id, driver_id, booking_id?, pickup, dropoff, state, price, payment_id | booking_id unique when activated |
| `ride_events` | ride_id, type, actor, location, payload, at | immutable, append-only |
| `offers` | ride_id/booking_id, driver_id, price, expires_at, state, counter_offer | bid fields optional |
| `counter_offers` | offer_id, driver_id, amount, price_band_id, expires_at | reserved |
| `price_bands` | zone_id, category, min, max | reserved |
| `assignments` | ride/booking, driver, type (auto/manual), state | |
| `location_pings` | driver_id, ride_id, lat, lng, accuracy, at | ephemeral, partitioned |
| `payment_intents` | ride/booking, provider, amount, state, provider_ref, attempts | |
| `ledger_entries` | txn_id, account, debit, credit, currency, ref | double-entry |
| `payouts` | driver_id, period, amount, state | manual in MVP |
| `ratings` | ride_id, by, rating, tags, comment | |
| `incidents` | ride_id, type, status, notes, ops_user | |
| `notification_jobs` | user_id, type, payload, channel, state, attempts | |
| `devices` | user_id, fcm_token, platform, last_seen | |
| `refresh_tokens` | user_id, token_hash, device_id, expires_at, rotated_at | |
| `audit_log` | actor, action, entity, before/after | ops actions |

**Indexes:** GiST on pickup/dropoff, B-tree on `(driver_id, state)`, `(rider_id, created_at)`, unique `(series_id, occurrence_date)`; partition `location_pings` and `ride_events` by month.

---

## 7. State machines

### 7.1 Booking
```
DRAFT → SCHEDULED → ASSIGNMENT_PENDING → DRIVER_ASSIGNED → REMINDERS_SENT
      → ACTIVATED → COMPLETED
exceptions: UNASSIGNED_AT_DEADLINE, DRIVER_WENT_OFFLINE, RIDER_CANCELLED,
            NO_DRIVER_AVAILABLE, PAYMENT_FAILED, ACTIVATION_FAILED
```
Rules: activation is idempotent (one ride per booking); prepayment must be `SUCCEEDED` before `SCHEDULED`; reassignment allowed until `ACTIVATED`.

### 7.2 Ride
```
REQUESTED → SEARCHING → ASSIGNED → DRIVER_ARRIVING → DRIVER_ARRIVED
          → CONFIRMATION_PENDING → IN_PROGRESS → COMPLETED
exceptions: CANCELLED_BY_RIDER, CANCELLED_BY_DRIVER, NO_SHOW, EXPIRED,
            REASSIGNED, PAYMENT_FAILED
```
Rules: `IN_PROGRESS` requires pickup-code verification; every transition writes `ride_events`; completion finalises fare and receipt.

### 7.3 Offer
```
CREATED → SENT → ACCEPTED | DECLINED | EXPIRED | COUNTERED (reserved)
```
Offer timeout is a **server timestamp** (`expires_at`), not a client interval.

### 7.4 Payment intent (M-Pesa)
```
CREATED → STK_SENT → PENDING → SUCCEEDED | FAILED | EXPIRED | REFUNDED
```
Callback must be idempotent; state transitions only forward; receipt emitted on `SUCCEEDED`.

### 7.5 Schedule series
```
DRAFT → ACTIVE ⇄ PAUSED → CANCELLED
ACTIVE → FINISHED (end date / occurrence count reached)
```
Rules: only `ACTIVE` generates occurrences; pause/resume affects future generation; cancellation stops future occurrences but leaves already-active bookings to be cancelled individually; payment failure cancels one occurrence and auto-pauses after two consecutive failures.

---

## 8. Realtime & tracking design

- **MQTT topics:** `rides/{rideId}` (state), `drivers/{driverId}/offers`, `drivers/{driverId}/status`, `chats/{chatId}`, `ops/zone/{zoneId}`.
- **Auth:** short-lived MQTT token derived from session; broker enforces topic ACL.
- **Polling fallback:** `/driver/poll` and `/rides/{id}` with server-supplied `interval_sec`; client backs off on errors; server may return `is_bidding_enabled`, queue state, messages.
- **Location cadence:** active trip 3–5 s; online idle 10–15 s; background driver location gated by foreground service; rider app foreground-only.
- **Reconciliation:** on app resume, client calls state endpoint; server compares `version`; stale client state is replaced. Trip completion is server-authoritative.

---

## 9. M-Pesa payment flow (MVP)

1. Rider confirms; backend validates quote/booking and creates `payment_intent(CREATED)`.
2. Backend calls Daraja STK push; stores `provider_ref`; state `STK_SENT`.
3. Daraja callback hits `/webhooks/mpesa/callback`; backend validates signature/payload and idempotency key.
4. Backend queries Daraja transaction status (defence in depth); updates state to `SUCCEEDED`/`FAILED`.
5. On success: ride/booking allowed to proceed; receipt ledger entries created; notification sent.
6. On timeout: state `EXPIRED`; client can retry with a new intent; old one closed.
7. Refund: ops action creates reversal entries and a Daraja B2C/refund request (or manual reconciliation in pilot).

**Invariants:** no ride starts on an unverified payment for scheduled/prepaid; every ledger txn balances; callbacks are idempotent by provider ref + status.

---

## 10. Dispatch console (MVP)

- Auth: ops users with roles `dispatcher`, `admin`.
- Live map: drivers, active rides, scheduled bookings; filters by status/zone.
- Rides/booking detail: timeline, events, payment, rider/driver contact (masked), actions (assign, reassign, cancel, refund, note).
- Schedule calendar: day/week view with assignment status and exception flags (`unassigned at T-15m`, driver offline).
- Exception queue: late activation, unassigned, SOS, payment failure, no-show dispute.
- Driver roster: status, documents, suspension.
- Basic analytics: trips, completion, on-time, cancellations, GMV, commission.
- All actions audited; destructive actions require confirmation + reason.

---

## 11. Security, privacy, operations

- **Auth:** short-lived access tokens (15 min), rotating refresh (30 days), device binding, revoke on logout.
- **Transport:** TLS 1.3; certificate pinning on auth/payment hosts; HSTS.
- **PII:** encrypt phone numbers at rest; tokenise where possible; access to rider/driver PII restricted to support roles; audit log.
- **DPA 2019:** consent for location/notifications/calendar; calendar data is processed on-device and never stored server-side in MVP; retention: ride/trip data 90 days hot + archive, ledger 7 years, logs 30 days; deletion workflow includes calendar cache purge.
- **Ops:** least privilege, MFA for admin, IP allowlist for console (optional), audit every action.
- **Observability:** OpenTelemetry traces, structured logs, Sentry, Grafana dashboards; alerts on payment failure rate, unassigned bookings, MQTT disconnects.
- **SLOs:** booking API 99.9%, p95 300 ms; tracking freshness p95 5 s; payment callback processing < 5 s.
- **Environments:** dev, staging (M-Pesa sandbox), pilot; feature flags for zones/pricing/bidding.

---

## 12. Architecture decision records (ADR summary)

| ADR | Decision | Why |
|---|---|---|
| ADR-01 | Server-driven scheduling | Evidence: Bolt server returns time screen/ETA/errors; policy changes without app release |
| ADR-02 | `Booking` separate from `Ride` | Evidence: dedicated scheduled API family; clean audit and activation semantics |
| ADR-03 | Bid-ready schema, no bid UI | Evidence: price bands/counter-offers exist; MVP keeps fixed + surge |
| ADR-04 | M-Pesa as challenge/callback state machine | Mirrors 3-D Secure contract; avoids lost payments |
| ADR-05 | Pickup-code confirmation gate | Evidence: rider-confirmation flow; reduces no-shows/wrong pickups |
| ADR-06 | MQTT primary + polling fallback | Evidence: HiveMQ MQTT + polling endpoints with server interval |
| ADR-07 | Modular monolith first | Delivery speed; split tracking/scheduling only when load demands |
| ADR-08 | Google Maps for rider, Mapbox candidate for driver | Evidence: Bolt splits vendors; decide after cost/navigation evaluation |
| ADR-09 | Shared identity, separate app permission models | Evidence: shared signer/cross-app login; rider no background location, driver needs it |
| ADR-10 | Immutable ride events | Required for disputes, safety, analytics, on-time metrics |
| ADR-11 | Recurring series as parent of occurrence bookings | Keeps each occurrence a normal booking while enabling pause/edit/cancel series |
| ADR-12 | Calendar processed on-device, read-only | Privacy by design; avoids holding calendar PII server-side |

---

## 13. Build sequence and dependencies

1. **Foundation:** auth/identity, users/drivers/vehicles, zone + pricing seed, API gateway, CI.
2. **Quote + on-demand booking:** quotes, matching, ride state, MQTT tracking, cash payment; **calendar suggestions** in rider home (client-side).
3. **Driver app core:** offers, trip flow, navigation handoff, earnings summary.
4. **M-Pesa:** intent state machine, callbacks, ledger, receipts (per-ride and per-occurrence).
5. **Scheduling:** time-options API, booking aggregate, assignment jobs, reminders, activation; **recurring series** (pattern validation, expansion job, pause/resume, per-occurrence payment).
6. **Dispatch console:** live map, boards, assign/reassign, exceptions.
7. **Safety:** SOS, share link, masked calls, pickup code (may start earlier with ride flow).
8. **Hardening:** load tests, security review, app-store assets, pilot runbook.

Dependencies: scheduling depends on quote/booking + driver identity + payments; recurring series depends on scheduling + payments + idempotent booking generation; calendar suggestions depend only on rider app permissions and quote flow; dispatch depends on ride/booking read models; safety tracking depends on ride state.

---

## 14. Open technical questions

1. Mapbox vs Google Maps for driver navigation (cost/licence/offline).
2. WhatsApp OTP availability and provider choice in Kenya.
3. CPaaS for masked calls (Sinch/Twilio/Africa's Talking).
4. Private emergency response provider selection and on-call rota (999 not used).
5. Data residency expectations for ODPC/DPA.
6. Whether to run dispatch console as separate deployable or inside monolith initially.
7. Recurring-series defaults: max 8-week horizon and per-occurrence payment at activation (confirm).
8. Calendar write-back / smarter event parsing (V0.2, not MVP).

*End of architecture delta v0.1. Next: prototype and technical design review, then build sprint 1.*
