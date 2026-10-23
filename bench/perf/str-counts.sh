#!/bin/sh
# usage: str-counts.sh <ms.toml|file.ms>...
# Dynamic String copy and drop counts: builds each program with MS_COUNT_STR=1 against the counting
# runtime (`ms-rt` feature `stats`, as in scripts/leak-check.sh) and prints the totals the program
# reports at exit, split into static strings (no count to change) and owned ones. Owned copies are
# the allocations unique ownership would add; `bench/perf/copy-report.sh` counts the static sites.
set -eu
repository=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repository"
stats_target="${LEAK_TARGET_DIR:-$repository/target/leak-stats}"
release=release
target=
if [ "$(uname -s)" = Linux ]; then
    target="$(uname -m)-unknown-linux-musl"
    release="$target/release"
    export "CC_$(echo "$target" | tr - _)=${CC:-cc}"
fi
CARGO_TARGET_DIR="$stats_target" cargo build --release --locked -q -p ms-native --features ms-rt/stats ${target:+--target "$target"}
cargo build --release --locked -q -p ms-cli
ms="$repository/target/release/ms"
MS_RT_LIB="$stats_target/$release/libms_native.a"
export MS_RT_LIB
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
for program in "$@"; do
    echo "== $program"
    MS_COUNT_STR=1 "$ms" build "$program" -o "$scratch/program" >/dev/null
    "$scratch/program" 2>&1 >/dev/null | grep 'ms-rt string' || echo "(no string copies or drops)"
done
