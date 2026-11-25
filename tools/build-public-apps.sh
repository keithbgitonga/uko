#!/usr/bin/env bash
# Build rider + driver APKs against a public API URL.
# Usage: ./tools/build-public-apps.sh https://uko-api.onrender.com/v1
set -euo pipefail
API="${1:?usage: $0 https://your-api/v1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${HOME}/opt/flutter/bin:${PATH}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-${HOME}/Android/Sdk}"
for app in rider driver; do
  echo "=== building ${app} against ${API} ==="
  (cd "${ROOT}/app/apps/${app}" && flutter build apk --debug --target-platform android-arm64 \
    --dart-define=API_BASE_URL="${API}")
done
echo "APKs:"
ls -lh "${ROOT}"/app/apps/*/build/app/outputs/flutter-apk/app-debug.apk
