# Uko? Rider app (Flutter)

Not bootstrapped yet — run `make mobile-bootstrap` after installing Flutter 3.x.

Planned feature folders (Riverpod + go_router):
- `lib/features/auth` — phone entry, OTP, tokens, logout
- `lib/features/home` — map, recent/saved places, calendar suggestions
- `lib/features/booking` — destination, categories, quote, payment method
- `lib/features/schedule` — date/time picker, review, series management
- `lib/features/trip` — searching, driver assigned, live trip, pickup code, share link
- `lib/features/payments` — M-Pesa, cash, receipts
- `lib/features/safety` — SOS, contacts, support
- `lib/core` — theme, api client, auth storage, location, MQTT client

Sprint 1 target: auth + app shell + Boda quote stub wired to the API.

**Primary QA device:** Lenovo TB-J616X (Android 12/API 31, arm64, 3.7 GB RAM, ≈800 dp wide).
See [`../../spec/test-device-lenovo-tb-j616x.md`](../../spec/test-device-lenovo-tb-j616x.md). Use `adb reverse tcp:3000 tcp:3000` for local API access.
