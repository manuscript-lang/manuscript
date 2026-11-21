/* runtime/std/http_sync.c: the mutex, and the default waiter for threads that are not scheduler tasks. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "runtime/std/http_sync.h"

#include <uv.h>

#include "base/alloc.h"

struct MsHttpMutex {
  uv_mutex_t mutex;
};

MsHttpMutex *ms_http_mutex_new(void) {
  MsHttpMutex *mutex = ms_alloc_zeroed(sizeof *mutex);
  (void)uv_mutex_init(&mutex->mutex);
  return mutex;
}

void ms_http_mutex_free(MsHttpMutex *mutex) {
  if (mutex != NULL) {
    uv_mutex_destroy(&mutex->mutex);
    ms_free(mutex);
  }
}

void ms_http_mutex_lock(MsHttpMutex *mutex) {
  uv_mutex_lock(&mutex->mutex);
}

void ms_http_mutex_unlock(MsHttpMutex *mutex) {
  uv_mutex_unlock(&mutex->mutex);
}

/* ---- the default waiter: a condition and a flag ---- */

typedef struct Plain {
  uv_mutex_t mutex;
  uv_cond_t cond;
  bool woken;
} Plain;

static uint64_t plain_begin(void) {
  Plain *plain = ms_alloc_zeroed(sizeof *plain);
  (void)uv_mutex_init(&plain->mutex);
  (void)uv_cond_init(&plain->cond);
  return (uint64_t)(uintptr_t)plain;
}

static MsHttpWake plain_wait(uint64_t waiter, int64_t timeout_ns) {
  Plain *plain = (Plain *)(uintptr_t)waiter;
  uv_mutex_lock(&plain->mutex);
  MsHttpWake result = MS_HTTP_WOKEN;
  while (!plain->woken && result == MS_HTTP_WOKEN) {
    if (timeout_ns < 0) {
      uv_cond_wait(&plain->cond, &plain->mutex);
    } else if (uv_cond_timedwait(&plain->cond, &plain->mutex, (uint64_t)timeout_ns) != 0) {
      result = MS_HTTP_WAIT_TIMED_OUT;
    }
  }
  uv_mutex_unlock(&plain->mutex);
  return result;
}

static void plain_wake(uint64_t waiter) {
  Plain *plain = (Plain *)(uintptr_t)waiter;
  uv_mutex_lock(&plain->mutex);
  plain->woken = true;
  uv_cond_signal(&plain->cond);
  uv_mutex_unlock(&plain->mutex);
}

static void plain_end(uint64_t waiter) {
  Plain *plain = (Plain *)(uintptr_t)waiter;
  uv_cond_destroy(&plain->cond);
  uv_mutex_destroy(&plain->mutex);
  ms_free(plain);
}

static const MsHttpWaitOps plain_ops = {plain_begin, plain_wait, plain_wake, plain_end};
static const MsHttpWaitOps *installed = &plain_ops;

void ms_http_set_wait_ops(const MsHttpWaitOps *ops) {
  installed = ops != NULL ? ops : &plain_ops;
}

const MsHttpWaitOps *ms_http_wait_ops(void) {
  return installed;
}
