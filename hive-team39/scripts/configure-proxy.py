#!/usr/bin/env python3
"""Allow Hive's MR execution user to proxy only itself, only from the edge IP."""
import os
from pathlib import Path
import shutil
import sys
import xml.etree.ElementTree as ET

assert os.geteuid() == 0, 'Run with sudo'
target = Path('/opt/hadoop/etc/hadoop/core-site.xml')
backup = target.with_name('core-site.xml.before-hive-team39')
if not backup.exists():
    shutil.copy2(target, backup)
tree = ET.parse(target)
root = tree.getroot()
for key, value in {'hadoop.proxyuser.hive.hosts': sys.argv[1], 'hadoop.proxyuser.hive.users': 'hive'}.items():
    entries = [p for p in root.findall('property') if p.findtext('name') == key]
    if entries:
        assert len(entries) == 1 and entries[0].findtext('value') == value, f'Conflicting existing setting: {key}'
    else:
        prop = ET.SubElement(root, 'property')
        ET.SubElement(prop, 'name').text = key
        ET.SubElement(prop, 'value').text = value
ET.indent(root)
temporary = target.with_suffix('.xml.team39-new')
tree.write(temporary, encoding='utf-8', xml_declaration=True)
shutil.copymode(target, temporary)
stat = target.stat()
os.chown(temporary, stat.st_uid, stat.st_gid)
temporary.replace(target)
print('PROXY CONFIG PASS hive -> hive only, from edge IP only')
