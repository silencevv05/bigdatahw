#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/common.sh"
check_controller

[[ -f "$ROOT/configs/mapred-site.xml" ]] || { echo 'Missing configs/mapred-site.xml' >&2; exit 1; }
[[ -f "$ROOT/systemd/mapreduce-historyserver.service" ]] || { echo 'Missing systemd/mapreduce-historyserver.service' >&2; exit 1; }
[[ -x /opt/hadoop/bin/mapred ]] || { echo 'Hadoop is missing from /opt/hadoop on edge' >&2; exit 1; }
id mapred >/dev/null 2>&1 || { echo 'Missing mapred OS user on edge' >&2; exit 1; }
systemctl -q is-active yarn-resourcemanager.service || { echo 'ResourceManager is not active' >&2; exit 1; }
ssh_node "$NN" 'systemctl -q is-active hdfs-namenode.service' || { echo 'NameNode is not active' >&2; exit 1; }
for node in team-39-00 team-39-01; do
  ssh_node "$node" 'systemctl -q is-active yarn-nodemanager.service' || { echo "$node NodeManager is not active" >&2; exit 1; }
done

echo 'Checking HDFS access from edge as mapred...'
sudo -u mapred /opt/hadoop/bin/hdfs dfs -ls / >/dev/null

echo 'Backing up and updating MapReduce configuration for small YARN workers...'
if [[ ! -e "$ROOT/configs/mapred-site.xml.before-history.bak" ]]; then
  cp "$ROOT/configs/mapred-site.xml" "$ROOT/configs/mapred-site.xml.before-history.bak"
fi
python3 - "$ROOT/configs/mapred-site.xml" <<'PY'
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
path = Path(sys.argv[1])
root = ET.parse(path).getroot()
values = {
    'mapreduce.jobhistory.address': '10.39.0.10:10020',
    'mapreduce.jobhistory.webapp.address': '10.39.0.10:19888',
    'mapreduce.jobhistory.intermediate-done-dir': '/mr-history/tmp',
    'mapreduce.jobhistory.done-dir': '/mr-history/done',
    'yarn.app.mapreduce.am.resource.mb': '512',
    'yarn.app.mapreduce.am.command-opts': '-Xmx384m',
    'mapreduce.map.memory.mb': '512',
    'mapreduce.map.java.opts': '-Xmx384m',
    'mapreduce.reduce.memory.mb': '512',
    'mapreduce.reduce.java.opts': '-Xmx384m',
    'mapreduce.application.classpath': '$HADOOP_MAPRED_HOME/share/hadoop/mapreduce/*,$HADOOP_MAPRED_HOME/share/hadoop/mapreduce/lib/*',
}
for name, value in values.items():
    matches = [p for p in root.findall('property') if p.findtext('name') == name]
    if len(matches) > 1:
        raise SystemExit(f'Duplicate configuration property: {name}')
    if matches:
        target = matches[0]
        val = target.find('value')
        if val is None:
            val = ET.SubElement(target, 'value')
        val.text = value
    else:
        p = ET.SubElement(root, 'property')
        ET.SubElement(p, 'name').text = name
        ET.SubElement(p, 'value').text = value
ET.indent(root, space='  ')
temp = path.with_suffix('.xml.tmp')
ET.ElementTree(root).write(temp, encoding='UTF-8', xml_declaration=True)
temp.replace(path)
print('mapred-site.xml: updated, XML valid')
PY

echo 'Creating JobHistory and MapReduce staging directories in HDFS...'
ssh_node "$NN" 'set -e;
  H=/opt/hadoop/bin/hdfs;
  sudo -u hdfs "$H" dfs -mkdir -p /mr-history/tmp /mr-history/done /tmp/hadoop-yarn/staging /user/team;
  sudo -u hdfs "$H" dfs -chmod 755 /mr-history;
  sudo -u hdfs "$H" dfs -chown mapred /mr-history/tmp /mr-history/done;
  sudo -u hdfs "$H" dfs -chmod 1777 /mr-history/tmp /tmp/hadoop-yarn/staging;
  sudo -u hdfs "$H" dfs -chmod 750 /mr-history/done;
  sudo -u hdfs "$H" dfs -chown team /user/team;
  sudo -u hdfs "$H" dfs -chmod 755 /user/team'

echo 'Installing MapReduce configuration on edge and NodeManagers...'
sudo install -m 0644 -o root -g root "$ROOT/configs/mapred-site.xml" /opt/hadoop/etc/hadoop/mapred-site.xml
for node in team-39-00 team-39-01; do
  scp_node "$ROOT/configs/mapred-site.xml" "$node" /tmp/team39-mapred-site.xml
  ssh_node "$node" 'sudo install -m 0644 -o root -g root /tmp/team39-mapred-site.xml /opt/hadoop/etc/hadoop/mapred-site.xml'
done

sudo install -d -m 0750 -o mapred -g mapred /var/lib/mapred /var/log/mapred
sudo install -m 0644 -o root -g root "$ROOT/systemd/mapreduce-historyserver.service" /etc/systemd/system/mapreduce-historyserver.service
sudo systemctl daemon-reload
sudo systemctl enable mapreduce-historyserver.service
sudo systemctl restart mapreduce-historyserver.service
sudo systemctl --no-pager is-active mapreduce-historyserver.service
echo 'JobHistory started. Run: bash scripts/check-history.sh'
