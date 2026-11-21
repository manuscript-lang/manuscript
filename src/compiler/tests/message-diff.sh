#!/bin/sh
# Compares one family of C checker diagnostics with frozen goldens of the Rust CLI's `ms check --json`, byte for
# byte. Usage: message-diff.sh NAME REGEX CASES_DIR
#   NAME      the family, for the output and the work directory
#   REGEX     an extended regular expression matching the start of every message of the family
#   CASES_DIR handcrafted cases (src/compiler/tests/<dir>/*.ms), each with its Rust document in NAME.json beside it
# The C document (ms_resolve_dump: the full program check of the file) must equal the golden; where the golden
# holds no message, C must report none. Cases where Rust reports anything outside the family have no golden.
# MS_REGEN=1 rewrites the goldens from a Rust `ms` ($MS_RUST, default target/release/ms). Run from the repository
# root.
set -eu
name=$1
pattern=$2
cases=$3
out=target/c-compiler/$name
rm -rf "$out"
mkdir -p "$out/c"
if [ "${MS_REGEN:-}" = 1 ]; then
    rust=$PWD/${MS_RUST:-target/release/ms}
    for file in "$cases"/*.ms; do
        golden=${file%.ms}.json
        rm -f "$golden"
        first=$(cd "$cases" && "$rust" check "$(basename "$file")" --json 2>&1 || true)
        messages=$(printf '%s\n' "$first" | grep -c '"message":' || true)
        family=$(printf '%s\n' "$first" | grep -cE "\"message\": \"($pattern)" || true)
        [ "$messages" -eq "$family" ] && printf '%s\n' "$first" > "$golden"
    done
    exit 0
fi
sh src/compiler/tests/cbuild.sh ms_resolve_dump
bin=target/cmake/test/compiler
ls "$cases"/*.ms > "$out/files.txt"
tr '\n' '\0' < "$out/files.txt" | xargs -0 "$bin/ms_resolve_dump" src/stdlib > "$out/c.txt"
# One file per source file: the C document of each.
awk -v dir="$out/c" '/^== /{n++; name=sprintf("%s/%05d", dir, n); print substr($0,4) > (name ".src"); next} {print > (name ".json")}' "$out/c.txt"
status=0
compared=0
reported=0
for src in "$out"/c/*.src; do
    base=${src%.src}
    file=$(cat "$src")
    golden=${file%.ms}.json
    [ "$(head -1 "$base.json" 2>/dev/null)" = "skipped" ] && continue
    [ -f "$golden" ] || continue
    if [ "$(grep -c '"message":' "$golden")" -eq 0 ]; then
        [ "$(grep -c '"message":' "$base.json")" -eq 0 ] || { echo "FAIL $file: C reports what Rust does not"; status=1; }
    else
        reported=$((reported + 1))
        cmp -s "$golden" "$base.json" || { echo "FAIL $file"; diff "$golden" "$base.json" | head -8; status=1; }
    fi
    compared=$((compared + 1))
done
echo "compared $compared files ($reported with $name errors)"
[ "$reported" -gt 0 ] || { echo "no $name error compared"; status=1; }
exit $status
