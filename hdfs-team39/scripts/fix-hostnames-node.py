#!/usr/bin/env python3

from pathlib import Path
import os
import shutil
import socket
import tempfile

hosts = {
    "team-39-en": "10.39.0.10",
    "team-39-nn": "10.39.0.11",
    "team-39-00": "10.39.0.12",
    "team-39-01": "10.39.0.13",
}
name = socket.gethostname().split(".")[0]
if name not in hosts:
    raise SystemExit(f"Unexpected host {name}. Nothing changed")
if os.geteuid() != 0:
    raise SystemExit("Run with sudo")

ip = hosts[name]
fqdn = f"{name}.hse.c.mws"
path = Path('/etc/hosts')
original = path.read_text()
lines = []
for line in original.splitlines():
    fields = line.split('#', 1)[0].split()
    if not fields:
        lines.append(line)
        continue
    address, *aliases = fields
    if address == '127.0.1.1' and (name in aliases or fqdn in aliases):
        leftover = [a for a in aliases if a not in (name, fqdn)]
        if leftover:
            lines.append('127.0.1.1 ' + ' '.join(leftover))
        continue
    if address == ip:
        aliases = [a for a in aliases if a not in (name, fqdn)]
        if aliases:
            lines.append(address + ' ' + ' '.join(aliases))
        continue
    lines.append(line)
lines.append(f'{ip} {fqdn} {name}')
new_text = '\n'.join(lines).rstrip() + '\n'
if original == new_text:
    print(f'{name}: /etc/hosts already correct')
else:
    backup = Path('/etc/hosts.team39.backup')
    if not backup.exists():
        shutil.copy2(path, backup)
    stat = path.stat()
    fd, tmp = tempfile.mkstemp(dir='/etc', prefix='.team39-hosts-')
    try:
        with os.fdopen(fd, 'w') as output:
            output.write(new_text)
        os.chmod(tmp, stat.st_mode)
        os.chown(tmp, stat.st_uid, stat.st_gid)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
    print(f'{name}: /etc/hosts updated; original at {backup}')
