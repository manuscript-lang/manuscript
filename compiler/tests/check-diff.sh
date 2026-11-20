#!/bin/sh
# Compares the C checker's tables with the Rust checker's, byte for byte, and runs the C unit tests.
# Run from the repository root: `make c-compiler-test` runs this after syntax-diff.sh.
#   tables  the bundled standard library as loaded into the symbol tables (crates/ms-check c_oracle)
#   scope   the name-resolution diagnostics of every fixture that imports only `@std/` modules
# The set of compared things grows with each checker pass the C side gains; a pass is not
# "ported" until its line here passes.
set -eu
out=target/c-compiler
mkdir -p "$out"

cargo build --release --locked -p ms-check --example c_oracle
oracle=target/release/examples/c_oracle

cflags="-std=c11 -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=undefined -Wall -Wextra -Werror -Wno-format-truncation -Icompiler/include -Iruntime/include"
cc $cflags compiler/src/libms.c compiler/tools/ms_check_dump.c -o "$out/check-dump" -lm
cc $cflags compiler/src/libms.c compiler/tests/types_test.c -o "$out/types-test" -lm
cc $cflags compiler/src/libms.c compiler/tests/ownership_test.c -o "$out/ownership-test" -lm
cc $cflags compiler/src/libms.c compiler/tests/recursion_test.c -o "$out/recursion-test" -lm
"$out/ownership-test"
"$out/types-test"
"$out/recursion-test"

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
# Name resolution: the diagnostics of the families the C pass implements, for the scope fixtures
# and the whole conformance corpus. The files must produce some, or the comparison proves nothing.
files=$(find compiler/tests/scope tests/conformance/fixtures -name '*.ms' | sort)
"$oracle" --scope $files > "$out/scope.rust"
"$out/check-dump" stdlib --scope $files > "$out/scope.c"
# The Rust checker stops before every pass when desugaring an inherent `impl` fails; the C
# checker does not desugar yet, so those files are left out of the comparison until it does.
drop_unchecked() {
    awk -v list="$out/scope.unchecked" '
        BEGIN { while ((getline line < list) > 0) skip[line] = 1 }
        /^== / { dropped = ($2 in skip) }
        !dropped { print }' "$1"
}
awk '/^== / { file = $2 } /^unchecked$/ { print file }' "$out/scope.rust" > "$out/scope.unchecked"
drop_unchecked "$out/scope.rust" > "$out/scope.rust.kept"
drop_unchecked "$out/scope.c" > "$out/scope.c.kept"
mv "$out/scope.rust.kept" "$out/scope.rust"
mv "$out/scope.c.kept" "$out/scope.c"
if cmp -s "$out/scope.rust" "$out/scope.c" && [ -s "$out/scope.rust" ]; then
    echo "ok   scope ($(grep -c "^[0-9]*:[0-9]*: " "$out/scope.rust") diagnostics, $(grep -c "^typeref" "$out/scope.rust") type references)"
else
    echo "FAIL scope: first difference"
    diff "$out/scope.rust" "$out/scope.c" | head -20 || true
    status=1
fi
exit $status
