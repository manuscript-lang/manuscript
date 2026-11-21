#!/bin/sh
# Compares one family of C checker diagnostics with the Rust CLI's, byte for byte, through `ms check --json`.
# Usage: message-diff.sh NAME REGEX CASES_DIR
#   NAME      the family, for the output and the work directory
#   REGEX     an extended regular expression matching the start of every message of the family
#   CASES_DIR handcrafted cases (compiler/tests/<dir>/*.ms), compared along with every single-module .ms file
#             under tests/ and examples/
# On every file where Rust reports only that family or nothing, the C document (ms_resolve_dump: the full
# program check of the file) must equal Rust's. Run from the repository root; the Rust `ms` is
# target/release/ms (or $MS_RUST).
set -eu
name=$1
pattern=$2
cases=$3
out=target/c-compiler/$name
rust=$PWD/${MS_RUST:-target/release/ms}
rm -rf "$out"
mkdir -p "$out/c"
sh compiler/tests/cbuild.sh ms_resolve_dump
bin=target/cmake/test/compiler
{ ls "$cases"/*.ms; git ls-files 'tests/*.ms' 'examples/*.ms'; } > "$out/files.txt"
tr '\n' '\0' < "$out/files.txt" | xargs -0 "$bin/ms_resolve_dump" stdlib > "$out/c.txt"
# One file per source file: the C document of each.
awk -v dir="$out/c" '/^== /{n++; name=sprintf("%s/%05d", dir, n); print substr($0,4) > (name ".src"); next} {print > (name ".json")}' "$out/c.txt"
status=0
compared=0
reported=0
for src in "$out"/c/*.src; do
    base=${src%.src}
    file=$(cat "$src")
    [ "$(head -1 "$base.json" 2>/dev/null)" = "skipped" ] && continue
    first=$(cd "$(dirname "$file")" && "$rust" check "$(basename "$file")" --json 2>&1 || true)
    messages=$(printf '%s\n' "$first" | grep -c '"message":' || true)
    family=$(printf '%s\n' "$first" | grep -cE "\"message\": \"($pattern)" || true)
    if [ "$messages" -ne "$family" ]; then continue; fi
    if [ "$messages" -eq 0 ]; then
        [ "$(grep -c '"message":' "$base.json")" -eq 0 ] || { echo "FAIL $file: C reports what Rust does not"; status=1; }
    else
        reported=$((reported + 1))
        printf '%s\n' "$first" | cmp -s - "$base.json" || { echo "FAIL $file"; printf '%s\n' "$first" | diff - "$base.json" | head -8; status=1; }
    fi
    compared=$((compared + 1))
done
echo "compared $compared files ($reported with $name errors)"
[ "$reported" -gt 0 ] || { echo "no $name error compared"; status=1; }
exit $status
