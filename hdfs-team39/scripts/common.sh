#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/inventory.ini"
KEY="${HDFS_SSH_KEY:-$HOME/.ssh/team_internal}"
SSH_OPTIONS=(-i "$KEY" -o BatchMode=yes -o ConnectTimeout=10)
ssh_node() { ssh "${SSH_OPTIONS[@]}" "team@$1" "${@:2}"; }
scp_node() { scp -q "${SSH_OPTIONS[@]}" "$1" "team@$2:$3"; }
check_controller() {
  [[ $(hostname -s) == team-39-en ]] || { echo 'Run on team-39-en as team' >&2; exit 1; }
  [[ $(id -un) == team ]] || { echo 'Run as team, NOT with sudo' >&2; exit 1; }
  [[ -r "$KEY" ]] || { echo "Missing SSH key: $KEY" >&2; exit 1; }
}
