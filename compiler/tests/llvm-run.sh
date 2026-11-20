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
#include <string.h>
#include <stdint.h>
typedef struct { uint8_t *ptr; uint64_t tagged; } Str;
extern long msmain(void);
long msrt_test_add(long a, long b) { return a + b; }
void msrt_test_str(long n, Str *out) { out->ptr = calloc((size_t)n + 1, 1); out->tagged = (uint64_t)n; }
long msrt_test_len(const Str *s) { return (long)s->tagged; }
void msrt_string_clone(const Str *s, Str *out) { out->ptr = malloc(s->tagged + 1); memcpy(out->ptr, s->ptr, s->tagged + 1); out->tagged = s->tagged; }
void msrt_string_free(const Str *s) { free(s->ptr); }
void msrt_fault_int_overflow(void) { exit(134); }
void msrt_fault_int_range(void) { exit(135); }
void msrt_fault_div_zero(void) { exit(136); }
void msrt_fault_rem_zero(void) { exit(137); }
void msrt_fault_div_overflow(long a, long b) { (void)a; (void)b; exit(138); }
void msrt_index_fault(long a, long b) { (void)a; (void)b; exit(139); }
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
