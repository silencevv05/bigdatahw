#!/usr/bin/env python3
"""Root-only host configuration. Secrets never enter the repository or stdout."""
import os
from pathlib import Path
import pwd
import secrets
import subprocess
import sys
import xml.etree.ElementTree as ET


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def xml_file(path, properties, private=False):
    root = ET.Element('configuration')
    for name, value in properties.items():
        prop = ET.SubElement(root, 'property')
        ET.SubElement(prop, 'name').text = name
        ET.SubElement(prop, 'value').text = str(value)
    ET.indent(root)
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True, mode=0o755)
    temporary = target.with_suffix('.xml.new')
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o640 if private else 0o644)
    with os.fdopen(fd, 'wb') as out:
        ET.ElementTree(root).write(out, encoding='utf-8', xml_declaration=True)
    os.chown(temporary, 0, pwd.getpwnam('hive').pw_gid)
    os.chmod(temporary, 0o640 if private else 0o644)
    temporary.replace(target)


def main():
    assert os.geteuid() == 0, 'Run using sudo'
    ip, nn_uri = sys.argv[1:]
    try:
        pwd.getpwnam('hive')
    except KeyError:
        run('useradd', '--system', '--home-dir', '/var/lib/hive-team39',
            '--create-home', '--shell', '/usr/sbin/nologin', 'hive')
    for path in ('/var/lib/hive-team39', '/var/log/hive-team39', '/var/log/hive-team39/operations',
                 '/var/lib/hive-team39/tmp', '/etc/hive-team39'):
        run('install', '-d', '-o', 'hive', '-g', 'hive', '-m', '0750', path)
    os.chown('/etc/hive-team39', 0, 0)
    os.chmod('/etc/hive-team39', 0o755)
    run('install', '-d', '-o', 'team', '-g', 'team', '-m', '0750', '/var/lock/hive-team39')
    Path('/etc/tmpfiles.d/hive-team39.conf').write_text('d /run/lock/hive-team39 0750 team team -\n')
    password_file = Path('/etc/hive-team39/db-password')
    if not password_file.exists():
        with os.fdopen(os.open(password_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as out:
            out.write(secrets.token_hex(32) + '\n')
    password = password_file.read_text().strip()
    assert len(password) == 64 and all(c in '0123456789abcdef' for c in password)
    run('systemctl', 'enable', '--now', 'postgresql')
    # psql's stdin carries the secret; it is absent from argv and logs.
    sql = rf"""DO $$ BEGIN
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='hive_team39') THEN
        CREATE ROLE hive_team39 LOGIN PASSWORD '{password}';
      END IF;
    END $$;
    SELECT 'CREATE DATABASE hive_team39 OWNER hive_team39 ENCODING ''UTF8'''
      WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='hive_team39')\gexec
    """
    run('runuser', '-u', 'postgres', '--', 'psql', '-X', '-v', 'ON_ERROR_STOP=1', input=sql,
        stdout=subprocess.DEVNULL)
    common = {
        'fs.defaultFS': nn_uri,
        'hive.metastore.warehouse.dir': '/warehouse/team39/managed',
        'hive.metastore.warehouse.external.dir': '/warehouse/team39/external',
        'hive.metastore.schema.verification': 'true',
        'datanucleus.schema.autoCreateAll': 'false',
        'hive.exec.scratchdir': '/tmp/hive-team39',
        'hive.exec.local.scratchdir': '/var/lib/hive-team39/tmp',
        'hive.downloaded.resources.dir': '/var/lib/hive-team39/tmp/resources',
        'hive.execution.engine': 'mr',
        'hive.exec.mode.local.auto': 'false',
        'hive.exec.dynamic.partition': 'true',
        'hive.exec.dynamic.partition.mode': 'nonstrict',
        'hive.exec.max.dynamic.partitions': '1000',
        'hive.exec.max.dynamic.partitions.pernode': '1000',
        'hive.support.concurrency': 'true',
        'hive.txn.manager': 'org.apache.hadoop.hive.ql.lockmgr.DbTxnManager',
        'hive.compactor.initiator.on': 'false',
        'hive.compactor.worker.threads': '0',
        # No end-user impersonation. Avoid the alpha-2 TUGI wrapper losing peer IP.
        'hive.metastore.execute.setugi': 'false',
        'mapreduce.framework.name': 'yarn',
        'mapreduce.map.memory.mb': '512',
        'mapreduce.reduce.memory.mb': '512',
        'mapreduce.map.java.opts': '-Xmx384m',
        'mapreduce.reduce.java.opts': '-Xmx384m',
        'yarn.app.mapreduce.am.resource.mb': '512',
        'yarn.app.mapreduce.am.command-opts': '-Xmx384m',
        'mapreduce.map.env': 'JAVA_HOME=/opt/hive-java8',
        'mapreduce.reduce.env': 'JAVA_HOME=/opt/hive-java8',
        'yarn.app.mapreduce.am.env': 'JAVA_HOME=/opt/hive-java8,HADOOP_MAPRED_HOME=/opt/hadoop',
    }
    server = dict(common, **{
        'hive.metastore.uris': f'thrift://{ip}:9083',
        'hive.server2.thrift.bind.host': ip,
        'hive.server2.thrift.port': '10000',
        'hive.server2.authentication': 'NONE',
        'hive.server2.enable.doAs': 'false',
        'hive.server2.thrift.min.worker.threads': '5',
        'hive.server2.thrift.max.worker.threads': '50',
        'hive.server2.webui.host': ip,
        'hive.server2.webui.port': '10002',
        'hive.server2.logging.operation.log.location': '/var/log/hive-team39/operations',
        'hive.server2.metrics.enabled': 'true',
        'hive.server2.tez.initialize.default.sessions': 'false',
    })
    metastore = dict(common, **{
        'javax.jdo.option.ConnectionURL': 'jdbc:postgresql://127.0.0.1:5432/hive_team39',
        'javax.jdo.option.ConnectionDriverName': 'org.postgresql.Driver',
        'javax.jdo.option.ConnectionUserName': 'hive_team39',
        'javax.jdo.option.ConnectionPassword': password,
        'hive.metastore.thrift.bind.host': ip,
        'metastore.thrift.bind.host': ip,
        'hive.metastore.port': '9083',
        'hadoop.proxyuser.hive.hosts': ip,
        'hadoop.proxyuser.hive.users': 'hive',
    })
    xml_file('/etc/hive-team39/metastore/hive-site.xml', metastore, private=True)
    xml_file('/etc/hive-team39/server/hive-site.xml', server)
    xml_file('/etc/hive-team39/client/hive-site.xml', {
        'hive.metastore.uris': f'thrift://{ip}:9083',
        'fs.defaultFS': nn_uri,
    })
    hadoop_conf = Path('/etc/hive-team39/hadoop')
    hadoop_conf.mkdir(exist_ok=True, mode=0o755)
    (hadoop_conf / 'hadoop-env.sh').write_text('export JAVA_HOME=/opt/hive-java8\n')
    core = ET.parse('/opt/hadoop/etc/hadoop/core-site.xml').getroot()
    core_properties = {p.findtext('name'): p.findtext('value') for p in core.findall('property')}
    core_properties.update({'hadoop.proxyuser.hive.hosts': ip, 'hadoop.proxyuser.hive.users': 'hive'})
    xml_file(hadoop_conf / 'core-site.xml', core_properties)
    for folder in ('metastore', 'server', 'client', 'hadoop'):
        for name in ('core-site.xml', 'hdfs-site.xml', 'yarn-site.xml', 'mapred-site.xml', 'log4j.properties'):
            link = Path('/etc/hive-team39') / folder / name
            if folder == 'hadoop' and name == 'core-site.xml':
                continue
            source = (Path('/opt/hadoop/etc/hadoop') if folder == 'hadoop' else hadoop_conf) / name
            if link.is_symlink() and link.readlink() != source:
                link.unlink()
            if not link.exists():
                link.symlink_to(source)
    Path('/etc/hive-team39/service.env').write_text('''JAVA_HOME=/opt/hive-java8
HIVE_HOME=/opt/hive
HADOOP_HOME=/opt/hadoop
HADOOP_MAPRED_HOME=/opt/hadoop
HADOOP_CONF_DIR=/etc/hive-team39/hadoop
HADOOP_LOG_DIR=/var/log/hive-team39
HIVE_LOG_DIR=/var/log/hive-team39
HADOOP_USER_NAME=hive
HIVESERVER2_PID_DIR=/var/lib/hive-team39
''')


if __name__ == '__main__':
    main()
