#!/bin/sh
# Compares the C checker's tables with the Rust checker's, byte for byte, and runs the C unit tests.
# Run from the repository root: `make c-compiler-test` runs this after syntax-diff.sh.
#   tables  the bundled standard library as loaded into the symbol tables (crates/ms-check c_oracle)
# The set of compared things grows with each checker pass the C side gains; a pass is not
# "ported" until its line here passes.
set -eu
out=target/c-compiler
mkdir -p "$out"

cargo build --release --locked -p ms-check --example c_oracle
oracle=target/release/examples/c_oracle

cflags="-std=c11 -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=undefined -Wall -Wextra -Werror -Wno-format-truncation -Icompiler/include"
cc $cflags compiler/src/libms.c compiler/tools/ms_check_dump.c -o "$out/check-dump"
cc $cflags compiler/src/libms.c compiler/tests/types_test.c -o "$out/types-test"
"$out/types-test"

status=0
"$oracle" > "$out/tables.rust"
"$out/check-dump" stdlib > "$out/tables.c"
if cmp -s "$out/tables.rust" "$out/tables.c"; then
    echo "ok   tables ($(grep -c '^module' "$out/tables.rust") native modules)"
else
    echo "FAIL tables: first difference"
    diff "$out/tables.rust" "$out/tables.c" | head -20 || true
    status=1
fi
exit $status
