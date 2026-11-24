[Wiki](../index.md) › [Runtime](index.md)

# Natives end a cancelled call by returning

Decision (Chinmay, 2026-11-23, structural fixes for leaks; [proposal](../../proposals/cancel-returns-through-runtime-c.md)): runtime C never unwinds past its caller. A native that sees a cancel calls `ms_cancel_deliver()` (sets the task's `unwinding` byte) and returns an empty result at once; each frame above returns on its error path and the compiled call site leaves by its exit ([faults and cancels leave by return](faults-and-cancels-leave-by-return.md)).

Rules:
- A cancelled wait answers a value (`MS_WAITER_CANCELLED` from core waits, `MS_STATUS_CANCELLED` from natives); the call ends where compiled code receives the status (`msrt_native_failed`, which also delivers when a stop is pending and a layer rewrote the status).
- Free what the native owns before it delivers or finishes: `ms_fail_finish_at` delivers when a stop request is pending, so anything freed after it leaks (an fs native that freed its job after the finish leaked 16 MB per cancelled `read_file`; fixture `stdlib/cancelled-file-read-frees-buffer`).
- A native that calls generated code (sort comparators, filters) lets the callee run on: a callee that sees `unwinding` returns at its next park. Loops around callbacks keep their `poll_cancel()` checks.
- A connection task whose join of the handler is cancelled cancels the handler and joins it under a shield before returning (fixture `stdlib/http-close-cancels-waiting-handler`). An accepted connection travels to its worker as an owning handle (`NativeAccepted`), not a raw id (#6774).
- `ms_lint` enforces the runtime directories (`NO_UNWIND` in `src/lint/rules.c`).

Apply when: adding or changing a native that parks, waits, or polls for cancellation.
