#!/bin/sh
# The driver: unit tests for the stage table and parse entry point, then the thin `ms` executable
# run in front of the Rust `ms` (MS_RUST_CLI, default target/release/ms) to prove commands pass
# through unchanged. Run from the repository root: `make c-driver-test`.
set -eu
out=target/c-compiler
mkdir -p "$out"
cflags="-std=c11 -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=undefined -Wall -Wextra -Werror -Wno-format-truncation -Icompiler/include -Iruntime/include"
cc $cflags compiler/src/libms.c compiler/src/driver.c compiler/tests/driver_test.c -o "$out/driver_test"
"$out/driver_test"
cc $cflags compiler/src/libms.c compiler/src/driver.c compiler/tools/ms.c -o "$out/ms"

rust=${MS_RUST_CLI:-target/release/ms}
[ -x "$rust" ] || { echo "driver-test: build the Rust ms first (make build) or set MS_RUST_CLI"; exit 1; }
export MS_RUST_CLI="$rust"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
printf 'fn main() Int:\n\treturn 3\n' > "$tmp/a.ms"
for args in "--version" "help fmt" "check $tmp/a.ms" "fmt --check $tmp/a.ms" "run $tmp/a.ms" "bogus"; do
    set +e
    "$rust" $args > "$tmp/rust.out" 2> "$tmp/rust.err"; rs=$?
    "$out/ms" $args > "$tmp/c.out" 2> "$tmp/c.err"; cs=$?
    set -e
    if [ "$rs" != "$cs" ] || ! cmp -s "$tmp/rust.out" "$tmp/c.out" || ! cmp -s "$tmp/rust.err" "$tmp/c.err"; then
        echo "FAIL ms $args (status $rs vs $cs)"; exit 1
    fi
    echo "ok   ms $args (status $cs)"
done
MS_DRIVER_TRACE=1 "$out/ms" check "$tmp/a.ms" 2>&1 >/dev/null | grep -q 'check -> rust'
echo "ok   trace"
