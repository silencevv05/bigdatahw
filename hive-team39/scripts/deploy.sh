#!/usr/bin/env bash
# Run from the edge node as team. Does not format or restart Hadoop.
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_edge
[[ -x /opt/hadoop/bin/hdfs && -r "$INTERNAL_KEY" ]]
export DEBIAN_FRONTEND=noninteractive
sudo env DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  postgresql libpostgresql-jdbc-java aria2 python3 curl
mkdir -p "$ROOT/.cache"
sudo python3 "$ROOT/scripts/configure-hosts.py" "$ROOT/config/hosts.tsv"
for host in "$NAMENODE_HOST" $WORKER_HOSTS; do
  scp -q -i "$INTERNAL_KEY" "$ROOT/scripts/configure-hosts.py" "$ROOT/config/hosts.tsv" "team@$host:/tmp/"
  ssh -n -i "$INTERNAL_KEY" -o BatchMode=yes "team@$host" \
    'sudo python3 /tmp/configure-hosts.py /tmp/hosts.tsv'
done

fetch_verified() {
  local url=$1 output=$2 digest=$3
  if [[ ! -f "$output" || -f "$output.aria2" ]]; then
    aria2c --max-connection-per-server=8 --split=8 --min-split-size=1M \
      --summary-interval=0 --console-log-level=warn --max-tries=5 --retry-wait=3 \
      --connect-timeout=20 --timeout=60 --auto-file-renaming=false \
      --checksum="sha-256=$digest" --dir="$(dirname "$output")" \
      --out="$(basename "$output")" "$url"
  fi
  printf '%s  %s\n' "$digest" "$output" | sha256sum -c -
}
fetch_verified "$HIVE_URL" "$ROOT/.cache/apache-hive-$HIVE_VERSION-bin.tar.gz" "$HIVE_SHA256"
fetch_verified "$JDK_URL" "$ROOT/.cache/temurin8.tar.gz" "$JDK_SHA256"

if [[ ! -d /opt/apache-hive-$HIVE_VERSION-bin ]]; then
  sudo tar -xzf "$ROOT/.cache/apache-hive-$HIVE_VERSION-bin.tar.gz" -C /opt
fi
if [[ -e /opt/hive && $(readlink -f /opt/hive) != "/opt/apache-hive-$HIVE_VERSION-bin" ]]; then
  echo 'Another Hive installation owns /opt/hive; refusing to replace it.' >&2; exit 1
fi
sudo ln -sfn "/opt/apache-hive-$HIVE_VERSION-bin" /opt/hive
if [[ ! -f /opt/hive-java8/.team39-sha256 ]]; then
  [[ ! -e /opt/hive-java8 ]] || { echo 'Unmanaged /opt/hive-java8 exists' >&2; exit 1; }
  sudo mkdir /opt/hive-java8
  sudo tar -xzf "$ROOT/.cache/temurin8.tar.gz" --strip-components=1 -C /opt/hive-java8
  printf '%s\n' "$JDK_SHA256" | sudo tee /opt/hive-java8/.team39-sha256 >/dev/null
fi
[[ $(cat /opt/hive-java8/.team39-sha256) == "$JDK_SHA256" ]]
sudo install -m 0644 /usr/share/java/postgresql.jar /opt/hive/lib/postgresql.jar

# The MR AM and task JVMs use the same Java 8 as Hive; Hadoop daemons keep Java 11.
for host in $WORKER_HOSTS; do
  if ! ssh -n -i "$INTERNAL_KEY" -o BatchMode=yes "team@$host" \
    "test -r /opt/hive-java8/.team39-sha256 && test \"\$(cat /opt/hive-java8/.team39-sha256)\" = '$JDK_SHA256'"; then
    scp -q -i "$INTERNAL_KEY" "$ROOT/.cache/temurin8.tar.gz" "team@$host:/tmp/team39-temurin8.tar.gz"
    ssh -n -i "$INTERNAL_KEY" -o BatchMode=yes "team@$host" \
      "set -eu; printf '%s  %s\\n' '$JDK_SHA256' /tmp/team39-temurin8.tar.gz | sha256sum -c -; \
       test ! -e /opt/hive-java8; sudo mkdir /opt/hive-java8; \
       sudo tar -xzf /tmp/team39-temurin8.tar.gz --strip-components=1 -C /opt/hive-java8; \
       printf '%s\\n' '$JDK_SHA256' | sudo tee /opt/hive-java8/.team39-sha256 >/dev/null; \
       rm /tmp/team39-temurin8.tar.gz"
  fi
done

sudo python3 "$ROOT/scripts/configure-proxy.py" "$EDGE_IP"
scp -q -i "$INTERNAL_KEY" "$ROOT/scripts/configure-proxy.py" "team@$NAMENODE_HOST:/tmp/team39-configure-proxy.py"
ssh -n -i "$INTERNAL_KEY" -o BatchMode=yes "team@$NAMENODE_HOST" \
  "sudo python3 /tmp/team39-configure-proxy.py '$EDGE_IP' && sudo -u hdfs /opt/hadoop/bin/hdfs dfsadmin -refreshSuperUserGroupsConfiguration"
sudo -u yarn /opt/hadoop/bin/yarn rmadmin -refreshSuperUserGroupsConfiguration
sudo python3 "$ROOT/scripts/configure.py" "$EDGE_IP" "$NAMENODE_URI"
ssh -n -i "$INTERNAL_KEY" -o BatchMode=yes "team@$NAMENODE_HOST" \
  "sudo -u hdfs /opt/hadoop/bin/hdfs dfs -mkdir -p /tmp /user/hive /warehouse/team39/managed /warehouse/team39/external /data/team39/hive/staging; \
   sudo -u hdfs /opt/hadoop/bin/hdfs dfs -chmod 1777 /tmp; \
   sudo -u hdfs /opt/hadoop/bin/hdfs dfs -chown -R hive:hive /user/hive /warehouse/team39 /data/team39/hive; \
   sudo -u hdfs /opt/hadoop/bin/hdfs dfs -chmod -R 755 /warehouse/team39 /data/team39/hive /user/hive"

# A failed connection is not evidence of an uninitialized database.
TABLE_COUNT=$(sudo -u postgres psql -X -A -t -d hive_team39 -v ON_ERROR_STOP=1 \
  -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';")
if [[ "$TABLE_COUNT" == 0 ]]; then
  sudo -u hive env JAVA_HOME="$JAVA_HOME" HADOOP_HOME="$HADOOP_HOME" \
    HADOOP_CONF_DIR="$HADOOP_CONF_DIR" \
    HIVE_CONF_DIR=/etc/hive-team39/metastore HADOOP_HEAPSIZE=512 \
    /opt/hive/bin/schematool -dbType postgres -initSchema
fi
sudo -u hive env JAVA_HOME="$JAVA_HOME" HADOOP_HOME="$HADOOP_HOME" \
  HADOOP_CONF_DIR="$HADOOP_CONF_DIR" \
  HIVE_CONF_DIR=/etc/hive-team39/metastore HADOOP_HEAPSIZE=512 \
  /opt/hive/bin/schematool -dbType postgres -info
sudo install -m 0644 "$ROOT/systemd/hive-team39-metastore.service" /etc/systemd/system/
sudo install -m 0644 "$ROOT/systemd/hive-team39-server.service" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable hive-team39-metastore hive-team39-server
sudo systemctl restart hive-team39-metastore hive-team39-server
bash "$ROOT/scripts/wait-ready.sh"
echo 'DEPLOY PASS: PostgreSQL -> remote Metastore -> HiveServer2 -> HDFS/YARN'
