#!/bin/sh
# usage: run.sh [repeats]; builds the competence kernels in Manuscript and Go and prints
# microseconds (min of N runs) and the Manuscript/Go ratio per kernel. Checksums must match.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
MS=${MS:-$ROOT/ms}; GO=${GO:-go}; N=${1:-5}
case "$N" in ''|*[!0-9]*|0) echo 'repeats must be a positive integer' >&2; exit 2;; esac
MS=$(command -v "$MS"); GO=$(command -v "$GO")
case "$MS" in /*) ;; *) MS="$(pwd)/$MS";; esac
case "$GO" in /*) ;; *) GO="$(pwd)/$GO";; esac
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT HUP INT TERM
cp -r "$HERE/go" "$HERE/ms" "$W/"
(cd "$W/go" && CGO_ENABLED=0 "$GO" build -buildvcs=false -trimpath -o bench .)
(cd "$W/ms" && rm -f ms.lock && "$MS" build ms.toml -o bench >&2)
: > "$W/raw.txt"
i=0
while [ "$i" -lt "$N" ]; do
  for v in go ms; do "$W/$v/bench" | sed "s/^/$v /" >> "$W/raw.txt"; done
  i=$((i + 1))
done
awk '
  { k = $2; v = $1; if (!((v, k) in t) || $3 < t[v, k]) t[v, k] = $3; sum[v, k] = $4
    if (!(k in seen)) { seen[k] = 1; order[++n] = k } }
  END {
    printf "%-16s %10s %10s %7s\n", "kernel", "go us", "ms us", "ms/go"
    for (j = 1; j <= n; j++) { k = order[j]
      bad = (sum["go", k] != sum["ms", k]) ? "  CHECKSUM MISMATCH" : ""
      printf "%-16s %10d %10d %6.2fx%s\n", k, t["go", k], t["ms", k], t["ms", k] / t["go", k], bad }
  }' "$W/raw.txt"
