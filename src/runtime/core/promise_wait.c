/* Waiting for promises, sleeps, limits and descriptor readiness. See promise.h. */
#include "runtime/core/promise_table.h"

#include "runtime/core/cancel.h"
#include "runtime/core/fault.h"
#include "runtime/core/fault_kept.h"
#include "runtime/core/group.h"
#include "runtime/core/isolate.h"
#include "runtime/core/promise_remote.h"
#include "runtime/core/queue.h"
#include "runtime/core/worker.h"

/* ---- waiting ---- */

static int64_t outcome(size_t row) {
  const Hot *const hot = &promise_table.hot.ptr[row];
  switch (hot->state) {
  case STATE_OK:
    return MS_PROMISE_OK;
  case STATE_ERROR:
    return MS_PROMISE_ERROR;
  case STATE_FAILED:
    return MS_PROMISE_FAILED;
  case STATE_CANCELLED:
    return (hot->flags & FLAG_TIMED_OUT) != 0 ? MS_PROMISE_TIMEOUT : MS_PROMISE_CANCELLED;
  case STATE_TAKEN:
    return MS_PROMISE_CLOSED;
  default:
    return -1;
  }
}

static int64_t earliest(int64_t a, int64_t b) { return a < b ? a : b; }

int64_t ms_promise_outcome(MsPromise id) {
  const ptrdiff_t row = promise_row_of(id);
  return row < 0 ? MS_PROMISE_CLOSED : outcome((size_t)row);
}

void ms_promise_watch(MsPromise id, uint64_t token) {
  const ptrdiff_t row = promise_row_of(id);
  if (row < 0 || promise_table.hot.ptr[row].state != STATE_PENDING) {
    ms_token_post_remote(token, 0);
    return;
  }
  watch_list_push(&promise_table.watches, (Watch){(uint32_t)row, promise_table.hot.ptr[row].generation, token});
  promise_table.hot.ptr[row].flags |= FLAG_WATCHED;
}

/* ms_promise_wait, which also says in `*settled` the row the outcome was read from (-1 when there is none). */
static inline MS_ALWAYS_INLINE int64_t wait_row(MsPromise id, int64_t timeout_ns, ptrdiff_t *settled) {
  *settled = -1;
  if (promise_is_foreign(id)) {
    return ms_remote_wait(id, timeout_ns);
  }
  const ptrdiff_t first = promise_row_of(id);
  if (first < 0) {
    return MS_PROMISE_CLOSED; /* its result was taken, which freed the row */
  }
  const int64_t asked = timeout_ns >= 0 ? ms_sched_now() + timeout_ns : NO_TIME;
  int64_t deadline = earliest(asked, earliest(promise_table.cold.ptr[first].limit, ms_task_defer_deadline()));
  ptrdiff_t row = promise_run_row(id, (size_t)first, deadline);
  for (;; row = promise_row_of(id)) {
    if (row < 0) {
      return MS_PROMISE_CLOSED;
    }
    const int64_t code = outcome((size_t)row);
    if (code >= 0) {
      *settled = row;
      return code;
    }
    const uint32_t woke = promise_park_on(id, deadline == NO_TIME ? -1 : deadline);
    if (woke == MS_WAIT_CANCELLED) {
      (void)ms_promise_end(id);
      return MS_WAITER_CANCELLED;
    }
    const ptrdiff_t after = promise_row_of(id);
    if (after < 0) {
      return MS_PROMISE_CLOSED;
    }
    const int64_t done = outcome((size_t)after);
    if (done >= 0) {
      *settled = after;
      return done;
    }
    if (woke == MS_WAIT_TIMEOUT) {
      /* The promise's own limit passed: stop it as the limit timer does and wait for its work to unwind, so a
       * resource the work holds is closed when `wait` answers (a race between this wake and the timer left it open). */
      const int64_t limit = promise_table.cold.ptr[after].limit;
      if (limit != NO_TIME && limit <= ms_sched_now()) {
        promise_timer_fire((uint64_t)id, limit);
        deadline = asked;
        continue;
      }
      promise_request_cancel((size_t)after);
      return MS_PROMISE_TIMEOUT;
    }
  }
}

int64_t ms_promise_wait(MsPromise id, int64_t timeout_ns) {
  ptrdiff_t settled = -1;
  return wait_row(id, timeout_ns, &settled);
}

MS_ALWAYS_INLINE int64_t ms_promise_result(MsPromise id, const MsTypeDesc *desc, uint8_t *out, bool *taken) {
  ptrdiff_t settled = -1;
  const int64_t code = wait_row(id, -1, &settled);
  *taken = false;
  if (code == MS_PROMISE_OK) {
    *taken = settled >= 0 ? promise_take_row((size_t)settled, desc, out) : ms_promise_take(id, desc, out);
  }
  return code;
}

bool ms_promise_finished(MsPromise id) {
  if (promise_is_foreign(id)) {
    return false; /* asking its owner waits */
  }
  const ptrdiff_t row = promise_row_of(id);
  return row < 0 || promise_table.hot.ptr[row].state != STATE_PENDING;
}

bool ms_promise_done(MsPromise id) {
  if (promise_is_foreign(id)) {
    return ms_remote_done(id);
  }
  const ptrdiff_t row = promise_row_of(id);
  if (row < 0) {
    return true;
  }
  const bool elsewhere = (promise_table.hot.ptr[row].flags & (FLAG_QUEUED | FLAG_REMOTE)) != 0;
  if (promise_table.hot.ptr[row].state == STATE_PENDING && (promise_table.cold.ptr[row].closure != NULL || elsewhere)) {
    /* A task that has not run yet gets its turn, and mail from the isolate that took the work is read, so
     * polling done makes progress. */
    ms_task_yield();
  }
  const ptrdiff_t after = promise_row_of(id);
  return after < 0 || promise_table.hot.ptr[after].state != STATE_PENDING;
}

MsPromiseProbe ms_promise_probe(MsPromise id) {
  if (promise_is_foreign(id)) {
    return ms_remote_probe(id);
  }
  const ptrdiff_t row = promise_row_of(id);
  if (row < 0) {
    return MS_PROMISE_GONE;
  }
  const uint8_t state = promise_table.hot.ptr[row].state;
  if (state == STATE_PENDING) {
    return MS_PROMISE_PENDING;
  }
  return promise_ended_without_value(state) ? MS_PROMISE_FAILED_PROBE : MS_PROMISE_DONE_PROBE;
}

bool ms_promise_is_foreign(MsPromise id) { return promise_is_foreign(id); }

bool ms_promise_completes_elsewhere(MsPromise id) {
  if (promise_is_foreign(id)) {
    return true;
  }
  const ptrdiff_t row = promise_row_of(id);
  return row >= 0 && promise_table.hot.ptr[row].state == STATE_PENDING && (promise_table.hot.ptr[row].flags & FLAG_REMOTE_WAKE) != 0;
}

void ms_promise_set_grouped(MsPromise id, bool grouped) {
  if (promise_is_foreign(id)) {
    ms_remote_set_grouped(id, grouped);
    return;
  }
  const ptrdiff_t row = promise_row_of(id);
  if (row < 0) {
    return;
  }
  if (grouped) {
    promise_table.hot.ptr[row].flags |= FLAG_GROUPED;
  } else {
    promise_table.hot.ptr[row].flags &= (uint16_t)~FLAG_GROUPED;
  }
}

bool ms_promise_run_inline(MsPromise id) {
  if (promise_is_foreign(id)) {
    return ms_remote_run_inline(id);
  }
  const ptrdiff_t row = promise_row_of(id);
  if (row < 0 || promise_table.hot.ptr[row].state != STATE_PENDING || (promise_table.hot.ptr[row].flags & FLAG_DEFERRED) == 0) {
    return false;
  }
  /* False when another isolate took the work from the queue first: the caller must not read that as a run. */
  return promise_run_deferred(id, NO_TIME, true);
}

/* ---- waiting for any ---- */

static ptrdiff_t first_done(const MsPromise *ids, size_t count) {
  for (size_t at = 0; at < count; at++) {
    if (promise_is_foreign(ids[at])) {
      if (ms_remote_probe(ids[at]) != MS_PROMISE_PENDING) {
        return (ptrdiff_t)at;
      }
      continue;
    }
    const ptrdiff_t row = promise_row_of(ids[at]);
    if (row < 0 || promise_table.hot.ptr[row].state != STATE_PENDING) {
      return (ptrdiff_t)at;
    }
  }
  return -1;
}

static void set_tokens(const MsPromise *ids, size_t count, uint64_t from, uint64_t to) {
  for (size_t at = 0; at < count; at++) {
    if (promise_is_foreign(ids[at])) {
      continue;
    }
    const ptrdiff_t row = promise_row_of(ids[at]);
    if (row < 0) {
      continue;
    }
    if (to != 0 && promise_table.hot.ptr[row].token != 0) {
      promise_fail("promise: another task is already waiting on this promise");
    }
    if (to != 0 || promise_table.hot.ptr[row].token == from) {
      promise_table.hot.ptr[row].token = to;
    }
  }
}

static bool is_queued(MsPromise id) {
  const ptrdiff_t row = promise_row_of(id);
  return row >= 0 && (promise_table.hot.ptr[row].flags & FLAG_QUEUED) != 0;
}

/* Whether any id is another isolate's. */
static bool any_foreign(const MsPromise *ids, size_t count) {
  for (size_t at = 0; at < count; at++) {
    if (promise_is_foreign(ids[at])) {
      return true;
    }
  }
  return false;
}

/* The first finished id of a list that may hold other isolates' promises (a gone one reads as finished). */
static ptrdiff_t first_done_mixed(const MsPromise *ids, size_t count) {
  for (size_t at = 0; at < count; at++) {
    if (promise_is_foreign(ids[at])) {
      if (ms_remote_probe(ids[at]) != MS_PROMISE_PENDING) {
        return (ptrdiff_t)at;
      }
      continue;
    }
    const ptrdiff_t row = promise_row_of(ids[at]);
    if (row < 0 || promise_table.hot.ptr[row].state != STATE_PENDING) {
      return (ptrdiff_t)at;
    }
  }
  return -1;
}

/* wait_any over a list with promises of other isolates: local ones wake the waiter through their token slot, the
 * others by watching, so one REMOTE token serves all of them. */
static int64_t wait_any_mixed(const MsPromise *ids, size_t count, int64_t timeout_ns) {
  int64_t deadline = timeout_ns >= 0 ? ms_sched_now() + timeout_ns : NO_TIME;
  deadline = earliest(deadline, ms_task_defer_deadline());
  ptrdiff_t done = first_done_mixed(ids, count);
  for (size_t at = 0; done < 0 && at < count; at++) {
    if (promise_is_foreign(ids[at]) ? ms_remote_run_inline(ids[at]) : promise_run_deferred(ids[at], deadline, false)) {
      done = first_done_mixed(ids, count);
    }
  }
  for (;;) {
    if (done >= 0) {
      return done;
    }
    const uint64_t token = ms_token_new(MS_TOKEN_REMOTE);
    if (token == 0) {
      promise_fail("promise: out of wait tokens");
    }
    set_tokens(ids, count, 0, token);
    for (size_t at = 0; at < count; at++) {
      if (promise_is_foreign(ids[at])) {
        (void)ms_remote_watch_post(ids[at], token);
      }
    }
    uint64_t value = 0;
    uint32_t result = 0;
    (void)ms_token_park_at(token, deadline == NO_TIME ? -1 : deadline, &value, &result);
    set_tokens(ids, count, token, 0);
    (void)ms_token_free(token);
    if (result == MS_WAIT_CANCELLED) {
      return MS_WAITER_CANCELLED;
    }
    done = first_done_mixed(ids, count);
    if (done < 0 && result == MS_WAIT_TIMEOUT) {
      return -1;
    }
  }
}

int64_t ms_promise_wait_any(const MsPromise *ids, size_t count, int64_t timeout_ns) {
  if (any_foreign(ids, count)) {
    return wait_any_mixed(ids, count, timeout_ns);
  }
  int64_t deadline = timeout_ns >= 0 ? ms_sched_now() + timeout_ns : NO_TIME;
  deadline = earliest(deadline, ms_task_defer_deadline());
  if (first_done(ids, count) < 0) {
    /* Only work deferred to its waiter runs here; queued work stays for the isolate's idle turn or another's. */
    for (size_t at = 0; at < count && first_done(ids, count) < 0; at++) {
      if (!is_queued(ids[at])) {
        (void)promise_run_deferred(ids[at], deadline, false);
      }
    }
  }
  for (;;) {
    const ptrdiff_t done = first_done(ids, count);
    if (done >= 0) {
      return done;
    }
    bool elsewhere = false;
    for (size_t at = 0; at < count; at++) {
      elsewhere = elsewhere || ms_promise_completes_elsewhere(ids[at]);
    }
    const uint64_t token = ms_token_new(elsewhere ? MS_TOKEN_REMOTE : 0);
    if (token == 0) {
      promise_fail("promise: out of wait tokens");
    }
    set_tokens(ids, count, 0, token);
    for (size_t at = 0; at < count; at++) {
      if (promise_is_foreign(ids[at])) {
        (void)ms_remote_watch_post(ids[at], token); /* an owner that is gone reads as done below */
      }
    }
    uint64_t value = 0;
    uint32_t result = 0;
    (void)ms_token_park_at(token, deadline == NO_TIME ? -1 : deadline, &value, &result);
    set_tokens(ids, count, token, 0);
    (void)ms_token_free(token);
    if (result == MS_WAIT_CANCELLED) {
      return MS_WAITER_CANCELLED;
    }
    const ptrdiff_t after = first_done(ids, count);
    if (after >= 0) {
      return after;
    }
    if (result == MS_WAIT_TIMEOUT) {
      return -1;
    }
  }
}

/* ---- sleeps and limits ---- */

MsPromise ms_promise_sleep(int64_t ns) {
  const MsPromise id = ms_promise_new();
  const size_t row = promise_row_or_fault(id);
  const int64_t at = ms_sched_now() + (ns > 0 ? ns : 0);
  promise_table.cold.ptr[row].deadline = at;
  ms_sched_arm((uint64_t)id, at);
  return id;
}

/* The wait of a readiness promise ran out: the continuation completes it, or it reads as MS_WAIT_TIMEOUT. */
static void readiness_timed_out(MsPromise id, size_t row) {
  promise_leave_fd(id, row);
  MsPromiseRetry retry = promise_table.cold.ptr[row].retry;
  promise_table.cold.ptr[row].retry = NULL;
  if (retry != NULL) {
    (void)retry(id, promise_table.cold.ptr[row].retry_state, MS_WAIT_TIMEOUT);
  }
  const ptrdiff_t again = promise_row_of(id);
  if (again >= 0 && promise_table.hot.ptr[again].state == STATE_PENDING) {
    ms_promise_io_done_int(id, MS_WAIT_TIMEOUT);
  }
}

bool promise_timer_live(uint64_t id, int64_t deadline) {
  const ptrdiff_t row = promise_row_of((MsPromise)id);
  return row >= 0 && promise_table.hot.ptr[row].state == STATE_PENDING &&
       (promise_table.cold.ptr[row].deadline == deadline || promise_table.cold.ptr[row].limit == deadline);
}

void promise_timer_fire(uint64_t id, int64_t deadline) {
  const MsPromise promise = (MsPromise)id;
  ptrdiff_t row = promise_row_of(promise);
  if (row >= 0 && promise_table.cold.ptr[row].limit == deadline) {
    promise_table.hot.ptr[row].flags |= FLAG_TIMED_OUT;
    promise_table.cold.ptr[row].limit = NO_TIME;
    promise_stop(promise);
    row = promise_row_of(promise);
  }
  if (row >= 0 && promise_table.hot.ptr[row].state == STATE_PENDING && promise_table.cold.ptr[row].deadline == deadline) {
    promise_table.cold.ptr[row].deadline = NO_TIME;
    if (promise_table.cold.ptr[row].fd >= 0) {
      readiness_timed_out(promise, (size_t)row);
    } else {
      ms_promise_io_done_unit(promise);
    }
  }
}

/* ---- descriptor readiness ---- */

static void arm_timeout(MsPromise id, size_t row, int64_t timeout_ns) {
  if (timeout_ns >= 0) {
    const int64_t at = ms_sched_now() + timeout_ns;
    promise_table.cold.ptr[row].deadline = at;
    ms_sched_arm((uint64_t)id, at);
  }
}

MsPromise ms_promise_ready(int fd, uint32_t events, int64_t timeout_ns) {
  const MsPromise id = ms_promise_new();
  const int armed = ms_sched_fd_wait_begin((uint64_t)id, fd, events);
  if (armed == MS_POLL_FAILED) {
    ms_promise_drop(id);
    return -1;
  }
  if (armed == MS_POLL_ALWAYS) {
    ms_promise_io_done_int(id, events & (MS_WAIT_READ | MS_WAIT_WRITE));
    return id;
  }
  const size_t row = promise_row_or_fault(id);
  promise_table.cold.ptr[row].fd = fd;
  promise_table.cold.ptr[row].events = events;
  arm_timeout(id, row, timeout_ns);
  return id;
}

bool ms_promise_io_on_ready(MsPromise id, int fd, uint32_t events, int64_t timeout_ns, MsPromiseRetry retry,
              uintptr_t state) {
  const ptrdiff_t found = promise_row_of(id);
  if (found < 0) {
    return false;
  }
  const int armed = ms_sched_fd_wait_begin((uint64_t)id, fd, events);
  if (armed == MS_POLL_FAILED) {
    return false;
  }
  if (armed == MS_POLL_ALWAYS) {
    (void)retry(id, state, events & (MS_WAIT_READ | MS_WAIT_WRITE));
    return true;
  }
  Cold *const cold = &promise_table.cold.ptr[found];
  cold->fd = fd;
  cold->events = events;
  cold->retry = retry;
  cold->retry_state = state;
  arm_timeout(id, (size_t)found, timeout_ns);
  return true;
}

/* The poller reports `bits` for the descriptor `id` waits on: true when the promise is done with it. */
bool promise_fd_ready(uint64_t id, uint32_t bits) {
  const MsPromise promise = (MsPromise)id;
  ptrdiff_t found = promise_row_of(promise);
  if (found < 0 || promise_table.hot.ptr[found].state != STATE_PENDING) {
    return true;
  }
  const uint32_t wanted = bits & (promise_table.cold.ptr[found].events | MS_WAIT_HUP);
  if (wanted == 0) {
    return false;
  }
  const MsPromiseRetry retry = promise_table.cold.ptr[found].retry;
  if (retry != NULL && !retry(promise, promise_table.cold.ptr[found].retry_state, wanted)) {
    return false;
  }
  found = promise_row_of(promise);
  if (found >= 0) {
    promise_table.cold.ptr[found].fd = -1; /* the scheduler removes the wait now */
    promise_table.cold.ptr[found].retry = NULL;
  }
  if (retry == NULL) {
    ms_promise_io_done_int(promise, wanted);
  }
  return true;
}
