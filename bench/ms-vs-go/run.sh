#!/bin/sh
# usage: run.sh [repeats]   builds both versions in a scratch dir and prints a table
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
MS=${MS:-ms}; GO=${GO:-go}; N=${1:-7}
W=$(mktemp -d); cp -r "$HERE/go" "$HERE/ms" "$W/"
python3 -c "
for i in range(200000): print('2026-03-01T00:00:00Z 10.1.2.3 GET /api/users/%d 200'%i)" > "$W/lines.txt"
(cd "$W/go" && "$GO" build -o bench .)
(cd "$W/ms" && rm -f ms.lock && "$MS" build ms.toml -o bench)
for v in go ms; do
  for i in $(seq "$N"); do "$W/$v/bench" < "$W/lines.txt" | grep -v '^#' | sed "s/^/$v /"; done
done > "$W/raw.txt"
python3 "$HERE/table.py" "$W/raw.txt" "$N"
