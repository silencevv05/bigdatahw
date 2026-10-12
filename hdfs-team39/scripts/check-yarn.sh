#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
check_controller

echo 'ResourceManager:'
systemctl --no-pager is-active yarn-resourcemanager.service
for host in team-39-00 team-39-01; do
  echo "NodeManager on $host:"
  ssh_node "$host" 'systemctl --no-pager is-active yarn-nodemanager.service'
done

python3 - <<'PY'
import json
import urllib.request
url = 'http://10.39.0.10:8088/ws/v1/cluster/nodes'
try:
    with urllib.request.urlopen(url, timeout=12) as resp:
        data = json.load(resp)
except Exception as exc:
    raise SystemExit(f'Cannot reach YARN RM API {url}: {exc}')
nodes = data.get('nodes') or {}
nodes = nodes.get('node', []) if isinstance(nodes, dict) else []
if isinstance(nodes, dict):
    nodes = [nodes]
print(f'YARN registered NodeManagers: {len(nodes)}')
for item in nodes:
    print(f'  {item.get("id")}: state={item.get("state")}, memoryMB={item.get("totalResource", {}).get("memory") if isinstance(item.get("totalResource"), dict) else "n/a"}')
if len(nodes) != 2 or any(item.get('state') != 'RUNNING' for item in nodes):
    raise SystemExit('FAIL: expected exactly 2 RUNNING NodeManagers')
# ResourceManager may report hostnames in NodeId even if a private IP is configured.
# Match the two expected registered hosts, not an assumed IP representation.
hosts = {str(item.get('id', '')).rsplit(':', 1)[0] for item in nodes}
expected_hosts = {'team-39-00', 'team-39-01'}
if hosts != expected_hosts:
    raise SystemExit(f'FAIL: expected NodeManagers {sorted(expected_hosts)}, got {sorted(hosts)}')
print('PASS: ResourceManager + 2 RUNNING NodeManagers')
PY
