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
# A fault call sits in a block QBE may lay out away from its operation: each one is preceded by a `.loc` of the
# line that faults (4 and 5 in fault_line.mir), or the trace would name another line or none.
"$bin/ms_mir_build" compiler/tests/asm-tables/fault_line.mir --opt none --no-verify > "$out/fault_line.ssa"
"$bin/qbe" -t "$target" "$out/fault_line.ssa" > "$out/fault_line.s"
lines=$(awk '/\.loc 1 /{line=$3} /msrt_fault_int_overflow/{print line}' "$out/fault_line.s" | sort | tr '\n' ' ')
if [ "$lines" = "4 5 " ]; then echo "ok   asm-tables fault blocks"; else echo "FAIL asm-tables fault blocks: lines '$lines', want '4 5 '"; exit 1; fi
# The LLVM release path: debug locations in the IR, `clang -S`, the same tool with `--strip-lines` (no `.loc` is left
# in the program), and the same check against what clang's assembly gives (the calls inlined by the MIR optimizer
# have no code of their own at -O0, so their lines are the helper's).
"$bin/ms_mir_build" compiler/tests/qbe/lines.mir --backend llvm --opt none --tables-meta "$out/llvm.meta" > "$out/llvm.ll"
clang -S -O0 -Wno-override-module -o "$out/llvm.s" "$out/llvm.ll"
"$bin/ms_asm_tables" "$out/llvm.meta" "$out/llvm.s" --prefix "$prefix" --strip-lines > "$out/llvm.tables.s"
if grep -q '^[[:space:]]*\.loc' "$out/llvm.tables.s"; then echo "FAIL asm-tables llvm: .loc left in the output"; exit 1; fi
clang "$out/llvm.tables.s" -DMS_LLVM_LINES compiler/tests/asm_tables_check.c -o "$out/llvm"
"$out/llvm" && echo "ok   asm-tables llvm lines"
# The assembly LLVM writes for every platform the release builds target (ELF and Mach-O `.loc`, COFF `.cv_loc`,
# indented directives, labels with comments) takes the tables and still assembles for that platform.
printf 'F asm_tables_input.c\nY h\t0\t1\th\nY f\t0\t2\tf\n' > "$out/input.meta"
for entry in x86_64-linux-gnu: aarch64-linux-gnu: x86_64-apple-macos:_ aarch64-apple-macos:_ \
    x86_64-pc-windows-msvc: aarch64-pc-windows-msvc: x86_64-pc-windows-gnu:; do
    triple=${entry%%:*}
    pre=${entry#*:}
    clang -S -g -O1 --target="$triple" compiler/tests/asm_tables_input.c -o "$out/input.s"
    "$bin/ms_asm_tables" "$out/input.meta" "$out/input.s" --prefix "$pre" > "$out/input.tables.s"
    clang -c --target="$triple" "$out/input.tables.s" -o "$out/input.o"
    echo "ok   asm-tables $triple"
done
