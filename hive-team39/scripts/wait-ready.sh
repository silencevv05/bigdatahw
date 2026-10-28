#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_edge
mkdir -p "$ROOT/build"
deadline=$((SECONDS + 240))
while (( SECONDS < deadline )); do
  if timeout --kill-after=3s 20s bash -c 'source "$1/scripts/common.sh"; beeline_run -e "SELECT 1;"' _ "$ROOT" \
    >"$ROOT/build/readiness.out" 2>"$ROOT/build/readiness.err"; then
    grep -qx '1' "$ROOT/build/readiness.out"
    echo 'READY: real JDBC session and SELECT 1 succeeded'
    exit 0
  fi
  sleep 2
done
tail -40 "$ROOT/build/readiness.err" >&2
sudo journalctl -u hive-team39-metastore -u hive-team39-server -n 50 --no-pager >&2
exit 1
