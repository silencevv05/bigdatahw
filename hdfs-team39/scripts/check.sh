#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
check_controller
for host in $ALL_NODES; do
  echo "===== $host ====="
  ssh_node "$host" 'id hdfs; systemctl is-active hdfs-datanode.service'
done
ssh_node "$NN" 'systemctl is-active hdfs-namenode.service; systemctl is-active hdfs-secondary.service'
echo 'Waiting for exactly 3 live DataNodes...'
for i in {1..24}; do
  REPORT="$(ssh_node "$NN" 'sudo -u hdfs /opt/hadoop/bin/hdfs dfsadmin -report')"
  if grep -qE '^Live datanodes \(3\):' <<<"$REPORT" && ! grep -qE '^Dead datanodes \([1-9][0-9]*\):' <<<"$REPORT"; then break; fi
  sleep 5
done
printf '%s\n' "$REPORT" | grep -E 'Live datanodes|Dead datanodes' || true
grep -qE '^Live datanodes \(3\):' <<<"$REPORT" || { echo 'Expected 3 live nodes' >&2; exit 1; }
! grep -qE '^Dead datanodes \([1-9][0-9]*\):' <<<"$REPORT" || { echo 'Some DataNodes are dead' >&2; exit 1; }
echo 'Testing write/read/three replicas/fsck...'
ssh_node "$NN" 'set -e;
  printf "team-39 automated HDFS check\n" >/tmp/team39-hdfs-test.txt;
  sudo -u hdfs /opt/hadoop/bin/hdfs dfs -mkdir -p /team39-check;
  sudo -u hdfs /opt/hadoop/bin/hdfs dfs -put -f /tmp/team39-hdfs-test.txt /team39-check/check.txt;
  sudo -u hdfs /opt/hadoop/bin/hdfs dfs -setrep -w 3 /team39-check/check.txt;
  CONTENT="$(sudo -u hdfs /opt/hadoop/bin/hdfs dfs -cat /team39-check/check.txt)";
  [[ "$CONTENT" == "team-39 automated HDFS check" ]] || exit 1;
  sudo -u hdfs /opt/hadoop/bin/hdfs fsck /team39-check/check.txt -files -blocks -locations >/tmp/team39-fsck.log;
  cat /tmp/team39-fsck.log;
  grep -q "Status: HEALTHY" /tmp/team39-fsck.log'
echo 'PASS: 3 DataNodes healthy, read/write OK, replication=3, fsck HEALTHY.'
