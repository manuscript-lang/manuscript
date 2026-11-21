/* The reactor's platform hooks on Unix: libuv polls every descriptor and nothing else needs watching. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include <signal.h>

#include "runtime/io/reactor_internal.h"
#include "runtime/sys/sys.h"

bool ms_io_platform_open(MsIoReactor *reactor) {
  (void)reactor;
  return true;
}

void ms_io_platform_close(MsIoReactor *reactor) { (void)reactor; }

bool ms_io_platform_owns(const MsIoReactor *reactor, uintptr_t fd) {
  (void)reactor;
  (void)fd;
  return false;
}

void ms_io_platform_flush(MsIoReactor *reactor) { (void)reactor; }

int ms_io_platform_poll_init(uv_loop_t *loop, uv_poll_t *handle, int fd) { return uv_poll_init(loop, handle, fd); }

/* libuv sleeps in whole milliseconds; sleeping on its backend descriptor has nanosecond resolution. */
bool ms_io_platform_wait(MsIoReactor *reactor, int64_t timeout_ns) {
  uv_loop_t *loop = ms_io_reactor_loop(reactor);
  if (!ms_sys_fd_wait_readable(uv_backend_fd(loop), timeout_ns)) {
    return false;
  }
  (void)uv_run(loop, UV_RUN_NOWAIT);
  return true;
}

bool ms_io_object_watch(uintptr_t handle) {
  (void)handle;
  return false;
}

void ms_io_object_drop(uintptr_t handle) { (void)handle; }

size_t ms_io_platform_stop_signals(const int **signals) {
  static const int watched[] = {SIGINT, SIGTERM};
  *signals = watched;
  return sizeof watched / sizeof watched[0];
}

bool ms_io_platform_is_interrupt(int signal_number) { return signal_number == SIGINT; }
