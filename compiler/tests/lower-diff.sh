#!/bin/sh
# Compares the C lowering's MIR with the Rust lowering's, function by function.
# Run from the repository root: `make c-compiler-test` runs this after check-diff.sh.
# Rust lowers a whole program and keeps only what `main` reaches; C lowers the functions the
# checker claims (compiler/src/check_body.c) and the pass supports (compiler/src/lower_body.c).
# Each function is keyed by file and name, and only the keys both sides produced are compared; a
# function C produced that Rust left out is unreachable from `main` and is not counted.
set -eu
out=target/c-compiler
mkdir -p "$out"

cargo build --release --locked -p ms-build --example c_lower_oracle
cflags="-std=c11 -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=undefined -Wall -Wextra -Werror -Wno-format-truncation -Icompiler/include -Iruntime/include"
cc $cflags compiler/src/libms.c compiler/tools/ms_lower_dump.c -o "$out/lower-dump" -lm

files=$(find compiler/tests/lower tests/conformance/fixtures -name '*.ms' | sort)
"$out/lower-dump" stdlib $files > "$out/lower.c"
# Rust lowering is slow per file, so it runs only where C lowered something.
lowered_files=$(awk '/^=== / { file = $2 } /^fn @/ { print file }' "$out/lower.c" | sort -u)
target/release/examples/c_lower_oracle $lowered_files > "$out/lower.rust" 2>/dev/null

# One line per function block, `file name|block with newlines as \n`, sorted by key.
keyed() {
    awk '
        /^=== / { file = $2; next }
        /^fn @/ { name = $2; sub(/\(.*/, "", name); key = file " " name; body = ""; infn = 1 }
        infn { body = body $0 "\\n" }
        infn && /^}/ { print key "|" body; infn = 0 }' "$1" | sort
}
keyed "$out/lower.c" > "$out/lower.c.keyed"
keyed "$out/lower.rust" > "$out/lower.rust.all"
# A name Rust emits twice (a closure or an entry wrapper beside the function) is ambiguous: skip it.
cut -d'|' -f1 "$out/lower.rust.all" | uniq -u > "$out/lower.rust.keys"
awk -F'|' -v list="$out/lower.rust.keys" '
    BEGIN { while ((getline line < list) > 0) have[line] = 1 }
    $1 in have' "$out/lower.c.keyed" > "$out/lower.c.compared"
cut -d'|' -f1 "$out/lower.c.compared" > "$out/lower.compared.keys"
awk -F'|' -v list="$out/lower.compared.keys" '
    BEGIN { while ((getline line < list) > 0) keep[line] = 1 }
    $1 in keep' "$out/lower.rust.all" > "$out/lower.rust.compared"
if cmp -s "$out/lower.rust.compared" "$out/lower.c.compared" && [ -s "$out/lower.c.compared" ]; then
    echo "ok   lower ($(wc -l < "$out/lower.c.compared") functions compared of $(wc -l < "$out/lower.c.keyed") lowered in C)"
else
    echo "FAIL lower: first difference"
    diff "$out/lower.rust.compared" "$out/lower.c.compared" | head -20 || true
    exit 1
fi
