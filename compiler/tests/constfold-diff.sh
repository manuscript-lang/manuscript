#!/bin/sh
# Compares compiler/src/constfold.c with the Rust constant folding it ports
# (crates/ms-syntax/examples/c_fold_oracle.rs) on random arithmetic over literals. Run from the
# repository root. FOLD_CASES and FOLD_SEED size and seed the run.
set -eu
out=target/c-compiler
mkdir -p "$out"
cases=${FOLD_CASES:-20000}
seed=${FOLD_SEED:-1}

cargo build --release --locked -p ms-syntax --example c_fold_oracle
oracle=target/release/examples/c_fold_oracle
cc -std=c11 -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=undefined -Wall -Wextra -Werror \
    -Icompiler/include -Iruntime/include compiler/src/libms.c compiler/tools/ms_constfold_dump.c -o "$out/constfold_dump" -lm

"$oracle" gen "$cases" "$seed" > "$out/constfold.cases"
"$oracle" < "$out/constfold.cases" > "$out/constfold.rust"
"$out/constfold_dump" < "$out/constfold.cases" > "$out/constfold.c.out"
if cmp -s "$out/constfold.rust" "$out/constfold.c.out"; then
    echo "constfold: $(wc -l < "$out/constfold.cases") expressions identical"
else
    diff "$out/constfold.rust" "$out/constfold.c.out" | head -20
    echo "constfold: C and Rust differ" >&2
    exit 1
fi
