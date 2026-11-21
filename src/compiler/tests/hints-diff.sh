#!/bin/sh
# Compares src/compiler/src/syntax/hints.c with the Rust helpers it ports (src/compiler/tests/hints_oracle.rs holds
# them verbatim) on random queries. Run from the repository root. HINTS_CASES and HINTS_SEED size and
# seed the run.
set -eu
out=target/c-compiler
mkdir -p "$out"
cases=${HINTS_CASES:-20000}
seed=${HINTS_SEED:-1}

rustc --edition 2021 -O -o "$out/hints_oracle" src/compiler/tests/hints_oracle.rs
sh src/compiler/tests/cbuild.sh ms_hints_dump
bin=target/cmake/test/compiler

"$out/hints_oracle" gen "$cases" "$seed" > "$out/hints.cases"
"$out/hints_oracle" < "$out/hints.cases" > "$out/hints.rust"
"$bin/ms_hints_dump" < "$out/hints.cases" > "$out/hints.c.out"
if cmp -s "$out/hints.rust" "$out/hints.c.out"; then
    echo "hints: $(wc -l < "$out/hints.cases") queries identical"
else
    diff "$out/hints.rust" "$out/hints.c.out" | head -20
    echo "hints: C and Rust differ" >&2
    exit 1
fi
