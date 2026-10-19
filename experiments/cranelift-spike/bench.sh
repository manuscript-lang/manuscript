#!/bin/sh
# usage: bench.sh [repeats]; runs the whole-program kernels built five ways
# and prints min-of-N microseconds with ratios to hand-written Go:
#   ms     today's Manuscript (Go backend)
#   c-ms   hand-written C with Manuscript semantics, clang -O2
#   cl     this spike: msc + Cranelift, checks and polls on
#   cl-unchecked  msc --no-checks --no-poll
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
K=$ROOT/bench/perf/kernels
MS=${MS:-$ROOT/ms}; GO=${GO:-$ROOT/toolchain/go/bin/go}; N=${1:-5}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT HUP INT TERM
(cd "$HERE" && cargo build --release -q)
MSC=$HERE/target/release/msc
cp -r "$K/go" "$K/ms" "$W/"
(cd "$W/go" && CGO_ENABLED=0 "$GO" build -buildvcs=false -trimpath -o bench .)
(cd "$W/ms" && rm -f ms.lock && "$MS" build ms.toml -o bench >&2)
mkdir -p "$W/c-ms" "$W/cl" "$W/cl-unchecked"
clang -O2 -std=c11 -ffp-contract=off "$K/c/ms.c" -o "$W/c-ms/bench"
"$MSC" "$HERE/kernels/main.ms" -o "$W/cl/bench"
"$MSC" "$HERE/kernels/main.ms" -o "$W/cl-unchecked/bench" --no-checks --no-poll
versions='go ms c-ms cl cl-unchecked'
: > "$W/raw.txt"
i=0
while [ "$i" -lt "$N" ]; do
  order=$versions
  r=0
  while [ "$r" -lt "$i" ]; do order="${order#* } ${order%% *}"; r=$((r + 1)); done
  for v in $order; do
    "$W/$v/bench" > "$W/sample.txt"
    sed "s/^/$v /" "$W/sample.txt" >> "$W/raw.txt"
  done
  i=$((i + 1))
done
python3 "$K/table.py" "$W/raw.txt"
