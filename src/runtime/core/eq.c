/* The equality cycle guard: while a comparison of two objects runs, the pair is registered, so a comparison that
 * reaches the same pair again (a cycle) assumes equal instead of recursing forever. The pairs live in the running
 * task's unwind state, so a task switch needs no copy and a guard that catches a fault drops what the fault left
 * behind (ms_guard_leave). */
#include "runtime/core/eq.h"
#include "runtime/core/fault.h"
#include "runtime/core/scheduler.h"

enum { MAX_EQ_DEPTH = 200000 };

uint8_t msrt_eq_enter(const uint8_t *a, const uint8_t *b) {
  MsUnwind *const unwind = &ms_task_running()->unwind;
  const uintptr_t left = (uintptr_t)a;
  const uintptr_t right = (uintptr_t)b;
  for (size_t i = 0; i < unwind->eq_pairs.len; i++) {
    if (unwind->eq_pairs.ptr[i].a == left && unwind->eq_pairs.ptr[i].b == right) {
      return 0; /* already comparing this pair: the comparison assumes equal */
    }
  }
  if (unwind->eq_pairs.len >= MAX_EQ_DEPTH) {
    ms_fault_text(MS_FAULT_KIND_FAULT, "equality comparison is nested too deeply");
  }
  ms_eq_pair_list_push(&unwind->eq_pairs, (MsEqPair){.a = left, .b = right});
  return 1;
}

void msrt_eq_leave(const uint8_t *a, const uint8_t *b) {
  (void)a;
  (void)b;
  MsUnwind *const unwind = &ms_task_running()->unwind;
  if (unwind->eq_pairs.len > 0) {
    unwind->eq_pairs.len--;
  }
}
