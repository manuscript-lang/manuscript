/* runtime/std/http_sync.h: what the HTTP client needs to wait without a thread of its own. A mutex, and the
 * waiter hooks: a task parks on a token and the engine thread posts it; a plain thread (a test, a tool)
 * blocks on a condition. The runtime installs the task hooks once with ms_http_set_wait_ops. */
#ifndef MS_RUNTIME_STD_HTTP_SYNC_H
#define MS_RUNTIME_STD_HTTP_SYNC_H

#include "base/safe.h"

typedef struct MsHttpMutex MsHttpMutex;
MsHttpMutex *ms_http_mutex_new(void);
void ms_http_mutex_free(MsHttpMutex *mutex);
void ms_http_mutex_lock(MsHttpMutex *mutex);
void ms_http_mutex_unlock(MsHttpMutex *mutex);

/* How a wait ended. */
typedef enum MsHttpWake {
  MS_HTTP_WOKEN = 0,
  MS_HTTP_WAIT_TIMED_OUT = 1,
  MS_HTTP_WAIT_CANCELLED = 2
} MsHttpWake;

typedef struct MsHttpWaitOps {
  /* A fresh waiter, called by the thread that will wait. */
  uint64_t (*begin)(void);
  /* Parks until `wake(waiter)` was called (before or during), the deadline passes (negative: none) or the
   * caller is cancelled. */
  MsHttpWake (*wait)(uint64_t waiter, int64_t timeout_ns);
  /* From any thread. */
  void (*wake)(uint64_t waiter);
  /* The waiter is finished with. */
  void (*end)(uint64_t waiter);
} MsHttpWaitOps;

void ms_http_set_wait_ops(const MsHttpWaitOps *ops);
const MsHttpWaitOps *ms_http_wait_ops(void);

#endif
