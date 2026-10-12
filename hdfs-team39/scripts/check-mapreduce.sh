#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/common.sh"
check_controller
HADOOP=/opt/hadoop/bin/hadoop
HDFS=/opt/hadoop/bin/hdfs
[[ -x "$HADOOP" && -x "$HDFS" ]] || { echo 'Missing Hadoop binaries on edge' >&2; exit 1; }
JAR=/opt/hadoop/share/hadoop/mapreduce/hadoop-mapreduce-examples-3.4.0.jar
[[ -f "$JAR" ]] || { echo "Missing $JAR" >&2; exit 1; }
BASE="/user/team/team39-wordcount-$(date +%Y%m%d-%H%M%S)-$$"
INPUT=$(mktemp)
OUTPUT=$(mktemp)
trap 'rm -f "$INPUT" "$OUTPUT"' EXIT
cat > "$INPUT" <<'EOF'
hadoop yarn hdfs
hadoop yarn
yarn mapreduce
hadoop hdfs
EOF
$HDFS dfs -mkdir -p "$BASE/input"
$HDFS dfs -put "$INPUT" "$BASE/input/words.txt"
echo "Running WordCount from $BASE/input to $BASE/output"
"$HADOOP" jar "$JAR" wordcount "$BASE/input" "$BASE/output"
$HDFS dfs -cat "$BASE/output/part-r-00000" > "$OUTPUT"
printf '\nActual results:\n'
cat "$OUTPUT"
python3 - "$OUTPUT" <<'PY'
from pathlib import Path
import sys
expected = {'hadoop': 3, 'hdfs': 2, 'mapreduce': 1, 'yarn': 3}
lines = Path(sys.argv[1]).read_text().splitlines()
actual = {}
for line in lines:
    name, count = line.split()
    actual[name] = int(count)
if actual != expected:
    raise SystemExit(f'FAIL: wanted {expected}, got {actual}')
print('PASS: WordCount output matches expected values')
PY
printf 'HDFS results kept at: %s/output\n' "$BASE"
