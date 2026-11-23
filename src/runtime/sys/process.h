/* sys/process.h: process state the OS layer owns and libuv does not wrap: the file-creation mask, user and group
 * identity, and the process title; and observing operating-system signals. Implemented per platform: posix/process.c,
 * posix/signal.c and windows/process.c, windows/signal.c (which report UV_ENOTSUP for what the platform lacks).
 *
 * A function returns 0 or a negative libuv status (UV_E*), so the natives report it as they report libuv's own
 * errors. A list or text it returns is allocated with ms_alloc and the caller frees it with ms_free.
 */
#ifndef MS_RUNTIME_SYS_PROCESS_H
#define MS_RUNTIME_SYS_PROCESS_H

#include "base/safe.h"

typedef enum MsSysIdentity { MS_SYS_ID_UID, MS_SYS_ID_GID, MS_SYS_ID_EUID, MS_SYS_ID_EGID } MsSysIdentity;

/* The process's user or group id, or -1 on a platform that has none. */
int64_t ms_sys_process_identity(MsSysIdentity which);
/* Sets the file-creation mask and reports the previous one. */
MS_NODISCARD MS_NONNULL int ms_sys_process_umask(uint32_t mask, uint32_t *previous);
/* The supplementary groups of the process. */
MS_NODISCARD MS_NONNULL int ms_sys_process_groups(int64_t **list, size_t *count);
MS_NODISCARD int ms_sys_process_set_groups(const int64_t *list, size_t count);
MS_NODISCARD int ms_sys_process_set_identity(MsSysIdentity which, uint32_t id);
/* The group ids of user `name` (its primary group included); UV_ENOENT for an unknown user. */
MS_NODISCARD MS_NONNULL int ms_sys_process_user_groups(const char *name, int64_t **list, size_t *count);

/* ---- signals ---- */

typedef struct MsSysSignals MsSysSignals;

enum { MS_SYS_SIGNAL_MAX = 64, MS_SYS_SIGNALS_FULL = -1 /* no observer slot is free */ };

/* Whether `signal` can be observed here (1..MS_SYS_SIGNAL_MAX, not SIGKILL or SIGSTOP). */
bool ms_sys_signal_valid(int64_t signal);
/* Runs on the OS's thread when a signal arrives or the observer is stopped; only where there is no descriptor. */
typedef void (*MsSysSignalNotify)(void *context);
/* Whether a process can only signal itself by ms_sys_signal_raise (Windows) rather than by kill. */
bool ms_sys_signal_self_by_raise(void);
/* Windows only: counts SIGINT (2) or SIGTERM (15) for this process's own observers, as a console control event would.
 * `kill` of the process's own id uses it, the way POSIX delivers a signal a process sends itself. */
void ms_sys_signal_raise(int signal);
/* Starts observing the signals whose bit (signal - 1) is set in `mask`. The OS buffers about `capacity` signals (at
 * most 64 KiB). Returns 0, MS_SYS_SIGNALS_FULL, or a negative libuv status. */
MS_NODISCARD MS_NONNULL_ARGS(5) int ms_sys_signals_open(uint64_t mask, size_t capacity, MsSysSignalNotify notify,
                                                        void *context, MsSysSignals **out);
/* Copies up to `capacity` waiting signal numbers into `out` without blocking; returns how many. */
MS_NONNULL size_t ms_sys_signals_take(MsSysSignals *observer, uint8_t *out, size_t capacity);
/* The descriptor that becomes readable when a signal is waiting or the observer is stopped; -1 where the platform
 * delivers through `notify` instead. */
MS_NONNULL int ms_sys_signals_fd(const MsSysSignals *observer);
/* Whether a signal is waiting to be taken. */
MS_NONNULL bool ms_sys_signals_pending(const MsSysSignals *observer);
/* Stops observing and wakes a waiting task (a hang-up on the descriptor, or a notify). Safe to repeat. */
MS_NONNULL void ms_sys_signals_stop(MsSysSignals *observer);
/* Stops and frees the observer. */
MS_NONNULL void ms_sys_signals_destroy(MsSysSignals *observer);

/* ---- a child process and what it leads ---- */

/* The processes a child leads: its process group (POSIX; the child is started detached, so its pid is the group id) or
 * its job object (Windows), so that ending the child ends its whole tree. */
typedef struct MsSysGroup MsSysGroup;

/* The group of the child `pid`; `process_handle` is libuv's uv_process_t.process_handle (Windows; ignored elsewhere). */
MS_RETURNS_NONNULL MsSysGroup *ms_sys_group_new(int64_t pid, void *process_handle);
/* Asks the group to end (SIGTERM, or SIGKILL when `force` or the signal fails; Windows has no graceful signal). */
MS_NONNULL void ms_sys_group_signal(MsSysGroup *group, bool force);
/* Kills whatever remains, also after the leader was reaped (its pid is the group id). */
MS_NONNULL void ms_sys_group_kill(MsSysGroup *group);
/* The exit code libuv's exit callback reports as `status` and `signal`: -1 when a signal or ms_sys_group_signal ended
 * the child (Windows reports that as an ordinary code). */
MS_NONNULL int64_t ms_sys_group_exit_code(const MsSysGroup *group, int64_t status, int signal);
/* The peak resident set size of the child in bytes, 0 when unknown: sampled while it runs (Linux), the most any
 * reaped child used (other POSIX), or read from the process handle at exit (Windows; call it in the exit callback). */
MS_NONNULL int64_t ms_sys_group_peak_resident(const MsSysGroup *group, bool exited);
MS_NONNULL void ms_sys_group_free(MsSysGroup *group);

/* Replaces the process image; returns only on failure, as a libuv status (UV_ENOTSUP on Windows). `env` is the whole
 * environment. */
MS_NONNULL int ms_sys_process_exec(const char *file, char *const *argv, char *const *env);

#endif
