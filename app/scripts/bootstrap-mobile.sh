#!/usr/bin/env bash
# Bootstraps the two Flutter apps once the Flutter SDK is installed.
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter is not installed. Install Flutter 3.x, then re-run 'make mobile-bootstrap'."
  exit 1
fi
if [ ! -f apps/rider/pubspec.yaml ]; then
  (cd apps && flutter create --org ke.uko --project-name uko_rider rider)
fi
if [ ! -f apps/driver/pubspec.yaml ]; then
  (cd apps && flutter create --org ke.uko --project-name uko_driver driver)
fi
echo "Flutter apps created. See apps/rider/README.md for feature-folder layout."
