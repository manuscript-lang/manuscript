#!/bin/sh
# Compiles each src/compiler/tests/run/*.mir, src/compiler/tests/llvm/*.mir and src/compiler/tests/llvm-only/*.mir through
# the C MIR reader, the C LLVM emitter and clang, runs it, and compares its exit status with the .exit file beside it.
# Run from the repository root: `make c-compiler-test`.
set -eu
out=target/c-compiler/llvm
mkdir -p "$out"
sh src/compiler/tests/cbuild.sh ms_mir_llvm
bin=target/cmake/test/compiler
status=0
for mir in src/compiler/tests/run/*.mir src/compiler/tests/llvm/*.mir src/compiler/tests/llvm-only/*.mir; do
    name=${mir%.mir}
    base=$(basename "$name")
    "$bin/ms_mir_llvm" "$mir" > "$out/$base.ll"
    clang -O2 -Wno-override-module "$out/$base.ll" src/compiler/tests/backend_rt.c -o "$out/$base"
    got=0
    "$out/$base" || got=$?
    want=$(cat "$name.exit")
    if [ "$got" = "$want" ]; then echo "ok   llvm $base"; else echo "FAIL llvm $base: exit $got, want $want"; status=1; fi
done
# Pointers are `ptr` at a runtime call, so LLVM knows the block `free` takes is a pointer.
if grep -l 'msrt_free"(i64' "$out"/*.ll; then echo "FAIL llvm: msrt_free takes i64"; status=1; fi
# What the direct-emission test (crates/ms-cli/tests/llvm.rs) checks of the Rust emitter, for this one: a borrowed
# aggregate parameter is a readonly nocapture pointer, a register-only loop-free function is memory(none), and list
# element accesses carry the scalar alias class.
for fact in 'ptr nonnull readonly nocapture align 8 dereferenceable([0-9]*) %in0' 'willreturn nofree nosync memory(none)' 'load [a-z0-9]*, ptr %a[0-9]*, !tbaa !'; do
    if ! grep -lq -- "$fact" "$out"/*.ll; then echo "FAIL llvm: no function has: $fact"; status=1; fi
done
exit $status
