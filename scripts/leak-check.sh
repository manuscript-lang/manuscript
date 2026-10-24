#!/bin/sh
# Leak sweep (`make leak-check`, usable without make): runs the programs of the conformance corpus that finish
# normally against a runtime built with allocation counters (`ms-rt` feature `stats`), which prints the count of
# live heap blocks at exit. A correct program frees everything it allocated, so any nonzero count is a leak.
# Faulting and rejected programs print no count and are skipped. Arguments name the files to sweep instead.
set -eu
repository=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repository"

stats_target="${LEAK_TARGET_DIR:-$repository/target/leak-stats}"
# Linux programs link statically against musl, so the counting runtime is a musl build too.
release=release
target=
if [ "$(uname -s)" = Linux ]; then
    target="$(uname -m)-unknown-linux-musl"
    release="$target/release"
    export "CC_$(echo "$target" | tr - _)=${CC:-cc}"
fi
CARGO_TARGET_DIR="$stats_target" cargo build --release --locked -q -p ms-native --features ms-rt/stats ${target:+--target "$target"}
cargo xtask runtime >/dev/null
cargo build --release --locked -q -p ms-cli
ms="$repository/target/release/ms"
MS_RT_LIB="$stats_target/$release/libms_native.a"
export MS_RT_LIB

if [ "$#" -eq 0 ]; then
    # shellcheck disable=SC2046 # corpus paths hold no spaces
    set -- $(grep -rl 'fn main' --include='*.ms' tests/conformance/fixtures/fuzz/run tests/conformance/fixtures/e2e tests/conformance/fixtures/examples | sort)
fi

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
swept=0
leaks=0
for file in "$@"; do
    file=$(CDPATH='' cd -- "$(dirname -- "$file")" && pwd)/$(basename -- "$file")
    count=$(cd "$scratch" && timeout 60 "$ms" run "$file" </dev/null 2>&1 >/dev/null | sed -n 's/^ms-rt live blocks at exit: //p' || true)
    [ -n "$count" ] || continue
    swept=$((swept + 1))
    if [ "$count" != 0 ]; then
        leaks=$((leaks + 1))
        echo "leak: $file left $count live blocks"
    fi
done
echo "swept $swept programs, $leaks leaking"
[ "$leaks" -eq 0 ]
