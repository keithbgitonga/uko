# driver

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.


## Verified on the Lenovo test bench (2026-11-22)

```bash
export PATH="$HOME/opt/flutter/bin:$PATH"
export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
flutter build apk --debug --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n ke.uko.driver/.MainActivity
```

Package: `ke.uko.driver`. Debug build points at `http://localhost:3000/v1` (tablet port 3000 → workstation 3100 via `adb reverse`).

Verified flow: dev-OTP login → Go online → incoming offer (Brian O., Westlands → Kileleshwa, KES 150) → Accept → trip page with pickup code → I've arrived → Start trip → Complete trip → completion dialog → back online.


## UI pass (2026-11-23)

- Map-led home with online/offline pill, earnings chip and bottom sheet.
- Offer card with 45-second countdown ring, rider/route/fare details.
- Trip screen with route map, 4-step timeline, pickup code and fare.


## Earnings (2026-11-23)

- `GET /driver/earnings` returns today/lifetime trips, gross, 20% commission and net (Nairobi day boundary).
- Home shows a **KES net today** chip and a “Today’s earnings” card with trip count, net and commission.


## Shift summary (2026-11-23)

- `GET /driver/shift` returns online state, on-shift since, online minutes today, trip count and net earnings (Nairobi day boundary); shifts are recorded on online/offline transitions and persisted.
- Home shows an “On shift · Xh Ym online today · N trips” strip above earnings.


## Notifications (2026-11-23)

- Bell icon opens an inbox backed by `GET /notifications`.
- Trip events create driver notifications: accepted, at pickup (with code), started, completed (net after commission).
- Pull-to-refresh and relative timestamps; verified on the test bench.


## Documents (2026-11-23)

- Account menu → **Documents**: pick Licence / Insurance / Vehicle, then **Take photo** or **Gallery** to upload a real image; demo buttons remain for bench testing.
- Status chips show `PENDING` / `APPROVED` / `REJECTED`.
- With `DOCUMENTS_REQUIRED=true`, both documents must be approved before the driver can go online.
