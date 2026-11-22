/* The exported fault, cleanup, shield and guard entry points. See fault_abi.h. */
#include "runtime/core/fault_abi.h"

#include "base/strbuild.h"
#include "runtime/core/scheduler.h"

enum {
  STACK_CLEANUP_RESERVE = 16 << 10, /* stack left for cleanups after a depth fault */
};

static MsUnwind *running(void) { return &ms_task_running()->unwind; }

/* ---- raising ---- */

void msrt_fault(const uint8_t *msg, size_t len) { ms_fault(MS_FAULT_KIND_FAULT, ms_span_of(msg, len)); }

void msrt_fault_string(const MsString *message) {
  ms_fault(MS_FAULT_KIND_FAULT, ms_string_span(message));
}

void msrt_panic(const MsString *message) {
  msrt_fault_string(message);
}

void msrt_fault_depth(void) {
  /* Cleanups run calls in the reserve, so the limit moves down before the report is built. */
  MsUnwind *const unwind = running();
  unwind->hdr.limit = unwind->stack_low == 0 ? 0 : unwind->stack_low + STACK_CLEANUP_RESERVE;
  ms_task_publish_limit();
  ms_fault_text(MS_FAULT_KIND_STACK_OVERFLOW,
                "stack overflow: call depth limit exceeded (recursion too deep or stack frames too large); check the "
                "recursion for a missing base case, or iterate instead");
}

void msrt_fault_unwrap_none(void) {
  ms_fault_text(MS_FAULT_KIND_FAULT,
                "called Optional.get() on none; check is_some first, or pass a default: get(default: ...)");
}

void msrt_fault_result_get(void) {
  ms_fault_text(MS_FAULT_KIND_FAULT,
                "called Result.get() on error; check is_ok first, or pass a default: get(default: ...)");
}

void msrt_fault_result_err(void) {
  ms_fault_text(MS_FAULT_KIND_FAULT, "called Result.err() on ok; check is_error first");
}

void msrt_fault_int_overflow(void) {
  ms_fault_text(MS_FAULT_KIND_OVERFLOW,
                "Int overflow; the result does not fit in signed 64 bits, so bound the operands or use BigInt");
}

void msrt_fault_int_range(void) {
  ms_fault_text(MS_FAULT_KIND_OVERFLOW,
                "Int overflow; the result does not fit the sized integer type's range, so bound the operands or use a "
                "wider type");
}

void msrt_fault_div_zero(void) {
  ms_fault_text(MS_FAULT_KIND_DIVISION_BY_ZERO, "division by zero; right must be nonzero, found 0");
}

void msrt_fault_rem_zero(void) {
  ms_fault_text(MS_FAULT_KIND_DIVISION_BY_ZERO, "remainder by zero; right must be nonzero, found 0");
}

void msrt_fault_div_overflow(int64_t a, int64_t b) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "division overflow; found left ");
  ms_strbuild_append_i64(&text, a);
  ms_strbuild_append_text(&text, " and right ");
  ms_strbuild_append_i64(&text, b);
  ms_strbuild_append_text(&text, "; result must be between -9223372036854775808 and 9223372036854775807");
  ms_fault(MS_FAULT_KIND_OVERFLOW, ms_strbuild_span(&text));
}

/* ---- cleanups ---- */

size_t msrt_cleanup_push(MsCleanupFn run, uint8_t *arg) { return ms_cleanup_push(run, arg); }
void msrt_cleanup_run(size_t handle) { ms_cleanup_run(handle); }
void msrt_cleanup_discard(size_t handle) { ms_cleanup_discard(handle); }
void msrt_cleanup_remove(size_t handle) { ms_cleanup_remove(handle); }
void msrt_cleanup_cancel(size_t handle) { ms_cleanup_cancel(handle); }
size_t msrt_cleanup_base(void) { return ms_cleanup_base(); }
void msrt_cleanup_unwind_to(size_t base) { ms_cleanup_unwind_to(base); }
void msrt_cleanup_truncate(size_t base) { ms_cleanup_truncate(base); }
uint8_t msrt_unwind_drops(void) { return ms_unwind_drops() ? 1 : 0; }

/* ---- shields and cancellation ---- */

void msrt_shield_enter(void) { ms_shield_enter(); }
void msrt_shield_exit(void) { ms_shield_exit(); }
void msrt_cancel_edges(void) { ms_sched()->cancel_edges = true; }
void msrt_unwinding_pause(void) { (void)ms_unwinding_take(); }
void msrt_unwinding_resume(void) { ms_cancel_deliver(); }
uint8_t msrt_unwinding(void) { return ms_unwinding() ? 1 : 0; }
void msrt_cancelled(void) { ms_cancelled(); }
MsTaskHdr *msrt_isolate_hdr(void) { return &running()->hdr; }

void ms_sched_cancel_return(void) {
  if (ms_sched()->cancel_edges) {
    ms_cancel_deliver();
  } else {
    ms_cancelled();
  }
}

/* ---- guards ---- */

typedef struct AbiCall {
  void (*code)(uint8_t *);
  uint8_t *data;
} AbiCall;

static void run_abi_call(void *call) {
  const AbiCall *const abi = call;
  abi->code(abi->data);
}

uint8_t msrt_guard_call(void (*code)(uint8_t *), uint8_t *data, MsString *message) {
  AbiCall call = {.code = code, .data = data};
  MsFaultText report = {0};
  const MsGuardStatus status = ms_guard_call(run_abi_call, &call, &report);
  if (message != NULL) {
    *message = ms_string_from_span(ms_span_of(report.bytes, report.length));
  }
  ms_fault_text_free(&report);
  return (uint8_t)status; /* MS_GUARD_OK, _FAULT and _CANCELLED are the values the ABI returns */
}
