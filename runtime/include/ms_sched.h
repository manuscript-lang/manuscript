/* ms_sched.h: the scheduler services C natives use while the scheduler is still Rust: cancellation, the blocking
 * pool, and (Windows) overlapped pipes and waitable objects. The Rust side is crates/ms-rt/src/glue/c_sched.rs.
 *
 * Not part of the program ABI, so `cargo xtask symbols --check` ignores it. Task waits that are already C symbols
 * (msrt_task_wait_fd, msrt_task_sleep, msrt_token_new, msrt_token_park, msrt_token_free, msrt_token_post_remote)
 * are declared here too, so a native includes one header.
 *
 * Blocking pool rules (the Rust pool's, see crates/ms-rt/src/glue/pool.rs):
 *  - a job runs on a pool thread, where nothing may call into the runtime (no msrt_alloc, no faults) and nothing the
 *    runtime thread allocated may be freed; a job allocates with the C library's malloc and the runtime thread copies
 *    its result out;
 *  - a task that is cancelled while it waits abandons a running job: the pool keeps the job's data and calls its
 *    release function on the runtime thread once the job ends;
 *  - ms_sched_cancel_return() ends a call a cancel interrupted: release everything the call holds first, return a
 *    zero result at once, and run no more of the native after it returns.
 */
#ifndef MS_SCHED_H
#define MS_SCHED_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Bits of the result of msrt_task_wait_fd and msrt_task_sleep, and of its `events` argument. */
enum {
    MS_WAIT_READ = 1,
    MS_WAIT_WRITE = 2,
    MS_WAIT_HUP = 4,
    MS_WAIT_TIMEOUT = 8,
    MS_WAIT_CANCELLED = 16
};

/* Parks the running task until fd is ready for events or the timeout in nanoseconds passes (negative: none). */
uint32_t msrt_task_wait_fd(int32_t fd, uint32_t events, int64_t timeout_ns);
uint32_t msrt_task_sleep(int64_t ns);
/* Ends the poller registration on fd; call it before closing a descriptor a task may still be parked on. */
void msrt_task_forget_fd(int32_t fd);
/* Tokens: a wake-up a task parks on and any thread may post. Flag 1 makes a token any thread may post. */
uint64_t msrt_token_new(uint32_t flags);
uint32_t msrt_token_park(uint64_t token, int64_t timeout_ns, uint64_t *value);
void msrt_token_free(uint64_t token);
void msrt_token_post_remote(uint64_t token, uint64_t value);

/* Whether a stop request (SIGINT or SIGTERM) is pending for the running task. */
bool ms_sched_cancel_pending(void);
/* Holds stop requests (SIGINT and SIGTERM) back from the running task until the matching release, so it can
 * forward them and keep waiting; a cancel aimed at the task itself still applies. Holds nest, and a request that
 * arrived meanwhile applies at the last release. */
void ms_sched_stop_hold(void);
void ms_sched_stop_release(void);
/* Delivers the pending cancel by return; see the rules above. */
void ms_sched_cancel_return(void);
/* The OS code of the first failed write to standard output (0 when none), and a flush of the runtime's buffered
 * standard output. */
int32_t ms_sched_stdout_error(void);
void ms_sched_flush_stdout(void);
/* Registers a function to run once when the process exits (crates/ms-rt/src/process.rs while the process module is
 * Rust). */
void msrt_process_on_exit(void (*hook)(void));
/* Whether a bounded read of the running task has used its time (a wait loop must then fail with a timeout). */
bool ms_sched_read_limit_passed(void);
/* Marks the running task's stack as lent to another thread (true) or returned (false): while lent, the task keeps
 * its stack pages even when parked. Crates/ms-rt/src/task while the scheduler is Rust. */
void ms_sched_task_pin(bool lend);
/* The number of live tasks, and whether every task but the running one is stalled (parked on something no
 * running task will wake). */
size_t msrt_task_count(void);
bool msrt_task_others_stalled(void);
/* Whether the caller is a pool thread. */
bool ms_sched_on_pool_thread(void);
/* Whether the program has one task, so a blocking call can run inline instead of on the pool. */
bool ms_sched_pool_alone(void);

/* Takes an admission permit before copying a payload of `bytes` for a pool job (small payloads need none). Returns
 * whether a permit is held, which ms_sched_pool_release must return; *cancelled is set when a stop request ended
 * the wait, and no permit is held then. */
bool ms_sched_pool_admit(size_t bytes, bool *cancelled);
void ms_sched_pool_release(void);

typedef void (*MsSchedJobFn)(void *data);

/* How a wait on a pool job ended. */
typedef enum {
    MS_SCHED_DONE = 0,
    MS_SCHED_TIMED_OUT = 1,
    MS_SCHED_CANCELLED = 2
} MsSchedWait;

/* Runs run(data) on a pool thread and parks until it finishes or timeout_ns passes (negative: no limit). On
 * MS_SCHED_DONE the data is the caller's again. Otherwise the pool owns it and calls release(data) on the runtime
 * thread, now or when the abandoned job ends: the caller must not touch it. */
MsSchedWait ms_sched_pool_run(MsSchedJobFn run, MsSchedJobFn release, void *data, int64_t timeout_ns);

/* Runs run(data) on a pool thread and parks until it is done, however long that takes; a stop request is seen only
 * after the job ends. The data stays the caller's throughout and may be a local of the caller. Result: MS_SCHED_DONE
 * or MS_SCHED_CANCELLED, with the job complete either way. For jobs that always finish (regular files). */
MsSchedWait ms_sched_pool_run_shielded(MsSchedJobFn run, void *data);

#ifdef _WIN32
/* Overlapped named pipes driven by the runtime poller (a pipe is adopted once, then closed here). */
typedef enum {
    MS_PIPE_OK = 0,
    MS_PIPE_CANCELLED = 1,
    MS_PIPE_ERROR = 2
} MsPipeStatus;

bool ms_sched_pipe_adopt(intptr_t handle);
bool ms_sched_pipe_is_adopted(intptr_t handle);
/* *count is 0 at end of stream. On MS_PIPE_ERROR, *os_error is the Win32 code. */
MsPipeStatus ms_sched_pipe_read(intptr_t handle, uint8_t *buffer, size_t capacity, size_t *count, int32_t *os_error);
MsPipeStatus ms_sched_pipe_write(intptr_t handle, const uint8_t *data, size_t length, int32_t *os_error);
void ms_sched_pipe_close(intptr_t handle);

/* Waitable kernel objects (a child process): parks until signalled or the timeout passes. */
typedef enum {
    MS_OBJECT_SIGNALLED = 0,
    MS_OBJECT_TIMED_OUT = 1,
    MS_OBJECT_CANCELLED = 2,
    MS_OBJECT_UNWATCHABLE = 3
} MsObjectWait;

MsObjectWait ms_sched_object_wait(intptr_t handle, int64_t timeout_ns);
/* Ends the watch; call before closing the handle. */
void ms_sched_object_forget(intptr_t handle);
#endif

#endif
