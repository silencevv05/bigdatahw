#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_edge
[[ -x /opt/hadoop/bin/hdfs && -x /opt/hive/bin/beeline && -d /etc/hive-team39/client ]]
sudo env DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq aria2 python3 zip openjdk-11-jre-headless
mkdir -p "$ROOT/.cache"
ARCHIVE="$ROOT/.cache/spark-$SPARK_VERSION-bin-hadoop3.tgz"
if [[ ! -f "$ARCHIVE" || -f "$ARCHIVE.aria2" ]]; then
  aria2c --max-connection-per-server=8 --split=8 --min-split-size=1M \
    --summary-interval=0 --console-log-level=warn --max-tries=5 --retry-wait=3 \
    --connect-timeout=20 --timeout=60 --auto-file-renaming=false \
    --checksum="sha-512=$SPARK_SHA512" --dir="$ROOT/.cache" \
    --out="$(basename "$ARCHIVE")" "$SPARK_URL"
fi
printf '%s  %s\n' "$SPARK_SHA512" "$ARCHIVE" | sha512sum -c -
if [[ ! -d /opt/spark-$SPARK_VERSION-bin-hadoop3 ]]; then
  sudo tar -xzf "$ARCHIVE" -C /opt
fi
if [[ -e "$SPARK_HOME" && $(readlink -f "$SPARK_HOME") != "/opt/spark-$SPARK_VERSION-bin-hadoop3" ]]; then
  echo "Another installation owns $SPARK_HOME." >&2; exit 1
fi
sudo ln -sfn "/opt/spark-$SPARK_VERSION-bin-hadoop3" "$SPARK_HOME"
sudo install -d -m 0755 "$SPARK_CONF_DIR"
{
  cat "$ROOT/config/spark-defaults.conf"
  printf '\nspark.driver.host %s\nspark.driver.bindAddress %s\n' "$EDGE_IP" "$EDGE_IP"
  printf 'spark.sql.warehouse.dir %s/warehouse/team39/external/spark\n' "$NAMENODE_URI"
  printf 'spark.yarn.archive %s/data/team39/spark/lib/spark-%s-jars.zip\n' "$NAMENODE_URI" "$SPARK_VERSION"
} | sudo tee "$SPARK_CONF_DIR/spark-defaults.conf" >/dev/null
printf '<configuration><property><name>hive.metastore.uris</name><value>%s</value></property></configuration>\n' "$METASTORE_URI" \
  | sudo tee "$SPARK_CONF_DIR/hive-site.xml" >/dev/null
sudo install -d -o hive -g hive -m 0755 /var/lib/spark-team39
sudo install -d -o team -g team -m 0755 /var/lock/spark-team39
printf '%s\n' 'd /run/lock/spark-team39 0755 team team -' \
  | sudo tee /etc/tmpfiles.d/spark-team39.conf >/dev/null
ssh -n -i "$INTERNAL_KEY" -o BatchMode=yes "team@$NAMENODE_HOST" \
  'set -eu; sudo -u hdfs /opt/hadoop/bin/hdfs dfs -mkdir -p /data/team39/spark/input /data/team39/spark/lib /warehouse/team39/external/dz4_daily_orders; sudo -u hdfs /opt/hadoop/bin/hdfs dfs -chown -R hive:hive /data/team39/spark /warehouse/team39/external/dz4_daily_orders'
JARS="$ROOT/.cache/spark-$SPARK_VERSION-jars.zip"
if [[ ! -f "$JARS" ]]; then
  (cd "$SPARK_HOME/jars" && zip -0 -q "$JARS" ./*.jar)
fi
sudo install -o hive -g hive -m 0644 "$JARS" /var/lib/spark-team39/jars.zip
hdfs_run dfs -put -f /var/lib/spark-team39/jars.zip "/data/team39/spark/lib/spark-$SPARK_VERSION-jars.zip"
"$SPARK_HOME/bin/spark-submit" --version
echo 'DEPLOY PASS: Spark is ready for YARN.'
