#!/bin/sh
# Builds compiler/tests/qbe/lines.mir with `ms_mir_build --tables-meta`, QBE and ms_asm_tables (no debug info is
# read) and links it with compiler/tests/asm_tables_check.c, which checks the tables the program hands the runtime.
# Run from the repository root: `make c-compiler-test`.
set -eu
out=target/c-compiler/asm-tables
mkdir -p "$out"
sh compiler/tests/cbuild.sh ms_mir_build ms_asm_tables qbe
bin=target/cmake/test/compiler
case "$(uname -s)-$(uname -m)" in
Darwin-arm64) target=arm64_apple prefix=_ ;;
Darwin-*) target=amd64_apple prefix=_ ;;
*-aarch64 | *-arm64) target=arm64 prefix= ;;
*) target=amd64_sysv prefix= ;;
esac
# The tools leak their module on exit (the sanitizer build reports it); the leak is not what this checks.
export ASAN_OPTIONS=detect_leaks=0
"$bin/ms_mir_build" compiler/tests/qbe/lines.mir --opt none --tables-meta "$out/lines.meta" > "$out/lines.ssa"
"$bin/qbe" -t "$target" "$out/lines.ssa" > "$out/lines.s"
"$bin/ms_asm_tables" "$out/lines.meta" "$out/lines.s" --prefix "$prefix" > "$out/lines.tables.s"
cc "$out/lines.tables.s" compiler/tests/asm_tables_check.c -o "$out/lines"
"$out/lines" && echo "ok   asm-tables lines"
