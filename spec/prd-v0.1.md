# Uko? — Product Requirements Document (MVP v0.1)

**Status:** scope freeze v1.0 for sign-off · **Date:** 2026-11-21 · **Owner:** Uko? product lead
**Basis:** Phase 1 evidence (Bolt Rider CA.234.0 / Bolt Driver DA.157.0, 80.5% weighted reference coverage), Uko? plan v0.1, decisions D1–D8.

**Scope freeze (2026-11-21):** Boda-only pilot · no cancellation fee during the pilot · ~20% commission · private emergency response · brand “Uko?”. **Recurring schedules and calendar suggestions are in the MVP.** Scheduling window: 45 minutes–90 days (pilot default; confirm).

---

## 1. Vision

**Uko?** (Swahili: “Where are you?”) is a rider-tracking and scheduled-rides platform for Kenya. A passenger books a ride now or for later, a driver-partner sees exactly where they are needed and when, and an operator sees every ride, rider-partner and shift on one live map — with a shareable tracking link for the people waiting at home.

**MVP promise:** in one Nairobi zone, a rider can book on-demand or schedule a ride up to 90 days ahead, see the driver live, pay with M-Pesa or cash, and share the trip; a driver can accept both kinds of work, navigate and complete trips; a dispatcher can watch, assign and fix exceptions.

---

## 2. Goals and non-goals

### Goals (MVP)
1. Reliable on-demand booking with an upfront price and live ETA.
2. Scheduled rides that are **assigned before pickup**, prepaid, reminded and accountable.
3. A driver app that handles offers, scheduled jobs, navigation, earnings visibility and trip state.
4. A dispatch console that can see, assign, reassign, cancel and support rides.
5. M-Pesa and cash payments with a correct ledger and receipts.
6. Minimum viable safety: SOS, share trip, trusted contacts, pickup code, masked calls.
7. English + Swahili, low-bandwidth tolerant, Android-first.

### Non-goals (MVP)
Food, scooters, parcel, car rental; iOS; automated payouts; price-bidding UI; card payments; corporate billing; audio recording/STT; ride-check automation; multi-country; calendar write-back.

---

## 3. Personas

| Persona | Primary job | Success looks like |
|---|---|---|
| **Passenger** (rider) | Get to a place on time, at a known price, safely | Books in ≤3 taps; driver arrives when promised; can share live trip |
| **Driver-partner** | Earn predictably with clear rules | Sees offers/scheduled jobs, accepts confidently, gets paid correctly |
| **Dispatcher / ops** | Keep the zone moving and fix exceptions | Sees all rides, reassigns, calls, refunds from one screen |
| **Trusted contact** | Know a passenger arrived safely | Opens a link, sees live location and ETA, gets arrival notice |
| **Finance/admin** | Reconcile money | Every payment maps to a ride and a ledger entry |

---

## 4. MVP scope

### 4.1 In scope (release 0.1)
- Android rider app, Android driver app, web dispatch console, public track link.
- Identity: phone OTP (SMS, WhatsApp autofill if available), profile, one active device.
- On-demand booking: pickup/drop-off, **Boda category only at pilot**, upfront quote, ETA, matching, cancellation.
- Scheduled rides: single booking, **45 min–90 days ahead** (pilot default), server-validated time options, prepayment, driver pre-assignment/broadcast, reminders, cancellation and no-show rules.
- **Recurring schedules:** weekly pattern (selected weekdays), start/end, series management (pause/edit future/cancel occurrence or series), occurrences generated as individual bookings.
- **Calendar suggestions:** opt-in calendar read to suggest destinations and pre-fill scheduling from events; read-only, processed on device.
- Driver: online/offline, offer accept/decline, scheduled request list, navigation handoff, trip state machine, pickup code check, earnings summary.
- Tracking: MQTT primary + polling fallback; rider/driver/dispatch/track link see one state.
- Payments: M-Pesa STK (on-demand and scheduled prepay), cash (on-demand only), receipts, ledger; refunds by ops.
- Safety: SOS/emergency call registration, share trip link, trusted contacts, masked calls, pickup code.
- Notifications: push + SMS fallback, event taxonomy (ride, chat, call, incident, scheduled reminder).
- Ratings (both ways), support case entry, trip history.
- Dispatch: live map, rides board, schedule calendar, manual assign/reassign, driver roster, cancel/refund, incident queue, basic analytics.
- Localization EN/SW; EAT timestamps.

### 4.2 Out of scope (backlog)
Card/3DS payments, price bidding, corporate/work profiles, driver rental/lending, in-trip audio recording, ride-check automation, calendar write-back, passkeys, iOS, additional cities.

### 4.3 Release shape

| Release | Scope |
|---|---|
| **0.1 MVP** | Above in-scope list incl. **recurring schedules + calendar suggestions**, single zone, Android |
| **0.2** | Card/3DS via provider, automated payouts, ride-check, iOS |
| **0.3** | Price bidding/counter-offers, corporate accounts, audio recording/STT, second city |

---

## 5. Core user journeys

### J1 — Book now
1. Rider opens app → pickup auto-detected → enters destination.
2. App shows categories + upfront prices + ETA.
3. Rider selects category and payment method → confirms.
4. Backend quotes, creates ride, starts matching.
5. Rider sees searching → driver assigned (name, vehicle, plate, rating) → live ETA.
6. Driver arrives; pickup code verified; trip starts.
7. Trip completes; receipt; rating.

**Acceptance:** booking in ≤3 taps from home; quote locked at confirmation; every state visible on rider, driver and dispatch.

### J2 — Schedule a ride
1. Rider picks destination, toggles **Schedule**, chooses date/time.
2. Backend returns valid time options (server-driven), ETA and prerequisites; errors if area/distance/timeframe/payment unsupported.
3. Rider reviews booking (date, time, addresses, vehicle, payment) and confirms; prepayment authorised.
4. At T-24h: pre-assignment attempted; at T-45m: broadcast if unassigned; at T-15m: re-broadcast/escalate.
5. Rider receives reminders (T-24h, T-1h), “driver assigned”, “driver en route”.
6. Driver must be online by T-20m; booking activates into a live ride at the scheduled time.
7. Cancellations are **free during the pilot** (no cancellation fee). Rider no-show: driver waits 10 minutes, then cancels with **no fee**; reliability is tracked on both sides.

**Acceptance:** booking can be created, edited (date/address), cancelled with reason; driver sees it in scheduled list with fixed price and online-by time; if unassigned at T-15m, dispatcher is alerted.

### J2b — Set up a recurring schedule
1. Rider completes a scheduled booking, then chooses **Repeat**.
2. Selects weekdays (e.g. Mon–Fri), pickup time, start date and end condition (after N rides or by date).
3. Backend validates the pattern, computes occurrences and shows the next few dates + policy summary.
4. Rider confirms; series becomes **active** and occurrences are generated ahead of time as bookings.
5. Rider can pause/resume the series, edit the time/address for future occurrences, cancel one occurrence or the whole series.
6. Each occurrence follows the normal scheduled-ride rules (pre-assignment, reminders, activation); payment is collected at activation (M-Pesa), and a failed payment cancels that occurrence only and notifies the rider.

**Acceptance:** a Mon–Fri 07:00 series generates the next occurrences; pausing stops generation; cancelling one occurrence does not affect the rest; failed payment affects only that occurrence.

### J2c — Schedule from the calendar
1. Rider opts in to calendar access with a clear rationale.
2. App shows “From your calendar” suggestions on the home/schedule screen for upcoming events with a location.
3. Rider taps a suggestion → destination/pickup and date are pre-filled → normal schedule flow.
4. Rider can turn calendar access off at any time; suggestions disappear and no calendar data is stored server-side.

**Acceptance:** granting access shows suggestions; denying keeps the app fully usable; suggestions only use events with a usable location; revoking access removes suggestions.

### J3 — Driver receives work
- **On-demand:** offer push/poll → offer card with price, pickup, drop-off, ETA, rating → accept/decline within server-supplied timeout → accepted ride.
- **Scheduled:** scheduled requests list → accept in advance → fixed price + online-by → reminders → activate at time.
- Driver can go online/offline; app shows demand/queue state where available.

### J4 — Live tracking & sharing
Rider/dispatch track link sees driver location, ETA, trip status. Track link is a signed, expiring URL with no account access. Share stops at trip end.

### J5 — Pay
- **M-Pesa:** rider confirms → backend creates payment intent → STK push → rider enters PIN → callback → state verified → receipt. Failure/retry/cancel handled.
- **Cash:** driver marks cash collected at completion; ledger records driver cash debt.
- **Scheduled:** prepaid only (M-Pesa MVP).
- Refunds: ops can refund a completed/cancelled payment with reason; audit log.

### J6 — Safety
In-trip: SOS button → call emergency line and create incident; share trip; trusted contacts get SMS with link; masked call to driver; pickup code prevents wrong-car pickup.

### J7 — Dispatch exception
Dispatcher sees late/unassigned/cancelled rides → calls driver/rider (masked) → reassigns or cancels/refunds → adds case note. All actions audited.

---

## 6. Functional requirements

Requirements use IDs for traceability. Each has acceptance criteria in Given/When/Then form where useful.

### 6.1 Identity & accounts
- **FR-AUTH-01** Phone number + OTP login (SMS; WhatsApp autofill if the device supports it).
- **FR-AUTH-02** Access token + rotating refresh token; logout revokes session; one active session per device.
- **FR-AUTH-03** Profile: name, photo (optional), language, emergency contacts.
- **FR-AUTH-04** Account deletion request with retention policy.
- **FR-AUTH-05** Driver onboarding: documents, vehicle, approval status, document expiry.

*AC:* given a valid OTP, a new rider lands on the home map with an active token; expired/rotated refresh is rejected.

### 6.2 Booking & pricing
- **FR-BOOK-01** Pickup/drop-off selection, saved places, recent destinations.
- **FR-BOOK-02** Category list with upfront price, ETA, capacity.
- **FR-BOOK-03** Quote is fixed at confirmation; changes only via approved re-quote.
- **FR-BOOK-04** Cancellation with reason; **no cancellation fee during pilot**; the fee policy remains a server-owned field set to 0.
- **FR-BOOK-05** Duplicate-booking guard for the same rider.
- **FR-PRICE-01** Zone-based fare rules: base, distance, time, minimum fare, surge multiplier, promo.
- **FR-PRICE-02** Fare breakdown on quote and receipt.
- **FR-PRICE-03** Bid-ready contracts reserved (`Offer`, `CounterOffer`, `PriceBand`) but no UI in MVP.

*AC:* quote shown to rider equals receipt total unless an approved change (route/wait) is authorised.

### 6.3 Scheduling
- **FR-SCH-01** Schedule entry from fare confirmation (toggle), not a separate flow.
- **FR-SCH-02** Server returns valid pickup-time options, drop-off ETA, prerequisites and banners; client does not compute rules.
- **FR-SCH-03** Create scheduled booking with fixed price; prepayment required.
- **FR-SCH-04** Edit date/time/address before activation (server-validated).
- **FR-SCH-05** Cancel with reason; fee per window; refund handling.
- **FR-SCH-06** Assignment: pre-assign T-24h where possible; broadcast T-45m; re-broadcast T-15m; escalate.
- **FR-SCH-07** Driver online-by T-20m; auto-reassign if not.
- **FR-SCH-08** Reminders T-24h/T-1h to rider; assignment/en-route notifications.
- **FR-SCH-09** Manual operator assignment/reassignment.
- **FR-SCH-10** Booking activation creates the live ride exactly once (idempotent).
- **FR-SCH-11** Error taxonomy: area not supported, distance too long, timeframe invalid, payment method required, category unavailable.

*AC:* a booking created for tomorrow 07:00 is assigned by 06:00 and activates at 07:00; if no driver by T-15m, dispatch sees it in the exception queue.

### 6.3a Recurring schedules
- **FR-REC-01** Create a series from a scheduled booking: weekdays, pickup time, start date, end condition (N occurrences or end date), max horizon 8 weeks.
- **FR-REC-02** Server validates the pattern and returns the occurrence preview + policy summary.
- **FR-REC-03** Occurrences are generated as individual bookings by a daily job, at least 14 days ahead, idempotently (`series_id + occurrence_date` unique).
- **FR-REC-04** Series states: `ACTIVE`, `PAUSED`, `CANCELLED`, `FINISHED`. Pause/resume affects only future generation.
- **FR-REC-05** Edit future occurrences (time/address) from the series screen; already-active occurrences are unaffected.
- **FR-REC-06** Cancel a single occurrence or the whole series; no cancellation fee during pilot.
- **FR-REC-07** Payment: collect per occurrence at activation (M-Pesa); a failed payment cancels that occurrence only; after 2 consecutive failures the series is auto-paused and the rider is notified.
- **FR-REC-08** Each occurrence uses the standard scheduled-ride assignment, reminders and driver online-by rules; dispatcher sees series context in the booking detail.

*AC:* a series created for Mon–Fri 07:00 generates the next 14 days; pausing stops new occurrences; payment failure affects one occurrence and is visible to rider and dispatch.

### 6.3b Calendar suggestions
- **FR-CAL-01** Opt-in calendar permission with an onboarding rationale and a clear “not now” path.
- **FR-CAL-02** Read-only access to calendar events with a location/address; no write-back in MVP.
- **FR-CAL-03** Show up to 3 “From your calendar” suggestions for events in the next 7 days (event title, time, location).
- **FR-CAL-04** Tapping a suggestion pre-fills pickup/drop-off and date; rider completes the normal booking/schedule flow.
- **FR-CAL-05** Process calendar data on device; send only the selected destination/time to the backend, never raw calendar content; revoke at any time.
- **FR-CAL-06** No suggestion when the event has no usable location; rider can dismiss suggestions.

*AC:* with permission granted, a calendar event with an address produces a suggestion that pre-fills a scheduled ride; with permission denied the app works unchanged; revoked access removes suggestions and local cache.

### 6.4 Ride lifecycle
- **FR-RIDE-01** Canonical ride states: `REQUESTED`, `SEARCHING`, `ASSIGNED`, `DRIVER_ARRIVING`, `DRIVER_ARRIVED`, `CONFIRMATION_PENDING`, `IN_PROGRESS`, `COMPLETED` + exception states.
- **FR-RIDE-02** Every transition writes an immutable ride event (actor, time, location, reason).
- **FR-RIDE-03** Pickup confirmation code: rider 4-digit code shown; driver verifies before starting.
- **FR-RIDE-04** Wait timers: free waiting 5 min; no-show after 10 min (configurable by zone).
- **FR-RIDE-05** Route change/stop addition handled with re-quote (MVP: no mid-trip stops unless dispatcher).
- **FR-RIDE-06** Dispatcher can reassign an unstarted ride and cancel with refund.
- **FR-RIDE-07** Trip completion triggers fare finalisation, receipt, ratings, driver earnings entry.

### 6.5 Driver app
- **FR-DRV-01** Online/offline toggle with status reasons; server-visible status.
- **FR-DRV-02** Offer card with server-supplied response timer; accept/decline; auto-decline on timeout.
- **FR-DRV-03** Scheduled requests list: fixed price, pickup time, online-by, accept/cancel policy.
- **FR-DRV-04** Trip flow: navigate → arrived → verify pickup code → start → complete.
- **FR-DRV-05** Earnings summary: trip earnings, **20% commission**, cash collected, payout expectation (payouts manual in MVP, weekly cadence).
- **FR-DRV-06** Document status and expiry warnings.
- **FR-DRV-07** Safety menu: SOS, support, report issue.

### 6.6 Tracking & realtime
- **FR-TRK-01** MQTT primary channel (orders, offers, chat, trip events); polling fallback with server-provided interval.
- **FR-TRK-02** Location ingest: driver app sends location at active-trip cadence; server keeps last-known, discards old pings.
- **FR-TRK-03** ETA computed server-side; all clients show same ETA.
- **FR-TRK-04** Public track link: signed token, expiry = trip end + 30 min, no PII beyond first name/vehicle.
- **FR-TRK-05** State reconciliation after app death/background resumption.

### 6.7 Payments & ledger
- **FR-PAY-01** M-Pesa STK push via Daraja; state machine `CREATED → STK_SENT → PENDING → SUCCEEDED / FAILED / EXPIRED / REFUNDED`.
- **FR-PAY-02** Idempotent callbacks; payment verified server-side before receipt.
- **FR-PAY-03** Cash on-demand only; driver cash-debt ledger.
- **FR-PAY-04** Double-entry ledger for every payment, refund, commission, payout.
- **FR-PAY-05** Receipts with fare breakdown; email/SMS option.
- **FR-PAY-06** Ops refund with reason and audit trail.
- **FR-PAY-07** **20% commission** is booked to the ledger per completed ride; driver payout reports use net earnings.

### 6.8 Safety & support
- **FR-SAFE-01** In-trip SOS: registers emergency event, dials emergency line, notifies on-call ops.
- **FR-SAFE-02** Share trip from rider and driver apps.
- **FR-SAFE-03** Trusted contacts stored; SMS with track link on share.
- **FR-SAFE-04** Masked call between rider and driver (CPaaS).
- **FR-SAFE-05** Incident case created and visible to dispatch.
- **FR-SAFE-06** Support form with category and ride reference; ticket visible to ops.

### 6.9 Dispatch console
- **FR-OPS-01** Live map with all online drivers, active rides, scheduled bookings (filters by status/zone).
- **FR-OPS-02** Rides board: search by id/phone; detail with timeline, events, payment.
- **FR-OPS-03** Schedule calendar with assignment status and exception flags.
- **FR-OPS-04** Manual assign/reassign with conflict check.
- **FR-OPS-05** Driver roster with status/document expiry; suspend driver.
- **FR-OPS-06** Cancel/refund action with reason; audit.
- **FR-OPS-07** Incident queue and case notes.
- **FR-OPS-08** Zone/pricing admin (MVP: view + limited edit, feature-flagged).
- **FR-OPS-09** Basic analytics: rides, completion rate, on-time %, cancellations, GMV, commission.

### 6.10 Notifications
- **FR-NOTIF-01** Event taxonomy: ride updates, driver assigned/en route, scheduled reminders, chat, call, incident, payment.
- **FR-NOTIF-02** Separate push channels: default, ride updates, chat, calls, silent, incident.
- **FR-NOTIF-03** Push → deeplink → correct screen; payload carries `type`, `ride/booking id`, `deeplink`, `screen`, `message_type`.
- **FR-NOTIF-04** SMS fallback for critical events (OTP, driver assignment, scheduled reminder).
- **FR-NOTIF-05** Push delivery lifecycle tracked (sent/opened/action) for reliability analytics.

---

## 7. Non-functional requirements

| Area | Target |
|---|---|
| Availability | 99.9% monthly for booking/tracking APIs |
| Latency | API p95 ≤ 300 ms; quote p95 ≤ 500 ms; location update visible ≤ 5 s p95 |
| Reliability | schedule assignment ≥ 95% ≥ 1h before pickup; on-time pickup ≥ 90% pilot |
| Scale | 5,000 concurrent drivers, 20,000 rides/day (design headroom, pilot much smaller) |
| Security | TLS 1.3, certificate pinning on auth/payment hosts, OWASP MASVS-L2 target, device binding, RBAC for ops |
| Privacy | Kenya DPA 2019: consent, DPIA, retention (ride data 90 days hot, 7 years ledger), deletion workflow |
| Accessibility | TalkBack support on core flows; minimum 48dp targets; contrast AA |
| Localisation | EN/SW; all strings external; EAT timezone |
| Offline | queued rider/driver actions; reconnect without duplicate rides; idempotency keys |
| Battery | active-trip tracking < 8%/hour; no background location in rider app |
| App size | APK < 35 MB; cold start < 3 s on mid-range Android |

---

## 8. Compliance checklist

- [ ] IP/clean-room: requirements only; no Bolt code/assets/UI; original brand.
- [ ] Data Protection Act 2019: ODPC registration, DPIA, consent screens, retention/deletion, breach process.
- [ ] Payments: PCI scope stays with provider; M-Pesa merchant onboarding and callback security.
- [ ] Transport: driver licence, vehicle, insurance checks with expiry automation.
- [ ] Consumer: visible fares/cancellation terms; complaint handling.
- [ ] App stores: background location (driver), data safety, safety declarations.
- [ ] Insurance and incident SOP for pilot.

---

## 9. Parity scorecard (launch gate)

| Area | Weight | Launch target | Evidence |
|---|---|---|---|
| Booking & fare | 14% | 90% | Quote/receipt equality; ≤3 taps; cancellation policy display |
| Scheduled + recurring booking | 20% | 90% | Create/edit/cancel/assign/remind/activate/no-show; series create/pause/cancel one; 50 scheduled rides |
| Live tracking & ETA | 15% | 85% | All surfaces agree; ETA error ≤2 min p80 |
| Driver trip flow | 14% | 90% | Offer→arrive→confirm→start→complete on 10 devices |
| Payments & receipts | 10% | 80% | M-Pesa happy/failure/retry; receipt = ledger; cash recorded; per-occurrence charging |
| Safety & support | 10% | 75% | SOS + share ≤2 taps; incident case created |
| Dispatch & operations | 9% | 80% | See/assign/reassign/cancel/refund from one screen; series context |
| Calendar suggestions | 3% | 80% | Permission grant/deny, suggestion pre-fill, revoke; no server storage |
| Reliability & performance | 5% | NFR | 2-hour load test + pilot week metrics |

**Weighted score ≥ 85%** to launch; rows below target require a signed waiver with mitigation.

---

## 10. UAT scenarios (must pass)

1. Book now → driver assigned → pickup code verified → complete → receipt.
2. Schedule 3 days ahead → assigned by T-1h → activate on time → complete.
3. Schedule tomorrow 07:00 → driver cancels at 06:30 → reassigned → rider notified.
4. Rider edits scheduled booking time; price unchanged (fixed at booking).
5. Rider cancels a scheduled ride and a series occurrence: **no fee** in pilot; both sides see cancellation.
6. Rider no-show: 10-min wait, driver cancels, **no fee**; reliability tracked.
7. M-Pesa payment fails; rider retries; success; receipt reconciles.
8. Scheduled occurrence payment fails at activation; only that occurrence cancels; series continues.
9. Series: create Mon–Fri 07:00, pause, resume, edit future time, cancel one occurrence, cancel series.
10. Calendar: grant permission → suggestion appears → pre-fill schedule → revoke permission → suggestions disappear.
11. Cash trip completes; driver cash debt incremented.
12. SOS triggered in-trip; incident appears in dispatch; share link active.
13. Driver loses signal mid-trip; state recovers on reconnect; no duplicate completion.
14. Dispatcher reassigns an unstarted scheduled ride; both riders/drivers see updated state.
15. Track link works without login and expires after trip.

---

## 11. Metrics

**North-star:** completed rides per active week in the pilot zone.
**Guardrails:** ride completion rate ≥ 90%, cancellation rate ≤ 10%, on-time pickup ≥ 90%, payment success ≥ 97%, crash-free sessions ≥ 99.5%, SOS response < 60 s.

---

## 12. Decisions and open questions

### Settled for MVP
- D1: rider = passenger + rider-partner; both scheduling modes.
- D2: Kenya, one Nairobi zone; **Boda only** at pilot.
- D3: passengers book ahead; dispatchers schedule shifts/assignments.
- D4: M-Pesa STK + cash at MVP; card in 0.2.
- D5: Android-first; iOS in 0.2.
- D9: pickup confirmation code in MVP; audio recording/ride-check in 0.2.
- D10: price bidding reserved in data model, not in UI until 0.3.
- D16: **Recurring schedules are in the MVP** — weekly pattern, max 8-week horizon, occurrences generated 14 days ahead, billed per occurrence at activation.
- D17: **Calendar suggestions are in the MVP** — read-only, on-device processing, opt-in, suggestions only for events with a location; no calendar write-back.

### Frozen decisions (v1.0)
- **D11:** Boda-only category mix at pilot; Go/Comfort/XL deferred until after pilot.
- **D12:** No cancellation fee during the pilot; the policy field remains configurable and is set to 0.
- **D13:** ~20% commission per completed ride; weekly payout cadence (manual payouts in MVP).
- **D14:** Private emergency response (Uko? ops on-call + private responder), not 999 integration.
- **D15:** Brand “Uko?” confirmed.

### Assumptions to confirm
- Scheduling window: **45 min lead time, up to 90 days ahead** (pilot default). Change only if a shorter pilot window is preferred.
- Recurring schedules: **max 8-week series horizon** and **per-occurrence payment at activation** (pilot default).
- Calendar suggestions: suggestions limited to events with a usable address in the **next 7 days**.

---

## 13. Release plan and gates

| Phase | Deliverable | Gate |
|---|---|---|
| Requirements & design | This PRD + prototype + architecture delta | Signed scope |
| Core MVP build | Apps + backend + dispatch | Alpha demo |
| Scheduling & ops | Scheduling engine + recurring series + calendar suggestions + console | 50 scheduled rides; series + calendar UAT |
| Payments/safety/hardening | Production M-Pesa + safety | UAT + security review |
| Pilot | Single-zone pilot | Parity score ≥85% or waivers |

*End of PRD v0.1. Next document: architecture-delta-v0.1.md.*
