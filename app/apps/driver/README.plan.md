# Uko? Driver app (Flutter)

Not bootstrapped yet — run `make mobile-bootstrap` after installing Flutter 3.x.

Planned feature folders:
- `lib/features/auth` — phone/OTP, documents, approval status
- `lib/features/home` — online/offline, queue state, earnings summary
- `lib/features/offers` — offer card, accept/decline timer, scheduled requests
- `lib/features/trip` — navigate, arrived, pickup code verify, start/complete
- `lib/features/shift` — availability/online schedule
- `lib/core` — api client, MQTT, location foreground service, map/navigation adapter

Sprint 1 target: auth + app shell; Sprint 2 target: offers + trip flow.

**Primary QA device:** Lenovo TB-J616X (Android 12/API 31, arm64, 3.7 GB RAM). See [`../../spec/test-device-lenovo-tb-j616x.md`](../../spec/test-device-lenovo-tb-j616x.md). Test background-location and foreground-service behaviour here on API 31.
