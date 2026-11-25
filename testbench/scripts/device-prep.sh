#!/usr/bin/env bash
# Prepares the Lenovo test bench for a Uko? test run.
set -euo pipefail

SERIAL="${1:-$(adb devices | awk 'NR==2{print $1}')}"
if [ -z "${SERIAL}" ]; then
  echo "No adb device found. Plug in the tablet and accept USB debugging." >&2
  exit 1
fi

echo "Preparing device: ${SERIAL}"
adb -s "${SERIAL}" wait-for-device
adb -s "${SERIAL}" shell svc power stayon true
adb -s "${SERIAL}" shell settings put system screen_off_timeout 1800000
adb -s "${SERIAL}" shell settings put global window_animation_scale 0
adb -s "${SERIAL}" shell settings put global transition_animation_scale 0
adb -s "${SERIAL}" shell settings put global animator_duration_scale 0
adb -s "${SERIAL}" reverse tcp:3000 tcp:3000
adb -s "${SERIAL}" logcat -c

echo "--- device ---"
adb -s "${SERIAL}" shell getprop ro.product.model
adb -s "${SERIAL}" shell getprop ro.build.version.release
echo "--- reverse ---"
adb -s "${SERIAL}" reverse --list
echo "--- battery ---"
adb -s "${SERIAL}" shell dumpsys battery | grep -E 'level|status' | head -2
echo "Ready."
