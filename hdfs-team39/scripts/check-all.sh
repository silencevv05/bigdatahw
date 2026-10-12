#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
check_controller
bash "$ROOT/scripts/check.sh"
bash "$ROOT/scripts/check-yarn.sh"
bash "$ROOT/scripts/check-history.sh"
bash "$ROOT/scripts/check-local-ui.sh"
if [[ "${1:-}" == '--mapreduce' ]]; then
  bash "$ROOT/scripts/check-mapreduce.sh"
elif [[ $# -gt 0 ]]; then
  echo 'Usage: bash scripts/check-all.sh [--mapreduce]' >&2
  exit 2
fi
echo 'PASS: HDFS, YARN, JobHistory, local web interfaces.'
