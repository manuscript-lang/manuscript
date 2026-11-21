/* Threads and the wake-up signal between them on every platform, over libuv's portable thread API. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include <uv.h>

#include "base/alloc.h"
#include "runtime/sys/sys.h"

struct MsSysThread {
  uv_thread_t thread;
};

MsSysThread *ms_sys_thread_spawn(size_t stack, MsSysThreadFn start, void *arg) {
  MsSysThread *const handle = ms_alloc(sizeof *handle);
  const uv_thread_options_t options = {.flags = stack == 0 ? UV_THREAD_NO_FLAGS : UV_THREAD_HAS_STACK_SIZE,
                                       .stack_size = stack};
  if (uv_thread_create_ex(&handle->thread, &options, start, arg) != 0) {
    ms_free(handle);
    return NULL;
  }
  return handle;
}

void ms_sys_thread_join(MsSysThread *thread) {
  (void)uv_thread_join(&thread->thread);
  ms_free(thread);
}

struct MsSysSignal {
  uv_mutex_t lock;
  uv_cond_t cond;
  bool sent;
};

MsSysSignal *ms_sys_signal_new(void) {
  MsSysSignal *const signal = ms_alloc(sizeof *signal);
  signal->sent = false;
  if (uv_mutex_init(&signal->lock) != 0) {
    ms_free(signal);
    return NULL;
  }
  if (uv_cond_init(&signal->cond) != 0) {
    uv_mutex_destroy(&signal->lock);
    ms_free(signal);
    return NULL;
  }
  return signal;
}

void ms_sys_signal_free(MsSysSignal *signal) {
  uv_cond_destroy(&signal->cond);
  uv_mutex_destroy(&signal->lock);
  ms_free(signal);
}

bool ms_sys_signal_wait(MsSysSignal *signal, int64_t timeout_ns) {
  uv_mutex_lock(&signal->lock);
  if (!signal->sent) {
    if (timeout_ns < 0) {
      uv_cond_wait(&signal->cond, &signal->lock);
    } else {
      (void)uv_cond_timedwait(&signal->cond, &signal->lock, (uint64_t)timeout_ns);
    }
  }
  const bool sent = signal->sent;
  signal->sent = false;
  uv_mutex_unlock(&signal->lock);
  return sent;
}

void ms_sys_signal_send(MsSysSignal *signal) {
  uv_mutex_lock(&signal->lock);
  signal->sent = true;
  uv_mutex_unlock(&signal->lock);
  uv_cond_signal(&signal->cond);
}
