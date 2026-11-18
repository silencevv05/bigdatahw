#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_edge
mkdir -p "$ROOT/build"

case "${1:?Specify check, spark or verify}" in
  check)
    hdfs_run dfs -test -s "$INPUT_URI"
    hdfs_run dfs -cat "$INPUT_URI" > "$ROOT/build/input.tsv"
    test -s "$ROOT/build/input.tsv"
    echo "HDFS PASS: $INPUT_URI"
    echo "Input rows: $(wc -l < "$ROOT/build/input.tsv")"
    yarn node -list
    ;;
  spark)
    sudo -n install -d -o hive -g hive -m 0755 /var/lib/prefect-team39
    sudo -n install -o hive -g hive -m 0644 \
      "$ROOT/app/orders.py" /var/lib/prefect-team39/orders.py

    sudo -n -u hive env \
      JAVA_HOME="$JAVA_HOME" \
      HADOOP_HOME="$HADOOP_HOME" \
      HADOOP_CONF_DIR="$HADOOP_CONF_DIR" \
      SPARK_HOME="$SPARK_HOME" \
      SPARK_CONF_DIR="$SPARK_CONF_DIR" \
      PYSPARK_PYTHON="$PYSPARK_PYTHON" \
      PYSPARK_DRIVER_PYTHON="$PYSPARK_DRIVER_PYTHON" \
      "$SPARK_HOME/bin/spark-submit" \
      --master yarn --deploy-mode client \
      /var/lib/prefect-team39/orders.py \
      --input "$INPUT_URI" --output "$OUTPUT_URI"
    ;;
  verify)
    beeline_run -f "$ROOT/sql/inspect.sql" \
      > "$ROOT/build/hive.tsv"
    /usr/bin/python3 "$ROOT/scripts/verify.py" \
      "$ROOT/build/input.tsv" "$ROOT/build/hive.tsv"
    cat "$ROOT/build/hive.tsv"
    ;;
  *)
    echo "Unknown stage: $1" >&2
    exit 2
    ;;
esac
