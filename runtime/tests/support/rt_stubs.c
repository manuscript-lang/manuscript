/* What the Rust runtime provides to runtime/core in a real build, stubbed for the C unit tests: faults that
 * jump back to the test, the ASCII table, objects, the cleanup stack and the map functions. */
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms_rt/desc.h"
#include "ms_rt/alloc.h"
#include "ms_rt/task.h"
#include "rt_calls.h"
#include "rt_stubs.h"

jmp_buf *ms_test_fault;
char ms_test_fault_message[256];
uint8_t ms_test_fault_kind;
size_t ms_test_cleanups;

#define MAX_CLEANUPS 8
static void (*cleanup_run[MAX_CLEANUPS])(uint8_t *);
static uint8_t *cleanup_arg[MAX_CLEANUPS];

__attribute__((weak)) _Noreturn void msfault_raise(uint8_t kind, const uint8_t *msg, size_t len) {
    if (ms_test_fault == NULL) {
        fprintf(stderr, "fault: %.*s\n", (int)len, msg);
        abort();
    }
    const size_t n = len < sizeof ms_test_fault_message - 1 ? len : sizeof ms_test_fault_message - 1;
    memcpy(ms_test_fault_message, msg, n);
    ms_test_fault_message[n] = 0;
    ms_test_fault_kind = kind;
    while (ms_test_cleanups > 0) { /* a fault runs the pending cleanups, newest first, before it jumps */
        ms_test_cleanups--;
        cleanup_run[ms_test_cleanups](cleanup_arg[ms_test_cleanups]);
    }
    longjmp(*ms_test_fault, 1);
}

__attribute__((weak)) _Noreturn void msrt_fault(const uint8_t *msg, size_t len) { msfault_raise(0, msg, len); }
__attribute__((weak)) _Noreturn void msrt_fault_div_zero(void) { msfault_raise(4, (const uint8_t *)"division by zero", 16); }
__attribute__((weak)) _Noreturn void msrt_fault_rem_zero(void) { msfault_raise(4, (const uint8_t *)"remainder by zero", 17); }

__attribute__((weak)) _Noreturn void msrt_index_fault(int64_t index, int64_t length) {
    char text[96];
    int n = snprintf(text, sizeof text, "index %lld out of range for length %lld", (long long)index, (long long)length);
    msfault_raise(6, (const uint8_t *)text, (size_t)n);
}

__attribute__((weak)) _Noreturn void msrt_list_index_fault(int64_t operation, int64_t index, int64_t len) {
    char text[96];
    int n = snprintf(text, sizeof text, "list op %lld index %lld length %lld", (long long)operation, (long long)index,
                     (long long)len);
    msfault_raise(6, (const uint8_t *)text, (size_t)n);
}

__attribute__((weak)) size_t msrt_cleanup_push(void (*run)(uint8_t *), uint8_t *arg) {
    cleanup_run[ms_test_cleanups] = run;
    cleanup_arg[ms_test_cleanups] = arg;
    return ++ms_test_cleanups;
}

__attribute__((weak)) void msrt_cleanup_discard(size_t handle) { ms_test_cleanups = handle - 1; }

/* The tests run the rollback path: a comparator may jump out. */
__attribute__((weak)) uint8_t msrt_rollback_needed(void) { return 1; }

/* Weak: core_task_abi links the real one (runtime/core/task_abi.c), every other core test runs without a scheduler. */
__attribute__((weak)) void msrt_task_grow(MsGrowFn shim, void *block) { shim(block); }
