#!/bin/sh
# usage: MS=target/release/ms bench/perf/workloads/run.sh [repeats]
# Realistic-program benchmark: builds the reference solutions of the small agent challenges
# (bench/agent/challenges/*/solutions) in Manuscript, Go and Rust, feeds each ~3 MB of its largest hidden
# stdin (repeated), checks that all three print identical output, and reports the minimum wall time in ms.
# Needs go and rustc on PATH. Unlike bench/perf/kernels, these are ordinary parsing/string/map programs.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
MS=${MS:-$ROOT/target/release/ms}
N=${1:-3}
case "$N" in ''|*[!0-9]*) echo 'repeats must be a positive integer' >&2; exit 2;; esac
if ! [ "$N" -gt 0 ] 2>/dev/null; then
	echo 'repeats must be a positive integer' >&2
	exit 2
fi
MS=$(command -v "$MS")
case "$MS" in /*) ;; *) MS="$(pwd)/$MS";; esac
if [ -n "${BENCH_OUTPUT:-}" ]; then
	mkdir -p "$BENCH_OUTPUT"
	W=$(mktemp -d "$BENCH_OUTPUT/workloads.XXXXXX")
	W=$(cd "$W" && pwd)
	printf 'Workload evidence: %s\n' "$W" >&2
else
	W=$(mktemp -d)
	trap 'rm -rf "$W"' EXIT HUP INT TERM
fi
printf '%-24s %8s %8s %8s %8s %8s\n' program 'ms ms' 'go ms' 'rust ms' 'ms/go' 'ms/rust' > "$W/table.pending"
for dir in "$ROOT"/bench/agent/challenges/c[0-4]*; do
	name=$(basename "$dir")
	mkdir -p "$W/$name/ms/src" "$W/$name/go" "$W/$name/rs"
	cp "$ROOT/bench/agent/templates/ms/ms.toml" "$W/$name/ms/"
	cp "$dir/solutions/ms/main.ms.ref" "$W/$name/ms/src/main.ms"
	cp "$dir/solutions/go/main.go.ref" "$W/$name/go/main.go"
	cp "$dir/solutions/rust/main.rs.ref" "$W/$name/rs/main.rs"
	(cd "$W/$name/go" && go mod init x >/dev/null 2>&1 && go build -buildvcs=false -o app .)
	(cd "$W/$name/rs" && rustc -O -o app main.rs)
	(cd "$W/$name/ms" && "$MS" build ms.toml -o app >/dev/null)
	python3 - "$dir/hidden/cases.json" "$W/$name/in" <<'PY'
import json, sys
cases = sorted(json.load(open(sys.argv[1])), key=lambda c: -len(c["stdin"]))
s = cases[0]["stdin"]
open(sys.argv[2], "w").write(s * max(1, 3_000_000 // max(1, len(s))))
PY
	python3 "$ROOT/bench/perf/workloads/measure.py" "$W/$name" "$N" "$name" >> "$W/table.pending"
done
mv "$W/table.pending" "$W/table.txt"
cat "$W/table.txt"
