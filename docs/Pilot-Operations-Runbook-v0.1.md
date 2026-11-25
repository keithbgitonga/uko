# Uko? — Pilot operations runbook (v0.1)

Companion to the [Pilot Readiness Review](Uko-Pilot-Readiness-Review-v0.4.pdf) and the [Pilot Kit](Pilot-Kit-v0.1.md). Covers the
daily checks, data safety, incident handling and access management for the internal pilot.

## 1. Daily checks (5 minutes)

```bash
# API + database health
curl -s http://localhost:3100/v1/health

# Daily pilot check (readiness, alerts, money, documents)
node tools/pilot-check.mjs

# End-to-end smoke (auth, quote, ride, cancel, scheduled, safety, dispatch)
node tools/pilot-smoke.mjs

# Full pilot dry run (documents, ride lifecycle, payment, rating, scheduling, SOS)
# Requires DOCUMENTS_REQUIRED=true and a freshly restarted API (OTP limits reset).
node tools/pilot-dry-run.mjs
```

Then open the dispatch console (`node app/apps/dispatch/serve.mjs` → http://localhost:8085):
check active rides, open incidents, the **Audit** tab and the **System** alerts
(`GET /health/alerts`). Any failed smoke check, critical alert, or open SOS older than
15 minutes is an escalation. If `ALERT_WEBHOOK_URL` is set, new alert sets are pushed to
the ops Slack channel automatically; acknowledge in-channel and in the System tab.

## 2. Data safety

Logical backups are JSON snapshots of every table (counts + SHA-256 manifest).

```bash
cd tools/pg
node backup.mjs                       # writes backups/uko-backup-<stamp>.json + manifest
node restore.mjs <backup.json> uko_restore   # restore into a fresh DB, verifies row counts
```

**Drill result (23 Nov 2026):** backup of 21 tables / 99 rows; a sentinel safety contact was
added after the backup; restore into a fresh `uko_restore` database inserted 94 rows
(schema migrations excluded) and verified **PASSED** — the sentinel was correctly absent and
live counts (rides 5, payments 3) matched the restored database.

Production target: managed Postgres with daily automated backups + a monthly restore drill.
Never restore into the live database without taking a fresh backup first.

## 3. Incident response (SOS)

1. Rider presses SOS → incident `OPEN`, ops on-call notified (simulated acknowledgement
   flips it to `ACKED`; production needs the real responder integration).
2. Dispatch console → **Incidents** → review rider, note, location → call rider.
3. Acknowledge privately via the responder while staying on the line; do **not** tell the
   rider to call 999 unless they ask or the situation is life-threatening.
4. If false alarm: rider cancels in-app or ops marks `RESOLVED`.
5. Log the incident, outcome and response time; review at the daily pilot stand-up.

## 4. Driver vetting

- In the dispatch console open **Documents**; review licence/insurance uploads and approve or reject with a reason.
- Each decision is audited. Set `DOCUMENTS_REQUIRED=true` for the pilot so a driver cannot go online until licence and insurance are approved.
- Keep rejected documents on file with the reason; ask the driver to re-upload from the app.

## 5. Dispatch access

- Only phones in `DISPATCH_PHONES` (comma-separated E.164) can use `/dispatch/*`; everyone
  else receives `403 DISPATCH_FORBIDDEN`.
- Every cancel-ride / resolve-incident is written to `audit_log` with actor, action, entity
  and detail; review the console **Audit** tab.
- Removing an operator: update `DISPATCH_PHONES` and restart the API.

## 6. OTP and SMS

- Dev mode (`SMS_PROVIDER=dev`) logs codes and returns `dev_code` only outside production.
- Pilot mode: `SMS_PROVIDER=africastalking` + `AT_USERNAME`, `AT_API_KEY`, `AT_SENDER_ID`.
- Limits: 3 OTP requests/hour/phone, 10/hour/IP, 10 verify attempts/10 min; `429 RATE_LIMITED`
  means wait — do not bypass by restarting the API during the pilot unless agreed.

## 7. Money

- Commission 20%; driver sees gross/commission/net for today and a shift summary.
- No cancellation fee in the pilot.
- Cash-first until Daraja reconciliation passes. Each day open the dispatch **Money** tab
  (`GET /dispatch/reconciliation`) and clear every mismatch: unpaid completed rides,
  amount mismatches, duplicate payments. Match M-Pesa receipts by checkout id.

## 8. Escalation ladder

| Severity | Example | Action |
|---|---|---|
| SEV1 | Safety incident, data loss, API down | Ops lead + engineering lead immediately; pause pilot bookings if needed |
| SEV2 | Payments failing, dispatch unavailable | Ops lead; switch to cash and paper board; fix within the day |
| SEV3 | Single ride dispute, app glitch | Log, reply in the support channel, review next stand-up |

## 9. Post-pilot review inputs

Smoke results, audit log, incident log, dispatch metrics (assignment time, completion,
cancellations), payment reconciliation and rider/driver feedback.
