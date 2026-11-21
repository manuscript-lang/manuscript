#!/bin/sh
# The program's main and fault tables as their own LLVM unit: compiles a program and its tables unit
# separately, links them with a runtime whose msrt_start checks that the first line entry of the table
# holds a code address (the relocation of a code address into the blob), and runs it.
# Run from the repository root: `make c-compiler-test`.
set -eu
out=target/c-compiler/llvm-main
mkdir -p "$out"
sh src/compiler/tests/cbuild.sh ms_mir_llvm
bin=target/cmake/test/compiler
cat > "$out/rt.c" <<'C'
#include <stdint.h>
#include <stdlib.h>
long msrt_alloc(long n) { return (long)malloc((size_t)n); }
void msrt_free(long p) { free((void *)p); }
typedef long (*Entry)(void);
long msrt_start(long entry, long tables, long argc, long argv) {
    (void)argc; (void)argv;
    const uint64_t *table = (const uint64_t *)tables;
    const uint64_t *lines = (const uint64_t *)table[3]; /* the pointer at byte 24 */
    if (lines[0] == 0) return 90; /* a code address was left unrelocated */
    return ((Entry)entry)();
}
C
status=0
for name in closure data iface; do
    mir=src/compiler/tests/llvm/$name.mir
    "$bin/ms_mir_llvm" "$mir" --main "$out/$name.main.ll" > "$out/$name.ll"
    clang -O1 -Wno-override-module "$out/$name.ll" "$out/$name.main.ll" "$out/rt.c" -o "$out/$name"
    got=0
    "$out/$name" || got=$?
    want=$(cat "src/compiler/tests/llvm/$name.exit")
    if [ "$got" = "$want" ]; then echo "ok   llvm-main $name"; else echo "FAIL llvm-main $name: exit $got, want $want"; status=1; fi
done
exit $status
