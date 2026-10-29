#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_edge
INPUT="${1:-$ROOT/../hive-team39/data/orders.tsv}"
mkdir -p "$ROOT/build"
exec 9>/var/lock/spark-team39/run.lock
flock -n 9 || { echo 'Another DZ4 job is running; retry later.' >&2; exit 75; }
python3 "$ROOT/../hive-team39/scripts/validate_input.py" "$INPUT" \
  "$ROOT/build/validated.tsv" "$ROOT/build/input.json"
sudo install -o hive -g hive -m 0644 "$ROOT/build/validated.tsv" /var/lib/spark-team39/orders.tsv
sudo install -o hive -g hive -m 0644 "$ROOT/app/orders.py" /var/lib/spark-team39/orders.py
hdfs_run dfs -put -f /var/lib/spark-team39/orders.tsv "$INPUT_URI"
sudo -n -u hive env JAVA_HOME="$JAVA_HOME" HADOOP_HOME="$HADOOP_HOME" \
  HADOOP_CONF_DIR="$HADOOP_CONF_DIR" SPARK_CONF_DIR="$SPARK_CONF_DIR" \
  PYSPARK_PYTHON="$PYSPARK_PYTHON" PYSPARK_DRIVER_PYTHON="$PYSPARK_DRIVER_PYTHON" \
  "$SPARK_HOME/bin/spark-submit" --master yarn --deploy-mode client \
  /var/lib/spark-team39/orders.py --input "$INPUT_URI" --output "$OUTPUT_URI" \
  >"$ROOT/build/spark.log" 2>&1 || { tail -80 "$ROOT/build/spark.log" >&2; exit 1; }
grep -E '^(APPLICATION_ID|MASTER|EXECUTORS|SPARK PASS)' "$ROOT/build/spark.log"
beeline_run -f "$ROOT/sql/inspect.sql" >"$ROOT/build/hive.tsv" 2>"$ROOT/build/hive.log" || {
  tail -60 "$ROOT/build/hive.log" >&2; exit 1;
}
python3 "$ROOT/scripts/verify.py" "$ROOT/build/validated.tsv" "$ROOT/build/hive.tsv"
