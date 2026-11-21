#!/bin/sh
# Compares the C lowering's MIR with the Rust lowering's, function by function.
# Run from the repository root: `make c-compiler-test` runs this after check-diff.sh.
# Rust lowers a whole program and keeps only what `main` reaches; C lowers the functions the
# checker claims (compiler/src/check/check_body.c) and the pass supports (compiler/src/check/lower_body.c).
# Each function is keyed by file and name, and only the keys both sides produced are compared; a
# function C produced that Rust left out is unreachable from `main` and is not counted.
set -eu
export LC_ALL=C
out=target/c-compiler
mkdir -p "$out"

cargo build --release --locked -p ms-build --example c_lower_oracle
sh compiler/tests/cbuild.sh ms_lower_dump
dump=${MS_C_BUILD:-target/cmake/test}/compiler/ms_lower_dump

files=$(find compiler/tests/lower tests/conformance/fixtures -name '*.ms' | sort)
"$dump" stdlib $files > "$out/lower.c"
# Rust lowering is slow per file, so it runs only where C lowered something.
lowered_files=$(awk '/^=== / { file = $2 } /^fn @/ { print file }' "$out/lower.c" | sort -u)
target/release/examples/c_lower_oracle $lowered_files > "$out/lower.rust" 2>/dev/null

# Two constructs C lowers its own way: a `while` (Rust threads a parameter through the loop header
# as a block parameter, C keeps the one value it is) and a `match` (Rust tests the arms one by one,
# C branches once with `switch`, or `br_if` on a Bool). The dump tool marks a function holding one
# (`; divergent`); it is left out of the text comparison and the verifier checks it instead (the
# dump tool exits non-zero when a lowered function fails to verify).
# One line per function block: `file name|block with newlines as \n`, sorted by key.
# The copies of a generic function are `name`, `name.1`, ... in the order a lowering made them, which
# differs between the two (Rust takes bodies from a stack, C in declaration order). They are compared
# by name and signature: `@name.N` is read as `@name`, and the key carries the parameter and result types.
keyed() {
    sed -E 's/(@[A-Za-z_][A-Za-z_0-9]*)\.[0-9]+/\1/g' "$1" | awk '
        /^=== / { file = $2; next }
        /^; divergent$/ { looped = 1; next }
        /^fn @/ { name = $2; sub(/\(.*/, "", name); sig = $0; sub(/^fn @[^(]*/, "", sig); sub(/ (ret_borrowed|ret_view|export|!).*$/, "", sig)
                  key = file " " name " " sig; body = ""; infn = 1 }
        infn { body = body $0 "\\n" }
        infn && /^}/ { if (!looped) print key "|" body; infn = 0; looped = 0 }' | sort
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
# A function both sides emit once must have the same signature: parameter and result types, `move` modes and
# the `ret_borrowed`, `ret_view` and `export` flags, which callers lowered by either side rely on. The text
# comparison above keys on the types, so a function whose signature differs would be left out of it as
# a function only C produced; this lists them, divergent functions included.
signatures() {
    sed -E 's/(@[A-Za-z_][A-Za-z_0-9]*)\.[0-9]+/\1/g' "$1" | awk '
        /^=== / { file = $2; next }
        /^fn @/ { name = $2; sub(/\(.*/, "", name); sig = $0; sub(/^fn @[^(]*/, "", sig); sub(/ !.*$/, "", sig)
                  print file " " name "|" sig }' | sort
}
signatures "$out/lower.c" > "$out/sig.c"
signatures "$out/lower.rust" > "$out/sig.rust"
# Names each side emits once.
cut -d'|' -f1 "$out/sig.c" | uniq -u > "$out/sig.c.once"
cut -d'|' -f1 "$out/sig.rust" | uniq -u > "$out/sig.rust.once"
awk -F'|' -v c="$out/sig.c.once" -v r="$out/sig.rust.once" '
    BEGIN { while ((getline l < c) > 0) inc[l] = 1; while ((getline l < r) > 0) inr[l] = 1 }
    FNR == NR { if ($1 in inc && $1 in inr) csig[$1] = $2; next }
    ($1 in csig) && csig[$1] != $2 { printf "%s\n  C:    %s\n  Rust: %s\n", $1, csig[$1], $2; bad++ }
    END { exit bad > 0 }' "$out/sig.c" "$out/sig.rust" > "$out/sig.diff" || {
    echo "FAIL lower signatures: C and Rust differ on a function both emit"
    head -20 "$out/sig.diff"
    exit 1
}

if cmp -s "$out/lower.rust.compared" "$out/lower.c.compared" && [ -s "$out/lower.c.compared" ]; then
    echo "ok   lower ($(wc -l < "$out/lower.c.compared") functions compared of $(wc -l < "$out/lower.c.keyed") lowered in C)"
else
    echo "FAIL lower: first difference"
    diff "$out/lower.rust.compared" "$out/lower.c.compared" | head -20 || true
    exit 1
fi

# What the functions compute: the same calls on the C module and on the Rust one, for every function
# C lowered that Rust also emitted once. This is the check for the divergent constructs and holds for
# all the others as well.
"$dump" stdlib --run $lowered_files > "$out/run.c"
"$dump" --run-mir "$out/lower.rust" > "$out/run.rust"
# Each line keyed by file and function, then only the keys with as many lines on both sides.
run_keyed() { sed -E 's/^([^ ]+ [A-Za-z_][A-Za-z_0-9]*)\.[0-9]+\(/\1(/' "$1" | awk '{ print $1 " " substr($2, 1, index($2, "(") - 1) "|" $0 }' | sort; }
run_keyed "$out/run.c" > "$out/run.c.keyed"
run_keyed "$out/run.rust" > "$out/run.rust.keyed"
for side in c rust; do
    cut -d'|' -f1 "$out/run.$side.keyed" | uniq -c | awk '{ c = $1; $1 = ""; sub(/^ /, ""); print $0 "|" c }' | sort -t'|' -k1,1 > "$out/run.$side.counts"
done
join -t'|' "$out/run.c.counts" "$out/run.rust.counts" | awk -F'|' '$2 == $3 { print $1 }' > "$out/run.keys"
for side in c rust; do
    awk -F'|' -v list="$out/run.keys" 'BEGIN { while ((getline line < list) > 0) keep[line] = 1 } $1 in keep' "$out/run.$side.keyed" > "$out/run.$side.compared"
done
if cmp -s "$out/run.rust.compared" "$out/run.c.compared" && [ -s "$out/run.c.compared" ]; then
    echo "ok   lower run ($(wc -l < "$out/run.keys") functions, $(wc -l < "$out/run.c.compared") calls)"
else
    echo "FAIL lower run: first difference"
    diff "$out/run.rust.compared" "$out/run.c.compared" | head -20 || true
    exit 1
fi
