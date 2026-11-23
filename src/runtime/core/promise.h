/* promise.h: promise slots for @std/concurrency/promise.ms.; the program ABI
 * (`msrt_promise_*`) is a thin layer over it.
 *
 * A promise is one row of its thread's table, named by an id `generation << 32 | (row + 1)`: a stale id never
 * matches. Only promise(fn) runs a task. An I/O promise (a pipe read, a timer, a readiness wait) has no task: the
 * operation tries its system call at once and registers a retry that the poller calls when it would block.
 *
 * Outcome codes of ms_promise_wait: 0 ok (the result is in the row), 1 the operation's own error (the error value
 * is in the row), 2 timed out, 3 cancelled, 4 closed (the result was already taken), 5 failed (a fault inside).
 *
 * Everything here runs on the scheduler thread that owns the promise. Another thread's completion arrives as a
 * mail event (see the multi-thread scheduler) and calls these on the owner.
 */
#ifndef MS_RUNTIME_CORE_PROMISE_H
#define MS_RUNTIME_CORE_PROMISE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "runtime/core/fault.h"
#include "base/desc.h"
#include "base/list.h"
#include "base/safe.h"
#include "base/string.h"
#include "runtime/core/task.h"

typedef int64_t MsPromise;

MS_LIST_DEFINE(MsPromiseList, ms_promise_list, MsPromise)

enum {
  MS_PROMISE_OK = 0,
  MS_PROMISE_ERROR = 1,
  MS_PROMISE_TIMEOUT = 2,
  MS_PROMISE_CANCELLED = 3,
  MS_PROMISE_CLOSED = 4,
  MS_PROMISE_FAILED = 5,
};

/* What a wait answers when the waiting task itself was cancelled. Runtime C never unwinds past its caller: each
 * frame returns this, and the program's entry (msrt_*) ends the call with ms_sched_cancel_return. */
#define MS_WAITER_CANCELLED INT64_MIN

/* A native continuation of an I/O promise, registered with ms_promise_on_drop. The runtime calls it with the
 * promise, the state word, and the ready bits (MS_WAIT_READ, WRITE, HUP) when its descriptor is ready, MS_WAIT_TIMEOUT
 * when the limit passed, or MS_WAIT_CANCELLED when the promise ends before completing. It retries its system call
 * and answers true once it has completed the promise. On MS_WAIT_TIMEOUT it must complete the promise; on
 * MS_WAIT_CANCELLED its answer is ignored and it only releases what the state word names. */
typedef bool (*MsPromiseRetry)(MsPromise id, uintptr_t state, uint32_t bits);

/* A value that a promise ended without anyone taking, and that came from a pipe (`pipe` != 0): the pipe puts it
 * back at the head of its queue so no value is lost. Set once by the pipe module; NULL drops the value. */
typedef void (*MsPromiseUnread)(int64_t pipe, void *block, const MsTypeDesc *desc);
void ms_promise_set_unread(MsPromiseUnread unread);

/* Fills the hooks the promise table needs from the scheduler (end_started, the timer callbacks, teardown) into
 * `hooks`, keeping the others. Call before ms_sched_set_hooks. */
void ms_promise_hooks(MsSchedHooks *hooks) MS_NONNULL;

/* ---- lifecycle ---- */

/* A pending promise. */
MsPromise ms_promise_new(void);
/* Completes with the value at `value` (`desc->size` bytes, taken: the table owns it afterwards): `failed` makes it the
 * operation's error value. Later completions drop their value. */
void ms_promise_put(MsPromise id, uint8_t *value, const MsTypeDesc *desc, bool failed) MS_NONNULL_ARGS(2, 3);
/* Moves the result of a promise whose wait returned 0 or 1 into `out` (`desc->size` bytes); false when none. */
MS_NODISCARD bool ms_promise_take(MsPromise id, const MsTypeDesc *desc, uint8_t *out) MS_NONNULL;
/* Whether the promise has finished, in any way; a closed id reads as done. */
bool ms_promise_done(MsPromise id);
/* Waits up to `timeout_ns` (negative: no limit) and returns an outcome code. A cancel arriving while it waits ends
 * the promise and answers MS_WAITER_CANCELLED. */
int64_t ms_promise_wait(MsPromise id, int64_t timeout_ns);
/* Makes the promise listen to the cancel switch `cancel`: when it fires the promise is cancelled. Call it once the work
 * has started. Replaces an earlier switch. */
void ms_promise_on_cancel(MsPromise id, int64_t cancel);
/* Gives the promise a notice and a grace for its end: when its owner ends it (ms_promise_end, drop, unwinding), the
 * switch `drain` fires first and the work has `grace_ns` (negative: no limit) to finish before it is cancelled. An
 * explicit ms_promise_cancel skips the notice. */
void ms_promise_drain(MsPromise id, int64_t drain, int64_t grace_ns);
/* Cancels the promise if unfinished, without waiting. */
void ms_promise_cancel(MsPromise id);
/* Ends the promise's limit `timeout_ns` from now: it is cancelled and a wait reports a timeout. */
void ms_promise_limit(MsPromise id, int64_t timeout_ns);
/* Cancels and joins the work, keeps the row; true when a value is left to take. */
bool ms_promise_end(MsPromise id);
/* Ends the promise and frees its row and any value left in it. */
void ms_promise_drop(MsPromise id);
/* The report of the fault that failed the promise (owned by the caller); length 0 when none. */
MsFaultText ms_promise_fault_report(MsPromise id);

/* What a wait group needs to know of a promise. */
typedef enum MsPromiseProbe {
  MS_PROMISE_GONE = 0, /* closed or stale */
  MS_PROMISE_PENDING,
  MS_PROMISE_DONE_PROBE,   /* finished with a value */
  MS_PROMISE_FAILED_PROBE, /* finished without a value: an error, a fault or a cancel */
} MsPromiseProbe;
MsPromiseProbe ms_promise_probe(MsPromise id);
/* Whether another thread or isolate may finish `id`: a waiter must then park on a remote token, or the scheduler
 * reports a deadlock while the work runs elsewhere. */
bool ms_promise_completes_elsewhere(MsPromise id);

/* Whether the promise has ended as far as this isolate can tell without waiting: no yield, no ask. A promise of
 * another isolate reads as not ended. For mail handlers and the idle path, where the running task is parked. */
bool ms_promise_finished(MsPromise id);

/* Whether `id` belongs to another isolate's table. */
bool ms_promise_is_foreign(MsPromise id);
/* Marks a pending promise as a wait group member: ms_group_finished is called when it finishes. */
void ms_promise_set_grouped(MsPromise id, bool grouped);
/* Runs deferred work on the caller's stack, when `id` has some; true when it ran. */
bool ms_promise_run_inline(MsPromise id);
/* The index in `ids` of the first of `count` promises to finish, waiting up to `timeout_ns` (negative: no limit);
 * -1 on timeout, MS_WAITER_CANCELLED on a cancel. */
int64_t ms_promise_wait_any(const MsPromise *ids, size_t count, int64_t timeout_ns);

/* ---- work ---- */

/* Runs `closure` (a function value, owned by the promise) as a task of this thread. Starting twice faults. */
void ms_promise_start(MsPromise id, MsObj *closure, const MsString *site) MS_NONNULL_ARGS(2);
/* Starts the work as a task of this thread, never queued for another isolate (I/O work whose handles are thread-bound). */
void ms_promise_start_here(MsPromise id, MsObj *closure, const MsString *site) MS_NONNULL_ARGS(2);
/* Like start_here for work no task owns (the idle pool's requests): the promise is on no task's list of started work. */
void ms_promise_start_detached(MsPromise id, MsObj *closure) MS_NONNULL_ARGS(2);
/* Like start, but on the least loaded isolate (with one isolate, here). */
void ms_promise_start_spread(MsPromise id, MsObj *closure, const MsString *site) MS_NONNULL_ARGS(2);
/* Like start, but with no other task running the work waits for its waiter (runs on the waiter's stack). */
void ms_promise_start_idle(MsPromise id, MsObj *closure, const MsString *site) MS_NONNULL_ARGS(2);
/* The work is not run until a waiter asks for it. */
void ms_promise_defer(MsPromise id, MsObj *closure) MS_NONNULL_ARGS(2);

/* ---- I/O promises (no task) ---- */

/* A promise that finishes after `ns` nanoseconds with an Int. */
MsPromise ms_promise_sleep(int64_t ns);
/* Completes with a unit value: a wait answers 0 and the take reads it as Void. */
void ms_promise_io_done_unit(MsPromise id);
/* Completes with no value: the end of a pipe or stream. A wait answers 0 and the take finds nothing. */
void ms_promise_io_done(MsPromise id);
/* Completes with an Int. */
void ms_promise_io_done_int(MsPromise id, int64_t value);
/* Completes with `block` (a heap block holding an owned value of `desc`, taken). `pipe` != 0 names the pipe that
 * gave the value up, so an untaken value goes back through the unread hook. A completed promise drops the block. */
void ms_promise_io_done_block(MsPromise id, void *block, const MsTypeDesc *desc, int64_t pipe) MS_NONNULL_ARGS(2, 3);
/* A promise for the readiness of `fd` for `events` (MS_WAIT_READ, WRITE, ...), limited by `timeout_ns` (negative:
 * none). It finishes with an Int of the ready bits, MS_WAIT_TIMEOUT when the limit passed; a descriptor that cannot
 * be polled is ready at once. Returns -1 when `fd` cannot be waited on. */
MsPromise ms_promise_ready(int fd, uint32_t events, int64_t timeout_ns);
/* A descriptor wait for an I/O promise `id`: `retry` is called with the ready bits (or MS_WAIT_TIMEOUT, or
 * MS_WAIT_CANCELLED when the promise ends first). False when `fd` cannot be waited on. */
MS_NODISCARD bool ms_promise_io_on_ready(MsPromise id, int fd, uint32_t events, int64_t timeout_ns,
                     MsPromiseRetry retry, uintptr_t state) MS_NONNULL_ARGS(5);
/* Registers the native continuation of an I/O promise: called with MS_WAIT_CANCELLED if the promise ends first. */
void ms_promise_on_drop(MsPromise id, MsPromiseRetry cancel, uintptr_t state) MS_NONNULL_ARGS(2);

/* Wakes the waiter of `id` when another thread (a pipe peer) completes the promise: marks the row so a waiter
 * parks on a remote token. Set before the first wait. */
void ms_promise_set_remote_wake(MsPromise id);

/* ---- ids of another isolate ---- */

/* The calls above accept an id that names another isolate's table: the owner answers by mail (promise_remote.c). The
 * two below are what that owner-side needs. */

/* The outcome code of a finished promise (see the top), or -1 while it is pending. */
int64_t ms_promise_outcome(MsPromise id);
/* Posts the remote token `token` when `id` finishes (at once when it has). */
void ms_promise_watch(MsPromise id, uint64_t token);

/* Frees the table of this thread; a value nobody took is dropped. */
void ms_promises_teardown(void);

#endif
