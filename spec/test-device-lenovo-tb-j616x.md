# Uko? — Primary test device profile

**Device:** Lenovo TB-J616X (Lenovo Tab M8-class tablet)
**Status:** connected via USB/adb on the build workstation · no Uko? package installed yet
**Role:** primary Android QA device for the MVP; the app must run well on this class of hardware before pilot.

---

## 1. Hardware and OS profile (observed via adb)

| Field | Value |
|---|---|
| Serial (workstation) | `HA1JE58L` |
| Model / device | Lenovo TB-J616X |
| Android | **12** (API 31) |
| Build fingerprint | `Lenovo/TB-J616X/TB-J616X:12/SP1A.210812.016/TB-J616X_S240253_241016_ROW:user/release-keys` |
| Security patch | 2024-10-05 (old — see risks) |
| CPU ABI | `arm64-v8a` (+ `armeabi-v7a`) |
| RAM | 3.7 GB total (low-end class) |
| Screen | 1200 × 2000 px, 240 dpi → **≈800 × 1333 dp** (tablet, portrait native) |
| Google Play services | 26.45.31 |
| Capabilities | telephony/GSM, IMS, GPS + network location, Bluetooth/BLE, cameras, Vulkan/GLES |
| Developer settings | window/transition/animator scales all **0** (animations already off); stay-awake-while-plugged-in = 3 |

---

## 2. Test implications

### Android 12 / API 31 behaviour
- **Notification runtime permission (`POST_NOTIFICATIONS`)** does not exist until API 33 — the tablet will not show the permission prompt; test that path on an API 33+ device/emulator before pilot.
- **Background location**: on API 31 the driver app must request `ACCESS_BACKGROUND_LOCATION` via settings and run a foreground service; test the "Allow all the time" flow explicitly.
- **Foreground-service start restrictions**: test resume/relaunch behaviour when the app is backgrounded.
- **Approximate vs precise location** toggle: test booking and ETA with approximate location enabled.
- Target SDK 36 behaviours (e.g. foreground-service types) still apply; this device is a useful compatibility target but **not** a complete matrix.

### Tablet form factor
- ≈800 dp width means the rider and driver apps must render on a wide screen: use responsive max-width containers, avoid stretched maps, and check edge-to-edge/large-window behaviour.
- Dispatch console is web (tablet browser can be used for smoke testing only).
- Check portrait and landscape; the apps are phone-first, so tablet support = "does not break", not a tablet-optimised layout.

### Telephony / OTP
- Telephony features are present, but a tablet's SIM may be absent/inactive. For automated tests use **development OTP (`dev_code`)**; for manual SMS tests confirm an active SIM or use WhatsApp OTP.
- Masked-call testing needs a SIM/CPaaS test number; otherwise use the VoIP test path.

### Performance and battery
- 3.7 GB RAM is a good low-end proxy: watch cold start, map rendering and battery during active-trip tracking.
- Disable battery optimisation for the driver debug build (`Settings → Apps → Uko? Driver → Battery → Unrestricted`) and test the OEM battery manager behaviour.

### Security
- Security patch is **October 2024** — acceptable for internal testing; do not treat it as a pilot production device. Pilot devices need a supported patch level.

---

## 3. Workstation setup notes

USB debugging is enabled and adb recognises the device (`adb devices` → `HA1JE58L device`).

Connect the tablet to the local API without Wi-Fi/LAN changes:
```bash
adb reverse tcp:3000 tcp:3000
# app base URL on device: http://localhost:3000/v1
adb reverse --list
```

Install dev builds:
```bash
flutter build apk --debug           # from apps/rider or apps/driver
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb logcat | grep -iE 'uko|flutter|AndroidRuntime'
```

Capture evidence for QA:
```bash
adb exec-out screencap -p > shot.png
adb shell screenrecord --time-limit 60 /sdcard/uko-qa.mp4
```

---

## 4. Sprint 1 acceptance use

| Task | Device check |
|---|---|
| FND-8 rider shell | Install debug APK; login with dev OTP; session survives relaunch; logout works |
| FND-9 driver shell | Install debug APK; login; online/offline placeholder; document placeholder |
| FND-11 auth e2e | Run the auth flow against local API via `adb reverse`; capture logcat on failure |
| FND-7 conventions | Confirm request IDs/errors render in the debug logs on device |

---

## 4a. Verified on this device (2026-11-22)

- Toolchain installed on the workstation: Flutter **3.50.1**, Android SDK 36 + build-tools 36.0.0.
- Built and installed the first rider app: `ke.uko.rider`, debug arm64 APK (74 MB).
- Verified end-to-end: launch → phone prefilled → Send code → dev OTP auto-fill → Verify → home screen showing the signed-in phone number.
- API access: `adb reverse tcp:3000 tcp:3100` (workstation port 3000 is in use by another app; Uko? API runs on 3100).
- Evidence: `../testbench/evidence/rider-launch-2.png`, `rider-otp.png`, `rider-home.png`.
- No crash observed in logcat; app runs in landscape on the tablet.

## 5. Gaps to close before pilot

1. Add at least one **API 33+** phone (e.g. Samsung/Tecno/Infinix) and one **Android 13/14** low-end phone to complement this Android 12 tablet.
2. Verify active SIM / telephony on the tablet (SMS OTP, masked calls) or document the fallback.
3. Add an emulator AVD (Pixel-class, API 34) to CI/QA for reproducible screenshot tests.
4. Record device-specific battery notes for the driver foreground-service test.
