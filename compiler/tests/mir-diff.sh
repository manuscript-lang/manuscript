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

cc -std=c11 -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=undefined -Wall -Wextra -Werror \
    -Icompiler/include -Iruntime/include compiler/src/libms.c compiler/tools/ms_mir_dump.c -o "$out/dump" -lm
cc -std=c11 -O1 -Wall -Wextra -Werror compiler/tests/mutate.c -o "$out/mutate"

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
"$out/dump" ops > "$out/ops.c"
check ops "$out/ops.rust" "$out/ops.c"

git ls-files '*.mir' > "$out/files.txt"
rm -rf "$out/fuzz"
mkdir -p "$out/fuzz"
"$out/mutate" "$out/fuzz" "$fuzz" "$seed" "$out/files.txt" mir
: > "$out/fuzz.txt"
for f in "$out"/fuzz/*.mir; do
    rc=0
    timeout 3 "$oracle" print "$f" > /dev/null 2>&1 || rc=$?
    if [ "$rc" != 124 ]; then echo "$f" >> "$out/fuzz.txt"; fi
done

for set in files fuzz; do
    tr '\n' '\0' < "$out/$set.txt" | xargs -0 "$oracle" print > "$out/print-$set.rust"
    tr '\n' '\0' < "$out/$set.txt" | xargs -0 "$out/dump" print > "$out/print-$set.c"
    check "print $set ($(grep -c '^===' "$out/print-$set.rust") files)" "$out/print-$set.rust" "$out/print-$set.c"
done
for set in files fuzz; do
    tr '\n' '\0' < "$out/$set.txt" | xargs -0 "$oracle" analysis > "$out/analysis-$set.rust"
    tr '\n' '\0' < "$out/$set.txt" | xargs -0 "$out/dump" analysis > "$out/analysis-$set.c"
    check "analysis $set" "$out/analysis-$set.rust" "$out/analysis-$set.c"
done
for set in files fuzz; do
    tr '\n' '\0' < "$out/$set.txt" | xargs -0 "$oracle" boxing > "$out/boxing-$set.rust"
    tr '\n' '\0' < "$out/$set.txt" | xargs -0 "$out/dump" boxing > "$out/boxing-$set.c"
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
    tr '\n' '\0' < "$out/$set.txt" | xargs -0 "$out/dump" layout > "$out/layout-$set.c"
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
    tr '\n' '\0' < "$out/$set.txt" | xargs -0 "$out/dump" run > "$out/run-$set.c"
    check "run $set" "$out/run-$set.rust" "$out/run-$set.c"
done
# The optimisation passes: both implementations run one pass on the same verified module.
# MS_MIR_CORPUS names a folder of unoptimised modules (`ms emit` of the conformance fixtures) that
# is checked as well.
cp "$out/files.txt" "$out/opt-files.txt"
if [ -n "${MS_MIR_CORPUS:-}" ]; then find "$MS_MIR_CORPUS" -name '*.mir' | sort >> "$out/opt-files.txt"; fi
tr '\n' '\0' < "$out/opt-files.txt" | xargs -0 "$oracle" verified | tr '\n' '\0' > "$out/verified.0"
for pass in bytetake strfuse loopslot optparam ifconv reserve appendfast; do
    xargs -0 "$oracle" opt $pass < "$out/verified.0" > "$out/opt-$pass.rust"
    xargs -0 "$out/dump" opt $pass < "$out/verified.0" > "$out/opt-$pass.c"
    check "opt $pass ($(grep -c '^changed true' "$out/opt-$pass.rust") of $(grep -c '^===' "$out/opt-$pass.rust") changed)" "$out/opt-$pass.rust" "$out/opt-$pass.c"
done
exit $status

