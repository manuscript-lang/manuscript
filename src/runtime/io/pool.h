/* pool.h: the blocking pool for calls the kernel cannot wait on (file-system calls, regular-file reads and writes,
 * console and pipe reads on Windows).
 *
 * A few threads, started on demand, run jobs from one queue; the submitting task parks on a remote token that the
 * thread posts when the job ends. MS_POOL_THREADS sets the thread count (default 4).
 *
 * Rules for a job: it runs on a pool thread, where it may allocate with ms_alloc but must not fault, park, or touch
 * task or scheduler state. A task cancelled while it waits abandons a running job: the pool keeps the job's data and
 * calls its release function on the submitting thread once the job ends. After a pool call returns cancelled, release
 * what the call holds and end the task with ms_cancelled.
 */
#ifndef MS_RUNTIME_IO_POOL_H
#define MS_RUNTIME_IO_POOL_H

#include "base/safe.h"

typedef void (*MsPoolJobFn)(void *data);

/* How a wait on a pool job ended. */
typedef enum MsPoolWait {
  MS_POOL_DONE = 0,
  MS_POOL_TIMED_OUT = 1,
  MS_POOL_CANCELLED = 2,
} MsPoolWait;

/* Runs run(data) on a pool thread and parks until it finishes or timeout_ns passes (negative: no limit). On
 * MS_POOL_DONE the data is the caller's again. Otherwise the pool owns it and calls release(data) on the submitting
 * thread, now or when the abandoned job ends: the caller must not touch it. */
MS_NONNULL_ARGS(1, 2) MsPoolWait ms_pool_run(MsPoolJobFn run, MsPoolJobFn release, void *data, int64_t timeout_ns);

/* Runs run(data) on a pool thread and parks until it is done, however long that takes; a stop request is seen only
 * after the job ends. The data stays the caller's throughout and may be a local of the caller. Result: MS_POOL_DONE or
 * MS_POOL_CANCELLED, with the job complete either way. For jobs that always finish (regular files). */
MS_NONNULL_ARGS(1) MsPoolWait ms_pool_run_shielded(MsPoolJobFn run, void *data);

/* Takes an admission permit before copying a payload of `bytes` for a pool job (small payloads need none). Returns
 * whether a permit is held, which ms_pool_release must return; *cancelled is set when a stop request ended the wait,
 * and no permit is held then. */
MS_NONNULL bool ms_pool_admit(size_t bytes, bool *cancelled);
void ms_pool_release(void);

/* Whether the caller is a pool thread. */
bool ms_pool_on_thread(void);

#endif
