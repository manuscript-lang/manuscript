#!/bin/sh
# Runs each MIR pass in both implementations on the same verified MIR (every .mir file in the
# repository and mutated copies of them) and compares the rewritten module, the changed flag and
# the cold blocks byte for byte. Run from the repository root: `make c-compiler-test`.
# To add a pass: write it, add its name to `run_pass` in c_pass_oracle.rs and ms_mir_pass.c, and
# to PASSES here. MS_MIR_FUZZ sets the mutant count (default 600).
set -eu
out=target/c-compiler/mir-pass
mkdir -p "$out"
fuzz=${MS_MIR_FUZZ:-600}
seed=${MS_FUZZ_SEED:-1}
PASSES="exit_drops expand expand-nochecks expand_owned cancel_edges"

cargo build --release --locked -p ms-mir --example c_pass_oracle
oracle=target/release/examples/c_pass_oracle

cc -std=c11 -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=undefined -Wall -Wextra -Werror \
    -Icompiler/include -Iruntime/include compiler/src/libms.c compiler/tools/ms_mir_pass.c -lm -o "$out/pass"
cc -std=c11 -O1 -Wall -Wextra -Werror compiler/tests/mutate.c -o "$out/mutate"

git ls-files '*.mir' > "$out/files.txt"
rm -rf "$out/fuzz"
mkdir -p "$out/fuzz"
"$out/mutate" "$out/fuzz" "$fuzz" "$seed" "$out/files.txt" mir
# A mutant can hang the Rust parser (a stray token in a function header loops there); it is dropped.
: > "$out/fuzz.txt"
for f in "$out"/fuzz/*.mir; do
    if [ -n "$(timeout 3 "$oracle" valid "$f" 2> /dev/null)" ]; then echo "$f" >> "$out/fuzz.txt"; fi
done

status=0
for set in files fuzz; do
    cp "$out/$set.txt" "$out/valid-$set.txt"
    for pass in $PASSES; do
        tr '\n' '\0' < "$out/valid-$set.txt" | xargs -0 "$oracle" pass "$pass" > "$out/$pass-$set.rust"
        tr '\n' '\0' < "$out/valid-$set.txt" | xargs -0 "$out/pass" pass "$pass" > "$out/$pass-$set.c"
        if cmp -s "$out/$pass-$set.rust" "$out/$pass-$set.c"; then
            echo "ok   mir pass $pass $set ($(wc -l < "$out/valid-$set.txt") files)"
        else
            echo "FAIL mir pass $pass $set: first difference"
            diff "$out/$pass-$set.rust" "$out/$pass-$set.c" | head -20 || true
            status=1
        fi
    done
done
exit $status
