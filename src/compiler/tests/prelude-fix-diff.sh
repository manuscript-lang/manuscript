#!/bin/sh
# Compares src/compiler/src/syntax/prelude_fix.c with the redundant-prelude-import fix of
# crates/ms-check/src/prelude_imports.rs (crates/ms-syntax/examples/c_prelude_fix_oracle.rs holds it
# verbatim) on random import statements. Run from the repository root. PRELUDE_FIX_CASES and
# PRELUDE_FIX_SEED size and seed the run.
set -eu
out=target/c-compiler
mkdir -p "$out"
cases=${PRELUDE_FIX_CASES:-20000}
seed=${PRELUDE_FIX_SEED:-1}

cargo build --release --locked -p ms-syntax --example c_prelude_fix_oracle
oracle=target/release/examples/c_prelude_fix_oracle
sh src/compiler/tests/cbuild.sh ms_prelude_fix_dump
bin=target/cmake/test/compiler

"$oracle" gen "$cases" "$seed" > "$out/prelude_fix.cases"
"$oracle" < "$out/prelude_fix.cases" > "$out/prelude_fix.rust"
"$bin/ms_prelude_fix_dump" < "$out/prelude_fix.cases" > "$out/prelude_fix.c.out"
if cmp -s "$out/prelude_fix.rust" "$out/prelude_fix.c.out"; then
    echo "prelude_fix: $(wc -l < "$out/prelude_fix.cases") cases identical"
else
    diff "$out/prelude_fix.rust" "$out/prelude_fix.c.out" | head -20
    echo "prelude_fix: C and Rust differ" >&2
    exit 1
fi
