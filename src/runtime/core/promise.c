/* The promise promise_table of a thread. See promise.h.
 *
 * Rows are split in two arrays: the hot one holds what a wait and a wake touch (state, flags, generation, the
 * waiter's token), the cold one everything else, so the scheduler's common paths read 16 bytes per promise. The
 * promises a task started form a doubly linked list threaded through the cold rows by index, with its head in the
 * task record, so a cancelled frame visits only its own promises and ending one is constant time.
 */
#include "runtime/core/promise_table.h"

#include <stdatomic.h>

#include "runtime/core/cancel.h"
#include "runtime/core/fault.h"
#include "runtime/core/fault_kept.h"
#include "runtime/core/group.h"
#include "runtime/core/isolate.h"
#include "runtime/core/promise_remote.h"
#include "runtime/core/queue.h"
#include "runtime/core/worker.h"

_Thread_local Table promise_table;
static MsPromiseUnread unread_hook;

void ms_promise_set_unread(MsPromiseUnread unread) { unread_hook = unread; }

/* ---- rows ---- */

void promise_fail(const char *text) { ms_fault_text(MS_FAULT_KIND_FAULT, text); }

static void drop_closure(uint8_t *closure) { msrt_obj_drop((MsObj *)__builtin_assume_aligned(closure, _Alignof(MsObj))); }

size_t promise_row_or_fault(MsPromise id) {
  const ptrdiff_t row = promise_row_of(id);
  if (row < 0) {
    promise_fail("promise: no such promise");
  }
  return (size_t)row;
}

/* Remembers the program line that started the work (`site`, or NULL for none), so a fault in the work can name it.
 * The compiler passes a literal, whose bytes live forever; any other string is copied. */
static void keep_started(Cold *cold, const MsString *site) {
  if (site == NULL) {
    return;
  }
  const uint64_t tag = site->tagged >> MS_STRING_TAG_SHIFT;
  cold->started = tag == MS_STRING_TAG_STATIC || tag == MS_STRING_TAG_INLINE ? *site : ms_string_clone(site);
}

void promise_release_result(size_t row) {
  Cold *const cold = &promise_table.cold.ptr[row];
  uint8_t *const bytes = promise_result_bytes(cold);
  if (bytes != NULL) {
    ms_slot_drop_owned(cold->desc, bytes);
    ms_free(cold->result);
  }
  cold->result = NULL;
  cold->small_result = false;
  cold->desc = NULL;
}

static void reset_row(size_t row) {
  promise_table.cold.ptr[row] = (Cold){.deadline = NO_TIME, .limit = NO_TIME, .fd = -1, .started = ms_string_empty()};
  Hot *const hot = &promise_table.hot.ptr[row];
  hot->flags = 0;
  hot->token = 0;
}

static void grow_table(void) {
  hot_list_push(&promise_table.hot, (Hot){0});
  cold_list_push(&promise_table.cold, (Cold){0});
}

MsPromise ms_promise_new(void) {
  size_t row = 0;
  if (promise_table.free_rows.len != 0) {
    row = promise_table.free_rows.ptr[--promise_table.free_rows.len];
  } else {
    row = promise_table.hot.len;
    grow_table();
  }
  Hot *const hot = &promise_table.hot.ptr[row];
  hot->generation = (hot->generation + 1) & GENERATION_MASK;
  if (hot->generation == 0) {
    hot->generation = 1;
  }
  hot->state = STATE_PENDING;
  reset_row(row);
  return promise_make_id(row);
}

bool promise_ended_without_value(uint8_t state) {
  return state == STATE_ERROR || state == STATE_FAILED || state == STATE_CANCELLED;
}

/* Posts the tokens of the isolates watching `row` and forgets them. */
void promise_post_watches(size_t row) {
  Hot *const hot = &promise_table.hot.ptr[row];
  size_t kept = 0;
  for (size_t i = 0; i < promise_table.watches.len; i++) {
    const Watch watch = promise_table.watches.ptr[i];
    if (watch.row == row && watch.generation == hot->generation) {
      ms_token_post_remote(watch.token, 0);
    } else {
      promise_table.watches.ptr[kept++] = watch;
    }
  }
  promise_table.watches.len = kept;
  hot->flags &= (uint16_t)~FLAG_WATCHED;
}

void promise_wake(size_t row) {
  Hot *const hot = &promise_table.hot.ptr[row];
  if ((hot->flags & FLAG_GROUPED) != 0 && hot->state != STATE_PENDING) {
    hot->flags &= (uint16_t)~FLAG_GROUPED;
    ms_group_finished(promise_make_id(row), promise_ended_without_value(hot->state));
  }
  const uint64_t token = hot->token;
  hot->token = 0;
  if (token != 0) {
    ms_token_post(token, 1);
  }
  if ((hot->flags & FLAG_WATCHED) != 0 && hot->state != STATE_PENDING) {
    promise_post_watches(row);
  }
}

/* ---- completion ---- */

static void drop_block(void *block, const MsTypeDesc *desc, int64_t pipe) {
  if (block == NULL) {
    return; /* a completion without a value */
  }
  if (pipe != 0 && unread_hook != NULL) {
    unread_hook(pipe, block, desc);
    return;
  }
  ms_slot_drop_owned(desc, block);
  ms_free(block);
}

/* The row has its result: it finishes now, or once its work's task has ended. */
static void settle(Hot *hot, Cold *cold, size_t row, bool failed) {
  cold->retry = NULL;
  if (cold->closure != NULL || (hot->flags & FLAG_REMOTE) != 0) {
    /* The work's task is still ending: its owned resources close first. */
    hot->flags |= (uint16_t)(FLAG_HELD | (failed ? FLAG_HELD_ERROR : 0));
    return;
  }
  hot->state = failed ? STATE_ERROR : STATE_OK;
  promise_wake(row);
}

/* Completes `row` with `block` unless it already finished; `block` is taken either way. */
static void complete(size_t row, void *block, const MsTypeDesc *desc, bool failed, int64_t pipe) {
  Hot *const hot = &promise_table.hot.ptr[row];
  Cold *const cold = &promise_table.cold.ptr[row];
  if (hot->state != STATE_PENDING || (hot->flags & FLAG_HELD) != 0) {
    if (block != NULL) {
      drop_block(block, desc, pipe);
    }
    return;
  }
  cold->result = block;
  cold->desc = desc;
  cold->pipe = pipe;
  settle(hot, cold, row, failed);
}

/* Copies a value that fits a row. Most are one, two or three whole words, which copy without a call. */
static inline void copy_small(void *to, const void *from, size_t size) {
  if (size == 8) {
    __builtin_memcpy(to, from, 8);
  } else if (size == 16) {
    __builtin_memcpy(to, from, 16);
  } else if (size == 24) {
    __builtin_memcpy(to, from, 24);
  } else {
    __builtin_memcpy(to, from, size);
  }
}

/* Completes `row` with the `desc` value at `value`, which fits the row; the value is taken either way. */
static void complete_small(size_t row, const uint8_t *value, const MsTypeDesc *desc, bool failed) {
  Hot *const hot = &promise_table.hot.ptr[row];
  Cold *const cold = &promise_table.cold.ptr[row];
  if (hot->state != STATE_PENDING || (hot->flags & FLAG_HELD) != 0) {
    uint64_t copy[PROMISE_SMALL_WORDS];
    __builtin_memcpy(copy, value, desc->size);
    ms_slot_drop_owned(desc, (uint8_t *)copy);
    return;
  }
  copy_small(cold->small, value, desc->size);
  cold->small_result = true;
  cold->result = NULL;
  cold->desc = desc;
  cold->pipe = 0;
  settle(hot, cold, row, failed);
}

/* Mails a result to the isolate that owns `id`; a stale id, or an owner that is gone, drops it. */
static void send_done(MsPromise id, void *block, const MsTypeDesc *desc, bool failed, int64_t pipe) {
  const uint32_t owner = (uint32_t)((uint64_t)id >> ISOLATE_SHIFT);
  MsMail *const mail = promise_is_foreign(id) ? ms_alloc(sizeof *mail) : NULL;
  if (mail != NULL) {
    *mail = (MsMail){.kind = MS_MAIL_PROMISE,
             .a = MAIL_DONE | (failed ? 1u << 16 : 0u),
             .b = (uint64_t)id,
             .c = (uint64_t)pipe,
             .p = block,
             .q = desc};
    if (ms_isolate_post(owner, mail)) {
      return;
    }
    ms_free(mail);
  }
  drop_block(block, desc, pipe);
}

void ms_promise_put(MsPromise id, uint8_t *value, const MsTypeDesc *desc, bool failed) {
  const ptrdiff_t row = promise_row_of(id);
  const size_t size = desc->size;
  if (row >= 0 && size <= sizeof promise_table.cold.ptr[row].small) {
    complete_small((size_t)row, value, desc, failed);
    return;
  }
  uint8_t *const block = ms_alloc(size > 0 ? size : 1);
  __builtin_memcpy(block, value, size);
  if (row < 0) {
    send_done(id, block, desc, failed, 0);
    return;
  }
  complete((size_t)row, block, desc, failed, 0);
}

void ms_promise_io_done_block(MsPromise id, void *block, const MsTypeDesc *desc, int64_t pipe) {
  const ptrdiff_t row = promise_row_of(id);
  if (row < 0) {
    send_done(id, block, desc, false, pipe);
    return;
  }
  complete((size_t)row, block, desc, false, pipe);
}

void ms_promise_io_done(MsPromise id) {
  const ptrdiff_t row = promise_row_of(id);
  if (row >= 0) {
    complete((size_t)row, NULL, NULL, false, 0);
  } else if (promise_is_foreign(id)) {
    send_done(id, NULL, NULL, false, 0); /* a pipe's last writer closing on another isolate ends a parked reader */
  }
}

void ms_promise_io_done_int(MsPromise id, int64_t value) {
  const ptrdiff_t row = promise_row_of(id);
  if (row >= 0) {
    complete_small((size_t)row, (const uint8_t *)&value, &ms_desc_int, false);
    return;
  }
  int64_t *const block = ms_alloc(sizeof value);
  *block = value;
  ms_promise_io_done_block(id, block, &ms_desc_int, 0);
}

void ms_promise_io_done_unit(MsPromise id) { ms_promise_io_done_int(id, 0); }

bool ms_promise_take(MsPromise id, const MsTypeDesc *desc, uint8_t *out) {
  if (promise_is_foreign(id)) {
    return ms_remote_take(id, desc, out);
  }
  const ptrdiff_t row = promise_row_of(id);
  if (row < 0 || promise_result_bytes(&promise_table.cold.ptr[row]) == NULL) {
    return false;
  }
  Cold *const cold = &promise_table.cold.ptr[row];
  if (cold->small_result) {
    copy_small(out, cold->small, desc->size);
    cold->small_result = false;
  } else {
    __builtin_memcpy(out, cold->result, desc->size);
    ms_free(cold->result);
    cold->result = NULL;
  }
  cold->desc = NULL;
  promise_table.hot.ptr[row].state = STATE_TAKEN;
  return true;
}

void ms_promise_set_remote_wake(MsPromise id) {
  const ptrdiff_t row = promise_row_of(id);
  if (row >= 0) {
    promise_table.hot.ptr[row].flags |= FLAG_REMOTE_WAKE;
  }
}

void ms_promise_on_drop(MsPromise id, MsPromiseRetry cancel, uintptr_t state) {
  const ptrdiff_t row = promise_row_of(id);
  if (row < 0 || promise_table.hot.ptr[row].state != STATE_PENDING) {
    (void)cancel(id, state, MS_WAIT_CANCELLED);
    return;
  }
  promise_table.cold.ptr[row].retry = cancel;
  promise_table.cold.ptr[row].retry_state = state;
}

/* ---- the lists of started promises ---- */

static void link_started(size_t row) {
  Cold *const cold = &promise_table.cold.ptr[row];
  const uint32_t old = ms_task_started_swap(cold->creator, (uint32_t)row + 1);
  cold->next_started = old;
  cold->prev_started = 0;
  if (old != 0) {
    promise_table.cold.ptr[old - 1].prev_started = (uint32_t)row + 1;
  }
}

static void unlink_started(size_t row, MsTaskHandle creator) {
  Cold *const cold = &promise_table.cold.ptr[row];
  const uint32_t prev = cold->prev_started;
  const uint32_t next = cold->next_started;
  if (prev != 0) {
    promise_table.cold.ptr[prev - 1].next_started = next;
  } else if (ms_task_started_head(creator) == (uint32_t)row + 1) {
    (void)ms_task_started_swap(creator, next);
  }
  if (next != 0) {
    promise_table.cold.ptr[next - 1].prev_started = prev;
  }
  cold->next_started = 0;
  cold->prev_started = 0;
}

/* ---- the work's task ---- */

/* A promise's work and the id it completes: what the closure is called with. */
typedef struct Work {
  MsPromise id;
  MsObj *closure;
} Work;

static void run_work(void *argument) {
  const Work *const work = argument;
  MsClosure *const closure = (MsClosure *)(void *)work->closure;
  closure->code(closure, work->id);
}

/* The task of promise `id` ended with `status` (a MsGuardStatus); records how, drops the closure and wakes. */
static void work_ended(MsPromise id, MsGuardStatus status, MsFaultText message) {
  const ptrdiff_t found = promise_row_of(id);
  if (found < 0) {
    ms_fault_text_free(&message);
    return;
  }
  const size_t row = (size_t)found;
  Hot *const hot = &promise_table.hot.ptr[row];
  Cold *const cold = &promise_table.cold.ptr[row];
  MsObj *const closure = cold->closure;
  if (status == MS_GUARD_FAULT && !ms_string_is_empty(&cold->started)) {
    /* The work ran on another isolate, whose report cannot name where this one started it. */
    ms_fault_text_add_started(&message, ms_string_span(&cold->started));
  }
  promise_release_started(cold);
  if (closure != NULL) {
    /* Dropping the closure can park (a captured resource closes). The row keeps the closure until then, so an end
     * that races with it waits for the drop instead of freeing the row under it. */
    msrt_obj_drop(closure);
    cold->closure = NULL;
  }
  hot->flags &= (uint16_t) ~(FLAG_REMOTE | FLAG_WANT_CANCEL);
  if (cold->creator != 0) {
    unlink_started(row, cold->creator);
    cold->creator = 0;
  }
  cold->task = 0;
  cold->runner_task = 0;
  const bool interrupted = (hot->flags & (FLAG_TIMED_OUT | FLAG_STOPPED)) != 0;
  if (hot->state == STATE_PENDING && (hot->flags & FLAG_HELD) != 0) {
    /* A promise whose limit passed or that was cancelled reports that, not the error its work returned on the
     * way out (a wait inside the work that finds its child cancelled returns an error before the work's own
     * cancellation is seen, so the outcome would otherwise depend on timing). */
    const bool error = (hot->flags & FLAG_HELD_ERROR) != 0;
    if (error && interrupted) {
      promise_release_result(row);
    }
    hot->state = STATE_OK;
    if (error) {
      hot->state = interrupted ? STATE_CANCELLED : STATE_ERROR;
    }
    hot->flags &= (uint16_t) ~(FLAG_HELD | FLAG_HELD_ERROR);
  } else if (hot->state == STATE_PENDING) {
    if (status == MS_GUARD_FAULT) {
      cold->report = message;
      message = (MsFaultText){0};
      hot->state = STATE_FAILED;
    } else {
      hot->state = status == MS_GUARD_CANCELLED || interrupted ? STATE_CANCELLED : STATE_FAILED;
    }
    if (hot->state == STATE_FAILED && cold->report.bytes == NULL) {
      static const char text[] = "promise: the work ended without a result";
      cold->report.bytes = ms_alloc(sizeof text - 1);
      __builtin_memcpy(cold->report.bytes, text, sizeof text - 1);
      cold->report.length = sizeof text - 1;
    }
  }
  ms_fault_text_free(&message);
  promise_wake(row);
}

/* The work of `row` ended with a fault: the report names where the work was started from, and a task under a test's
 * output capture leaves its record for the test runner. */
static void finish_report(size_t row, MsGuardStatus status, MsFaultText *message) {
  if (status != MS_GUARD_FAULT) {
    return;
  }
  Cold *const cold = &promise_table.cold.ptr[row];
  if (!ms_string_is_empty(&cold->started)) {
    ms_fault_text_add_started(message, ms_string_span(&cold->started));
    promise_release_started(cold);
  }
  const uint64_t capture = ms_task_capture();
  if (capture != 0) {
    ms_test_keep_fault(capture, message);
  }
}

static void work_entry(void *argument) {
  const MsPromise id = (MsPromise)(uintptr_t)argument; // NOLINT(performance-no-int-to-ptr): the id travels as the argument word
  const ptrdiff_t row = promise_row_of(id);
  if (row < 0 || promise_table.cold.ptr[row].closure == NULL) {
    return;
  }
  MsFaultText message = {0};
  Work work = {.id = id, .closure = promise_table.cold.ptr[row].closure};
  const MsGuardStatus status = ms_guard_call(run_work, &work, &message);
  finish_report((size_t)row, status, &message);
  /* Ending drops the closure, which closes what it captured: like any implicit close it runs shielded, since a
   * cancelled task would otherwise be cancelled again at its first park. */
  ms_shield_enter();
  work_ended(id, status, message);
  ms_shield_exit();
}

/* The row of an id ms_promise_new just returned. */
static size_t new_row(MsPromise id) { return (size_t)((uint64_t)id & 0xffffffffu) - 1; }

static void start_task(MsPromise id, MsObj *closure, const MsString *site) {
  const size_t row = new_row(id);
  Cold *const cold = &promise_table.cold.ptr[row];
  cold->closure = closure;
  cold->creator = ms_task_current();
  cold->started_at = ms_cleanup_base();
  keep_started(cold, site);
  link_started(row);
  MsTaskStatus status = MS_TASK_OK;
  void *const argument = (void *)(uintptr_t)id; // NOLINT(performance-no-int-to-ptr): the id travels as the argument word
  const MsTaskHandle task = ms_task_spawn(work_entry, argument, MS_SPAWN_DETACHED, 0, &status);
  if (task == 0) {
    unlink_started(row, cold->creator);
    cold->closure = NULL;
    cold->creator = 0;
    promise_release_started(cold);
    msrt_obj_drop(closure);
    promise_fail("promise: cannot start the work: out of stacks");
  }
  promise_table.cold.ptr[row].task = task;
}

/* Puts the work in this isolate's queue, where its waiter runs it inline or another isolate takes it once it is
 * `age_ns` old. False when workers are off or the queue has no room: the caller starts a task instead. */
static bool queue_work(MsPromise id, MsObj *closure, const MsString *site) {
  const size_t row = new_row(id);
  Cold *const cold = &promise_table.cold.ptr[row];
  Hot *const hot = &promise_table.hot.ptr[row];
  /* Stress mode queues every start aged, so any idle isolate may take it. */
  if (!ms_queue_push(ms_sched()->isolate, (uint64_t)id, closure, ms_workers_stress(), &cold->queue_sequence)) {
    return false;
  }
  cold->closure = closure;
  cold->creator = ms_task_current();
  cold->started_at = ms_cleanup_base();
  keep_started(cold, site);
  link_started(row);
  if (ms_workers_limit() <= 1) {
    /* No other thread can take it: it reads as deferred work its waiter runs, and starts at the next switch. */
    hot->flags |= FLAG_DEFERRED | FLAG_QUEUED;
    ms_sched_note_queued();
    return true;
  }
  hot->flags |= FLAG_DEFERRED | FLAG_QUEUED | FLAG_REMOTE_WAKE;
  ms_workers_nudge();
  return true;
}

MsPromise ms_promise_start_here(MsObj *closure, const MsString *site) {
  const MsPromise id = ms_promise_new();
  start_task(id, closure, site);
  return id;
}

MsPromise ms_promise_start(MsObj *closure, const MsString *site) {
  const MsPromise id = ms_promise_new();
  if (!queue_work(id, closure, site)) {
    start_task(id, closure, site);
  }
  return id;
}

/* Sends the work of `id` to run as a task on `target`, as if that isolate had taken it from the queue: the row reads as
 * queued work no queue holds, so its waiter finds it remote. False when the mail cannot be sent. */
static bool send_work(MsPromise id, MsObj *closure, const MsString *site, uint32_t target) {
  const size_t row = new_row(id);
  Cold *const cold = &promise_table.cold.ptr[row];
  Hot *const hot = &promise_table.hot.ptr[row];
  MsMail *const mail = ms_alloc(sizeof *mail);
  *mail = (MsMail){.kind = MS_MAIL_PROMISE, .a = MS_MAIL_START, .b = (uint64_t)id, .p = closure};
  if (!ms_isolate_post(target, mail)) {
    ms_free(mail);
    return false;
  }
  cold->closure = closure;
  cold->creator = ms_task_current();
  cold->started_at = ms_cleanup_base();
  keep_started(cold, site);
  link_started(row);
  hot->flags |= FLAG_DEFERRED | FLAG_QUEUED | FLAG_REMOTE_WAKE;
  return true;
}

MsPromise ms_promise_start_spread(MsObj *closure, const MsString *site) {
  const MsPromise id = ms_promise_new();
  const uint32_t target = ms_workers_spread_pick();
  if (target == MS_NO_ISOLATE || target == ms_sched()->isolate || !send_work(id, closure, site, target)) {
    start_task(id, closure, site);
  }
  return id;
}

/* Takes the queued work of `row` back from the queue. True when it is still this isolate's (its flags then read as
 * deferred work); false when another isolate took it, and the row now reads as running remotely. */
bool promise_claim_queued(size_t row) {
  Hot *const hot = &promise_table.hot.ptr[row];
  Cold *const cold = &promise_table.cold.ptr[row];
  hot->flags &= (uint16_t)~FLAG_QUEUED;
  const bool ours = ms_queue_remove(ms_sched()->isolate, (uint64_t)promise_make_id(row), cold->queue_sequence);
  if (cold->creator != 0 && ours) {
    unlink_started(row, cold->creator);
    cold->creator = 0;
  }
  if (!ours) {
    hot->flags &= (uint16_t)~FLAG_DEFERRED;
    hot->flags |= FLAG_REMOTE;
    cold->closure = NULL; /* the isolate that took it owns the closure now */
  }
  return ours;
}

MsPromise ms_promise_defer(MsObj *closure) {
  const MsPromise id = ms_promise_new();
  const size_t row = new_row(id);
  promise_table.hot.ptr[row].flags |= FLAG_DEFERRED;
  promise_table.cold.ptr[row].closure = closure;
  return id;
}

MsPromise ms_promise_start_idle(MsObj *closure, const MsString *site) {
  if (ms_task_count() <= 1) {
    return ms_promise_defer(closure);
  }
  return ms_promise_start_here(closure, site);
}

/* Records how a guarded inline run ended. */
static void end_guarded_run(MsPromise id, MsGuardStatus status, MsFaultText message) {
  const ptrdiff_t row = promise_row_of(id);
  if (row < 0 || status == MS_GUARD_OK || promise_table.hot.ptr[row].state != STATE_PENDING) {
    ms_fault_text_free(&message);
    return;
  }
  finish_report((size_t)row, status, &message);
  if (status == MS_GUARD_FAULT) {
    promise_table.cold.ptr[row].report = message;
    promise_table.hot.ptr[row].state = STATE_FAILED;
  } else {
    ms_fault_text_free(&message);
    promise_table.hot.ptr[row].state = STATE_CANCELLED;
  }
  promise_wake((size_t)row);
}

/* Runs the deferred work of `id` on the caller's stack, ending by `deadline` (NO_TIME: no limit). With `guarded`, a
 * fault or a cancel inside the work ends the promise as failed or cancelled instead of unwinding the caller (the
 * run of a wait group, which a failing member interrupts). */
bool promise_run_deferred(MsPromise id, int64_t deadline, bool guarded) {
  const ptrdiff_t found = promise_row_of(id);
  if (found < 0 || (promise_table.hot.ptr[found].flags & FLAG_DEFERRED) == 0) {
    return false;
  }
  const size_t row = (size_t)found;
  /* Work taken back from the queue ends only its own promise when it faults, as it would on another isolate. */
  const bool was_queued = (promise_table.hot.ptr[row].flags & FLAG_QUEUED) != 0;
  if (was_queued && deadline != NO_TIME) {
    /* Work on this stack notices a limit only at its own waits, so a bounded wait leaves queued work to run as a
     * task of its own, which a limit can cancel (a consumer that never waits would otherwise outlive it). */
    return false;
  }
  if (was_queued && ms_workers_stress()) {
    return false; /* stress mode: the waiter parks and another isolate takes the work */
  }
  if (was_queued && !promise_claim_queued(row)) {
    return false;
  }
  guarded = guarded || was_queued;
  promise_table.hot.ptr[row].flags &= (uint16_t)~FLAG_DEFERRED;
  MsObj *const closure = promise_table.cold.ptr[row].closure;
  promise_table.cold.ptr[row].closure = NULL;
  int64_t until = deadline;
  if (promise_table.cold.ptr[row].limit < until) {
    until = promise_table.cold.ptr[row].limit;
  }
  const int64_t inherited = ms_task_defer_deadline();
  if (inherited < until) {
    until = inherited;
  }
  const int64_t earlier = ms_task_set_defer_deadline(until);
  MsFaultText message = {0};
  MsGuardStatus status = MS_GUARD_OK;
  Work work = {.id = id, .closure = closure};
  const size_t handle = ms_cleanup_push(drop_closure, (uint8_t *)closure);
  if (guarded) {
    status = ms_guard_call(run_work, &work, &message);
  } else {
    run_work(&work);
  }
  ms_cleanup_discard(handle);
  msrt_obj_drop(closure);
  (void)ms_task_set_defer_deadline(earlier);
  end_guarded_run(id, status, message);
  return true;
}

/* ---- work taken by another isolate ---- */


/* The work of a promise another isolate owns, running here as a task. */
typedef Work Taken;

static void post_promise_mail(uint32_t target, MsMail *mail) {
  if (!ms_isolate_post(target, mail)) {
    ms_free(mail); /* the owner is gone: nobody waits for the result */
  }
}

static void send_ended(const Taken *taken, MsGuardStatus status, MsFaultText message) {
  MsMail *const mail = ms_alloc(sizeof *mail);
  *mail = (MsMail){.kind = MS_MAIL_PROMISE,
           .a = MAIL_ENDED | (uint64_t)status << 8,
           .b = (uint64_t)taken->id,
           .c = message.length,
           .p = message.bytes};
  if (!ms_isolate_post((uint32_t)((uint64_t)taken->id >> ISOLATE_SHIFT), mail)) {
    ms_free(message.bytes);
    ms_free(mail);
  }
  /* The mail carries the message text only; the structured detail stays with this isolate and ends here. */
  MsFaultText detail = {.detail = message.detail};
  ms_fault_text_free(&detail);
}

static void taken_entry(void *argument) {
  Taken *const taken = argument;
  MsMail *const started = ms_alloc(sizeof *started);
  *started = (MsMail){.kind = MS_MAIL_PROMISE, .a = MAIL_STARTED, .b = (uint64_t)taken->id, .c = ms_task_current()};
  post_promise_mail((uint32_t)((uint64_t)taken->id >> ISOLATE_SHIFT), started);
  MsFaultText message = {0};
  const MsGuardStatus status = ms_guard_call(run_work, taken, &message);
  if (status == MS_GUARD_FAULT && ms_task_capture() != 0) {
    ms_test_keep_fault(ms_task_capture(), &message);
  }
  /* Dropping the closure closes what it captured: like any implicit close it runs shielded. */
  ms_shield_enter();
  msrt_obj_drop(taken->closure);
  send_ended(taken, status, message);
  ms_shield_exit();
  ms_free(taken);
}

/* Runs the work of promise `id` of another isolate as a detached task here. True when the task exists. */
static bool run_taken(MsPromise id, MsObj *closure) {
  Taken *const taken = ms_alloc(sizeof *taken);
  *taken = (Taken){.id = id, .closure = closure};
  MsTaskStatus status = MS_TASK_OK;
  if (ms_task_spawn(taken_entry, taken, MS_SPAWN_DETACHED, 0, &status) != 0) {
    return true;
  }
  static const char text[] = "promise: cannot start the work: out of stacks";
  MsFaultText message = {.bytes = ms_alloc(sizeof text - 1), .length = sizeof text - 1};
  __builtin_memcpy(message.bytes, text, sizeof text - 1);
  send_ended(taken, MS_GUARD_FAULT, message);
  msrt_obj_drop(closure);
  ms_free(taken);
  return false;
}

/* Runs the owner's own queued work as a task of this isolate (its waiter is busy elsewhere). */
static bool run_own(MsPromise id) {
  const ptrdiff_t found = promise_row_of(id);
  if (found < 0) {
    return false;
  }
  const size_t row = (size_t)found;
  Cold *const cold = &promise_table.cold.ptr[row];
  promise_table.hot.ptr[row].flags &= (uint16_t) ~(FLAG_DEFERRED | FLAG_QUEUED);
  MsTaskStatus status = MS_TASK_OK;
  void *const argument = (void *)(uintptr_t)id; // NOLINT(performance-no-int-to-ptr): the id travels as the argument word
  cold->task = ms_task_spawn(work_entry, argument, MS_SPAWN_DETACHED, 0, &status);
  return cold->task != 0;
}

/* This thread's looking state (see ms_isolate_look_begin): on from the first timed rest for queued work until the
 * thread takes work, runs something of its own, or has seen the queues empty for MS_WORKER_EMPTY_LOOKS looks. */
typedef struct Look {
  bool on;
  uint32_t empty;  /* looks in a row that found every queue empty */
  int64_t rest_ns; /* the shortest rest before the next look */
} Look;
static _Thread_local Look look;

static void look_start(void) {
  if (!look.on) {
    look = (Look){.on = true, .rest_ns = MS_WORKER_BEAT_NS};
    ms_isolate_look_begin();
  }
}

static void look_stop(void) {
  if (look.on) {
    look.on = false;
    ms_isolate_look_end();
  }
}

/* Whether any queue this isolate may take from holds work. */
static bool queues_hold_work(uint32_t self) {
  for (uint32_t other = 0; other < MS_MAX_ISOLATES; other++) {
    if ((other == self || ms_isolate_live(other)) && ms_queue_length(other) != 0) {
      return true;
    }
  }
  return false;
}

/* The scheduler is about to block: take the oldest queued work of this isolate (its owner is idle) or of another that
 * waited out the beat. Otherwise say how long to rest: until the oldest entry may be taken, and while this isolate
 * is looking, at least its look rest, which doubles with every look that takes nothing. */
static bool idle_work(int64_t *wait_ns) {
  const uint32_t self = ms_sched()->isolate;
  *wait_ns = -1;
  if (ms_workers_limit() <= 1 && ms_queue_length(self) == 0) {
    return false; /* one thread and nothing queued: no clock, no other queue to look at */
  }
  const int64_t now = ms_sched_now();
  int64_t wait = -1;
  for (uint32_t other = 0; other < MS_MAX_ISOLATES; other++) {
    const bool own = other == self;
    if ((!own && !ms_isolate_live(other)) || ms_queue_length(other) == 0) {
      continue;
    }
    const int64_t beat = own ? ms_workers_own_beat() : MS_WORKER_BEAT_NS;
    uint64_t id = 0;
    void *work = NULL;
    if (ms_queue_steal(other, now, beat, &id, &work)) {
      if (own ? run_own((MsPromise)id) : run_taken((MsPromise)id, work)) {
        look_stop();
        if (queues_hold_work(self)) {
          ms_workers_nudge_next(); /* this isolate is busy now: the rest needs another one looking */
        }
        return true;
      }
      continue;
    }
    const int64_t oldest = ms_queue_oldest(other, now);
    if (oldest != INT64_MAX) {
      const int64_t left = oldest + beat - now;
      wait = wait < 0 || left < wait ? left : wait;
    }
  }
  const bool nudged = ms_isolate_take_nudge();
  if (wait < 0) {
    /* Nothing is queued. An isolate woken for work that its waiter ran first keeps looking for a while, so the next
     * starts of the burst wake nobody. */
    if (nudged) {
      look_start();
    }
    if (!look.on) {
      return false;
    }
    look.empty++;
    if (look.empty > MS_WORKER_EMPTY_LOOKS) {
      look_stop();
      if (!queues_hold_work(self)) {
        return false; /* a start from here on finds nobody looking and wakes an isolate */
      }
      look_start();
    }
    wait = look.rest_ns;
  } else {
    look_start();
    look.empty = 0;
    if (wait < look.rest_ns && ms_workers_limit() > 1) {
      wait = look.rest_ns;
    }
  }
  look.rest_ns = look.rest_ns * 2 < MS_WORKER_LOOK_MAX_NS ? look.rest_ns * 2 : MS_WORKER_LOOK_MAX_NS;
  *wait_ns = wait > 0 ? wait : 0;
  return false;
}

/* The scheduler left its idle path with something of its own to run: this isolate is not looking for work. */
static void idle_over(void) { look_stop(); }

/* One thread runs everything: its queued work starts as tasks, oldest first, before the next switch, which is when
 * a task started at once would first have run. With more threads the queue is left to waiters, the idle turn and
 * thieves. */
static void start_queued(void) {
  if (ms_workers_limit() > 1) {
    return;
  }
  const uint32_t self = ms_sched()->isolate;
  uint64_t id = 0;
  void *work = NULL;
  while (ms_queue_steal(self, 0, -1, &id, &work)) {
    (void)run_own((MsPromise)id);
  }
}

/* Whether work this isolate would take now is waiting (checked once the isolate is marked sleeping). */
static bool work_pending(void) {
  const uint32_t self = ms_sched()->isolate;
  const int64_t now = ms_sched_now();
  for (uint32_t other = 0; other < MS_MAX_ISOLATES; other++) {
    const bool own = other == self;
    if ((own || ms_isolate_live(other)) && ms_queue_length(other) != 0 &&
      ms_queue_oldest(other, now) <= now - (own ? ms_workers_own_beat() : MS_WORKER_BEAT_NS)) {
      return true;
    }
  }
  return false;
}

/* A promise event arrived by mail; takes `mail`. */
static void promise_mail(MsMail *mail) {
  const uint64_t op = mail->a & 0xffu;
  const MsPromise id = (MsPromise)mail->b;
  if (op == MS_MAIL_ASK) {
    ms_remote_serve(mail);
    return;
  }
  if (op == MS_MAIL_WATCH) {
    ms_remote_watch(mail);
    return;
  }
  if (op == MS_MAIL_SWITCH) {
    ms_cancel_serve(mail);
    return;
  }
  if (op == MS_MAIL_START) {
    (void)run_taken(id, mail->p);
    ms_free(mail);
    return;
  }
  if (op == MS_MAIL_CANCEL_ID) {
    ms_promise_cancel(id);
    ms_free(mail);
    return;
  }
  if (op != MAIL_CANCEL) {
    /* Mail about queued work means another isolate took it before its owner looked: the row reads as remote. */
    const ptrdiff_t queued = promise_row_of(id);
    if (queued >= 0 && (promise_table.hot.ptr[queued].flags & FLAG_QUEUED) != 0) {
      (void)promise_claim_queued((size_t)queued);
    }
  }
  if (op == MAIL_CANCEL) {
    ms_task_cancel((MsTaskHandle)mail->b);
  } else if (op == MAIL_DONE) {
    const ptrdiff_t row = promise_row_of(id);
    if (row >= 0) {
      complete((size_t)row, mail->p, (const MsTypeDesc *)mail->q, (mail->a >> 16 & 1u) != 0, (int64_t)mail->c);
    } else {
      drop_block(mail->p, (const MsTypeDesc *)mail->q, (int64_t)mail->c);
    }
  } else if (op == MAIL_STARTED) {
    const ptrdiff_t row = promise_row_of(id);
    if (row >= 0 && (promise_table.hot.ptr[row].flags & FLAG_REMOTE) != 0) {
      promise_table.cold.ptr[row].runner = mail->from;
      promise_table.cold.ptr[row].runner_task = (MsTaskHandle)mail->c;
      if ((promise_table.hot.ptr[row].flags & FLAG_WANT_CANCEL) != 0) {
        promise_request_cancel((size_t)row);
      }
    }
  } else if (op == MAIL_ENDED) {
    const MsFaultText message = {.bytes = mail->p, .length = mail->c};
    work_ended(id, (MsGuardStatus)(mail->a >> 8 & 0xffu), message);
  }
  ms_free(mail);
}

static void drop_queued_work(void *work) { msrt_obj_drop((MsObj *)__builtin_assume_aligned(work, _Alignof(MsObj))); }

/* Mail nobody will read: frees the result block or fault text it carries. Pipe credit no longer matters. */
static void discard_mail(MsMail *mail) {
  if (mail->kind != MS_MAIL_PROMISE) {
    return;
  }
  const uint32_t op = (uint32_t)(mail->a & 0xffu);
  if (op == MAIL_DONE && mail->p != NULL) {
    ms_slot_drop_owned((const MsTypeDesc *)mail->q, mail->p);
    ms_free(mail->p);
  } else if (op == MAIL_ENDED) {
    ms_free(mail->p);
  }
}

void ms_promises_teardown(void) {
  ms_queue_release(ms_sched()->isolate, drop_queued_work); /* work no thief took; stolen work belongs to the thief */
  ms_groups_teardown();
  ms_cancel_teardown();
  for (size_t row = 0; row < promise_table.hot.len; row++) {
    if (promise_table.hot.ptr[row].state != STATE_FREE) {
      promise_release_result(row);
      promise_release_started(&promise_table.cold.ptr[row]);
      ms_fault_text_free(&promise_table.cold.ptr[row].report);
    }
  }
  ms_free(promise_table.hot.ptr);
  ms_free(promise_table.cold.ptr);
  ms_free(promise_table.free_rows.ptr);
  ms_free(promise_table.watches.ptr);
  promise_table = (Table){0};
}

void ms_promise_hooks(MsSchedHooks *hooks) {
  hooks->end_started = promise_end_started;
  hooks->timer_live = promise_timer_live;
  hooks->timer_fire = promise_timer_fire;
  hooks->fd_ready = promise_fd_ready;
  hooks->mail = promise_mail;
  hooks->idle = idle_work;
  hooks->idle_over = idle_over;
  hooks->start_queued = start_queued;
  hooks->pending = work_pending;
  ms_group_hooks(hooks);
  hooks->teardown = ms_promises_teardown;
  hooks->discard_mail = discard_mail;
}
