#!/bin/sh
# Compares the C front end with the Rust one, byte for byte, on every Manuscript file in the
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

cc -std=c11 -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=undefined -Wall -Wextra -Werror \
    -Icompiler/include -Iruntime/include compiler/src/libms.c compiler/tools/ms_syntax_dump.c -o "$out/dump" -lm
cc -std=c11 -O1 -Wall -Wextra -Werror compiler/tests/mutate.c -o "$out/mutate"

git ls-files '*.ms' > "$out/files.txt"
rm -rf "$out/fuzz"
mkdir -p "$out/fuzz"
"$out/mutate" "$out/fuzz" "$fuzz" "$seed" "$out/files.txt"
ls "$out"/fuzz/*.ms > "$out/fuzz.txt"

status=0
for mode in ${MS_MODES:-tokens ast codes partial ids}; do
    for set in files fuzz; do
        # xargs keeps the command line short and the oracle's per-process cost low.
        tr '\n' '\0' < "$out/$set.txt" | xargs -0 "$oracle" "$mode" > "$out/$mode-$set.rust"
        tr '\n' '\0' < "$out/$set.txt" | xargs -0 "$out/dump" "$mode" > "$out/$mode-$set.c"
        if cmp -s "$out/$mode-$set.rust" "$out/$mode-$set.c"; then
            echo "ok   $mode $set ($(grep -c '^===' "$out/$mode-$set.rust") files)"
        else
            echo "FAIL $mode $set: first difference"
            diff "$out/$mode-$set.rust" "$out/$mode-$set.c" | head -20 || true
            status=1
        fi
    done
done
# Codes of messages in every phase: the committed list of phase<TAB>message lines.
"$oracle" codes compiler/tests/codes.txt | sed 1d > "$out/codes-list.rust"
"$out/dump" codes compiler/tests/codes.txt | sed 1d > "$out/codes-list.c"
if cmp -s "$out/codes-list.rust" "$out/codes-list.c"; then
    echo "ok   codes list ($(wc -l < "$out/codes-list.rust") messages)"
else
    echo "FAIL codes list: first difference"
    diff "$out/codes-list.rust" "$out/codes-list.c" | head -20 || true
    status=1
fi
exit $status
