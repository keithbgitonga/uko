#!/usr/bin/env bash
# Captures a screenshot + recent logcat for a named test flow.
set -euo pipefail
NAME="${1:?usage: capture.sh flow-name [serial]}"
SERIAL="${2:-$(adb devices | awk 'NR==2{print $1}')}"
STAMP="$(date +%Y-%m-%d-%H%M)"
DIR="$(cd "$(dirname "$0")/.." && pwd)/evidence"
mkdir -p "${DIR}"
OUT="${DIR}/${NAME}-${STAMP}"
adb -s "${SERIAL}" exec-out screencap -p > "${OUT}.png"
adb -s "${SERIAL}" logcat -d -v time > "${OUT}.log"
echo "saved ${OUT}.png"
echo "saved ${OUT}.log"
