#!/bin/sh
# Leak sweep (`make leak-check`, usable without make): runs the programs of the conformance corpus that finish
# normally against a runtime built with allocation counters (`ms-rt` feature `stats`), which prints the count of
# live heap blocks at exit. A correct program frees everything it allocated, so any nonzero count is a leak.
# Faulting and rejected programs print no count and are skipped. Arguments name the files to sweep instead.
set -eu
repository=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repository"

stats_target="${LEAK_TARGET_DIR:-$repository/target/leak-stats}"
# Linux programs link statically against musl and Windows ones against mingw-w64, so the counting runtime is built for that target too.
release=release
target=
case "$(uname -s)" in
    Linux)
        target="$(uname -m)-unknown-linux-musl"
        release="$target/release"
        export "CC_$(echo "$target" | tr - _)=${CC:-cc}"
        ;;
    MINGW*|MSYS*|CYGWIN*)
        # Windows programs link against the mingw-w64 (gnullvm) runtime, built with the bundled clang.
        # An emulated MSYS shell can report x86_64 on ARM64; match the installed Rust target.
        arch=$(rustc -vV | sed -n 's/^host: \([^-]*\)-.*/\1/p')
        target="$arch-pc-windows-gnullvm"
        release="$target/release"
        mingw="${MS_MINGW:-$repository/target/llvm-bundle/mingw}"
        export "CC_$(echo "$target" | tr - _)=$mingw/bin/$arch-w64-mingw32-clang"
        ;;
esac
CARGO_TARGET_DIR="$stats_target" cargo build --release --locked -q -p ms-native --features ms-rt/stats ${target:+--target "$target"}
cargo xtask runtime >/dev/null
cargo build --release --locked -q -p ms-cli --target-dir "$repository/target"
ms="$repository/target/release/ms"
MS_RT_LIB="$stats_target/$release/libms_native.a"
# `ms.exe` is a native program, which cannot read an MSYS path.
if command -v cygpath >/dev/null 2>&1; then MS_RT_LIB=$(cygpath -m "$MS_RT_LIB"); fi
export MS_RT_LIB

if [ "$#" -eq 0 ]; then
    # shellcheck disable=SC2046 # corpus paths hold no spaces
    set -- $(grep -rl 'def main' --include='*.ms' tests/conformance/fixtures/fuzz/run tests/conformance/fixtures/e2e tests/conformance/fixtures/examples | sort)
fi

# macOS has no timeout(1) by default; the sweep then runs unbounded.
limit=
if command -v timeout >/dev/null 2>&1; then
    limit="timeout 60"
fi
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
swept=0
leaks=0
for file in "$@"; do
    file=$(CDPATH='' cd -- "$(dirname -- "$file")" && pwd)/$(basename -- "$file")
    count=$(cd "$scratch" && $limit "$ms" run "$file" </dev/null 2>&1 >/dev/null | sed -n 's/^ms-rt live blocks at exit: //p' | awk '{ total += $1 } END { if (NR) print total }' || true)
    # A program that starts child processes prints one count per process; their sum is what leaked.
    [ -n "$count" ] || continue
    swept=$((swept + 1))
    if [ "$count" != 0 ]; then
        leaks=$((leaks + 1))
        echo "leak: $file left $count live blocks"
    fi
done
echo "swept $swept programs, $leaks leaking"
# A runtime that printed no count would otherwise pass without checking anything.
[ "$swept" -gt 0 ] || { echo "no program reported a live block count"; exit 1; }
[ "$leaks" -eq 0 ]
