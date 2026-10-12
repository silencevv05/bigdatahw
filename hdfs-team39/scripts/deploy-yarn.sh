#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/common.sh"
check_controller

for f in "$ROOT/configs/yarn-site.xml" "$ROOT/configs/mapred-site.xml" \
         "$ROOT/configs/core-site-edge.xml" \
         "$ROOT/systemd/yarn-resourcemanager.service" \
         "$ROOT/systemd/yarn-nodemanager.service"; do
  [[ -s "$f" ]] || { echo "Missing required file: $f" >&2; exit 1; }
done

python3 - "$ROOT/configs/yarn-site.xml" "$ROOT/configs/mapred-site.xml" "$ROOT/configs/core-site-edge.xml" <<'PY'
import sys
import xml.etree.ElementTree as ET

def config(path):
    root = ET.parse(path).getroot()
    return {p.findtext('name'): p.findtext('value') for p in root.findall('property')}

yarn, mr, core = map(config, sys.argv[1:])
required = {
    'yarn.resourcemanager.hostname': '10.39.0.10',
    'yarn.resourcemanager.webapp.address': '10.39.0.10:8088',
    'yarn.nodemanager.resource.memory-mb': '1536',
}
for key, expected in required.items():
    if yarn.get(key) != expected:
        raise SystemExit(f'Bad {key}: expected {expected}, got {yarn.get(key)}')
if 'mapreduce_shuffle' not in (yarn.get('yarn.nodemanager.aux-services') or '').split(','):
    raise SystemExit('Missing yarn.nodemanager.aux-services=mapreduce_shuffle')
if mr.get('mapreduce.framework.name') != 'yarn':
    raise SystemExit('mapreduce.framework.name must be yarn')
if core.get('fs.defaultFS') != 'hdfs://10.39.0.11:8020':
    raise SystemExit('Edge core-site.xml must point to NameNode RPC at 10.39.0.11:8020')
print('XML syntax and key properties: OK')
PY

[[ -x /opt/hadoop/bin/yarn ]] || { echo 'Edge: Hadoop missing in /opt/hadoop' >&2; exit 1; }
[[ "$(/opt/hadoop/bin/hadoop version | head -n1)" == 'Hadoop 3.4.0' ]] || {
  echo 'Edge Hadoop version must be 3.4.0' >&2; exit 1;
}
sudo -n true
if ! id yarn >/dev/null 2>&1; then
  sudo useradd --system --user-group --create-home --home-dir /var/lib/yarn \
    --shell /usr/sbin/nologin yarn
fi

ssh_node "$NN" 'systemctl -q is-active hdfs-namenode.service'
for host in team-39-nn team-39-00 team-39-01; do
  ssh_node "$host" 'systemctl -q is-active hdfs-datanode.service'
done
report="$(ssh_node "$NN" 'sudo -u hdfs /opt/hadoop/bin/hdfs dfsadmin -report')"
grep -qE '^Live datanodes \(3\):' <<<"$report" || {
  echo 'HDFS does not have 3 live DataNodes; aborting YARN deployment' >&2; exit 1;
}

echo 'Configuring ResourceManager on edge...'
sudo install -m 0644 -o root -g root "$ROOT/configs/core-site-edge.xml" \
  /opt/hadoop/etc/hadoop/core-site.xml
for f in yarn-site.xml mapred-site.xml; do
  sudo install -m 0644 -o root -g root "$ROOT/configs/$f" "/opt/hadoop/etc/hadoop/$f"
done
sudo install -d -m 0750 -o yarn -g yarn /var/log/yarn /var/lib/yarn
sudo install -m 0644 -o root -g root "$ROOT/systemd/yarn-resourcemanager.service" \
  /etc/systemd/system/yarn-resourcemanager.service
sudo systemctl daemon-reload
sudo systemctl enable yarn-resourcemanager.service
sudo systemctl restart yarn-resourcemanager.service
sudo systemctl --no-pager is-active yarn-resourcemanager.service

for host in team-39-00 team-39-01; do
  echo "Configuring NodeManager on $host..."
  ssh_node "$host" 'sudo -n true; test -x /opt/hadoop/bin/yarn; systemctl -q is-active hdfs-datanode.service'
  case "$host" in
    team-39-00) private_ip=10.39.0.12 ;;
    team-39-01) private_ip=10.39.0.13 ;;
    *) echo "Unexpected NodeManager host $host" >&2; exit 1 ;;
  esac
  local_nm_xml="$(mktemp)"
  python3 - "$ROOT/configs/yarn-site.xml" "$private_ip" "$local_nm_xml" <<'PYXML'
import sys
import xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
updates = {
    'yarn.nodemanager.hostname': sys.argv[2],
    'yarn.nodemanager.bind-host': '0.0.0.0',
    'yarn.nodemanager.webapp.address': sys.argv[2] + ':8042',
}
for name, value in updates.items():
    matched = next((p for p in root.findall('property') if p.findtext('name') == name), None)
    if matched is None:
        matched = ET.SubElement(root, 'property')
        ET.SubElement(matched, 'name').text = name
        ET.SubElement(matched, 'value').text = value
    else:
        matched.find('value').text = value
ET.indent(root)
ET.ElementTree(root).write(sys.argv[3], encoding='utf-8', xml_declaration=True)
PYXML
  scp_node "$local_nm_xml" "$host" '/tmp/team39-yarn-site.xml'
  rm -f "$local_nm_xml"
  scp_node "$ROOT/configs/mapred-site.xml" "$host" '/tmp/team39-mapred-site.xml'
  scp_node "$ROOT/systemd/yarn-nodemanager.service" "$host" '/tmp/team39-yarn-nodemanager.service'
  ssh_node "$host" 'set -e;
    if ! id yarn >/dev/null 2>&1; then
      sudo useradd --system --user-group --create-home --home-dir /var/lib/yarn --shell /usr/sbin/nologin yarn;
    fi;
    sudo install -d -m 0750 -o yarn -g yarn /var/lib/yarn /var/lib/yarn/local /var/lib/yarn/logs /var/log/yarn;
    sudo install -m 0644 -o root -g root /tmp/team39-yarn-site.xml /opt/hadoop/etc/hadoop/yarn-site.xml;
    sudo install -m 0644 -o root -g root /tmp/team39-mapred-site.xml /opt/hadoop/etc/hadoop/mapred-site.xml;
    sudo install -m 0644 -o root -g root /tmp/team39-yarn-nodemanager.service /etc/systemd/system/yarn-nodemanager.service;
    sudo systemctl daemon-reload;
    sudo systemctl enable yarn-nodemanager.service;
    sudo systemctl restart yarn-nodemanager.service;
    systemctl --no-pager is-active yarn-nodemanager.service'
done

echo 'ResourceManager and 2 NodeManagers deployed. Run bash scripts/check-yarn.sh.'
echo 'Note: JobHistory Server and external UI publishing are separate next stages.'
