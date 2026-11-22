/* The Windows half of the reactor: what libuv's loop does not cover for the scheduler.
 *
 * Sockets are libuv poll handles, as everywhere (reactor.c). Two more things reach the scheduler here:
 *   - Waitable kernel objects (a child process). The thread pool waits for them and tells the loop through an async
 *     handle; no thread of ours blocks.
 *   - A high-resolution timer. The loop sleeps in whole system ticks (about 15 ms), so a deadline arms a waitable
 *     timer whose signal wakes the loop at the finest resolution the system has.
 *
 * Events use the keys the scheduler already waits on: an object's waiters wait on its handle.
 * Compiled by the Windows legs only; the PR checks are Linux.
 */
#include <signal.h>

#include "base/alloc.h"
#include "base/list.h"
#include "runtime/io/reactor_internal.h"

#include <windows.h>

enum {
  SPIN_BELOW_NANOSECONDS = 1000000, /* the timer's own latency would overshoot a shorter wait */
  NANOSECONDS_PER_TICK = 100,       /* the unit of a waitable timer's due time */
};

typedef struct MsWindowsState MsWindowsState;

/* A watched kernel object. Its address is the context of the thread-pool wait, so it must not move. */
typedef struct MsObject {
  struct MsObject *next; /* the list in MsWindowsState */
  uintptr_t key;
  HANDLE wait;
  MsWindowsState *state;
} MsObject;

MS_LIST_DEFINE(KeyList, key_list, uintptr_t)

struct MsWindowsState {
  MsIoReactor *reactor;
  uv_async_t signalled_async; /* thread-pool waits tell the loop here */
  bool async_open;
  CRITICAL_SECTION lock; /* guards `signalled` */
  KeyList signalled;     /* objects that fired and are not yet queued */
  MsObject *objects;     /* every watched object */
  HANDLE timer;          /* the high-resolution timer, NULL when the system has none */
  HANDLE timer_wait;
};

static MsWindowsState *state_of(const MsIoReactor *reactor) { return ms_io_reactor_platform(reactor); }

/* ---- the high-resolution timer ---- */

static VOID CALLBACK on_timer_signal(PVOID context, BOOLEAN timed_out) {
  (void)timed_out;
  (void)uv_async_send(context);
}

static void timer_open(MsWindowsState *state) {
  enum { CREATE_WAITABLE_TIMER_HIGH_RESOLUTION_FLAG = 0x2, TIMER_ALL_ACCESS_RIGHTS = 0x1F0003 };
  state->timer = CreateWaitableTimerExW(NULL, NULL, CREATE_WAITABLE_TIMER_HIGH_RESOLUTION_FLAG, TIMER_ALL_ACCESS_RIGHTS);
  if (state->timer == NULL) {
    return; /* before Windows 10 1803: the caller falls back to a millisecond timer */
  }
  uv_async_t *const wake = ms_io_reactor_wake_handle(state->reactor);
  if (!RegisterWaitForSingleObject(&state->timer_wait, state->timer, on_timer_signal, wake, INFINITE, WT_EXECUTEDEFAULT)) {
    (void)CloseHandle(state->timer);
    state->timer = NULL;
  }
}

static void timer_close(MsWindowsState *state) {
  if (state->timer == NULL) {
    return;
  }
  (void)UnregisterWaitEx(state->timer_wait, INVALID_HANDLE_VALUE); /* returns after a running callback */
  (void)CloseHandle(state->timer);
  state->timer = NULL;
}

static void timer_arm(const MsWindowsState *state, int64_t nanoseconds) {
  LARGE_INTEGER due;
  const int64_t ticks = nanoseconds / NANOSECONDS_PER_TICK;
  due.QuadPart = -(ticks > 0 ? ticks : 1); /* a negative due time is relative */
  (void)SetWaitableTimer(state->timer, &due, 0, NULL, NULL, FALSE);
}

static int64_t now_nanoseconds(void) { return (int64_t)uv_hrtime(); }

bool ms_io_platform_wait(MsIoReactor *reactor, int64_t timeout_ns) {
  MsWindowsState *const state = state_of(reactor);
  uv_loop_t *const loop = ms_io_reactor_loop(reactor);
  if (timeout_ns < SPIN_BELOW_NANOSECONDS) {
    const int64_t deadline = now_nanoseconds() + timeout_ns;
    while (!ms_io_reactor_pending(reactor) && now_nanoseconds() < deadline) {
      (void)uv_run(loop, UV_RUN_NOWAIT);
    }
    return true;
  }
  if (state->timer == NULL) {
    return false;
  }
  timer_arm(state, timeout_ns);
  (void)uv_run(loop, UV_RUN_ONCE);
  (void)CancelWaitableTimer(state->timer); /* a wake for another reason must not leave a stale signal */
  return true;
}

int ms_io_platform_poll_init(uv_loop_t *loop, uv_poll_t *handle, int fd) {
  return uv_poll_init_socket(loop, handle, (uv_os_sock_t)fd); /* a Windows descriptor is a SOCKET */
}

/* ---- the table of objects ---- */

static MsObject *object_find(const MsWindowsState *state, uintptr_t key) {
  for (MsObject *object = state->objects; object != NULL; object = object->next) {
    if (object->key == key) {
      return object;
    }
  }
  return NULL;
}

bool ms_io_platform_owns(const MsIoReactor *reactor, uintptr_t fd) {
  return object_find(state_of(reactor), fd) != NULL;
}

/* ---- objects ---- */

/* Queues an event for each object that fired; the ones that do not fit stay for the next flush. */
static void signalled_flush(MsWindowsState *state) {
  EnterCriticalSection(&state->lock);
  size_t kept = 0;
  for (size_t index = 0; index < state->signalled.len; index++) {
    const MsIoEvent event = {.id = state->signalled.ptr[index], .result = 0, .kind = MS_IO_READ};
    if (!ms_io_reactor_push(state->reactor, event)) {
      state->signalled.ptr[kept] = state->signalled.ptr[index];
      kept++;
    }
  }
  state->signalled.len = kept;
  LeaveCriticalSection(&state->lock);
}

static void on_signalled_async(uv_async_t *handle) { signalled_flush(uv_handle_get_data((uv_handle_t *)handle)); }

/* Runs on a thread-pool thread when a watched object is signalled. */
static VOID CALLBACK on_object_signalled(PVOID context, BOOLEAN timed_out) {
  (void)timed_out;
  const MsObject *const object = context;
  MsWindowsState *const state = object->state;
  EnterCriticalSection(&state->lock);
  key_list_push(&state->signalled, object->key);
  LeaveCriticalSection(&state->lock);
  (void)uv_async_send(&state->signalled_async);
}

bool ms_io_object_watch(uintptr_t handle) {
  MsIoReactor *const reactor = ms_io_reactor_current();
  if (reactor == NULL) {
    return false;
  }
  MsWindowsState *const state = state_of(reactor);
  if (object_find(state, handle) != NULL) {
    return true;
  }
  MsObject *const object = ms_alloc_zeroed(sizeof *object);
  object->key = handle;
  object->state = state;
  /* WT_EXECUTEONLYONCE: the wait ends with the first signal; the scheduler watches again if it needs to. */
  if (!RegisterWaitForSingleObject(&object->wait, (HANDLE)handle, on_object_signalled, object, INFINITE,
                                   WT_EXECUTEONLYONCE)) {
    ms_free(object);
    return false;
  }
  object->next = state->objects;
  state->objects = object;
  return true;
}

/* Ends the wait on the object `key`: returns after a running callback, so the context is free to release. */
static void object_remove(MsWindowsState *state, uintptr_t key) {
  MsObject **link = &state->objects;
  while (*link != NULL && (*link)->key != key) {
    link = &(*link)->next;
  }
  MsObject *const object = *link;
  if (object == NULL) {
    return;
  }
  *link = object->next;
  (void)UnregisterWaitEx(object->wait, INVALID_HANDLE_VALUE);
  EnterCriticalSection(&state->lock);
  size_t kept = 0;
  for (size_t index = 0; index < state->signalled.len; index++) {
    if (state->signalled.ptr[index] != key) {
      state->signalled.ptr[kept] = state->signalled.ptr[index];
      kept++;
    }
  }
  state->signalled.len = kept;
  LeaveCriticalSection(&state->lock);
  ms_free(object);
}

void ms_io_object_drop(uintptr_t handle) {
  MsIoReactor *const reactor = ms_io_reactor_current();
  if (reactor != NULL) {
    object_remove(state_of(reactor), handle);
  }
}

/* ---- the reactor's hooks ---- */

void ms_io_platform_flush(MsIoReactor *reactor) { signalled_flush(state_of(reactor)); }

bool ms_io_platform_open(MsIoReactor *reactor) {
  MsWindowsState *const state = ms_alloc_zeroed(sizeof *state);
  state->reactor = reactor;
  InitializeCriticalSection(&state->lock);
  ms_io_reactor_set_platform(reactor, state);
  if (uv_async_init(ms_io_reactor_loop(reactor), &state->signalled_async, on_signalled_async) != 0) {
    return false; /* the reactor's own destroy ends the state through ms_io_platform_close */
  }
  state->async_open = true;
  uv_handle_set_data((uv_handle_t *)&state->signalled_async, state);
  timer_open(state);
  return true;
}

/* Releases the state once libuv no longer touches its async handle. */
static void state_release(MsWindowsState *state) {
  DeleteCriticalSection(&state->lock);
  key_list_free(&state->signalled);
  ms_free(state);
}

static void on_state_closed(uv_handle_t *handle) { state_release(uv_handle_get_data(handle)); }

void ms_io_platform_close(MsIoReactor *reactor) {
  MsWindowsState *const state = state_of(reactor);
  if (state == NULL) {
    return;
  }
  ms_io_reactor_set_platform(reactor, NULL);
  timer_close(state);
  while (state->objects != NULL) {
    object_remove(state, state->objects->key);
  }
  if (state->async_open) {
    uv_close((uv_handle_t *)&state->signalled_async, on_state_closed);
  } else {
    state_release(state);
  }
}

/* Ctrl-C, Ctrl-Break, and console close, logoff and shutdown (which reach the program as SIGHUP). */
size_t ms_io_platform_stop_signals(const int **signals) {
  static const int watched[] = {SIGINT, SIGBREAK, SIGHUP, SIGTERM};
  *signals = watched;
  return sizeof watched / sizeof watched[0];
}

bool ms_io_platform_is_interrupt(int signal_number) { return signal_number == SIGINT || signal_number == SIGBREAK; }
