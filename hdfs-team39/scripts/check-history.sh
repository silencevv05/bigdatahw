#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
check_controller
systemctl --no-pager is-active mapreduce-historyserver.service
sudo -u mapred /opt/hadoop/bin/hdfs dfs -ls /mr-history >/dev/null
python3 - <<'PY'
import json, time, urllib.request
url='http://10.39.0.10:19888/ws/v1/history/info'
for attempt in range(12):
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            payload=json.load(response)
        if 'historyInfo' not in payload:
            raise RuntimeError(f'Unexpected response: {payload}')
        print('JobHistory HTTP API available:', payload['historyInfo'])
        print('PASS: JobHistory Server started and HDFS history directories accessible')
        break
    except Exception as exc:
        if attempt == 11:
            raise SystemExit(f'FAIL: JobHistory API unavailable: {exc}')
        time.sleep(3)
PY
