/* The equality cycle guard: while a comparison of two objects runs, the pair is registered, so a comparison that
 * reaches the same pair again (a cycle) assumes equal instead of recursing forever. The pairs live in the running
 * task's unwind state, so a task switch needs no copy and a guard that catches a fault drops what the fault left
 * behind (ms_guard_leave). */
#include "eq.h"
#include "array.h"
#include "fault.h"
#include "scheduler.h"

enum { MAX_EQ_DEPTH = 200000 };

uint8_t msrt_eq_enter(const uint8_t *a, const uint8_t *b) {
    MsUnwind *const unwind = &ms_task_running()->unwind;
    const uintptr_t left = (uintptr_t)a;
    const uintptr_t right = (uintptr_t)b;
    for (size_t i = 0; i < unwind->eq_length; i++) {
        if (unwind->eq_pairs[i][0] == left && unwind->eq_pairs[i][1] == right) {
            return 0; /* already comparing this pair: the comparison assumes equal */
        }
    }
    if (unwind->eq_length >= MAX_EQ_DEPTH) {
        static const char message[] = "equality comparison is nested too deeply";
        ms_fault(MS_FAULT_KIND_FAULT, ms_bytes_of((const uint8_t *)message, sizeof message - 1));
    }
    void *items = unwind->eq_pairs;
    if (!ms_array_reserve_system(&items, &unwind->eq_capacity, unwind->eq_length + 1, sizeof unwind->eq_pairs[0])) {
        return 1; /* out of memory: the allocator already faulted */
    }
    unwind->eq_pairs = items;
    unwind->eq_pairs[unwind->eq_length][0] = left;
    unwind->eq_pairs[unwind->eq_length][1] = right;
    unwind->eq_length++;
    return 1;
}

void msrt_eq_leave(const uint8_t *a, const uint8_t *b) {
    (void)a;
    (void)b;
    MsUnwind *const unwind = &ms_task_running()->unwind;
    if (unwind->eq_length > 0) {
        unwind->eq_length--;
    }
}
