#!/bin/sh
# usage: bench/perf/stdlib-bench.sh [samples] [name-prefix]
# Runs the `bench` blocks of bench/perf/stdlib with ./ms (override with MS=) under `ms bench`, taking `samples` timed samples
# per case (default 5), and prints the median ns per operation for each case, optionally limited to names containing the prefix.
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
MS=${MS:-$ROOT/ms}
N=${1:-5}
FILTER=${2:-}
cd "$ROOT/bench/perf/stdlib"
"$MS" bench ms.toml --json --samples "$N" --filter "$FILTER" | python3 "$ROOT/bench/perf/stdlib_bench_table.py"
