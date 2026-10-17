#!/bin/sh
# usage: scripts/stdlib-bench.sh [repeats] [name-prefix]
# Builds bench/perf/stdlib with ./ms (override with MS=), runs it `repeats` times (default 5), and prints the
# median ns per operation for each case, optionally limited to names starting with name-prefix.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
MS=${MS:-$ROOT/ms}
N=${1:-5}
FILTER=${2:-}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
cp -R "$ROOT/bench/perf/stdlib/." "$W/"
(cd "$W" && "$MS" build ms.toml -o stdlib-bench >/dev/null)
i=0
while [ "$i" -lt "$N" ]; do
	"$W/stdlib-bench" | grep -v '^#'
	i=$((i + 1))
done | python3 "$ROOT/scripts/stdlib_bench_table.py" "$FILTER"
