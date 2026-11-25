# rider

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


## Verified build on the Lenovo test bench (2026-11-22)

```bash
export PATH="$HOME/opt/flutter/bin:$PATH"
export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
flutter build apk --debug --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n ke.uko.rider/.MainActivity
```

The debug build points at `http://localhost:3000/v1`; the test bench maps device port 3000 to workstation port 3100 (`adb reverse tcp:3000 tcp:3100`).
Auth flow verified on-device: OTP request → dev code auto-fill → verify → home.


## Booking flow (2026-11-22)

Screens: home → Book a Boda → pickup/drop-off → Get price → quote card with fare breakdown and M-Pesa/Cash → Confirm Boda → Finding your Boda → assigned driver card → Cancel ride.

Backend walking skeleton endpoints: `POST /v1/quotes`, `POST /v1/rides`, `GET /v1/rides/{id}`, `POST /v1/rides/{id}/cancel`; mock driver assignment after ~5 s.


## Scheduling + recurring (2026-11-22)

- Schedule a ride: pickup/drop-off, date picker (45 min–90 days), time picker → fixed fare
- Repeat weekly: weekday chips, end date (max 8 weeks), series created with 14-day occurrence horizon
- Manage screen: upcoming scheduled rides + weekly series with Pause/Resume
- Series times are displayed in EAT; backend stores `timeOfDay`/dates in Africa/Nairobi


## Calendar suggestions (2026-11-22)

- Home → Calendar suggestions → opt-in explainer; `READ_CALENDAR` requested only when the rider taps Allow.
- Native `MethodChannel("ke.uko.rider/calendar")` reads `CalendarContract.Instances` for the next 7 days, keeps events with a location, dedupes and returns candidates; Dart shows up to 3.
- Tapping a suggestion opens Schedule with drop-off + date/time prefilled.
- On-device only: no calendar data is sent to the API; only the chosen destination/time is submitted when the rider books.
- Kotlin bridge: `android/app/src/main/kotlin/ke/uko/rider/MainActivity.kt`.


## Payments (2026-11-22)

- Trip completed screen shows the fare and payment method.
- **Pay with M-Pesa**: calls `POST /payments/mpesa/stk`, shows "Check your phone…", polls payment status and renders the receipt on success (walking skeleton auto-succeeds after ~4 s).
- **Cash**: `POST /payments/cash/confirm` records the payment immediately.
- Backend: `src/payments` (payment states PENDING/SUCCESS/FAILED, receipt, `/simulate` for tests). Real Daraja STK/callback wiring pending sandbox credentials.


## Safety & SOS (2026-11-22)

- Home → **Safety & SOS**: private-response explainer, emergency contacts (add/list/remove), SOS button.
- SOS confirm dialog → `POST /safety/sos`; incident states `OPEN → ACKED → CANCELLED/RESOLVED` with a 2 s status poll.
- In-trip **SOS** button on the driver card opens the same flow with the active `rideId`.
- Backend: `src/safety`; pilot response model is Uko? ops on-call + private responder (no 999 dialling).


## UI pass (2026-11-23)

- Home is map-led: full-bleed stylised map (`RideMap` CustomPainter), floating Uko? header + zone/account chips, bottom sheet with “Where to?”, quick actions (Book a Boda / Schedule / Calendar / Safety), trips placeholder.
- Trip screen shows a route map with pickup/drop-off pins, driver marker and ETA chip above the driver card/pickup code.
- Real Google Maps SDK integration is planned for beta; the current painter keeps the flow testable without an API key.


## Trips & receipts (2026-11-23)

- Home → **Trips & receipts**: all rides with status, date/time, route and fare.
- Completed rides show a `Paid · receipt` badge (payment fetched per ride) and open a receipt bottom sheet with route, fare, payment method/status, receipt number and ride id.
- Uses `GET /rides` plus `GET /payments/ride/{rideId}`; history currently lives in the API’s in-memory stores until those domains move to Postgres.


## Booking sheet (2026-11-23)

- Home **Where to?** opens a draggable bottom sheet, with a destination field, saved places (Home/Work/Airport/Mall) and recent destinations derived from completed trips.
- Selecting a place opens **Book a Boda** with the drop-off prefilled; the booking page has a route-map header and quote card.


## Ratings (2026-11-23)

- Completed-trip receipt sheet includes a five-star **Rate your driver** control.
- `POST /ratings` stores the rating per ride (upsert) and notifies the driver.
