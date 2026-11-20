/* stop.h: stop requests and the cleanup grace timer, on libuv.
 *
 * One thread of its own runs a loop that watches SIGINT and SIGTERM (on Windows Ctrl-C and Ctrl-Break, and console
 * close, logoff and shutdown) and a timer for the grace period after the first request. The callbacks run on that
 * thread, never in a signal handler, so they may use any function; they must not block for long, because a second
 * request and the grace timer are delivered by the same thread.
 */
#ifndef MS_IO_STOP_H
#define MS_IO_STOP_H

#include <stdbool.h>
#include <stdint.h>

#include "ms_rt/safe.h"

/* The signal numbers a stop request reports, the same on every platform. */
enum {
    MS_STOP_INTERRUPT = 2,  /* SIGINT: Ctrl-C, Ctrl-Break */
    MS_STOP_TERMINATE = 15, /* SIGTERM: terminate, console close, logoff, shutdown */
};

/* A stop request arrived; `signal` is MS_STOP_INTERRUPT or MS_STOP_TERMINATE. */
typedef void (*MsStopFn)(int signal);
/* The grace period armed by ms_io_stop_arm ran out. It ends the process. */
typedef void (*MsStopExpiredFn)(void);

/* Starts the stop thread. Call once, before the first task. False when the loop or the thread cannot start; nothing
 * is left running then. */
MS_NODISCARD bool ms_io_stop_start(MsStopFn on_stop, MsStopExpiredFn on_expired);

/* Arms the grace timer: `on_expired` runs `seconds` from now unless ms_io_stop_end comes first. Arming again
 * restarts it. Safe from any thread once ms_io_stop_start succeeded. */
void ms_io_stop_arm(uint32_t seconds);

/* Ends the stop thread and releases the loop. Safe when ms_io_stop_start never ran. Tests and a clean exit use it. */
void ms_io_stop_end(void);

#endif
