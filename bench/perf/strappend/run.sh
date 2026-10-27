#!/bin/sh
# usage: run.sh [repeats]; compares StringBuilder.append against Rust's String::push_str for pieces of 4 B to 8 KiB,
# min of N runs per size, in microseconds to build about 1 MB.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
MS=${MS:-$ROOT/ms}; RUSTC=${RUSTC:-rustc}; N=${1:-5}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT HUP INT TERM
cp -r "$HERE/ms" "$W/"
(cd "$W/ms" && rm -f ms.lock && "$MS" build ms.toml -o bench >&2)
"$RUSTC" --edition 2021 -C opt-level=3 -C codegen-units=1 -o "$W/rust" "$HERE/rust/main.rs"
: > "$W/raw.txt"
i=0
while [ "$i" -lt "$N" ]; do
  for v in ms rust; do
    if [ "$v" = ms ]; then "$W/ms/bench"; else "$W/rust"; fi | awk -v v="$v" -F'\t' '{print $1 "\t" v "\t" $2}' >> "$W/raw.txt"
  done
  i=$((i + 1))
done
sort -t'	' -k1,1 -k2,2 -k3,3n "$W/raw.txt" | awk -F'\t' '
  { key=$1 SUBSEP $2; if (!(key in best)) { best[key]=$3; if (!($1 in seen)) { seen[$1]=1; order[++n]=$1 } } }
  END { printf "%-12s %10s %10s %8s\n", "size", "ms_us", "rust_us", "ratio";
        for (i=1;i<=n;i++) { k=order[i]; m=best[k SUBSEP "ms"]; r=best[k SUBSEP "rust"]; printf "%-12s %10d %10d %7.2fx\n", k, m, r, (r>0? m/r : 0) } }'
