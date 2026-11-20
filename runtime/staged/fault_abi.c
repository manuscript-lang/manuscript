/* The exported fault, cleanup, shield and guard entry points. See fault_abi.h; the state is the running task's
 * MsUnwind (unwind.h) and the reports are fault.h's.
 */
#include "fault_abi.h"

#include "scheduler.h"
#include "text.h"

enum {
    STACK_CLEANUP_RESERVE = 16 << 10, /* stack left for cleanups after a depth fault */
};

static MsUnwind *running(void) { return &ms_task_running()->unwind; }

static MsFaultKind kind_of(uint8_t code) {
    return code <= MS_FAULT_KIND_OUT_OF_MEMORY ? (MsFaultKind)code : MS_FAULT_KIND_FAULT;
}

/* ---- raising ---- */

void msfault_raise(uint8_t kind, const uint8_t *msg, size_t len) { ms_fault(kind_of(kind), ms_bytes_of(msg, len)); }

void msrt_fault(const uint8_t *msg, size_t len) { ms_fault(MS_FAULT_KIND_FAULT, ms_bytes_of(msg, len)); }

void ms_fault_hook(MsFaultKind kind, const char *message) {
    ms_fault(kind, ms_bytes_of((const uint8_t *)message, __builtin_strlen(message)));
}

void msrt_fault_string(const MsStr *message) {
    ms_fault(MS_FAULT_KIND_FAULT, ms_bytes_of(ms_str_data(message), ms_str_len(message)));
}

MS_NORETURN static void fault_text(MsFaultKind kind, const char *message) {
    ms_fault(kind, ms_bytes_of((const uint8_t *)message, __builtin_strlen(message)));
}

void msrt_fault_depth(void) {
    /* Cleanups run calls in the reserve, so the limit moves down before the report is built. */
    MsUnwind *const unwind = running();
    unwind->hdr.limit = unwind->stack_low == 0 ? 0 : unwind->stack_low + STACK_CLEANUP_RESERVE;
    ms_task_publish_limit();
    fault_text(MS_FAULT_KIND_STACK_OVERFLOW,
               "stack overflow: call depth limit exceeded (recursion too deep or stack frames too large); check the "
               "recursion for a missing base case, or iterate instead");
}

void msrt_index_fault(int64_t index, int64_t length) {
    MsText text = {.len = 0};
    ms_text_add(&text, "index ");
    ms_text_add_i64(&text, index);
    ms_text_add(&text, " out of range for length ");
    ms_text_add_i64(&text, length);
    ms_text_add(&text, "; pass a default: get(index:, default: ...)");
    fault_text(MS_FAULT_KIND_INDEX_OUT_OF_RANGE, text.bytes);
}

/* The name of a list mutator and the highest index it accepts; `operation` 0 insert (which also accepts `len`),
 * 1 remove, 2 set, 3 swap, 4 replace. */
static const char *list_operation(int64_t operation, int64_t len, int64_t *highest) {
    *highest = operation == 0 ? len : len - 1;
    switch (operation) {
    case 0: return "List.insert";
    case 1: return "List.remove";
    case 3: return "List.swap";
    case 4: return "List.replace";
    default: return "List.set";
    }
}

void msrt_list_index_fault(int64_t operation, int64_t index, int64_t len) {
    int64_t highest = 0;
    const char *const name = list_operation(operation, len, &highest);
    MsText text = {.len = 0};
    ms_text_add(&text, name);
    if (operation != 0 && len == 0) {
        ms_text_add(&text, ": index has no valid value for an empty collection, found ");
        ms_text_add_i64(&text, index);
    } else {
        ms_text_add(&text, ": index must be between ");
        ms_text_add_i64(&text, (int64_t)((uint64_t)0 - (uint64_t)len));
        ms_text_add(&text, " and ");
        ms_text_add_i64(&text, highest);
        ms_text_add(&text, " (negative indexes count from the end), found ");
        ms_text_add_i64(&text, index);
    }
    fault_text(MS_FAULT_KIND_INDEX_OUT_OF_RANGE, text.bytes);
}

void msrt_fault_unwrap_none(void) {
    fault_text(MS_FAULT_KIND_FAULT,
               "called Optional.get() on none; check is_some first, or pass a default: get(default: ...)");
}

void msrt_fault_result_get(void) {
    fault_text(MS_FAULT_KIND_FAULT, "called Result.get() on error; check is_ok first, or pass a default: get(default: ...)");
}

void msrt_fault_result_err(void) { fault_text(MS_FAULT_KIND_FAULT, "called Result.err() on ok; check is_error first"); }

void msrt_fault_int_overflow(void) {
    fault_text(MS_FAULT_KIND_OVERFLOW,
               "Int overflow; the result does not fit in signed 64 bits, so bound the operands or use BigInt");
}

void msrt_fault_int_range(void) {
    fault_text(MS_FAULT_KIND_OVERFLOW,
               "Int overflow; the result does not fit the sized integer type's range, so bound the operands or use a "
               "wider type");
}

void msrt_fault_div_zero(void) {
    fault_text(MS_FAULT_KIND_DIVISION_BY_ZERO, "division by zero; right must be nonzero, found 0");
}

void msrt_fault_rem_zero(void) {
    fault_text(MS_FAULT_KIND_DIVISION_BY_ZERO, "remainder by zero; right must be nonzero, found 0");
}

void msrt_fault_div_overflow(int64_t a, int64_t b) {
    MsText text = {.len = 0};
    ms_text_add(&text, "division overflow; found left ");
    ms_text_add_i64(&text, a);
    ms_text_add(&text, " and right ");
    ms_text_add_i64(&text, b);
    ms_text_add(&text, "; result must be between -9223372036854775808 and 9223372036854775807");
    fault_text(MS_FAULT_KIND_OVERFLOW, text.bytes);
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

uint8_t msrt_rollback_needed(void) {
    const MsTaskHdr *const hdr = &running()->hdr;
    return atomic_load_explicit(&hdr->guarded, memory_order_relaxed) != 0 || hdr->cleanup_length > 0 ? 1 : 0;
}

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

uint8_t msrt_guard_call(void (*code)(uint8_t *), uint8_t *data, MsStr *message) {
    AbiCall call = {.code = code, .data = data};
    MsFaultText report = {0};
    const MsGuardStatus status = ms_guard_call(run_abi_call, &call, &report);
    if (message != NULL) {
        static const uint8_t none[1] = {0};
        msrt_string_from_bytes(report.bytes != NULL ? report.bytes : none, report.length, message);
    }
    ms_fault_text_free(&report);
    return (uint8_t)status; /* MS_GUARD_OK, _FAULT and _CANCELLED are the values the ABI returns */
}
