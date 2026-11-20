#!/bin/sh
# Compares compiler/src/effects.c with crates/ms-check/src/effect_directives.rs (compiler/tests/effects_oracle.rs
# holds it verbatim) on random cases. Run from the repository root. EFFECTS_CASES and EFFECTS_SEED size
# and seed the run.
set -eu
out=target/c-compiler
mkdir -p "$out"
cases=${EFFECTS_CASES:-20000}
seed=${EFFECTS_SEED:-1}

rustc --edition 2021 -O -o "$out/effects_oracle" compiler/tests/effects_oracle.rs
cc -std=c11 -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=undefined -Wall -Wextra -Werror \
    -Icompiler/include -Iruntime/include compiler/src/libms.c compiler/tools/ms_effects_dump.c -o "$out/effects_dump" -lm

"$out/effects_oracle" gen "$cases" "$seed" > "$out/effects.cases"
"$out/effects_oracle" < "$out/effects.cases" > "$out/effects.rust"
"$out/effects_dump" < "$out/effects.cases" > "$out/effects.c.out"
if cmp -s "$out/effects.rust" "$out/effects.c.out"; then
    echo "effects: $(wc -l < "$out/effects.cases") cases identical"
else
    diff "$out/effects.rust" "$out/effects.c.out" | head -20
    echo "effects: C and Rust differ" >&2
    exit 1
fi
