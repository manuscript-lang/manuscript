#!/bin/sh
# Compares the C front end with the Rust one, byte for byte (the formatter has no Rust version left), on every Manuscript file in the
# repository and on mutated copies of them (token streams, and syntax trees once the parser exists).
# Run from the repository root: `make c-compiler-test`. MS_FUZZ sets the mutant count (default 3000;
# the nightly run uses more); MS_FUZZ_SEED picks the files.
set -eu
out=target/c-compiler
mkdir -p "$out"
fuzz=${MS_FUZZ:-3000}
seed=${MS_FUZZ_SEED:-1}

cargo build --release --locked -p ms-syntax --example c_oracle
oracle=target/release/examples/c_oracle

sh compiler/tests/cbuild.sh ms_syntax_dump mutate
bin=target/cmake/test/compiler

git ls-files '*.ms' > "$out/files.txt"
rm -rf "$out/fuzz"
mkdir -p "$out/fuzz"
"$bin/mutate" "$out/fuzz" "$fuzz" "$seed" "$out/files.txt"
ls "$out"/fuzz/*.ms > "$out/fuzz.txt"
# Re-laid-out copies of whole files: valid syntax the formatter has work to do on.
rm -rf "$out/layout"
mkdir -p "$out/layout"
"$bin/mutate" "$out/layout" "$fuzz" "$seed" "$out/files.txt" layout
ls "$out"/layout/*.ms > "$out/layout.txt"

status=0
for mode in ${MS_MODES:-tokens ast codes partial ids}; do
    for set in files fuzz layout; do
        # The layout set is for the formatter alone (below).
        if [ "$set" = layout ]; then
            continue
        fi
        # xargs keeps the command line short and the oracle's per-process cost low.
        tr '\n' '\0' < "$out/$set.txt" | xargs -0 "$oracle" "$mode" > "$out/$mode-$set.rust"
        tr '\n' '\0' < "$out/$set.txt" | xargs -0 "$bin/ms_syntax_dump" "$mode" > "$out/$mode-$set.c"
        if cmp -s "$out/$mode-$set.rust" "$out/$mode-$set.c"; then
            echo "ok   $mode $set ($(grep -c '^===' "$out/$mode-$set.rust") files)"
        else
            echo "FAIL $mode $set: first difference"
            diff "$out/$mode-$set.rust" "$out/$mode-$set.c" | head -20 || true
            status=1
        fi
    done
done
# The formatter, over the same sets: formatted output formats to itself. Its cases with expected output are
# compiler/tests/format-golden.sh; the Rust formatter it replaced matched it on every set here.
for set in files fuzz layout; do
    tr '\n' '\0' < "$out/$set.txt" | xargs -0 "$bin/ms_syntax_dump" stable | grep -v -e '^===' -e '^error invalid-utf8' > "$out/stable-$set.c" || true
    if [ -s "$out/stable-$set.c" ]; then
        echo "FAIL format $set: output is not stable"
        head -5 "$out/stable-$set.c"
        status=1
    else
        echo "ok   format $set"
    fi
done
# Codes of messages in every phase: the committed list of phase<TAB>message lines.
"$oracle" codes compiler/tests/codes.txt | sed 1d > "$out/codes-list.rust"
"$bin/ms_syntax_dump" codes compiler/tests/codes.txt | sed 1d > "$out/codes-list.c"
if cmp -s "$out/codes-list.rust" "$out/codes-list.c"; then
    echo "ok   codes list ($(wc -l < "$out/codes-list.rust") messages)"
else
    echo "FAIL codes list: first difference"
    diff "$out/codes-list.rust" "$out/codes-list.c" | head -20 || true
    status=1
fi
exit $status
