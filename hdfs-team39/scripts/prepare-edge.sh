#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
check_controller
sudo -n true
sudo python3 "$ROOT/scripts/fix-hostnames-node.py"
sudo apt-get update -qq
sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-11-jdk-headless tar curl python3 >/dev/null
if [[ -e /opt/hadoop && ! -x /opt/hadoop/bin/hadoop ]]; then
  echo 'Found an unknown /opt/hadoop. Refusing to overwrite it.' >&2
  exit 1
fi
if [[ ! -x /opt/hadoop/bin/hadoop ]]; then
  VERSION=3.4.0
  BASE="https://archive.apache.org/dist/hadoop/common/hadoop-${VERSION}"
  mkdir -p "$ROOT/.cache"
  ARCHIVE="$ROOT/.cache/hadoop-${VERSION}.tar.gz"
  [[ -s "$ARCHIVE" ]] || curl -fL --retry 3 -o "$ARCHIVE" "$BASE/hadoop-${VERSION}.tar.gz"
  curl -fsSL --retry 3 -o "$ARCHIVE.sha512" "$BASE/hadoop-${VERSION}.tar.gz.sha512"
  expected="$(grep -oEi '[0-9a-f]{128}' "$ARCHIVE.sha512" | head -1)"
  actual="$(sha512sum "$ARCHIVE" | awk '{print $1}')"
  [[ "${expected,,}" == "${actual,,}" ]] || { echo 'Hadoop SHA-512 mismatch' >&2; exit 1; }
  sudo tar -xzf "$ARCHIVE" -C /opt
  sudo mv /opt/hadoop-3.4.0 /opt/hadoop
  sudo chown -R root:root /opt/hadoop
fi
[[ "$(/opt/hadoop/bin/hadoop version | head -1)" == 'Hadoop 3.4.0' ]] || {
  echo 'Expected Hadoop 3.4.0 in /opt/hadoop' >&2; exit 1;
}
if ! sudo grep -qE '^export JAVA_HOME=' /opt/hadoop/etc/hadoop/hadoop-env.sh; then
  echo 'export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64' | sudo tee -a /opt/hadoop/etc/hadoop/hadoop-env.sh >/dev/null
fi
for user in yarn mapred; do
  if ! id "$user" >/dev/null 2>&1; then
    sudo useradd --system --user-group --create-home --home-dir "/var/lib/$user" --shell /usr/sbin/nologin "$user"
  fi
  sudo install -d -m 0750 -o "$user" -g "$user" "/var/lib/$user" "/var/log/$user"
done
echo 'PASS: edge ready, Hadoop 3.4.0, OpenJDK 11, yarn/mapred users.'
