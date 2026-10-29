#!/bin/sh
# usage: MS=target/release/ms sh bench/perf/datastructures/run.sh [repeats]
# Core data-structure operations in Manuscript, Go and Rust (ns per operation, best of N).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
MS=${MS:-$ROOT/target/release/ms}
N=${1:-5}
case "$N" in ''|*[!0-9]*) echo 'repeats must be a positive integer' >&2; exit 2;; esac
if ! [ "$N" -gt 0 ] 2>/dev/null; then
	echo 'repeats must be a positive integer' >&2
	exit 2
fi
MS=$(command -v "$MS")
case "$MS" in /*) ;; *) MS="$(pwd)/$MS";; esac
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
(cd "$HERE/ms" && "$MS" build ms.toml -o "$W/ms" >/dev/null)
(cd "$HERE/go" && CGO_ENABLED=0 go build -o "$W/go" .)
rustc --edition 2021 -C opt-level=3 -C codegen-units=1 -o "$W/rs" "$HERE/rust/main.rs"
i=0
: > "$W/raw.txt"
order='ms go rs'
while [ "$i" -lt "$N" ]; do
	for v in $order; do
		"$W/$v" > "$W/sample.txt"
		sed "s/^/$v /" "$W/sample.txt" >> "$W/raw.txt"
		printf '%s # end\n' "$v" >> "$W/raw.txt"
	done
	order="${order#* } ${order%% *}"
	i=$((i + 1))
done
python3 "$HERE/table.py" "$W/raw.txt" "$N"
