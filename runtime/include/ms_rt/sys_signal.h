/* ms_rt/sys_signal.h: observing operating-system signals, the platform half of runtime/std/signals.c. Implemented by
 * sys/posix/signal.c (a handler per signal that chains to the one installed before and writes the signal number to
 * a pipe) and sys/windows/signal.c (console control events, delivered as SIGINT and SIGTERM).
 *
 * An observer is opened for a set of signals, drained without blocking and stopped. The caller waits for one in the
 * way the platform allows: a descriptor to park on (ms_sys_signals_fd, POSIX) or, when there is none, the `notify`
 * callback it passed to open (Windows; it runs on the OS's thread). A signal that arrives while no task waits is
 * kept for the next take. The handler
 * that was in place before runs first, so the runtime's own SIGINT and SIGTERM handling records a stop request
 * before any observer can see the signal.
 */
#ifndef MS_RT_SYS_SIGNAL_H
#define MS_RT_SYS_SIGNAL_H

#include "ms_rt/base.h"
#include "ms_rt/safe.h"
#include "ms_rt/sys_fs.h"

typedef struct MsSysSignals MsSysSignals;

enum { MS_SYS_SIGNAL_MAX = 64, MS_SYS_SIGNALS_FULL = -1 /* no observer slot is free */ };

/* Whether `signal` can be observed here (1..MS_SYS_SIGNAL_MAX, not SIGKILL or SIGSTOP). */
bool ms_sys_signal_valid(int64_t signal);
/* Runs on the OS's thread when a signal arrives or the observer is stopped; only where there is no descriptor. */
typedef void (*MsSysSignalNotify)(void *context);
/* Windows only: counts SIGINT (2) or SIGTERM (15) for this process's own observers, as a console control event
 * would. `kill` of the process's own id uses it, the way POSIX delivers a signal a process sends itself. */
void ms_sys_signal_raise(int signal);
/* Starts observing the signals whose bit (signal - 1) is set in `mask`. The OS buffers about `capacity` signals
 * (at most 64 KiB). Returns 0, MS_SYS_SIGNALS_FULL, or the host's error code. */
MS_NODISCARD MsSysError ms_sys_signals_open(uint64_t mask, size_t capacity, MsSysSignalNotify notify, void *context,
                                            MsSysSignals **out);
/* Copies up to `capacity` waiting signal numbers into `out` without blocking; returns how many. */
size_t ms_sys_signals_take(MsSysSignals *observer, uint8_t *out, size_t capacity);
/* The descriptor that becomes readable when a signal is waiting or the observer is stopped; -1 where the platform
 * delivers through `notify` instead. */
int ms_sys_signals_fd(const MsSysSignals *observer);
/* Whether a signal is waiting to be taken. */
bool ms_sys_signals_pending(const MsSysSignals *observer);
/* Stops observing and wakes a waiting task (a hang-up on the descriptor, or a notify). Safe to repeat. */
void ms_sys_signals_stop(MsSysSignals *observer);
/* Stops and frees the observer. */
void ms_sys_signals_destroy(MsSysSignals *observer);

#endif
