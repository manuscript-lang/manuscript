/* stop.c: stop requests and the grace timer (see stop.h).
 *
 * One process-wide state: the loop, its signal watchers, the grace timer and two async handles that carry "arm" and
 * "quit" from other threads. Everything libuv touches after ms_io_stop_start belongs to the stop thread, except
 * uv_async_send, which any thread may call. The loop and every handle are initialized before the thread starts, so
 * the signals are watched from the moment ms_io_stop_start returns.
 */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "runtime/io/stop.h"

#include <stdatomic.h>

#include "runtime/io/reactor_internal.h"

enum { MILLISECONDS_PER_SECOND = 1000, MAX_WATCHED_SIGNALS = 4 };

typedef struct MsStopState {
  uv_loop_t loop;
  uv_signal_t signals[MAX_WATCHED_SIGNALS];
  size_t signal_count;
  uv_timer_t grace;
  uv_async_t arm_request;
  uv_async_t quit_request;
  uv_thread_t thread; /* joined by ms_io_stop_end */
  MsStopFn on_stop;
  MsStopExpiredFn on_expired;
  _Atomic uint32_t arm_seconds;
  bool running;
} MsStopState;

static MsStopState state;

/* The stop request a signal number stands for: MS_STOP_INTERRUPT for SIGINT (and Ctrl-Break on Windows),
 * MS_STOP_TERMINATE for every other watched signal (SIGTERM; console close, logoff and shutdown reach Windows
 * programs as SIGHUP). */
static int ms_io_stop_request_of(int signal_number) {
  return ms_io_platform_is_interrupt(signal_number) ? MS_STOP_INTERRUPT : MS_STOP_TERMINATE;
}

static void on_signal(uv_signal_t *handle, int signal_number) {
  (void)handle;
  state.on_stop(ms_io_stop_request_of(signal_number));
}

void ms_io_stop_raise(int signal_number) {
  if (state.running) {
    state.on_stop(ms_io_stop_request_of(signal_number));
  }
}

static void on_grace(uv_timer_t *handle) {
  (void)handle;
  state.on_expired();
}

static void on_arm(uv_async_t *handle) {
  (void)handle;
  const uint64_t milliseconds = (uint64_t)atomic_load(&state.arm_seconds) * MILLISECONDS_PER_SECOND;
  (void)uv_timer_start(&state.grace, on_grace, milliseconds, 0);
}

static void on_quit(uv_async_t *handle) {
  (void)handle;
  for (size_t i = 0; i < state.signal_count; i++) {
    uv_close((uv_handle_t *)&state.signals[i], NULL);
  }
  uv_close((uv_handle_t *)&state.grace, NULL);
  uv_close((uv_handle_t *)&state.arm_request, NULL);
  uv_close((uv_handle_t *)&state.quit_request, NULL);
}

static void run_loop(void *argument) {
  (void)argument;
  (void)uv_run(&state.loop, UV_RUN_DEFAULT);
}

/* Closes what ms_io_stop_start opened before it failed. `opened` is how many signal watchers exist. */
static void abandon(size_t opened, bool grace, bool arm, bool quit) {
  for (size_t i = 0; i < opened; i++) {
    uv_close((uv_handle_t *)&state.signals[i], NULL);
  }
  if (grace) {
    uv_close((uv_handle_t *)&state.grace, NULL);
  }
  if (arm) {
    uv_close((uv_handle_t *)&state.arm_request, NULL);
  }
  if (quit) {
    uv_close((uv_handle_t *)&state.quit_request, NULL);
  }
  (void)uv_run(&state.loop, UV_RUN_DEFAULT);
  (void)uv_loop_close(&state.loop);
}

bool ms_io_stop_start(MsStopFn on_stop, MsStopExpiredFn on_expired) {
  if (state.running || uv_loop_init(&state.loop) != 0) {
    return false;
  }
  state.on_stop = on_stop;
  state.on_expired = on_expired;
  atomic_store(&state.arm_seconds, 0);
  const int *watched = NULL;
  state.signal_count = ms_io_platform_stop_signals(&watched);
  size_t opened = 0;
  for (; opened < state.signal_count; opened++) {
    if (uv_signal_init(&state.loop, &state.signals[opened]) != 0) {
      abandon(opened, false, false, false);
      return false;
    }
    if (uv_signal_start(&state.signals[opened], on_signal, watched[opened]) != 0) {
      abandon(opened + 1, false, false, false);
      return false;
    }
  }
  if (uv_timer_init(&state.loop, &state.grace) != 0) {
    abandon(opened, false, false, false);
    return false;
  }
  if (uv_async_init(&state.loop, &state.arm_request, on_arm) != 0) {
    abandon(opened, true, false, false);
    return false;
  }
  if (uv_async_init(&state.loop, &state.quit_request, on_quit) != 0) {
    abandon(opened, true, true, false);
    return false;
  }
  if (uv_thread_create(&state.thread, run_loop, NULL) != 0) {
    abandon(opened, true, true, true);
    return false;
  }
  state.running = true;
  return true;
}

void ms_io_stop_arm(uint32_t seconds) {
  atomic_store(&state.arm_seconds, seconds);
  (void)uv_async_send(&state.arm_request);
}

void ms_io_stop_end(void) {
  if (!state.running) {
    return;
  }
  (void)uv_async_send(&state.quit_request);
  (void)uv_thread_join(&state.thread);
  (void)uv_loop_close(&state.loop);
  state.running = false;
}
