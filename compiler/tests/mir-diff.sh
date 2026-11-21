#!/bin/sh
# Compares the C MIR text reader and printer with the Rust ones, byte for byte, on every .mir file
# in the repository and on mutated copies (parse errors are compared by line). Also compares the
# opcode tables. Run from the repository root: `make c-compiler-test`. MS_MIR_FUZZ sets the mutant
# count (default 600). Mutants that hang the Rust parser (a stray token in a function header loops
# there) are dropped; the C parser reports an error for them.
set -eu
out=target/c-compiler/mir
mkdir -p "$out"
fuzz=${MS_MIR_FUZZ:-600}
seed=${MS_FUZZ_SEED:-1}

cargo build --release --locked -p ms-mir --example c_oracle
oracle=target/release/examples/c_oracle

sh compiler/tests/cbuild.sh ms_mir_dump mutate
bin=target/cmake/test/compiler

status=0
check() {
    # check NAME RUST_FILE C_FILE
    if cmp -s "$2" "$3"; then
        echo "ok   mir $1"
    else
        echo "FAIL mir $1: first difference"
        diff "$2" "$3" | head -20 || true
        status=1
    fi
}

"$oracle" ops > "$out/ops.rust"
"$bin/ms_mir_dump" ops > "$out/ops.c"
check ops "$out/ops.rust" "$out/ops.c"

git ls-files '*.mir' > "$out/files.txt"
rm -rf "$out/fuzz"
mkdir -p "$out/fuzz"
"$bin/mutate" "$out/fuzz" "$fuzz" "$seed" "$out/files.txt" mir
: > "$out/fuzz.txt"
for f in "$out"/fuzz/*.mir; do
    rc=0
    timeout 3 "$oracle" verify "$f" > "$out/one.txt" 2>&1 || rc=$?
    if [ "$rc" != 124 ] && ! grep -q '^oracle-panic' "$out/one.txt"; then echo "$f" >> "$out/fuzz.txt"; fi
done

for set in files fuzz; do
    tr '\n' '\0' < "$out/$set.txt" | xargs -0 "$oracle" print > "$out/print-$set.rust"
    tr '\n' '\0' < "$out/$set.txt" | xargs -0 "$bin/ms_mir_dump" print > "$out/print-$set.c"
    check "print $set ($(grep -c '^===' "$out/print-$set.rust") files)" "$out/print-$set.rust" "$out/print-$set.c"
done
for set in files fuzz; do
    tr '\n' '\0' < "$out/$set.txt" | xargs -0 "$oracle" analysis > "$out/analysis-$set.rust"
    tr '\n' '\0' < "$out/$set.txt" | xargs -0 "$bin/ms_mir_dump" analysis > "$out/analysis-$set.c"
    check "analysis $set" "$out/analysis-$set.rust" "$out/analysis-$set.c"
done
for set in files fuzz; do
    tr '\n' '\0' < "$out/$set.txt" | xargs -0 "$oracle" verify > "$out/verify-$set.rust"
    tr '\n' '\0' < "$out/$set.txt" | xargs -0 "$bin/ms_mir_dump" verify > "$out/verify-$set.c"
    check "verify $set" "$out/verify-$set.rust" "$out/verify-$set.c"
done
for set in files fuzz; do
    tr '\n' '\0' < "$out/$set.txt" | xargs -0 "$oracle" boxing > "$out/boxing-$set.rust"
    tr '\n' '\0' < "$out/$set.txt" | xargs -0 "$bin/ms_mir_dump" boxing > "$out/boxing-$set.c"
    check "boxing $set" "$out/boxing-$set.rust" "$out/boxing-$set.c"
done
# A mutant whose types contain themselves by value overflows the Rust layout's stack; the C layout
# reports it as failed instead, so such mutants are left out of the layout comparison.
: > "$out/layout-fuzz.txt"
while read -r f; do
    if timeout 3 "$oracle" layout "$f" > /dev/null 2>&1; then echo "$f" >> "$out/layout-fuzz.txt"; fi
done < "$out/fuzz.txt"
for set in files layout-fuzz; do
    tr '\n' '\0' < "$out/$set.txt" | xargs -0 "$oracle" layout > "$out/layout-$set.rust"
    tr '\n' '\0' < "$out/$set.txt" | xargs -0 "$bin/ms_mir_dump" layout > "$out/layout-$set.c"
    check "layout $set" "$out/layout-$set.rust" "$out/layout-$set.c"
done
# The interpreter: the program's output, exit code or fault, frames, and the drop and step counts.
# A mutant that panics the Rust interpreter (a malformed operand it indexes blindly) is left out.
: > "$out/run-fuzz.txt"
while read -r f; do
    if timeout 10 "$oracle" run "$f" > /dev/null 2>&1; then echo "$f" >> "$out/run-fuzz.txt"; fi
done < "$out/fuzz.txt"
for set in files run-fuzz; do
    tr '\n' '\0' < "$out/$set.txt" | xargs -0 "$oracle" run > "$out/run-$set.rust"
    tr '\n' '\0' < "$out/$set.txt" | xargs -0 "$bin/ms_mir_dump" run > "$out/run-$set.c"
    check "run $set" "$out/run-$set.rust" "$out/run-$set.c"
done
# The optimisation passes are checked against frozen goldens (compiler/tests/mir-pass-frozen.sh).
exit $status
