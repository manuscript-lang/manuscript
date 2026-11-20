#!/bin/sh
# Compiles each compiler/tests/qbe/*.mir through the C MIR reader, the C LLVM emitter and clang,
# runs it, and compares its exit status with the .exit file beside it (the QBE backend's programs:
# both backends take the same scalar subset and the same convention).
# Run from the repository root: `make c-compiler-test`.
set -eu
out=target/c-compiler/llvm
mkdir -p "$out"
sh compiler/tests/cbuild.sh ms_mir_llvm
bin=target/cmake/test/compiler
cat > "$out/rt.c" <<'C'
#include <stdlib.h>
extern long msmain(void);
void msrt_fault_int_overflow(void) { exit(134); }
int main(void) { return (int)msmain(); }
C
status=0
for mir in compiler/tests/qbe/*.mir compiler/tests/llvm/*.mir; do
    name=${mir%.mir}
    base=$(basename "$name")
    "$bin/ms_mir_llvm" "$mir" > "$out/$base.ll"
    clang -O2 -Wno-override-module "$out/$base.ll" "$out/rt.c" -o "$out/$base"
    got=0
    "$out/$base" || got=$?
    want=$(cat "$name.exit")
    if [ "$got" = "$want" ]; then echo "ok   llvm $base"; else echo "FAIL llvm $base: exit $got, want $want"; status=1; fi
done
exit $status
