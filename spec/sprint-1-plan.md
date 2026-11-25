# Uko? — Sprint 1 plan (Foundation)

**Sprint:** 1 of Phase 3 · **Proposed dates:** Mon 24 Nov – Fri 5 Dec 2026 (2 weeks)
**Goal:** a working walking skeleton — a rider can request and verify an OTP, receive rotating tokens, call `/me`; the database schema, zone and Boda pricing are seeded; the API is documented, containerised and CI-green.
**Companion docs:** `prd-v0.1.md`, `architecture-delta-v0.1.md`, `api-foundation-v0.1.md`.

---

## 1. Sprint goal and demo

**Sprint goal:** prove the foundation end-to-end on a developer machine — auth, schema, zone/pricing, gateway conventions, CI — so the booking and scheduling sprints can build without rework.

**Demo (10 minutes, end of sprint):**
1. `docker compose up -d` → Postgres/PostGIS, Redis, EMQX healthy.
2. `make db-migrate && make db-seed` → one Nairobi zone with Boda pricing.
3. `make api-dev` → Swagger at `/docs`, health at `/v1/health`.
4. From the Flutter rider shell: request OTP → verify → land on home screen; token stored securely.
5. `curl` refresh-token rotation: old refresh rejected; logout revokes.
6. CI pipeline green on the sprint PR.

---

## 2. Team and assumptions

| Role | People | Sprint 1 focus |
|---|---|---|
| Product owner | 0.5 shared | Acceptance, policy answers, demo |
| Tech lead / backend | 1 | Architecture, auth, database, review |
| Backend engineer | 1 | Users/profiles/documents, zones, gateway conventions |
| Flutter engineers | 2 | Rider + driver app shells, auth screens, secure token storage |
| Designer | 0.5 | Auth/onboarding visuals, component tokens |
| QA | 0.5 | Test plan, auth e2e, device matrix smoke |
| DevOps | 0.5 | Docker compose, CI, secrets, local onboarding |

**Environment note (this machine):** Node 22+, npm and the API scaffold are ready; **Flutter, Docker and Postgres are not installed**. FND-0 covers installing them on team machines before day 2. The API was built and smoke-tested without Docker using the in-memory walking skeleton.

**Primary test device:** Lenovo TB-J616X tablet — Android 12 (API 31), arm64-v8a, 3.7 GB RAM, 1200×2000 @ 240 dpi, connected over adb. Full profile and test constraints: [`test-device-lenovo-tb-j616x.md`](test-device-lenovo-tb-j616x.md). `adb reverse tcp:3000 tcp:3000` is configured so device builds can reach the local API at `http://localhost:3000/v1`.

---

## 3. Definition of done

- Code reviewed and merged; CI green (`npm run build` + tests).
- API endpoint has OpenAPI docs + validation + tests (happy path + one failure).
- No secrets in git; `.env.example` updated.
- Migration is forward-only, applied on a clean database, documented.
- Acceptance criteria demonstrated in the sprint review.
- Board ticket closed with a link to the PR and demo evidence.

---

## 4. Backlog

Estimates are ideal person-days (pd). IDs are used on the board.

| ID | Story | Owner | Est. | Depends on | Acceptance criteria |
|---|---|---|---|---|---|
| **FND-0** | Dev environment bootstrap: install Flutter 3.x, Docker, psql; run compose + migrate + seed; document in `app/README.md` | DevOps | 1 | — | Two engineers can go from clean machine to green health check and seeded zone in <30 min; **Lenovo tablet visible in `adb devices` and `adb reverse tcp:3000` configured** |
| **FND-1** | CI pipeline: install, build, typecheck, test; PR checkout; branch protection | DevOps | 1 | FND-0 | CI runs on PR, fails on type error; average <5 min |
| **FND-2** | Postgres/PostGIS schema: users, rider/driver profiles, vehicles, documents, devices, refresh tokens, zones, pricing rules | Backend | 2 | FND-0 | `make db-migrate` on clean DB creates all tables, enums, indexes, triggers; `\d` review passes |
| **FND-3** | OTP auth with SMS provider adapter (dev stub + Africa's Talking adapter behind an interface), rate limits, attempt caps | Backend | 3 | FND-2 | OTP send/verify works through API with dev stub; production adapter selected by env; rate limit returns 429; attempts capped |
| **FND-4** | Token lifecycle: access + rotating refresh persisted in Postgres, device binding, logout/revocation, expired-token handling | Backend | 2 | FND-2 | Refresh rotation works; reused refresh rejected; logout revokes; tokens survive API restart (DB-backed) |
| **FND-5** | User and profile APIs: `GET/PATCH /me`, rider profile, driver profile + document upload metadata, document expiry job stub | Backend | 3 | FND-2, FND-4 | Authenticated user can read/update profile; driver documents stored with expiry; job flags expiring docs |
| **FND-6** | Zones + Boda pricing reads from Postgres; pricing rule validation; seed replaces in-memory stub | Backend | 1.5 | FND-2 | `GET /zones`/`/zones/active` served from DB; seed idempotent; values match frozen pilot pricing |
| **FND-7** | API gateway conventions: versioning, error envelope, request IDs, validation, structured logs, CORS/security headers, rate limiter | Backend | 2 | FND-1 | Errors share one envelope with stable codes; request ID returned and logged; 4xx/5xx covered by tests |
| **FND-8** | Flutter rider shell: project bootstrap, theme, API client, secure token storage, phone/OTP screens, home placeholder | Flutter | 3 | FND-0, FND-3 | Rider can log in against local API; token stored in secure storage; relaunch stays logged in; logout works; **debug APK installs and runs on the Lenovo TB-J616X** |
| **FND-9** | Flutter driver shell: bootstrap, theme, API client, login, online/offline placeholder, document status placeholder | Flutter | 3 | FND-8 | Driver can log in; shell shows online toggle (local state) and document placeholder; **runs on the Lenovo TB-J616X in portrait and landscape (no layout break)** |
| **FND-10** | Security baseline: secret handling, TLS assumptions, OWASP MASVS checklist draft, PII fields classified | Tech lead + DevOps | 1 | FND-7 | Checklist reviewed; no PII in logs; secrets via env/secret manager plan |
| **FND-11** | Test suite: unit tests for auth/token logic, e2e for OTP flow against Postgres, CI coverage gate | QA + backend | 2 | FND-3, FND-4 | Tests run in CI; auth e2e covers happy path + rotation + reuse; coverage gate for auth module; **device smoke run on Lenovo tablet with logcat evidence** |

**Total:** ~25.5 person-days; fits 2 weeks for the team above.

### Stretch (only if ahead)
- FND-S1: Docker image for the API + compose `api` service.
- FND-S2: Basic dispatch shell (Next.js) with health/auth check.
- FND-S3: SMS provider sandbox credentials wired.

---

## 5. Already done in preparation (walking skeleton)

The repo `app/` is scaffolded and validated:

- NestJS modular-monolith skeleton with `health`, `auth`, `users`, `zones` modules.
- OTP request/verify, access + rotating refresh, logout, `/me` implemented against **in-memory stores** (deliberate stub).
- SQL foundation migration + Nairobi Boda seed (PostGIS).
- Docker Compose for Postgres/PostGIS, Redis, EMQX.
- Swagger at `/docs`, CI workflow, Makefile, `.env.example`.
- Build passes; smoke test passes: OTP → verify → `/me` → refresh rotation → old refresh rejected → logout revokes.

Sprint 1 tasks FND-2/FND-3/FND-4 replace the in-memory stores with Postgres repositories and the real SMS adapter.

---

## 6. Risks and dependencies

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Flutter/Docker not installed on team machines | High | Medium | FND-0 on day 1; pairing session; documented setup |
| SMS provider (Africa's Talking) account not ready | Medium | Medium | Dev stub + adapter interface; provider chosen before FND-3 ends |
| PostGIS/Postgres version drift | Low | Medium | Compose pins `postgis/postgis:16-3.4`; CI uses the same image |
| Auth security review delays | Low | High | Security checklist FND-10 early; external review before pilot |
| iOS/Flutter plugin constraints discovered late | Low | Low | Android-first; record plugin decisions in ADRs |
| Device matrix too narrow (one Android 12 tablet; no API 33+ phone) | Medium | Medium | Add API 33+/34 phone and emulator to QA before pilot; track in test-device doc |
| Tablet has no active SIM/inactive telephony | Medium | Low | Use dev OTP for automated tests; confirm SIM/WhatsApp OTP before manual SMS tests |

---

## 7. Ceremonies and board

- **Daily:** 15-min stand-up; blockers first.
- **Mid-sprint check:** demo the skeleton to the product owner (day 5).
- **Review + retro:** end of sprint; demo script above.
- **Board columns:** Backlog → Ready → In progress → In review → Done.
- **Ticket labels:** `foundation`, `backend`, `mobile`, `devops`, `security`, `qa`.

---

## 8. Exit criteria (sprint gate)

- [ ] CI green on `main`; branch protection enabled.
- [ ] Auth e2e passes against Postgres; refresh rotation/reuse/logout verified.
- [ ] Database schema + seed reviewed; `make db-migrate` idempotent on clean DB.
- [ ] Rider and driver shells log in against the API and persist sessions.
- [ ] Zone/Boda pricing served from DB.
- [ ] Error envelope + request IDs in place; Swagger current.
- [ ] Demo completed; FND-11 evidence attached to the sprint review.

If all exit criteria pass, Sprint 2 (quotes, on-demand booking, tracking skeleton) starts without carry-over.

---

## 9. Prep checklist before day 1

- [ ] Install Flutter 3.x + Android SDK on the two mobile dev machines.
- [ ] Install Docker + Compose; pull `postgis/postgis:16-3.4`, `redis:7-alpine`, `emqx/emqx:5.8`.
- [ ] Confirm Lenovo TB-J616X is connected (`adb devices`), `adb reverse tcp:3000 tcp:3000` set, USB debugging on, animations off (already 0).
- [ ] Create `.env` from `.env.example`; set local secrets.
- [ ] Sign off the four assumptions in the PRD (scheduling window, recurring horizon/payment, calendar window).
- [ ] Create the board from the backlog above and assign owners.
- [ ] Agree SMS provider and create sandbox credentials.
- [ ] `git init` + initial commit (not run yet — confirm repo destination/host first).

*End of Sprint 1 plan. Next: Sprint 2 plan once foundation exit criteria pass.*
