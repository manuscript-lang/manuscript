#!/bin/sh
# Compares src/compiler/src/syntax/fixes.c with the fix builders of crates/ms-check/src/suggestions.rs
# (crates/ms-syntax/examples/c_fixes_oracle.rs holds them verbatim) on random cases. Run from the
# repository root. FIXES_CASES and FIXES_SEED size and seed the run.
set -eu
out=target/c-compiler
mkdir -p "$out"
cases=${FIXES_CASES:-20000}
seed=${FIXES_SEED:-1}

cargo build --release --locked -p ms-syntax --example c_fixes_oracle
oracle=target/release/examples/c_fixes_oracle
sh src/compiler/tests/cbuild.sh ms_fixes_dump
bin=target/cmake/test/compiler

"$oracle" gen "$cases" "$seed" > "$out/fixes.cases"
"$oracle" < "$out/fixes.cases" > "$out/fixes.rust"
"$bin/ms_fixes_dump" < "$out/fixes.cases" > "$out/fixes.c.out"
if cmp -s "$out/fixes.rust" "$out/fixes.c.out"; then
    echo "fixes: $(wc -l < "$out/fixes.cases") cases identical"
else
    diff "$out/fixes.rust" "$out/fixes.c.out" | head -20
    echo "fixes: C and Rust differ" >&2
    exit 1
fi
