#!/bin/sh
# Compares the C visibility check (check_public.c: a public signature names no private type) with the Rust CLI's
# `ms check --json`, byte for byte: on every single-module file where Rust reports only that diagnostic or nothing,
# the C document must equal Rust's. The handcrafted cases of compiler/tests/public cover signatures, fields, cases,
# aliases, interface operations, bounds and defaults. Run from the repository root; the Rust `ms` is
# target/release/ms (or $MS_RUST).
set -eu
out=target/c-compiler/public
rust=$PWD/${MS_RUST:-target/release/ms}
rm -rf "$out"
mkdir -p "$out/c"
sh compiler/tests/cbuild.sh ms_resolve_dump
bin=target/cmake/test/compiler
{ ls compiler/tests/public/*.ms; git ls-files 'tests/*.ms' 'examples/*.ms'; } > "$out/files.txt"
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
    redundant=$(printf '%s\n' "$first" | grep -c '"message": "public signature exposes private type' || true)
    if [ "$messages" -ne "$redundant" ]; then continue; fi
    if [ "$messages" -eq 0 ]; then
        [ "$(grep -c '"message":' "$base.json")" -eq 0 ] || { echo "FAIL $file: C reports what Rust does not"; status=1; }
    else
        reported=$((reported + 1))
        printf '%s\n' "$first" | cmp -s - "$base.json" || { echo "FAIL $file"; printf '%s\n' "$first" | diff - "$base.json" | head -8; status=1; }
    fi
    compared=$((compared + 1))
done
echo "compared $compared files ($reported with public-signature errors)"
[ "$reported" -gt 0 ] || { echo "no redundant import compared"; status=1; }
exit $status
