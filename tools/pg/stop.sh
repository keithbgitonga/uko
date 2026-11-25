#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
export LD_LIBRARY_PATH="$DIR/node_modules/@embedded-postgres/linux-x64/native/lib:$DIR/libs/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
"$DIR/node_modules/@embedded-postgres/linux-x64/native/bin/pg_ctl" -D "$DIR/data" -m fast stop
