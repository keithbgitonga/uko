#!/usr/bin/env bash
# Starts the user-space PostgreSQL instance used for local development.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
export LD_LIBRARY_PATH="$DIR/node_modules/@embedded-postgres/linux-x64/native/lib:$DIR/libs/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
BIN="$DIR/node_modules/@embedded-postgres/linux-x64/native/bin"
DATA="$DIR/data"
SOCK="$DIR/run"
mkdir -p "$SOCK"
if [ ! -f "$DATA/PG_VERSION" ]; then
  echo "initialising cluster in $DATA"
  mkdir -p "$DATA"
  "$BIN/initdb" -D "$DATA" -U uko --auth=trust --encoding=UTF8 --locale=C >/tmp/uko-pg-init.log 2>&1 || { cat /tmp/uko-pg-init.log; exit 1; }
fi
"$BIN/pg_ctl" -D "$DATA" -l "$DIR/postgres.log" -o "-p 55432 -k $SOCK -c listen_addresses=127.0.0.1" -w start
sleep 1
node "$DIR/create-db.mjs"
echo "PostgreSQL ready on 127.0.0.1:55432 (database uko)"
