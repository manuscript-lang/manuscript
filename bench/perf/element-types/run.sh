#!/bin/sh
# Element-type matrix: Manuscript against Rust (rustc -O), microseconds, min of N.
# MS=./target/release/ms sh bench/perf/element-types/run.sh 5
set -e
N=${1:-5}
MS=${MS:-ms}
D=$(dirname "$0")
T=$(mktemp -d)
"$MS" build "$D/elements.ms" -o "$T/ms" >/dev/null
rustc -O "$D/elements.rs" -o "$T/rs" 2>/dev/null
i=0
while [ "$i" -lt "$N" ]; do
	"$T/ms" | sed 's/^/ms /' >>"$T/all"
	"$T/rs" | sed 's/^/rust /' >>"$T/all"
	i=$((i + 1))
done
awk '{ k = $2; key = $1 SUBSEP k
	if (!(key in m) || $3 < m[key]) m[key] = $3
	chk[$1 SUBSEP k] = $4; if (!(k in seen)) { seen[k] = 1; order[++n] = k } }
	END { printf "%-18s %10s %10s %7s %s\n", "case", "ms us", "rust us", "ratio", "checksum"
	for (j = 1; j <= n; j++) { k = order[j]; a = m["ms" SUBSEP k]; b = m["rust" SUBSEP k]
		ok = (chk["ms" SUBSEP k] == chk["rust" SUBSEP k]) ? "same" : "DIFFERENT"
		printf "%-18s %10d %10d %7.2f %s\n", k, a, b, a / b, ok } }' "$T/all"
rm -rf "$T"
