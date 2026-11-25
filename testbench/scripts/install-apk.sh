#!/usr/bin/env bash
# Installs a debug APK on the test bench.
set -euo pipefail
APK="${1:?usage: install-apk.sh path/to/app.apk [serial]}"
SERIAL="${2:-$(adb devices | awk 'NR==2{print $1}')}"
if [ ! -f "${APK}" ]; then echo "APK not found: ${APK}" >&2; exit 1; fi
echo "Installing ${APK} on ${SERIAL}"
adb -s "${SERIAL}" install -r -d "${APK}"
