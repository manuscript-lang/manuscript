#!/bin/sh
# Checks the C entry validation (compiler/src/check/check_entry.c) on the cases of compiler/tests/entry against
# compiler/tests/entry/expected.txt, the output the Rust `ms check` agreed with. Run from the repository root.
set -eu
out=target/c-compiler/entry
rm -rf "$out"
mkdir -p "$out"
sh compiler/tests/cbuild.sh ms_entry_dump
bin=target/cmake/test/compiler
ls compiler/tests/entry/*.ms | tr '\n' '\0' | xargs -0 "$bin/ms_entry_dump" stdlib > "$out/c.txt"
if cmp -s "$out/c.txt" compiler/tests/entry/expected.txt; then
    echo "compared $(grep -c . "$out/c.txt") entry cases"
else
    diff compiler/tests/entry/expected.txt "$out/c.txt" | head -20
    exit 1
fi
