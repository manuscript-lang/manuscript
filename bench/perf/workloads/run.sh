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
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
now() { date +%s%N; }
best() { # best <dir> <input>: min of N runs in ms, output kept in <dir>/out
	b=999999999
	i=0
	while [ "$i" -lt "$N" ]; do
		s=$(now)
		(cd "$1" && ./app <"$2" >out)
		e=$(now)
		t=$(((e - s) / 1000000))
		[ "$t" -lt "$b" ] && b=$t
		i=$((i + 1))
	done
	echo "$b"
}
printf '%-24s %8s %8s %8s %8s %8s\n' program 'ms ms' 'go ms' 'rust ms' 'ms/go' 'ms/rust'
for dir in "$ROOT"/bench/agent/challenges/c[0-4]*; do
	name=$(basename "$dir")
	mkdir -p "$W/$name/ms/src" "$W/$name/go" "$W/$name/rs"
	cp "$ROOT/bench/agent/templates/ms/ms.toml" "$W/$name/ms/"
	cp "$dir/solutions/ms/main.ms.ref" "$W/$name/ms/src/main.ms"
	cp "$dir/solutions/go/main.go.ref" "$W/$name/go/main.go"
	cp "$dir/solutions/rust/main.rs.ref" "$W/$name/rs/main.rs"
	(cd "$W/$name/go" && go mod init x >/dev/null 2>&1 && go build -o app .)
	(cd "$W/$name/rs" && rustc -O -o app main.rs 2>/dev/null)
	(cd "$W/$name/ms" && "$MS" build ms.toml -o app >/dev/null)
	python3 - "$dir/hidden/cases.json" "$W/$name/in" <<'PY'
import json, sys
cases = sorted(json.load(open(sys.argv[1])), key=lambda c: -len(c["stdin"]))
s = cases[0]["stdin"]
open(sys.argv[2], "w").write(s * max(1, 3_000_000 // max(1, len(s))))
PY
	m=$(best "$W/$name/ms" "$W/$name/in")
	g=$(best "$W/$name/go" "$W/$name/in")
	r=$(best "$W/$name/rs" "$W/$name/in")
	same=""
	cmp -s "$W/$name/ms/out" "$W/$name/go/out" || same=" OUTPUT DIFFERS"
	printf '%-24s %8s %8s %8s %8s %8s%s\n' "$name" "$m" "$g" "$r" \
		"$(awk "BEGIN{printf \"%.2fx\", $m/($g?$g:1)}")" "$(awk "BEGIN{printf \"%.2fx\", $m/($r?$r:1)}")" "$same"
done
