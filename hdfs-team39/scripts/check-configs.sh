#!/usr/bin/env bash

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for script in "$ROOT"/scripts/*.sh; do
  bash -n "$script"
done
python3 - "$ROOT" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
root = Path(sys.argv[1])
for file in sorted((root / 'configs').glob('*.xml')):
    xml = ET.parse(file).getroot()
    if xml.tag != 'configuration':
        raise SystemExit(f'FAIL: {file.name} root must be configuration')
    names = [p.findtext('name') for p in xml.findall('property')]
    if len(set(names)) != len(names):
        raise SystemExit(f'FAIL: {file.name} contains duplicate properties')
    print(f'PASS: {file.name}, {len(names)} properties')
print('PASS: all Bash scripts pass syntax checks')
PY
