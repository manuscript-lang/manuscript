#!/bin/sh
# Runtime micro-benchmarks next to Go equivalents (ns per op; lower is better). Release build.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
target=${CARGO_TARGET_DIR:-$root/target}
(cd "$root" && cargo build -q --release -p ms-rt)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cc -O2 -fno-omit-frame-pointer -o "$work/bench" "$here/bench.c" "$target/release/libms_rt.a" -lpthread -ldl -lm
echo "== ms-rt (ns/op)"; "$work/bench"
echo "== Go (ns/op, per element = ns/op / N)"
(cd "$here" && go test -run xxx -bench . -benchtime 3x bench_test.go 2>&1 | grep Benchmark)
