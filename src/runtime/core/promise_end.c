/* Stopping and ending promises. See promise.h. */
#include "runtime/core/promise_table.h"

#include "runtime/core/cancel.h"
#include "runtime/core/fault.h"
#include "runtime/core/fault_kept.h"
#include "runtime/core/group.h"
#include "runtime/core/isolate.h"
#include "runtime/core/promise_remote.h"
#include "runtime/core/queue.h"
#include "runtime/core/worker.h"

/* ---- stopping and ending ---- */

/* Asks the work of `id` to stop at its next cancellation point. */
void promise_request_cancel(size_t row) {
  Hot *const hot = &promise_table.hot.ptr[row];
  const Cold *const cold = &promise_table.cold.ptr[row];
  if ((hot->flags & FLAG_REMOTE) != 0) {
    if (cold->runner_task == 0) {
      hot->flags |= FLAG_WANT_CANCEL; /* applied when the runner says which task it is */
      return;
    }
    MsMail *const mail = ms_alloc(sizeof *mail);
    *mail = (MsMail){.kind = MS_MAIL_PROMISE, .a = MAIL_CANCEL, .b = cold->runner_task};
    if (!ms_isolate_post(cold->runner, mail)) {
      ms_free(mail);
    }
    return;
  }
  if (cold->closure != NULL && cold->task != 0) {
    ms_task_cancel(cold->task);
  }
}

/* Ends the descriptor wait of a pending promise. */
void promise_leave_fd(MsPromise id, size_t row) {
  Cold *const cold = &promise_table.cold.ptr[row];
  if (cold->fd >= 0) {
    ms_sched_fd_wait_end((uint64_t)id, cold->fd);
    cold->fd = -1;
  }
}

void promise_stop(MsPromise id) {
  const ptrdiff_t found = promise_row_of(id);
  if (found < 0 || promise_table.hot.ptr[found].state != STATE_PENDING) {
    return;
  }
  const size_t row = (size_t)found;
  Hot *const hot = &promise_table.hot.ptr[row];
  Cold *const cold = &promise_table.cold.ptr[row];
  if ((hot->flags & FLAG_QUEUED) != 0) {
    (void)promise_claim_queued(row);
  }
  if ((cold->closure != NULL && (hot->flags & FLAG_DEFERRED) == 0) || (hot->flags & FLAG_REMOTE) != 0) {
    hot->flags |= FLAG_STOPPED;
    promise_request_cancel(row);
    return;
  }
  if ((hot->flags & FLAG_DEFERRED) != 0) {
    hot->flags &= (uint16_t)~FLAG_DEFERRED;
    MsObj *const closure = cold->closure;
    cold->closure = NULL;
    msrt_obj_drop(closure);
  }
  promise_leave_fd(id, row);
  MsPromiseRetry retry = cold->retry;
  cold->retry = NULL;
  if (retry != NULL) {
    (void)retry(id, cold->retry_state, MS_WAIT_CANCELLED);
  }
  const ptrdiff_t again = promise_row_of(id);
  if (again >= 0 && promise_table.hot.ptr[again].state == STATE_PENDING) {
    promise_table.hot.ptr[again].state = STATE_CANCELLED;
    promise_wake((size_t)again);
  }
}

void ms_promise_cancel(MsPromise id) {
  if (promise_is_foreign(id)) {
    ms_remote_cancel(id);
    return;
  }
  promise_stop(id);
}

void ms_promise_on_cancel(MsPromise id, int64_t cancel) {
  if (promise_is_foreign(id)) {
    ms_remote_on_cancel(id, cancel);
    return;
  }
  const ptrdiff_t row = promise_row_of(id);
  if (row < 0) {
    return;
  }
  const int64_t previous = promise_table.cold.ptr[row].cancel;
  promise_table.cold.ptr[row].cancel = cancel;
  if (previous != 0) {
    ms_cancel_unregister(previous, id);
  }
  if (ms_cancel_register(cancel, id)) {
    promise_stop(id);
  }
}

void ms_promise_drain(MsPromise id, int64_t drain, int64_t grace_ns) {
  if (promise_is_foreign(id)) {
    ms_remote_drain(id, drain, grace_ns);
    return;
  }
  const ptrdiff_t row = promise_row_of(id);
  if (row >= 0) {
    promise_table.cold.ptr[row].drain = drain;
    promise_table.cold.ptr[row].grace = grace_ns;
  }
}

void ms_promise_limit(MsPromise id, int64_t timeout_ns) {
  if (promise_is_foreign(id)) {
    ms_remote_limit(id, timeout_ns);
    return;
  }
  const ptrdiff_t row = promise_row_of(id);
  if (row < 0) {
    return;
  }
  const int64_t at = ms_sched_now() + (timeout_ns > 0 ? timeout_ns : 0);
  promise_table.cold.ptr[row].limit = at;
  ms_sched_arm((uint64_t)id, at);
}

/* Parks the caller until `id` wakes it, `at_ns` passes (negative: never) or a cancel arrives; returns the wake
 * result (0 posted, MS_WAIT_TIMEOUT, MS_WAIT_CANCELLED). */
uint32_t promise_park_on(MsPromise id, int64_t at_ns) {
  const ptrdiff_t row = promise_row_of(id);
  if (row < 0) {
    return 0;
  }
  /* The row names the parked task itself: no token is made for a wait on one promise. */
  const uint64_t word = ms_task_wait_word();
  promise_table.hot.ptr[row].token = word;
  const uint32_t result = ms_task_park_word(at_ns, (promise_table.hot.ptr[row].flags & FLAG_REMOTE_WAKE) != 0);
  const ptrdiff_t after = promise_row_of(id);
  if (after >= 0 && promise_table.hot.ptr[after].token == word) {
    promise_table.hot.ptr[after].token = 0;
  }
  return result;
}

/* Ends the work of a pending promise: a promise with a drain switch is told first and cancelled only when its grace
 * runs out; any other is cancelled now. */
static void give_notice(MsPromise id, size_t row) {
  Cold *const cold = &promise_table.cold.ptr[row];
  const int64_t drain = cold->drain;
  if (drain == 0) {
    promise_request_cancel(row);
    return;
  }
  cold->drain = 0;
  const int64_t now = ms_sched_now();
  if (cold->grace >= 0 && (cold->limit == NO_TIME || cold->grace < cold->limit - now)) {
    ms_promise_limit(id, cold->grace);
  }
  ms_cancel_fire(drain);
}

/* Whether the row holds a result nobody took. */
static bool has_result(size_t row) {
  return promise_table.hot.ptr[row].state == STATE_OK && promise_result_bytes(&promise_table.cold.ptr[row]) != NULL;
}

/* Whether the row finished and its work is gone, so there is nothing to end. */
MS_ALWAYS_INLINE bool promise_row_settled(size_t row) {
  const Hot *const hot = &promise_table.hot.ptr[row];
  const Cold *const cold = &promise_table.cold.ptr[row];
  return hot->state != STATE_PENDING && cold->closure == NULL && cold->cancel == 0 &&
         (hot->flags & (FLAG_QUEUED | FLAG_DEFERRED | FLAG_REMOTE)) == 0;
}

bool ms_promise_end(MsPromise id) {
  if (promise_is_foreign(id)) {
    return ms_remote_end(id);
  }
  ptrdiff_t found = promise_row_of(id);
  if (found < 0) {
    return false;
  }
  Hot *hot = &promise_table.hot.ptr[found];
  Cold *const cold = &promise_table.cold.ptr[found];
  if (promise_row_settled((size_t)found)) {
    return has_result((size_t)found);
  }
  if (cold->cancel != 0) {
    ms_cancel_unregister(cold->cancel, id);
    cold->cancel = 0;
  }
  if ((hot->flags & FLAG_QUEUED) != 0) {
    (void)promise_claim_queued((size_t)found);
  }
  if ((hot->flags & FLAG_DEFERRED) != 0) {
    hot->flags &= (uint16_t)~FLAG_DEFERRED;
    MsObj *const closure = cold->closure;
    cold->closure = NULL;
    msrt_obj_drop(closure);
  }
  if (hot->state == STATE_PENDING) {
    promise_leave_fd(id, (size_t)found);
  }
  if (hot->state == STATE_PENDING && cold->retry != NULL) {
    MsPromiseRetry retry = cold->retry;
    cold->retry = NULL;
    (void)retry(id, cold->retry_state, MS_WAIT_CANCELLED);
  }
  if (promise_table.cold.ptr[found].closure != NULL || (promise_table.hot.ptr[found].flags & FLAG_REMOTE) != 0) {
    if (promise_table.hot.ptr[found].state == STATE_PENDING) {
      give_notice(id, (size_t)found);
    }
    ms_shield_enter();
    while ((found = promise_row_of(id)) >= 0 &&
         (promise_table.cold.ptr[found].closure != NULL || (promise_table.hot.ptr[found].flags & FLAG_REMOTE) != 0)) {
      (void)promise_park_on(id, -1);
    }
    ms_shield_exit();
  }
  found = promise_row_of(id);
  return found >= 0 && has_result((size_t)found);
}

/* Frees the settled row: its result, start line, report and watches. */
MS_ALWAYS_INLINE void promise_free_row(size_t row) {
  promise_release_result(row);
  promise_release_started(&promise_table.cold.ptr[row]);
  ms_fault_text_free(&promise_table.cold.ptr[row].report);
  if ((promise_table.hot.ptr[row].flags & FLAG_WATCHED) != 0) {
    promise_post_watches(row);
  }
  promise_table.hot.ptr[row].state = STATE_FREE;
  if (promise_table.hot.ptr[row].generation < GENERATION_MASK) {
    row_list_push(&promise_table.free_rows, (uint32_t)row);
  } /* else the row has used every generation: it is never reused, so an old id of it can never match a new promise */
}

void ms_promise_drop(MsPromise id) {
  if (promise_is_foreign(id)) {
    ms_remote_drop(id);
    return;
  }
  ptrdiff_t found = promise_row_of(id);
  if (found >= 0 && !promise_row_settled((size_t)found)) {
    (void)ms_promise_end(id);
    found = promise_row_of(id);
  }
  if (found >= 0) {
    promise_free_row((size_t)found);
  }
}

MS_ALWAYS_INLINE bool ms_promise_close(MsPromise id) {
  const ptrdiff_t found = promise_row_of(id);
  if (found < 0 && !promise_is_foreign(id)) {
    return false; /* the usual end: taking the result freed the row */
  }
  if (found >= 0 && promise_row_settled((size_t)found) && !has_result((size_t)found)) {
    promise_free_row((size_t)found);
    return false;
  }
  if (ms_promise_end(id)) {
    return true;
  }
  ms_promise_drop(id);
  return false;
}

MsFaultText ms_promise_fault_report(MsPromise id) {
  if (promise_is_foreign(id)) {
    return ms_remote_fault_report(id);
  }
  const ptrdiff_t row = promise_row_of(id);
  if (row < 0 || promise_table.cold.ptr[row].report.bytes == NULL) {
    return (MsFaultText){0};
  }
  return ms_fault_text_clone(&promise_table.cold.ptr[row].report);
}

/* A cancelled frame ends the promises it started at or above its cleanup height `base`, newest first: the work
 * borrows the frame's values, so it must end before they do. Work on this task's own stack (a deferred promise)
 * ends with it, and joining it would wait on itself. */
static ptrdiff_t next_to_end(MsTaskHandle me, size_t base) {
  for (uint32_t at = ms_task_started_head(me); at != 0; at = promise_table.cold.ptr[at - 1].next_started) {
    const Cold *const cold = &promise_table.cold.ptr[at - 1];
    const uint16_t flags = promise_table.hot.ptr[at - 1].flags;
    const bool elsewhere = (flags & (FLAG_QUEUED | FLAG_REMOTE)) != 0;
    if (cold->started_at >= base &&
      (elsewhere || (cold->closure != NULL && cold->task != 0 && cold->task != me))) {
      return (ptrdiff_t)at - 1;
    }
  }
  return -1;
}

void promise_end_started(size_t base) {
  const MsTaskHandle me = ms_task_current();
  ptrdiff_t row = 0;
  while ((row = next_to_end(me, base)) >= 0) {
    (void)ms_promise_end(promise_make_id((size_t)row));
  }
}

