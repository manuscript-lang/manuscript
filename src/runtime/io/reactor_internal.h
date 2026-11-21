/* What the platform files of the reactor (posix/platform.c, windows/platform.c) and reactor.c share. Not part of
 * the reactor's interface to the scheduler (reactor.h). */
#ifndef MS_RUNTIME_IO_REACTOR_INTERNAL_H
#define MS_RUNTIME_IO_REACTOR_INTERNAL_H

#include <uv.h>

#include "runtime/io/reactor.h"

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
/* The platform's state of `reactor`, as ms_io_platform_open stored it. */
MS_NONNULL void *ms_io_reactor_platform(const MsIoReactor *reactor);
MS_NONNULL_ARGS(1) void ms_io_reactor_set_platform(MsIoReactor *reactor, void *platform);

/* ---- one implementation per OS family: posix/platform.c, windows/platform.c ---- */

/* Opens the platform state (Windows: precise timer, signalled-object queue). False when it cannot. */
MS_NONNULL bool ms_io_platform_open(MsIoReactor *reactor);
/* Ends the platform state; libuv finishes closing its handles while the loop runs. */
MS_NONNULL void ms_io_platform_close(MsIoReactor *reactor);
/* Whether `fd` names a watched kernel object, not a descriptor libuv polls. */
MS_NONNULL bool ms_io_platform_owns(const MsIoReactor *reactor, uintptr_t fd);
/* Re-queues events that found the ring full. Call before running the loop. */
MS_NONNULL void ms_io_platform_flush(MsIoReactor *reactor);
/* Initialises a poll handle for the descriptor (a SOCKET on Windows). */
MS_NONNULL int ms_io_platform_poll_init(uv_loop_t *loop, uv_poll_t *handle, int fd);
/* Waits up to timeout_ns (positive) with the finest clock the system has, running the loop once; false when it has
 * none and the caller must use a millisecond timer. */
MS_NONNULL bool ms_io_platform_wait(MsIoReactor *reactor, int64_t timeout_ns);

#endif
