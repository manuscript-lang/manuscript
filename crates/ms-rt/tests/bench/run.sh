#!/bin/sh
# Native runtime micro-benchmarks (ns per op; lower is better). Release build.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
target=${CARGO_TARGET_DIR:-$root/target}
case "$target" in /*) ;; *) target="$root/$target" ;; esac
(cd "$root" && cargo build -q --release --locked -p ms-native --target-dir "$target")
# The runtime's C half (lists, maps, descriptors, ...) is built by ms-rt's build script beside the Rust half.
c_archive=$(ls -t "$target"/release/build/ms-rt-*/out/libms_c.a 2>/dev/null | head -1 || true)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cc -O2 -fno-omit-frame-pointer -o "$work/bench" "$here/bench.c" "$target/release/libms_native.a" $c_archive -lpthread -ldl -lm
echo "== ms-rt (ns/op)"; "$work/bench"
