#!/bin/sh
# usage: run.sh [repeats]; BENCH_OUTPUT retains binaries, input and raw samples.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
MS=${MS:-$ROOT/ms}; GO=${GO:-$ROOT/toolchain/go/bin/go}; N=${1:-7}
case "$N" in ''|*[!0-9]*|0) echo 'repeats must be a positive integer' >&2; exit 2;; esac
MS=$(command -v "$MS"); GO=$(command -v "$GO")
case "$MS" in /*) ;; *) MS="$(pwd)/$MS";; esac
case "$GO" in /*) ;; *) GO="$(pwd)/$GO";; esac
if [ -n "${BENCH_OUTPUT:-}" ]; then
  mkdir -p "$BENCH_OUTPUT"
  W=$(cd "$BENCH_OUTPUT" && pwd)
else
  W=$(mktemp -d)
  trap 'rm -rf "$W"' EXIT HUP INT TERM
fi
cp -r "$HERE/go" "$HERE/ms" "$W/"
python3 -c "
for i in range(200000): print('2026-03-01T00:00:00Z 10.1.2.3 GET /api/users/%d 200'%i)" > "$W/lines.txt"
(cd "$W/go" && CGO_ENABLED=0 "$GO" build -buildvcs=false -trimpath -ldflags="-s -w -buildid=" -o bench .)
(cd "$W/ms" && rm -f ms.lock && "$MS" build ms.toml -o bench >&2)
"$GO" version > "$W/environment.txt"
uname -sm >> "$W/environment.txt"
: > "$W/raw.txt"
i=0
while [ "$i" -lt "$N" ]; do
  # Alternate which language runs first to reduce order and thermal bias.
  if [ $((i % 2)) -eq 0 ]; then versions='go ms'; else versions='ms go'; fi
  for v in $versions; do
    # Check the executable before filtering: a pipeline can hide its failure.
    "$W/$v/bench" < "$W/lines.txt" > "$W/sample.txt"
    sed "s/^/$v /" "$W/sample.txt" >> "$W/raw.txt"
  done
  i=$((i + 1))
done
python3 "$HERE/table.py" "$W/raw.txt" "$N"
