#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/config/versions.env"
source "$ROOT/config/cluster.env"
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export HADOOP_HOME=/opt/hadoop HADOOP_CONF_DIR=/opt/hadoop/etc/hadoop
export SPARK_HOME=/opt/spark-team39 SPARK_CONF_DIR=/etc/spark-team39
export PYSPARK_PYTHON=/usr/bin/python3 PYSPARK_DRIVER_PYTHON=/usr/bin/python3
export HADOOP_HEAPSIZE=256
export PATH="$JAVA_HOME/bin:$HADOOP_HOME/bin:$SPARK_HOME/bin:$PATH"
INPUT_URI=$NAMENODE_URI/data/team39/spark/input/orders.tsv
OUTPUT_URI=$NAMENODE_URI/warehouse/team39/external/dz4_daily_orders

require_edge() {
  [[ $(hostname -s) == "$EDGE_HOST" && $(id -un) == team ]] || {
    echo "Run on $EDGE_HOST as team (without sudo)." >&2; exit 1;
  }
  sudo -n true
}
hdfs_run() {
  sudo -n -u hive env JAVA_HOME="$JAVA_HOME" HADOOP_HOME="$HADOOP_HOME" \
    HADOOP_CONF_DIR="$HADOOP_CONF_DIR" HADOOP_HEAPSIZE=256 "$HADOOP_HOME/bin/hdfs" "$@"
}
beeline_run() {
  env JAVA_HOME=/opt/hive-java8 HADOOP_HOME="$HADOOP_HOME" \
    HADOOP_CONF_DIR=/etc/hive-team39/hadoop HIVE_CONF_DIR=/etc/hive-team39/client \
    /opt/hive/bin/beeline -u "$JDBC_URL" -n team \
    --silent=true --showHeader=false --outputformat=tsv2 --force=false "$@"
}
