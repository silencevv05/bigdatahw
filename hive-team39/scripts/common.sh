#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/config/versions.env"
EDGE_HOST=team-39-en
EDGE_IP=10.39.0.10
NAMENODE_HOST=team-39-nn
NAMENODE_URI=hdfs://10.39.0.11:8020
WORKER_HOSTS="team-39-00 team-39-01"
INTERNAL_KEY="$HOME/.ssh/team_internal"
[[ ! -f "$ROOT/config/cluster.env" ]] || source "$ROOT/config/cluster.env"
export HADOOP_HOME=/opt/hadoop HADOOP_CONF_DIR=/etc/hive-team39/hadoop
export HADOOP_MAPRED_HOME=/opt/hadoop HIVE_HOME=/opt/hive
export JAVA_HOME=/opt/hive-java8 HIVE_CONF_DIR=/etc/hive-team39/client
export HADOOP_HEAPSIZE=256 HADOOP_CLIENT_OPTS=-Xmx256m
export PATH="$JAVA_HOME/bin:$HADOOP_HOME/bin:$HIVE_HOME/bin:$PATH"
JDBC_URL="jdbc:hive2://$EDGE_IP:10000/default"

require_edge() {
  [[ $(hostname -s) == "$EDGE_HOST" && $(id -un) == team ]] || {
    echo "Run on $EDGE_HOST as team (without sudo)." >&2; exit 1;
  }
  sudo -n true
}
beeline_run() {
  "$HIVE_HOME/bin/beeline" -u "$JDBC_URL" -n team --silent=true \
    --showHeader=false --outputformat=tsv2 --force=false "$@"
}
hdfs_as_hive() { sudo -n -u hive env JAVA_HOME="$JAVA_HOME" HADOOP_HOME="$HADOOP_HOME" \
  HADOOP_CONF_DIR="$HADOOP_CONF_DIR" "$HADOOP_HOME/bin/hdfs" "$@"; }
