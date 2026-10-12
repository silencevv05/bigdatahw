#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/common.sh"
check_controller
while read -r name ip port; do
  status=$(curl --noproxy '*' -s -o /dev/null -w '%{http_code}' \
    --max-time 8 --connect-timeout 3 "http://$ip:$port/" || true)
  if [[ ! "$status" =~ ^[23][0-9][0-9]$ ]]; then
    printf 'FAIL: %-13s %s:%s unavailable\n' "$name" "$ip" "$port" >&2
    exit 1
  fi
  printf 'PASS: %-13s HTTP %s (%s:%s)\n' "$name" "$status" "$ip" "$port"
done <<'EOF'
rm         10.39.0.10 8088
history    10.39.0.10 19888
nn         10.39.0.11 9870
secondary  10.39.0.11 9868
dn-nn      10.39.0.11 9864
dn-00      10.39.0.12 9864
dn-01      10.39.0.13 9864
nm-00      10.39.0.12 8042
nm-01      10.39.0.13 8042
EOF
echo 'PASS: 9 internal web interfaces reachable from edge.'
