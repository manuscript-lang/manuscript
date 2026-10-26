#!/bin/sh
# usage: MS=target/release/ms sh bench/perf/datastructures/run.sh [repeats]
# Core data-structure operations in Manuscript, Go and Rust (ns per operation, best of N).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
MS=${MS:-$ROOT/target/release/ms}
N=${1:-5}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
(cd "$HERE/ms" && "$MS" build ms.toml -o "$W/ms" >/dev/null)
(cd "$HERE/go" && CGO_ENABLED=0 go build -o "$W/go" .)
rustc --edition 2021 -C opt-level=3 -C codegen-units=1 -o "$W/rs" "$HERE/rust/main.rs"
i=0
: > "$W/raw.txt"
while [ "$i" -lt "$N" ]; do
	for v in ms go rs; do "$W/$v" | sed "s/^/$v /" >> "$W/raw.txt"; done
	i=$((i + 1))
done
python3 - "$W/raw.txt" <<'PY'
import sys
best = {}
for line in open(sys.argv[1]):
    v, name, ops, ns = line.split()
    per = int(ns) / int(ops)
    k = (name, v)
    best[k] = min(best.get(k, per), per)
names = list(dict.fromkeys(k[0] for k in best))
print(f"{'operation':34}{'ms':>9}{'go':>9}{'rust':>9}{'ms/go':>8}{'ms/rust':>9}")
for n in names:
    m, g, r = best[(n, 'ms')], best.get((n, 'go')), best.get((n, 'rs'))
    f = lambda x: f"{x:9.1f}" if x else f"{'-':>9}"
    print(f"{n:34}{f(m)}{f(g)}{f(r)}{(m/g if g else 0):8.2f}{(m/r if r else 0):9.2f}")
PY
