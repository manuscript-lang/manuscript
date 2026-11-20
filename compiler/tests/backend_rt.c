/* The runtime stand-ins the backend run tests link against (compiler/tests/qbe-run.sh and llvm-run.sh):
 * test helpers, fault functions that exit with distinct statuses, and the entry point. */
#define _GNU_SOURCE
#define _XOPEN_SOURCE 700
#define _DARWIN_C_SOURCE
#include "backend_rt.h"

#include <stdlib.h>
#include <string.h>
#include <stdint.h>
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

/* The program runs on a stack inside a 256 MiB region aligned to its size, with the recursion limit
 * (zero, so `stack.low` is false) in the region's last word, as the generated code expects. */
#include <sys/mman.h>
#include <ucontext.h>
#define REGION ((uintptr_t)256 << 20)
static ucontext_t main_context, program_context;
static int program_status;
static void run_program(void) { program_status = (int)msmain(); }
int main(void) {
    uint8_t *raw = mmap(NULL, 2 * REGION, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
    if (raw == MAP_FAILED) return 99;
    uint8_t *base = (uint8_t *)(((uintptr_t)raw + REGION - 1) & ~(REGION - 1));
    const uint64_t zero = 0;
    memcpy(base + REGION - 8, &zero, sizeof zero);
    getcontext(&program_context);
    program_context.uc_stack.ss_sp = base + REGION - 4096 - (1 << 20);
    program_context.uc_stack.ss_size = 1 << 20;
    program_context.uc_link = &main_context;
    makecontext(&program_context, run_program, 0);
    swapcontext(&main_context, &program_context);
    return program_status;
}
