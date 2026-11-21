/* signals.c: `watch_signals` for @std/process. A watcher buffers up to `capacity` signal numbers; the platform layer
 * (sys/process.h) says when one may be waiting, and `next` parks until it is. Observers keep no thread of their own: a
 * task waiting on a watcher parks on the platform's wake-up. */
#include "runtime/std/signals.h"

#include <stdatomic.h>

#include "base/alloc.h"
#include "runtime/core/isolate.h"
#include "runtime/core/task.h"
#include "runtime/std/fail.h"
#include "runtime/sys/process.h"

enum { MAX_CAPACITY = 1048576, DEFAULT_CAPACITY = 128, DRAIN = 256 };

typedef struct MsSignalWatcher {
  MsObj header;
  MsSysSignals *observer;
  uint8_t *queue; /* a ring of `capacity` signal numbers */
  size_t capacity, head, count;
  bool closed;
  atomic_uint_least64_t parked; /* the token of the task waiting where there is no descriptor; 0 when none */
} MsSignalWatcher;

static void watcher_drop(MsObj *object) {
  MsSignalWatcher *watcher = (MsSignalWatcher *)object;
  if (watcher->observer != NULL) {
    ms_sys_signals_destroy(watcher->observer);
  }
  ms_free(watcher->queue);
  ms_free(watcher);
}

/* Wakes the task parked on a token, once: the token is taken before it is posted. May run on an OS thread. */
static void notify(void *context) {
  MsSignalWatcher *watcher = context;
  const uint64_t token = atomic_exchange(&watcher->parked, 0);
  if (token != 0) {
    ms_token_post_remote(token, 1);
  }
}

/* Parks the task until a signal may be waiting or the watcher is closed. Returns the MS_WAIT_* bits of the wake. */
static uint32_t wait_for_signal(MsSignalWatcher *watcher) {
  const int fd = ms_sys_signals_fd(watcher->observer);
  if (fd >= 0) {
    return ms_task_wait_fd(fd, MS_WAIT_READ, -1);
  }
  /* A fresh token per park: a remote token counts as a pending wake-up only until its first post. */
  const uint64_t token = ms_token_new(MS_TOKEN_REMOTE);
  atomic_store(&watcher->parked, token);
  /* The platform counts before it notifies, and this stores the token before it re-reads the counts, so one of the two
   * sees the other. */
  uint32_t result = 0;
  if (!watcher->closed && !ms_sys_signals_pending(watcher->observer)) {
    uint64_t value = 0;
    (void)ms_token_park(token, -1, &value, &result);
  }
  atomic_store(&watcher->parked, 0);
  (void)ms_token_free(token);
  return result;
}

static uint8_t finish_status(uint8_t status, MsString *err) {
  MsFail fail = ms_fail_new();
  ms_fail_status(&fail, status);
  return ms_fail_finish(&fail, err);
}

uint8_t msstd_process_watch_signals(const MsList *signals, uint8_t has_capacity, int64_t capacity, MsObj **out,
                                    MsString *err) {
  const int64_t size = has_capacity != 0 ? capacity : DEFAULT_CAPACITY;
  if (signals->len == 0 || size < 1 || size > MAX_CAPACITY) {
    return finish_status(MS_STATUS_INVALID_INPUT, err);
  }
  uint64_t mask = 0;
  const int64_t *list = (const int64_t *)(const void *)signals->ptr;
  for (size_t i = 0; i < signals->len; i++) {
    if (!ms_sys_signal_valid(list[i])) {
      return finish_status(MS_STATUS_INVALID_INPUT, err);
    }
    mask |= UINT64_C(1) << (list[i] - 1);
  }
  MsSignalWatcher *watcher = ms_alloc_zeroed(sizeof *watcher);
  watcher->header.drop = watcher_drop;
  watcher->capacity = (size_t)size;
  watcher->queue = ms_alloc(watcher->capacity);
  const int code = ms_sys_signals_open(mask, watcher->capacity, notify, watcher, &watcher->observer);
  MsFail fail = ms_fail_new();
  if (code == MS_SYS_SIGNALS_FULL) {
    ms_fail_status(&fail, MS_STATUS_LIMIT_EXCEEDED);
  } else if (code != 0) {
    ms_fail_uv(&fail, code, "signal", ms_span_of(NULL, 0));
  }
  if (ms_fail_failed(&fail)) {
    watcher->observer = NULL;
    watcher_drop(&watcher->header);
  } else {
    *out = &watcher->header;
  }
  return ms_fail_finish(&fail, err);
}

/* Moves the signals the platform holds into the ring; those beyond `capacity` are dropped, as a full pipe drops them. */
static void fill(MsSignalWatcher *watcher) {
  uint8_t buffer[DRAIN];
  size_t taken = 0;
  while ((taken = ms_sys_signals_take(watcher->observer, buffer, sizeof buffer)) > 0) {
    for (size_t i = 0; i < taken && watcher->count < watcher->capacity; i++) {
      watcher->queue[(watcher->head + watcher->count++) % watcher->capacity] = buffer[i];
    }
  }
}

uint8_t msstd_process_signal_next(MsObj *object, int64_t *out, MsString *err) {
  MsSignalWatcher *watcher = (MsSignalWatcher *)object;
  for (;;) {
    if (watcher->closed) {
      return MS_STATUS_CLOSED;
    }
    fill(watcher);
    if (watcher->count > 0) {
      *out = watcher->queue[watcher->head];
      watcher->head = (watcher->head + 1) % watcher->capacity;
      watcher->count--;
      return MS_STATUS_OK;
    }
    MsFail fail = ms_fail_new();
    if (ms_fail_poll_cancel(&fail)) {
      return ms_fail_finish(&fail, err);
    }
    if (ms_task_read_limit_passed()) {
      return finish_status(MS_STATUS_TIMED_OUT, err);
    }
    if ((wait_for_signal(watcher) & MS_WAIT_CANCELLED) != 0) {
      ms_fail_text(&fail, "cancelled");
      return ms_fail_finish(&fail, err);
    }
  }
}

void msstd_process_signal_close(MsObj *object) {
  MsSignalWatcher *watcher = (MsSignalWatcher *)object;
  if (!watcher->closed) {
    watcher->closed = true;
    ms_sys_signals_stop(watcher->observer);
  }
}
