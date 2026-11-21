/* What the platform files of the reactor (src/runtime/io/windows) need from reactor.c. Not part of the reactor's
 * interface to the scheduler (reactor.h). */
#ifndef MS_IO_REACTOR_INTERNAL_H
#define MS_IO_REACTOR_INTERNAL_H

#include <uv.h>

#include "reactor.h"
#include "ring.h"

/* The loop of `reactor`. */
MS_NONNULL uv_loop_t *ms_io_reactor_loop(MsIoReactor *reactor);
/* The reactor's wake-up handle: uv_async_send on it ends a wait from any thread. */
MS_NONNULL uv_async_t *ms_io_reactor_wake_handle(MsIoReactor *reactor);
/* Queues `event` for the scheduler; false when the ring is full. Loop thread only. */
MS_NONNULL bool ms_io_reactor_push(MsIoReactor *reactor, MsIoEvent event);
/* Whether the wait that is running has something to report: queued events or a wake-up. */
MS_NONNULL bool ms_io_reactor_pending(const MsIoReactor *reactor);
/* The calling thread's reactor; NULL when it has none. */
MsIoReactor *ms_io_reactor_current(void);
/* The platform's state of `reactor`, as ms_io_windows_open stored it. */
MS_NONNULL void *ms_io_reactor_platform(const MsIoReactor *reactor);
MS_NONNULL_ARGS(1) void ms_io_reactor_set_platform(MsIoReactor *reactor, void *platform);

#ifdef _WIN32
/* The Windows hooks of reactor.c (windows/platform.c). */

/* Opens the platform state (precise timer, signalled-object queue). False when out of memory. */
MS_NONNULL bool ms_io_windows_open(MsIoReactor *reactor);
/* Ends every object watch and the timer; libuv finishes closing them while the loop runs. */
MS_NONNULL void ms_io_windows_close(MsIoReactor *reactor);
/* Whether `fd` names a watched object, not a socket. */
MS_NONNULL bool ms_io_windows_owns(const MsIoReactor *reactor, uintptr_t fd);
/* Re-queues events that found the ring full. Call before running the loop. */
MS_NONNULL void ms_io_windows_flush(MsIoReactor *reactor);
/* Waits up to timeout_ns (positive) for events with the finest clock the system has; false when it has none
 * and the caller must use a millisecond timer. */
MS_NONNULL bool ms_io_windows_wait(MsIoReactor *reactor, int64_t timeout_ns);
#endif

#endif
