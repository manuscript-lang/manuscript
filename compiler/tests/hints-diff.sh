#!/bin/sh
# Compares compiler/src/hints.c with the Rust helpers it ports (compiler/tests/hints_oracle.rs holds
# them verbatim) on random queries. Run from the repository root. HINTS_CASES and HINTS_SEED size and
# seed the run.
set -eu
out=target/c-compiler
mkdir -p "$out"
cases=${HINTS_CASES:-20000}
seed=${HINTS_SEED:-1}

rustc --edition 2021 -O -o "$out/hints_oracle" compiler/tests/hints_oracle.rs
cc -std=c11 -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=undefined -Wall -Wextra -Werror \
    -Icompiler/include -Iruntime/include compiler/src/libms.c compiler/tools/ms_hints_dump.c -o "$out/hints_dump" -lm

"$out/hints_oracle" gen "$cases" "$seed" > "$out/hints.cases"
"$out/hints_oracle" < "$out/hints.cases" > "$out/hints.rust"
"$out/hints_dump" < "$out/hints.cases" > "$out/hints.c.out"
if cmp -s "$out/hints.rust" "$out/hints.c.out"; then
    echo "hints: $(wc -l < "$out/hints.cases") queries identical"
else
    diff "$out/hints.rust" "$out/hints.c.out" | head -20
    echo "hints: C and Rust differ" >&2
    exit 1
fi
