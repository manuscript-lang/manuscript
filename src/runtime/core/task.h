/* task.h: cooperative tasks on one scheduler thread.; the program ABI (`msrt_task_*`,
 * `msrt_token_*`) is a thin layer over it that turns the statuses below into faults.
 *
 * A task is a stackful coroutine: it runs until it parks (a descriptor, a timer, a token, a join) or yields;
 * there is no preemption. Everything it needs while parked is one record, a slot in the handle table and the
 * pages of its stack it touched, so a parked task costs hundreds of bytes plus a page, not a thread.
 *
 * Handles are `generation << 32 | (slot + 1)`: a stale handle never matches a reused slot. Tokens are one-shot
 * slots a task parks on and code posts to; their ids carry the isolate in the top 12 bits.
 *
 * Everything is per scheduler thread (`ms_sched_teardown` ends this thread's scheduler); only
 * ms_sched_stop may be called from another thread.
 */
#ifndef MS_RUNTIME_CORE_TASK_H
#define MS_RUNTIME_CORE_TASK_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "runtime/core/fault.h"
#include "runtime/core/isolate.h"
#include "base/safe.h"
#include "runtime/core/unwind.h"

typedef uint64_t MsTaskHandle;
typedef void (*MsTaskEntry)(void *);

/* Results of a park, ORed together. */
#define MS_WAIT_READ 1u
#define MS_WAIT_WRITE 2u
#define MS_WAIT_HUP 4u
#define MS_WAIT_TIMEOUT 8u
#define MS_WAIT_CANCELLED 16u
/* Returned instead of a park result when the descriptor cannot be waited on at all. */
#define MS_WAIT_FAILED 64u
/* Request bit: keep the descriptor registered between waits. Only for a descriptor its owner drains before every
 * wait and keeps open for good. */
#define MS_WAIT_KEEP 32u
/* Request bit: the caller's system call on `fd` just found nothing more to take, so wait for the poller's next edge
 * of the registration the caller made (ms_io_edge_reset) instead of asking whether the descriptor is ready now. */
#define MS_WAIT_EDGE 256u
/* Internal: marks a descriptor waiter that is a promise, not a task. */
#define MS_WAIT_PROMISE 128u
/* Internal: marks a descriptor waiter that is a notify function (ms_sched_fd_notify); its kind is in the bits at
 * MS_WAIT_KIND_SHIFT. */
#define MS_WAIT_NOTIFY 512u
#define MS_WAIT_KIND_SHIFT 16

/* ms_task_spawn flags. */
#define MS_SPAWN_DETACHED 1u /* nobody joins; a fault in the task ends the process */
#define MS_SPAWN_FRONT 4u    /* runs before the tasks already ready: the spawner is about to wait for it */
#define MS_SPAWN_FATAL 2u    /* a fault ends the process as for a detached task, but the task can be joined */
/* ms_task_spawn stack request: a region of its own, 256 MiB (an isolate's main task). */
#define MS_TASK_ROOT_STACK ((size_t)256 << 20)

/* ms_token_new flags. */
#define MS_TOKEN_REMOTE 1u /* another thread will post it: until then the scheduler waits instead of reporting
                a deadlock */
#define MS_TOKEN_PEER 2u   /* with REMOTE: the post comes from another isolate */

#define MS_NO_DEADLINE INT64_MAX

/* What the scheduler asks of the code above it. Set once with ms_sched_set_hooks, before the first task. */
typedef struct MsSchedHooks {
  /* Reports a fault that leaves the running task (a deadlock found while it waits). Never returns: it leaves by
   * a guard or ends the process. */
  void (*fault)(MsFaultKind kind, const char *message);
  /* Ends the process after a stop request that no guard catches. Never returns. */
  void (*exit_process)(int status);
  /* Output buffered for a pipe or file must be visible before the scheduler blocks. May be NULL. */
  void (*flush_output)(void);
  /* The promise table ends the promises the running task started above cleanup height `base`. May be NULL. */
  void (*end_started)(size_t base);
  /* A task started with MS_SPAWN_FATAL faulted: the main isolate reports and exits the process; a worker records
   * the report and cancels itself, so this may return. May be NULL. */
  void (*task_fault)(const MsFaultText *message);
  /* Timers of other tables (the promise table's sleeps and limits), armed with ms_sched_arm: whether the entry
   * (id, deadline) still means something, and what to do when it is due. May be NULL together. */
  bool (*timer_live)(uint64_t id, int64_t deadline);
  void (*timer_fire)(uint64_t id, int64_t deadline);
  /* A descriptor a promise waits on (ms_sched_fd_wait_begin) has `bits` ready: true when the promise is done with
   * the descriptor (the wait is then removed), false to keep waiting. */
  bool (*fd_ready)(uint64_t id, uint32_t bits);
  /* While a task runs work inline for a wait group (ms_task_set_watch), each of its unshielded parks on `token` is
   * bracketed: park_begin answers true when the park must end at once (a member already failed), park_end when the
   * park that just returned was ended by a failure; both make the park report MS_WAIT_CANCELLED. */
  bool (*park_begin)(uint64_t token);
  bool (*park_end)(void);
  /* Mail of a kind the scheduler does not handle itself (the promise table's): the hook takes `mail` and frees it. */
  void (*mail)(MsMail *mail);
  /* Frees the other tables when the scheduler ends. May be NULL. */
  void (*teardown)(void);
  /* Frees what mail that was never delivered owns (its node is freed by the caller). */
  void (*discard_mail)(MsMail *mail);
  /* Before the scheduler blocks with nothing ready: starts work that waits elsewhere (a queued promise of another
   * isolate) as a task and answers true, or answers false with `*wait_ns` the longest it may block for that
   * work's sake (negative: no limit). May be NULL. */
  bool (*idle)(int64_t *wait_ns);
  /* The idle path ended: the scheduler has something to run. May be NULL. */
  void (*idle_over)(void);
  /* After the scheduler marked itself sleeping: whether work that idle would take has appeared since, so it must
   * not block. May be NULL. */
  bool (*pending)(void);
  /* Work was queued that only this thread can start (ms_sched_note_queued): starts it as tasks. Runs before the next
   * switch away from the running task, the first moment a task started at once could have run. May be NULL. */
  void (*start_queued)(void);
  /* A service isolate (a worker) with no task and no timer waits for mail and work instead of being deadlocked. */
  bool service;
} MsSchedHooks;

/* Descriptor readiness, supplied by src/runtime/io (msio_*, one libuv loop per thread). The bits are MS_WAIT_*. */
typedef struct MsPollReady {
  uintptr_t fd;
  uint32_t bits;
} MsPollReady;

enum { MS_POLL_ARMED = 0, MS_POLL_ALWAYS = 1, MS_POLL_FAILED = -1 };

typedef struct MsPollOps {
  /* One-shot interest in `fd`; MS_POLL_ALWAYS means it cannot be polled and is ready at once. */
  int (*watch)(int fd, uint32_t events);
  void (*unwatch)(int fd);
  /* Ends a kept registration before its owner closes the descriptor. */
  void (*forget)(int fd);
  /* Waits up to `timeout_ns` (0 never blocks, negative waits for an event); returns entries written to `out`
   * (at most `capacity`) or -1 when interrupted. */
  long (*wait)(int64_t timeout_ns, MsPollReady *out, size_t capacity);
} MsPollOps;

typedef enum MsTaskStatus {
  MS_TASK_OK = 0,
  MS_TASK_NO_SUCH_TASK,   /* a handle that no longer exists */
  MS_TASK_DETACHED,       /* join of a detached task */
  MS_TASK_SELF,           /* a task cannot join itself */
  MS_TASK_ALREADY_JOINED, /* another task is already joining it */
  MS_TASK_NO_STACK,       /* address space or mappings are used up */
  MS_TASK_STACK_OVERFLOW, /* a segment cannot be added: 511 are in use, or no slot is left */
} MsTaskStatus;

typedef enum MsTokenStatus {
  MS_TOKEN_OK = 0,
  MS_TOKEN_NO_SUCH_TOKEN, /* a park on a freed token */
  MS_TOKEN_BUSY,          /* another task already waits on it */
  MS_TOKEN_WAITED_ON,     /* freed while a task waits on it */
} MsTokenStatus;

/* ---- scheduler ---- */

/* Installs the hooks and the descriptor poller of this thread. Call before the first task; both are copied. */
void ms_sched_set_hooks(const MsSchedHooks *hooks, const MsPollOps *poll) MS_NONNULL;
/* Ends this thread's scheduler: frees every record, stack, table and token. No task may be mid-switch. */
void ms_sched_teardown(void);
/* Raises a stop request on this scheduler (a signal, a parent isolate): every waiting task that is not shielded
 * wakes with MS_WAIT_CANCELLED. Safe from any thread once the scheduler exists. */
void ms_sched_stop(uint8_t signal);
/* Makes the calling thread's scheduler the one ms_sched_stop_remote aims at (the main isolate's). Call it on that
 * thread, once its first task exists; ms_sched_clear_stop_target before ms_sched_teardown. */
void ms_sched_set_stop_target(void);
void ms_sched_clear_stop_target(void);
/* A stop request (`signal` is SIGINT's or SIGTERM's number) for the scheduler set with ms_sched_set_stop_target,
 * from any thread, a signal watcher's included: raises the cancel flag of its running task unless shielded (a loop
 * that never parks still stops), then wakes the scheduler so every parked task that is not shielded is cancelled.
 * Does nothing while no target is set. */
void ms_sched_stop_remote(uint8_t signal);
/* Registers this thread's scheduler as an isolate (see isolate.h): its index goes into token ids, and mail for it
 * wakes the poller through `wake`. Returns the index, or MS_NO_ISOLATE. */
uint32_t ms_sched_attach(MsWakeFn wake, void *argument);
/* The monotonic clock the scheduler reads, in nanoseconds. */
int64_t ms_sched_now(void);
/* The absolute deadline `timeout_ns` from now on that clock, saturating; MS_NO_DEADLINE for a negative timeout. */
static inline int64_t ms_sched_deadline_after(int64_t timeout_ns) {
  if (timeout_ns < 0) {
    return MS_NO_DEADLINE;
  }
  const int64_t now = ms_sched_now();
  return now > INT64_MAX - timeout_ns ? INT64_MAX : now + timeout_ns;
}
/* A promise (not a task) waits for `fd`: returns MS_POLL_ARMED, MS_POLL_ALWAYS (ready at once, nothing registered) or
 * MS_POLL_FAILED. The hooks' fd_ready is called with the ready bits. */
int ms_sched_fd_wait_begin(uint64_t id, int fd, uint32_t events);
void ms_sched_fd_wait_end(uint64_t id, int fd);
/* A descriptor waiter that is neither a task nor a promise: a function called on the scheduler's thread, inside its
 * poll, with the ready bits (MS_WAIT_READ, WRITE, HUP). It must not park. True ends the wait, false keeps it. It
 * costs one waiter node: no promise row, no allocation. */
typedef bool (*MsFdNotify)(uint64_t id, uint32_t bits);
enum { MS_FD_NOTIFY_KINDS = 8 };
/* The kind number of `notify` on this thread's scheduler, registering it on first use; -1 when MS_FD_NOTIFY_KINDS
 * functions are registered already. */
int ms_sched_fd_notify_kind(MsFdNotify notify) MS_NONNULL;
/* Waits for `fd` on behalf of (`kind`, `id`): MS_POLL_ARMED, MS_POLL_ALWAYS (ready at once, nothing registered) or
 * MS_POLL_FAILED. `events` are MS_WAIT_READ and MS_WAIT_WRITE, with MS_WAIT_KEEP or MS_WAIT_EDGE passed on to the
 * poller. */
int ms_sched_fd_notify(int kind, uint64_t id, int fd, uint32_t events);
/* Ends that wait if it is still registered. */
void ms_sched_fd_notify_end(int kind, uint64_t id, int fd);
/* Arms an entry for the timer_live and timer_fire hooks; wakes the scheduler's idle wait in time. */
void ms_sched_arm(uint64_t id, int64_t at_ns);

/* ---- tasks ---- */

/* Starts `entry(arg)` as a task. It first runs when the caller parks or yields. Returns 0 and sets `*status` when
 * no stack is available. */
MsTaskHandle ms_task_spawn(MsTaskEntry entry, void *arg, uint32_t flags, size_t stack_bytes, MsTaskStatus *status)
  MS_NONNULL_ARGS(1, 5);
MsTaskHandle ms_task_current(void);
/* Tasks that exist (running, runnable, waiting, finished and not yet joined), not counting a flow that only waits
 * for the isolate's main task. */
size_t ms_task_count(void);
void ms_task_yield(void);

/* Parks until `fd` is ready for `events`, the timeout (negative: none) passes, or a cancel arrives. Returns the
 * ready bits, MS_WAIT_TIMEOUT or MS_WAIT_CANCELLED. A file that cannot be polled is ready at once. */
uint32_t ms_task_wait_fd(int fd, uint32_t events, int64_t timeout_ns);
/* The same with an absolute deadline on ms_sched_now's clock (negative: none), so a caller that holds the time
 * reads no clock here. `fd` < 0 waits for the deadline alone. */
uint32_t ms_task_wait_fd_at(int fd, uint32_t events, int64_t at_ns);
uint32_t ms_task_sleep(int64_t ns);
void ms_task_forget_fd(int fd);

/* Requests cancellation: a parked task wakes with MS_WAIT_CANCELLED and its cancellation points fire. A handle
 * that no longer exists is ignored. */
void ms_task_cancel(MsTaskHandle handle);
/* Waits for a joinable task and reports how it ended in `*outcome`: 0 returned, 1 faulted (report in `*message`,
 * owned by the caller), 2 cancelled. A caller cancelled while waiting gets 2 and leaves the task unjoined. */
MsTaskStatus ms_task_join(MsTaskHandle handle, uint8_t *outcome, MsFaultText *message) MS_NONNULL_ARGS(2, 3);
/* True when the running task's last join found the task cancelled for running past its time limit. */
bool ms_task_timed_out(void);

/* Bounds every park of the running task until ms_task_read_limit_restore: no wait lasts past `timeout_ns` in all.
 * Returns the previous limit. */
int64_t ms_task_read_limit(int64_t timeout_ns);
void ms_task_read_limit_restore(int64_t previous);
/* The test output capture the running task prints to (0: standard output). Tasks it spawns inherit it. */
uint64_t ms_task_capture(void);
void ms_task_set_capture(uint64_t capture);
bool ms_task_read_limit_passed(void);
/* Cancels the running task `limit_ns` from now (negative: never), or at an absolute time. Replaces an earlier
 * limit. */
void ms_task_limit_current(int64_t limit_ns);
void ms_task_limit_current_at(int64_t at_ns);

/* The promise table keeps, per task, the head of the list of promises that task started (row + 1, 0 for none), so
 * a cancelled frame visits only its own. A handle that no longer exists reads as 0 and ignores a swap. */
uint32_t ms_task_started_head(MsTaskHandle handle);
uint32_t ms_task_started_swap(MsTaskHandle handle, uint32_t head);
/* The deadline a deferred promise run by the running task must end by (MS_NO_DEADLINE: none); set returns the old. */
int64_t ms_task_defer_deadline(void);
int64_t ms_task_set_defer_deadline(int64_t at_ns);

/* An opaque pointer the running task carries for the park hooks (the wait group it runs work for); returns the old. */
void *ms_task_watch(void);
void *ms_task_set_watch(void *watch);

/* Whether no other task could run while the current one blocks its thread (see task.c). */
bool ms_task_others_stalled(void);
/* Cancels every other task of this thread and lets each run to its end, so the frames of tasks still parked when
 * the thread's work is over unwind. */
void ms_task_unwind_others(void);

/* Runs `entry(arg)` as the isolate's main task on a region of its own and returns when it ends. The caller's flow
 * only waits, shielded from stop requests. `flags` are ms_task_spawn's (MS_SPAWN_FATAL for the main isolate);
 * `*outcome` is how the task ended, as for ms_task_join. */
MsTaskStatus ms_task_run_main(MsTaskEntry entry, void *arg, uint32_t flags, uint8_t *outcome, MsFaultText *message)
  MS_NONNULL_ARGS(1, 4, 5);

/* Whether a fault at `address` is the running task overrunning its stack: the address lies just below the lowest
 * address of the segment it runs on, within the reach a frame bigger than the guard can skip. Reads only, so the
 * fault handler may call it on its alternate stack. */
bool ms_task_stack_overflow_at(uintptr_t address);

/* Runs `shim(block)` on the task's next stack segment: the recursion check of a cyclic function found the stack
 * pointer below the limit of the current one. The segment is a guarded slot kept until the task ends. */
MsTaskStatus ms_task_grow(void (*shim)(void *), void *block) MS_NONNULL_ARGS(1);
/* Runs `fn(arg)`, on the task's next stack segment when fewer than MS_STACK_NATIVE_ROOM bytes remain before its
 * recursion limit: the check a recursive native makes the way a written cyclic function does. A stack that cannot grow
 * is a stack overflow fault. */
void ms_stack_call(void (*fn)(void *), void *arg) MS_NONNULL_ARGS(1);
/* Whether fewer than MS_STACK_NATIVE_ROOM bytes remain before the running task's recursion limit (the test
 * ms_stack_call makes), for a hot native that packs its arguments only when it must grow. */
bool ms_stack_low(void);
/* The segment the running task is on (0 is its home slot). */
uint32_t ms_task_segment(void);
/* Puts the running task back on `segment` after a guard exit skipped the returns of the grows above it. */
void ms_task_restore_segment(uint32_t segment);
/* The TEB stack words of `segment` of the running task as the task last left them (Windows; zeros elsewhere). */
void ms_task_segment_teb(uint32_t segment, uintptr_t out[3]);
/* Copies the running task's recursion limit to the cell of the segment it is on. */
void ms_task_publish_limit(void);

/* Asks for the hooks' start_queued before this thread's next task switch. */
void ms_sched_note_queued(void);

/* ---- wait words ---- */

/* A wait word names what a wake goes to: a token id, or the running task itself. ms_token_post takes either. */
uint64_t ms_task_wait_word(void);
/* Parks the running task until its own wait word is posted (0), `at_ns` passes (MS_WAIT_TIMEOUT; negative: never)
 * or a cancel arrives (MS_WAIT_CANCELLED). No token is made: the word is the task. `remote` says another thread's
 * event ends the park, so the scheduler waits instead of reporting a deadlock. A post while the task is not parked
 * this way is dropped, and a post meant for an earlier park of the task ends a later one, so the caller rechecks
 * what it waited for. */
uint32_t ms_task_park_word(int64_t at_ns, bool remote);

/* ---- tokens ---- */

/* A new token. */
uint64_t ms_token_new(uint32_t flags);
/* Parks until `id` is posted (`*result` 0, the value in `*value`), the deadline passes (MS_WAIT_TIMEOUT) or a
 * cancel arrives (MS_WAIT_CANCELLED). A post made earlier is kept, so the park returns at once. */
MsTokenStatus ms_token_park_at(uint64_t id, int64_t at_ns, uint64_t *value, uint32_t *result) MS_NONNULL_ARGS(4);
MsTokenStatus ms_token_park(uint64_t id, int64_t timeout_ns, uint64_t *value, uint32_t *result) MS_NONNULL_ARGS(4);
/* Posts from the scheduler's own thread: wakes the waiter, or keeps the post for the next park. A post to a freed
 * token, or to one that holds an untaken post, is dropped. */
void ms_token_post(uint64_t id, uint64_t value);
/* The completion sink of the libuv reactor (ms_io_set_completion_sink in src/runtime/io/reactor.h): posts a finished
 * operation's result to the token its caller parked on. The park's value is the result, an int32_t sign-extended to
 * 64 bits. Runs on the scheduler's thread, inside the poller's wait. */
void ms_sched_post_completion(uint64_t id, int32_t result, uint32_t kind);
/* Ends `id`; later posts are dropped. MS_TOKEN_WAITED_ON when a task waits on it (nothing changes). */
MsTokenStatus ms_token_free(uint64_t id);

#endif
