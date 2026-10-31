#!/bin/sh
# Ownership count gate (`make count-check`, usable without make): runs the programs of tests/ownership-counts in Debug and
# Release against a runtime built with counters (`ms-rt` feature `stats`) and compares what they report with the
# `# expect-debug:` and `# expect-release:` headers (`key=value` pairs from the runtime's "ms-rt counts:" line; absent keys
# are not checked) and `# expect-stdout:` lines (the program's stdout, in order, on both). Cleanup order is the stdout lines.
# A change may not raise a count without a stated reason; update the header in the same change.
set -eu
repository=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repository"

stats_target="${LEAK_TARGET_DIR:-$repository/target/leak-stats}"
release=release
target=
case "$(uname -s)" in
    Linux)
        target="$(uname -m)-unknown-linux-musl"
        release="$target/release"
        export "CC_$(echo "$target" | tr - _)=${CC:-cc}"
        ;;
    MINGW*|MSYS*|CYGWIN*)
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
if command -v cygpath >/dev/null 2>&1; then MS_RT_LIB=$(cygpath -m "$MS_RT_LIB"); fi
export MS_RT_LIB

# The headers are written against Linux and macOS. A Windows process makes one more 16-byte allocation than they do in
# every counted program, release and debug alike (the 15 programs with count headers each report allocs +1 and
# alloc_bytes +16), so the Windows run adds that constant to the expectation instead of loosening any count.
startup_allocs=0
startup_bytes=0
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) startup_allocs=1; startup_bytes=16 ;;
esac

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
failures=0
checked=0
if [ "$#" -eq 0 ]; then
    set -- tests/ownership-counts/*.ms
fi
for file in "$@"; do
    expected_out=$(sed -n 's/^# expect-stdout: //p' "$file")
    for build in debug release; do
        (cd "$scratch" && "$ms" run "$repository/$file" --build-type "$build" >"$scratch/out" 2>"$scratch/err") || true
        counts=$(sed -n 's/^ms-rt counts: //p' "$scratch/err")
        live=$(sed -n 's/^ms-rt live blocks at exit: //p' "$scratch/err")
        checked=$((checked + 1))
        if [ "$live" != 0 ]; then
            failures=$((failures + 1))
            echo "leak: $file ($build) left ${live:-an unreported number of} live blocks"
        fi
        want=$(sed -n "s/^# expect-$build: //p" "$file")
        for pair in $want; do
            checked=$((checked + 1))
            case "$pair" in
                allocs=*) pair="allocs=$(( ${pair#allocs=} + startup_allocs ))" ;;
                alloc_bytes=*) pair="alloc_bytes=$(( ${pair#alloc_bytes=} + startup_bytes ))" ;;
            esac
            case " $counts " in
                *" $pair "*) ;;
                *)
                    failures=$((failures + 1))
                    echo "count: $file ($build) wants $pair; runtime reported: $counts"
                    ;;
            esac
        done
        if [ -n "$expected_out" ]; then
            checked=$((checked + 1))
            if [ "$(cat "$scratch/out")" != "$expected_out" ]; then
                failures=$((failures + 1))
                echo "stdout: $file ($build) differs:"
                cat "$scratch/out"
            fi
        fi
    done
done
echo "checked $checked expectations, $failures failing"
[ "$checked" -gt 0 ] || { echo "no expectations ran"; exit 1; }
[ "$failures" -eq 0 ]
