/* The runtime stand-ins the backend run tests link against (src/compiler/tests/run-run.sh and llvm-run.sh):
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
void msrt_test_list(long n, List *out) { out->ptr = NULL; out->len = (uint64_t)n; out->cap = 0; }
/* The length of a string value of any kind, plus 100 when the bytes of a non-inline one do not start with 'A'. */
void msrt_test_ints(List *out) {
    static int64_t values[3] = {10, 20, 30};
    out->ptr = (uint8_t *)values; out->len = 3; out->cap = 0;
}
void msrt_test_map(int64_t *out) { for (int64_t i = 0; i < 7; i++) { out[i] = i + 1; } }
long msrt_test_mapsum(const int64_t *w) { long s = 0; for (int i = 0; i < 7; i++) { s += w[i]; } return s; }
long msrt_test_slen(const Str *s) {
    if ((s->tagged >> 62) == 1) { return (long)((s->tagged >> 56) & 15); }
    return (long)(s->tagged & 0x7fffffff) + (s->ptr[0] == 'A' ? 0 : 100);
}
/* The last byte of a string that is not inline (its data must reach the end, not stop at a whole word). */
long msrt_test_last(const Str *s);
long msrt_test_last(const Str *s) { return (long)s->ptr[(s->tagged & 0x7fffffff) - 1]; }
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
/* The task header the region's cell points at: the cancel flag is its byte at offset 8. */
static uint64_t task_header[2];
void msrt_test_cancel(void) { task_header[1] = 1; }

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
    const uint64_t header = (uint64_t)(uintptr_t)task_header;
    memcpy(base + REGION - 16, &header, sizeof header);
    getcontext(&program_context);
    program_context.uc_stack.ss_sp = base + REGION - 4096 - (1 << 20);
    program_context.uc_stack.ss_size = 1 << 20;
    program_context.uc_link = &main_context;
    makecontext(&program_context, run_program, 0);
    swapcontext(&main_context, &program_context);
    return program_status;
}
