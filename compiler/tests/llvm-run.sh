#!/bin/sh
# Compiles each compiler/tests/run/*.mir, compiler/tests/llvm/*.mir and compiler/tests/llvm-only/*.mir through
# the C MIR reader, the C LLVM emitter and clang, runs it, and compares its exit status with the .exit file beside it.
# Run from the repository root: `make c-compiler-test`.
set -eu
out=target/c-compiler/llvm
mkdir -p "$out"
sh compiler/tests/cbuild.sh ms_mir_llvm
bin=target/cmake/test/compiler
status=0
for mir in compiler/tests/run/*.mir compiler/tests/llvm/*.mir compiler/tests/llvm-only/*.mir; do
    name=${mir%.mir}
    base=$(basename "$name")
    "$bin/ms_mir_llvm" "$mir" > "$out/$base.ll"
    clang -O2 -Wno-override-module "$out/$base.ll" compiler/tests/backend_rt.c -o "$out/$base"
    got=0
    "$out/$base" || got=$?
    want=$(cat "$name.exit")
    if [ "$got" = "$want" ]; then echo "ok   llvm $base"; else echo "FAIL llvm $base: exit $got, want $want"; status=1; fi
done
# Pointers are `ptr` at a runtime call, so LLVM knows the block `free` takes is a pointer.
if grep -l 'msrt_free"(i64' "$out"/*.ll; then echo "FAIL llvm: msrt_free takes i64"; status=1; fi
exit $status
