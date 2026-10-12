#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
check_controller
VERSION=3.4.0
ARCHIVE="hadoop-${VERSION}.tar.gz"
BASE="https://archive.apache.org/dist/hadoop/common/hadoop-${VERSION}"
CACHE="$ROOT/.cache"
mkdir -p "$CACHE"
for host in $ALL_NODES; do
  echo "Checking SSH and sudo on $host"
  ssh_node "$host" 'hostname; sudo -n true; getent hosts team-39-nn >/dev/null'
done
# This project MUST NOT automatically migrate existing Hadoop installations.
for host in $ALL_NODES; do
  ssh_node "$host" 'if [[ -f /home/team/hdfs/name/current/VERSION ]]; then echo "Legacy NameNode metadata under /home/team: manual migration required" >&2; exit 8; fi' || {
    echo "Existing namespace or SSH issue on $host; review it manually before deploying" >&2
    exit 1
  }
done
if [[ ! -s "$CACHE/$ARCHIVE" ]]; then
  curl -fL --retry 3 -o "$CACHE/$ARCHIVE.part" "$BASE/$ARCHIVE"
  mv "$CACHE/$ARCHIVE.part" "$CACHE/$ARCHIVE"
fi
curl -fsSL --retry 3 -o "$CACHE/$ARCHIVE.sha512" "$BASE/$ARCHIVE.sha512"
EXPECTED="$(grep -oEi '[0-9a-f]{128}' "$CACHE/$ARCHIVE.sha512" | head -1)"
ACTUAL="$(sha512sum "$CACHE/$ARCHIVE" | awk '{print $1}')"
[[ "${EXPECTED,,}" == "${ACTUAL,,}" ]] || { echo 'SHA512 mismatch: stop' >&2; exit 1; }
for host in $ALL_NODES; do
  echo "===== Configuring $host ====="
  ssh_node "$host" 'mkdir -p /tmp/team39-config'
  scp_node "$CACHE/$ARCHIVE" "$host" '/tmp/hadoop-team39.tar.gz'
  for file in core-site.xml hdfs-site.xml workers; do
    scp_node "$ROOT/configs/$file" "$host" "/tmp/team39-config/$file"
  done
  scp_node "$ROOT/scripts/remote-setup.sh" "$host" '/tmp/team39-remote-setup.sh'
  ssh_node "$host" 'bash /tmp/team39-remote-setup.sh'
  scp_node "$ROOT/systemd/hdfs-datanode.service" "$host" '/tmp/hdfs-datanode.service'
  ssh_node "$host" 'sudo install -m 0644 /tmp/hdfs-datanode.service /etc/systemd/system/hdfs-datanode.service; sudo systemctl daemon-reload'
done
for kind in namenode secondary; do
  scp_node "$ROOT/systemd/hdfs-${kind}.service" "$NN" "/tmp/hdfs-${kind}.service"
  ssh_node "$NN" "sudo install -m 0644 /tmp/hdfs-${kind}.service /etc/systemd/system/hdfs-${kind}.service"
done
ssh_node "$NN" 'sudo systemctl daemon-reload'
# Refuse to reformat partially initialized or previously used namespaces.
echo 'Checking NameNode initialization...'
ssh_node "$NN" 'set -e;
 if [[ -f /var/lib/hdfs/name/current/VERSION ]]; then
   echo "NameNode already formatted; keep existing metadata"
 elif [[ -n "$(sudo find /var/lib/hdfs/name -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
   echo "Non-empty NameNode directory without VERSION: refusing to format" >&2; exit 1
 else
   sudo -u hdfs /opt/hadoop/bin/hdfs namenode -format -nonInteractive -clusterId CID-team39
 fi'
echo 'Starting NameNode, 3 DataNodes, SecondaryNameNode...'
ssh_node "$NN" 'sudo systemctl enable --now hdfs-namenode.service'
for host in $DNODES; do
  ssh_node "$host" 'sudo systemctl enable --now hdfs-datanode.service'
done
ssh_node "$NN" 'sudo systemctl enable --now hdfs-secondary.service'
echo 'Done. Run bash scripts/check.sh to verify cluster health.'
