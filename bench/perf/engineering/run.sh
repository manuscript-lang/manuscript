#!/bin/sh
# Engineering-task benchmark: the same everyday programs in Manuscript, C and Rust on generated input.
# Usage: MS=./target/release/ms sh bench/perf/engineering/run.sh [samples] [scale]
# Output of every sample is compared byte for byte with the C version; the table is the minimum wall
# time in ms (process start, stdin read and stdout included; compilation excluded).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
MS=${MS:-ms}
samples=${1:-5}
scale=${2:-1}
work=${BENCH_OUTPUT:-$(mktemp -d)}
mkdir -p "$work"

"$MS" run "$here/gen.ms" -- "$work/input" "$scale"
CC=${CC:-gcc}

tasks="logstats:access.log csvgroup:orders.csv wordfreq:words.txt sortrecords:records.txt grep:access.log"
printf '%-12s %10s %10s %10s %8s %8s\n' task ms c rust ms/c ms/rust
for t in $tasks; do
  name=${t%%:*}; file=$work/input/${t#*:}
  "$MS" build "$here/ms/$name.ms" -o "$work/${name}_ms" >/dev/null
  "$CC" -O2 -o "$work/${name}_c" "$here/c/$name.c"
  rustc -O -o "$work/${name}_rs" "$here/rust/$name.rs"
  "$work/${name}_c" <"$file" >"$work/$name.expected"
  best_ms=999999; best_c=999999; best_rs=999999
  i=0
  while [ "$i" -lt "$samples" ]; do
    for lang in ms c rs; do
      s=$(date +%s%N)
      "$work/${name}_$lang" <"$file" >"$work/$name.$lang.out"
      e=$(date +%s%N)
      cmp -s "$work/$name.expected" "$work/$name.$lang.out" || { echo "$name: $lang output differs" >&2; exit 1; }
      t_ms=$(( (e - s) / 1000000 ))
      eval "cur=\$best_$lang"
      [ "$t_ms" -lt "$cur" ] && eval "best_$lang=$t_ms"
    done
    i=$((i + 1))
  done
  awk -v n="$name" -v m="$best_ms" -v c="$best_c" -v r="$best_rs" 'BEGIN{printf "%-12s %10d %10d %10d %7.2fx %7.2fx\n", n, m, c, r, m/c, m/r}'
done
