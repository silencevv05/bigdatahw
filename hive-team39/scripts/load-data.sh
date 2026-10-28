#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_edge
INPUT="${1:-$ROOT/data/orders.tsv}"
mkdir -p "$ROOT/build"
# One shared writer lock, including invocations from different repository clones.
exec 9>/var/lock/hive-team39/load.lock
flock -n 9 || { echo 'Another ingestion is running; retry later.' >&2; exit 75; }
python3 "$ROOT/scripts/validate_input.py" "$INPUT" "$ROOT/build/validated.tsv" "$ROOT/build/manifest.json"
sudo install -d -o hive -g hive -m 0750 /var/lib/hive-team39/import
sudo install -o hive -g hive -m 0640 "$ROOT/build/validated.tsv" /var/lib/hive-team39/import/orders.tsv
hdfs_as_hive dfs -mkdir -p /data/team39/hive/staging/orders
hdfs_as_hive dfs -put -f /var/lib/hive-team39/import/orders.tsv /data/team39/hive/staging/orders/orders.tsv
beeline_run --hivevar "stage_uri=$NAMENODE_URI/data/team39/hive/staging/orders" \
  --hivevar "warehouse_uri=$NAMENODE_URI/warehouse/team39/external/orders" \
  -f "$ROOT/sql/schema.sql" >"$ROOT/build/schema.out" 2>"$ROOT/build/schema.err"
beeline_run -f "$ROOT/sql/load.sql" >"$ROOT/build/load.out" 2>"$ROOT/build/load.err" || {
  tail -80 "$ROOT/build/load.err" >&2; exit 1;
}
python3 "$ROOT/scripts/verify_load.py" "$ROOT/build/manifest.json" >"$ROOT/build/verify.sql"
beeline_run -f "$ROOT/build/verify.sql" >"$ROOT/build/partitions.tsv" 2>"$ROOT/build/verify.err"
python3 "$ROOT/scripts/verify_load.py" "$ROOT/build/manifest.json" "$ROOT/build/partitions.tsv"
