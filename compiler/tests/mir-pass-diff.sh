#!/bin/sh
# Runs each MIR pass in both implementations on the same verified MIR (every .mir file in the
# repository and mutated copies of them) and compares the rewritten module, the changed flag and
# the cold blocks byte for byte. Run from the repository root: `make c-compiler-test`.
# To add a pass: write it, add its name to `run_pass` in c_pass_oracle.rs and ms_mir_pass.c, and
# to PASSES here. MS_MIR_FUZZ sets the mutant count (default 600).
set -eu
# The standard-library sources both debug_files ports look for, as a checkout has them.
MS_STDLIB_DIR=${MS_STDLIB_DIR:-$PWD/stdlib}
export MS_STDLIB_DIR
out=target/c-compiler/mir-pass
mkdir -p "$out"
fuzz=${MS_MIR_FUZZ:-600}
seed=${MS_FUZZ_SEED:-1}
PASSES=${MS_MIR_PASSES:-"expand expand-nochecks expand_owned unwind glue glue_expand elaborate elaborate-cancel frames copies"}

cargo build --release --locked -p ms-mir --example c_pass_oracle
oracle=target/release/examples/c_pass_oracle

sh compiler/tests/cbuild.sh ms_mir_pass mutate
bin=target/cmake/test/compiler

git ls-files '*.mir' > "$out/files.txt"
rm -rf "$out/fuzz"
mkdir -p "$out/fuzz"
"$bin/mutate" "$out/fuzz" "$fuzz" "$seed" "$out/files.txt" mir
# A mutant can hang the Rust parser (a stray token in a function header loops there); it is dropped.
: > "$out/fuzz.txt"
for f in "$out"/fuzz/*.mir; do
    if [ -n "$(timeout 3 "$oracle" valid "$f" 2> /dev/null)" ]; then echo "$f" >> "$out/fuzz.txt"; fi
done

status=0
for set in files fuzz; do
    cp "$out/$set.txt" "$out/valid-$set.txt"
    for pass in $PASSES; do
        list="$out/valid-$set.txt"
        # The Raw fixtures of elaborate are not verifier-clean until elaborated (the Rust tests only
        # verify the output), so that pass also runs on them whole.
        if [ "$pass" = elaborate ] && [ "$set" = files ]; then
            { cat "$list"; git ls-files 'compiler/tests/mir/elaborate/*.mir'; } | sort -u > "$out/elaborate-list.txt"
            list="$out/elaborate-list.txt"
        fi
        if [ "$pass" = elaborate-cancel ] && [ "$set" = files ]; then
            # The elaborate fixtures, made task programs, and the task fixtures themselves.
            mkdir -p "$out/task"
            { cat "$list"; git ls-files 'compiler/tests/mir/elaborate-cancel/*.mir'; } | sort -u > "$out/cancel-list.txt"
            for f in $(git ls-files 'compiler/tests/mir/elaborate/*.mir'); do
                t="$out/task/$(basename "$f")"
                { head -1 "$f"; echo 'extern @msrt_promise_start(int) -> int spawns_task'; tail -n +2 "$f"; } > "$t"
                echo "$t" >> "$out/cancel-list.txt"
            done
            list="$out/cancel-list.txt"
        fi
        tr '\n' '\0' < "$list" | xargs -0 "$oracle" pass "$pass" > "$out/$pass-$set.rust"
        tr '\n' '\0' < "$list" | xargs -0 "$bin/ms_mir_pass" pass "$pass" > "$out/$pass-$set.c"
        if [ -n "${MS_MIR_FREEZE:-}" ] && [ "$set" = files ]; then
            # Keeps the Rust output of this pass as the golden the C pass is checked against once
            # the Rust passes are gone (compiler/tests/mir-pass-frozen.sh).
            mkdir -p compiler/tests/mir/frozen
            cp "$list" "compiler/tests/mir/frozen/$pass.list"
            gzip -9nc "$out/$pass-$set.rust" > "compiler/tests/mir/frozen/$pass.out.gz"
        fi
        if cmp -s "$out/$pass-$set.rust" "$out/$pass-$set.c"; then
            echo "ok   mir pass $pass $set ($(wc -l < "$list") files)"
        else
            echo "FAIL mir pass $pass $set: first difference"
            diff "$out/$pass-$set.rust" "$out/$pass-$set.c" | head -20 || true
            status=1
        fi
    done
done
exit $status
