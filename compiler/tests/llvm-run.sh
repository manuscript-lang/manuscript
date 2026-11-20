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
#include <sys/mman.h>
#include <ucontext.h>
typedef struct { uint8_t *ptr; uint64_t tagged; } Str;
extern long msmain(void);
long msrt_test_add(long a, long b) { return a + b; }
void msrt_test_str(long n, Str *out) { out->ptr = calloc((size_t)n + 1, 1); out->tagged = (uint64_t)n; }
long msrt_test_len(const Str *s) { return (long)s->tagged; }
void msrt_string_clone(const Str *s, Str *out) { out->ptr = malloc(s->tagged + 1); memcpy(out->ptr, s->ptr, s->tagged + 1); out->tagged = s->tagged; }
void msrt_string_free(const Str *s) { free(s->ptr); }
void *msrt_test_fn(void) { return malloc(8); }
void *msrt_obj_clone(void *o) { return o; }
void msrt_obj_drop(void *o) { (void)o; }
void msrt_fault_int_overflow(void) { exit(134); }
void msrt_fault_int_range(void) { exit(135); }
void msrt_fault_div_zero(void) { exit(136); }
void msrt_fault_rem_zero(void) { exit(137); }
void msrt_fault_div_overflow(long a, long b) { (void)a; (void)b; exit(138); }
void msrt_index_fault(long a, long b) { (void)a; (void)b; exit(139); }
long msrt_alloc(long n) { return (long)malloc((size_t)n); }
void msrt_free(long p) { free((void *)p); }
void msrt_cancelled(void) { exit(140); }
void msrt_fault_depth(void) { exit(141); }
/* The program runs on a stack inside a 256 MiB aligned region whose last 16 bytes are the cell the
   generated code reads: the task header (cancel flag at offset 8) and the stack limit. */
#define REGION (256UL << 20)
static uint64_t header[2];
static ucontext_t outer, inner;
static long result;
void msrt_test_cancel(void) { header[1] = 1; }
static void run(void) { result = msmain(); }
int main(void) {
    char *raw = mmap(0, 2 * REGION, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
    char *base = (char *)(((uintptr_t)raw + REGION - 1) & ~(REGION - 1));
    uint64_t *cell = (uint64_t *)(base + REGION - 16);
    cell[0] = (uint64_t)header;
    cell[1] = (uint64_t)(base + REGION - (1UL << 20) + 65536);
    getcontext(&inner);
    inner.uc_stack.ss_sp = base + REGION - (1UL << 20);
    inner.uc_stack.ss_size = (1UL << 20) - 4096;
    inner.uc_link = &outer;
    makecontext(&inner, run, 0);
    swapcontext(&outer, &inner);
    return (int)result;
}
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
