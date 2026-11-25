# Uko? — Pilot kit (v0.1)

Everything the pilot team needs to run a controlled Boda pilot in one Nairobi zone.
Companion to the [Pilot Readiness Review](Uko-Pilot-Readiness-Review-v0.4.pdf) and the
[Pilot Operations Runbook](Pilot-Operations-Runbook-v0.1.md).

## 1. Roles

| Role | Responsibility |
|---|---|
| Pilot lead (product) | Go/no-go, daily review, rider/driver comms |
| Ops lead | Dispatch console, SOS desk, vetting, reconciliation |
| Engineering on-call | API/apps/DB incidents, deploy + rollback |
| Safety responder | Private emergency response on SOS; on-call rota |
| Support | Rider/driver questions, refunds, lost items |

One person can hold ops + support in a small pilot, but the **responder must always be a
separate named person** with a phone that is answered.

## 2. Daily cadence

**Morning (15 min)**

```bash
node tools/pilot-check.mjs                 # readiness, alerts, money, documents
node tools/pilot-smoke.mjs                 # 15 API checks
```

- Open dispatch: **Overview**, **System** alerts, **Documents** pending, **Money** mismatches.
- Confirm responder is on shift; post “pilot open” with the support number.

**Evening (20 min)**

- Clear/annotate all Money mismatches; record cash reconciliation.
- Review SOS incidents and near misses; log response times.
- Check driver supply vs tomorrow’s scheduled/recurring rides.
- Post “pilot closed” summary: rides, completion, cancellations, CSAT, incidents, cash total.

## 3. Rider onboarding script (invite + call)

Send: “Karibu Uko? pilot! Book a Boda from the app, price is fixed before you confirm, no
cancellation fee. SOS in the app reaches our private responder — we do not call 999 for you
unless you ask. Support: <number>.”

Call/WhatsApp walkthrough: install app → OTP → **Where to?** → saved place or type →
**Get price** → **Confirm Boda** → share pickup code → pay cash or M-Pesa → rate the trip.

## 4. Driver onboarding checklist

- [ ] Phone, national ID, driving licence, insurance, vehicle photo captured in the app
- [ ] Documents approved in dispatch (licence + insurance required)
- [ ] Bike inspected: brakes, tyres, lights, helmet, rider helmet available
- [ ] App walkthrough: online/offline, accept/decline, arrive/start/complete, pickup code,
      earnings/shift, documents, report a problem
- [ ] Cash policy and daily payout expectations explained (20% commission)
- [ ] SOS policy: stay with the rider, call the responder, do not share rider data
- [ ] Signed pilot agreement + data protection acknowledgement
- [ ] Test ride completed with a staff rider

## 5. SOS drill (before rider onboarding)

1. Ops lead triggers a test SOS from a test rider account.
2. Responder must acknowledge within **60 seconds** by phone to ops.
3. Ops marks the incident resolved and records response time.
4. Repeat once per week during the pilot; log every drill.

## 6. Incident policy

- SOS → dispatch opens **Incidents**, calls the rider, stays on the line, responder
  handles emergency services if needed; ops writes the timeline in the incident log.
- Never promise the rider that 999 was called; tell them what is happening.
- Refunds: fare-level refunds can be approved by ops lead; anything larger escalates to
  the pilot lead. No cancellation fee in the pilot.

## 7. Go/no-go checklist (pilot day)

- [ ] Credentials configured (SMS, FCM, Maps, Daraja) and verified end-to-end
- [ ] Managed Postgres + backups + TLS live; `health/ready` green
- [ ] Responder agreement signed and rota published
- [ ] Driver documents approved; 8–12 drivers ready
- [ ] 15–25 riders invited with support number
- [ ] Signed release builds installed on pilot devices
- [ ] Privacy policy, terms, DPA signed
- [ ] Dispatch console allow-list updated
- [ ] Alert webhook connected to the ops channel
- [ ] Daily cadence + KPIs agreed

## 8. KPI tracker (daily)

| Date | Rides | Completed | Cancelled | Assignment min | GMV | Cash | M-Pesa | Commission | Incidents | CSAT |
|---|---|---|---|---|---|---|---|---|---|---|
|  |  |  |  |  |  |  |  |  |  |  |
|  |  |  |  |  |  |  |  |  |  |  |

Targets: assignment <3 min · completion ≥90% · cancellation ≤10% · zero unresolved
incidents · CSAT ≥4.5/5 · reconciliation clean daily.

## 9. Escalation

| Severity | Example | Action |
|---|---|---|
| SEV1 | Safety, data loss, API down | Pilot lead + engineering on-call now; pause bookings |
| SEV2 | Payments/dispatch unavailable | Switch to cash + paper; fix same day |
| SEV3 | Ride dispute/app glitch | Support logs; review next stand-up |

## 10. Scripts

- `node tools/pilot-check.mjs` — daily readiness/alert/money/document check
- `node tools/pilot-smoke.mjs` — 15 API flow checks
- `node tools/pilot-dry-run.mjs` — full API end-to-end dry run (document gate on)
- `cd tools/pg && node backup.mjs` / `node restore.mjs <file> uko_restore` — data drills
