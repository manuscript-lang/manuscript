#!/bin/sh
# usage: MS=target/release/ms sh bench/perf/workers/run.sh [repeats]
# Eight CPU-bound jobs (fib(38)) spread over 1, 2 and 4 workers; best wall time of N runs in ms.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
MS=${MS:-$ROOT/target/release/ms}
N=${1:-3}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
"$MS" build "$ROOT/bench/perf/workers/ms.toml" -o "$W/app" >/dev/null
now() { date +%s%N; }
one=""
printf '%-8s %10s %8s\n' workers 'best ms' speedup
for k in 1 2 4; do
	b=999999999
	i=0
	while [ "$i" -lt "$N" ]; do
		s=$(now)
		"$W/app" "$k" 8 38 >"$W/out"
		e=$(now)
		t=$(((e - s) / 1000000))
		[ "$t" -lt "$b" ] && b=$t
		i=$((i + 1))
	done
	[ -z "$one" ] && one=$b
	printf '%-8s %10s %8s\n' "$k" "$b" "$(awk "BEGIN{printf \"%.2fx\", $one/$b}")"
done
cat "$W/out"
