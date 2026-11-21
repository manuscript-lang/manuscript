#!/bin/sh
# Builds src/compiler/tests/run/lines.mir with `ms_mir_build --tables-meta`, clang and ms_asm_tables (no debug info is
# read) and links it with src/compiler/tests/asm_tables_check.c, which checks the tables the program hands the runtime.
# Run from the repository root: `make c-compiler-test`.
set -eu
out=target/c-compiler/asm-tables
mkdir -p "$out"
sh src/compiler/tests/cbuild.sh ms_mir_build ms_asm_tables
bin=target/cmake/test/compiler
case "$(uname -s)" in
Darwin) prefix=_ ;;
*) prefix= ;;
esac
# The tools leak their module on exit (the sanitizer build reports it); the leak is not what this checks.
export ASAN_OPTIONS=detect_leaks=0
# Debug locations in the IR, `clang -S`, the same tool with `--strip-lines` (no `.loc` is left
# in the program), and the same check against what clang's assembly gives (the calls inlined by the MIR optimizer
# have no code of their own at -O0, so their lines are the helper's).
"$bin/ms_mir_build" src/compiler/tests/run/lines.mir --opt none --tables-meta "$out/llvm.meta" > "$out/llvm.ll"
clang -S -O0 -Wno-override-module -o "$out/llvm.s" "$out/llvm.ll"
# A function the assembly lacks (LLVM inlined and removed it) is left out of the tables; it goes last, so the
# body numbers of the functions before it stay the same.
printf 'Y removed_function\t0\t1\tremoved_function\n' >> "$out/llvm.meta"
"$bin/ms_asm_tables" "$out/llvm.meta" "$out/llvm.s" --prefix "$prefix" --strip-lines > "$out/llvm.tables.s"
if grep -q '^[[:space:]]*\.loc' "$out/llvm.tables.s"; then echo "FAIL asm-tables llvm: .loc left in the output"; exit 1; fi
clang "$out/llvm.tables.s" -DMS_LLVM_LINES src/compiler/tests/asm_tables_check.c -o "$out/llvm"
"$out/llvm" && echo "ok   asm-tables llvm lines"
# Code of `inner` that LLVM inlined into `outer` (its function is gone): column 2 names the body of function 1 in
# the meta (one body number per function, counted after the scopes), which becomes a scope of its own.
"$bin/ms_asm_tables" src/compiler/tests/asm-tables/inlined.meta src/compiler/tests/asm-tables/inlined.s > "$out/inlined.tables.s"
clang "$out/inlined.tables.s" src/compiler/tests/asm_tables_inlined_check.c -o "$out/inlined"
"$out/inlined" && echo "ok   asm-tables inlined callee"
# The assembly LLVM writes for every platform the release builds target (ELF and Mach-O `.loc`, COFF `.cv_loc`,
# indented directives, labels with comments) takes the tables and still assembles for that platform.
printf 'F asm_tables_input.c\nY h\t0\t1\th\nY f\t0\t4\tf\n' > "$out/input.meta"
for entry in x86_64-linux-gnu: aarch64-linux-gnu: x86_64-apple-macos:_ aarch64-apple-macos:_ \
    x86_64-pc-windows-msvc: aarch64-pc-windows-msvc: x86_64-pc-windows-gnu:; do
    triple=${entry%%:*}
    pre=${entry#*:}
    clang -S -g -O1 --target="$triple" src/compiler/tests/asm_tables_input.c -o "$out/input.s"
    "$bin/ms_asm_tables" "$out/input.meta" "$out/input.s" --prefix "$pre" > "$out/input.tables.s"
    clang -c --target="$triple" "$out/input.tables.s" -o "$out/input.o"
    # Mach-O keeps only `L` labels out of its symbol table: a `.L` one splits the function into atoms, which breaks the
    # CFI of a large function in the assembler.
    case "$pre" in
    _) if grep -q '^\.Lms' "$out/input.tables.s"; then echo "FAIL asm-tables $triple: a .Lms label on Mach-O"; exit 1; fi ;;
    esac
    echo "ok   asm-tables $triple"
done
