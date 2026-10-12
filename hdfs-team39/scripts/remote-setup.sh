#!/usr/bin/env bash

set -euo pipefail
if [[ $(id -un) != team ]]; then echo 'Run as team' >&2; exit 1; fi
sudo -n true
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq openjdk-11-jdk-headless tar >/dev/null
if ! id hdfs >/dev/null 2>&1; then
  sudo useradd --system --create-home --home-dir /var/lib/hdfs --shell /usr/sbin/nologin --user-group hdfs
fi

if [[ -e /opt/hadoop && ! -x /opt/hadoop/bin/hdfs ]]; then
  echo 'ERROR: /opt/hadoop exists but has no Hadoop executable' >&2; exit 1
fi
if [[ -x /opt/hadoop/bin/hdfs ]]; then
  installed_version="$(/opt/hadoop/bin/hadoop version 2>/dev/null | head -n 1 || true)"
  if [[ "$installed_version" != 'Hadoop 3.4.0' ]]; then
    echo "Existing Hadoop install is not 3.4.0: $installed_version. Refusing in-place upgrade/downgrade" >&2
    exit 1
  fi
fi
if [[ ! -x /opt/hadoop/bin/hdfs ]]; then
  [[ -f /tmp/hadoop-team39.tar.gz ]] || { echo 'Missing Hadoop archive' >&2; exit 1; }
  sudo mkdir -p /opt

  sudo tar -xzf /tmp/hadoop-team39.tar.gz -C /opt
  sudo mv /opt/hadoop-3.4.0 /opt/hadoop
fi
sudo install -d -m 0750 -o hdfs -g hdfs /var/lib/hdfs /var/lib/hdfs/name /var/lib/hdfs/data /var/lib/hdfs/tmp /var/log/hdfs
sudo install -d -m 0755 -o root -g root /opt/hadoop/etc/hadoop
for f in core-site.xml hdfs-site.xml workers; do
  sudo install -m 0644 -o root -g root "/tmp/team39-config/$f" "/opt/hadoop/etc/hadoop/$f"
done

sudo tee /opt/hadoop/etc/hadoop/hadoop-env.sh >/dev/null <<'EOF'
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export HADOOP_LOG_DIR=/var/log/hdfs
export HADOOP_HEAPSIZE_MAX=768m
EOF
sudo chmod 0644 /opt/hadoop/etc/hadoop/hadoop-env.sh
sudo rm -f /tmp/hadoop-team39.tar.gz
