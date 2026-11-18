#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFECT_PYTHON="${PREFECT_PYTHON:-$HOME/venvs/hw_5/bin/python}"
mkdir -p "$PROJECT_DIR/build"
cd "$PROJECT_DIR"
"$PREFECT_PYTHON" flow.py 2>&1 | tee build/flow.log
