#!/bin/sh
# Compares src/compiler/src/check/import_hints.c with the Rust import hints and export messages on random
# queries built from the standard library's own names, misspelled. Run from the repository root.
# IMPORT_CASES and IMPORT_SEED size and seed the run.
set -eu
out=target/c-compiler
mkdir -p "$out"
cases=${IMPORT_CASES:-20000}
seed=${IMPORT_SEED:-1}

cargo build --release --locked -p ms-check --example c_import_oracle
oracle=target/release/examples/c_import_oracle
sh src/compiler/tests/cbuild.sh ms_import_hints_dump
bin=target/cmake/test/compiler

"$oracle" gen "$cases" "$seed" > "$out/import-hints.cases"
"$oracle" < "$out/import-hints.cases" > "$out/import-hints.rust"
"$bin/ms_import_hints_dump" src/stdlib < "$out/import-hints.cases" > "$out/import-hints.c.out"
if cmp -s "$out/import-hints.rust" "$out/import-hints.c.out"; then
    echo "import hints: $(wc -l < "$out/import-hints.cases") queries identical"
else
    paste -d'\n' "$out/import-hints.cases" "$out/import-hints.rust" "$out/import-hints.c.out" > /dev/null
    diff "$out/import-hints.rust" "$out/import-hints.c.out" | head -20
    echo "import hints: C and Rust differ" >&2
    exit 1
fi
