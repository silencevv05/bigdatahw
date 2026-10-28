#!/usr/bin/env python3
"""Normalize only the inventory's aliases; retain all unrelated host entries."""
import ipaddress
import os
from pathlib import Path
import shutil
import sys

assert os.geteuid() == 0, 'Run with sudo'
inventory = []
for line in Path(sys.argv[1]).read_text().splitlines():
    fields = line.split()
    if fields:
        assert len(fields) == 3 and not ipaddress.ip_address(fields[0]).is_loopback
        inventory.append(fields)
aliases = {alias for fields in inventory for alias in fields[1:]}
assert len(aliases) == 2 * len(inventory), 'Duplicate aliases in inventory'
target = Path('/etc/hosts')
backup = Path('/etc/hosts.before-hive-team39')
if not backup.exists():
    shutil.copy2(target, backup)
result = []
for line in target.read_text().splitlines():
    if line == '# Hive team-39 internal addresses':
        continue
    body, separator, comment = line.partition('#')
    fields = body.split()
    if len(fields) >= 2 and aliases.intersection(fields[1:]):
        remaining = [alias for alias in fields[1:] if alias not in aliases]
        if remaining:
            result.append(fields[0] + '\t' + ' '.join(remaining) + (f' #{comment}' if separator else ''))
    else:
        result.append(line)
result.append('# Hive team-39 internal addresses')
result.extend(' '.join(fields) for fields in inventory)
temporary = Path('/etc/hosts.team39-new')
temporary.write_text('\n'.join(result) + '\n')
shutil.copymode(target, temporary)
stat = target.stat()
os.chown(temporary, stat.st_uid, stat.st_gid)
temporary.replace(target)
print('HOSTS CONFIG PASS all inventory short names and FQDNs map to private IPs')
