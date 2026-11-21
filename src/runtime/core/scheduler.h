/* scheduler.h: the scheduler's records, shared by task.c, park.c, token.c and unwind.c. Internal to src/runtime/core:
 * nothing outside the scheduler includes it; the rest of the runtime uses task.h.
 *
 * One scheduler per thread (an isolate), reached through ms_sched(). Its state is plain tables indexed by small
 * integers, so a switch touches a few cache lines and a parked task is a record plus table entries:
 *
 *   slots[]       handle table: slot -> record and generation        (16 bytes per task, ever)
 *   ready         ring of runnable handles                           ( 8 bytes per runnable task)
 *   timers        heap of (deadline, handle)                         (16 bytes per timed wait)
 *   fd_queues[]   per descriptor: first and last waiter              ( 8 bytes per descriptor ever waited on)
 *   waiters[]     waiter nodes, doubly linked per descriptor         (32 bytes per task on a descriptor)
 *   tokens[]      one-shot park slots                                (32 bytes per token)
 */
#ifndef MS_CORE_SCHEDULER_H
#define MS_CORE_SCHEDULER_H

#include <stdatomic.h>

#include "stack.h"
#include "task.h"
#include "timers.h"

enum {
    MS_STATE_READY = 0,
    MS_STATE_RUNNING = 1,
    MS_STATE_WAITING = 2,
    MS_STATE_DONE = 3,
};

enum {
    MS_TASK_FLAG_DETACHED = 1,
    MS_TASK_FLAG_FATAL = 2,
    MS_TASK_FLAG_TIMED_OUT = 4,
    MS_TASK_FLAG_BORN_SHIELDED = 16, /* started while its spawner was shielded: the sweep does not cancel its parks */
    MS_TASK_FLAG_THREAD = 8, /* the record of the thread's own flow of control, not a task anything can cancel */
};

/* Slot of the waiter list nodes: index + 1, 0 ends a list. */
typedef uint32_t MsNode;

/* Stack segments a task grew into (ms_task_grow); allocated on the first grow. */
typedef struct MsTaskExtra {
    uint8_t **segments; /* owned: slot bases in order; kept until the task ends, so a loop at a boundary allocates
                           nothing */
    size_t segment_count;
    size_t segment_capacity;
    uintptr_t (*segment_teb)[MS_CTX_TEB_WORDS]; /* owned, Windows only: the stack words of each segment below the
                                                    current one */
    size_t segment_teb_count;
    size_t segment_teb_capacity;
} MsTaskExtra;

/* The record of one task. `unwind` is first: generated code reaches its header through the region cell. */
typedef struct MsTask {
    MsUnwind unwind;
    uintptr_t sp;       /* saved stack pointer while switched out */
    MsTaskHandle handle;
    MsTaskHandle joiner; /* the task joining this one, or 0 */
    uint64_t wait_token; /* the token this task is parked on, or 0 */
    uint8_t *stack;      /* start of the slot, guard included; NULL for the thread's own flow */
    size_t stack_length;
    MsTaskEntry entry;
    void *argument;
    int64_t deadline;   /* when the park times out, or MS_NO_DEADLINE */
    int64_t read_limit; /* every park ends by then (ms_task_read_limit), or MS_NO_DEADLINE */
    uint64_t capture;   /* the test output capture this task prints to, or 0; spawned tasks inherit it */
    int64_t kill_at;    /* when the task is cancelled for running too long, or MS_NO_DEADLINE */
    MsFaultText message; /* the fault message of a joinable task, until joined */
    MsTaskExtra *extra;  /* owned, or NULL: stack segments */
    uint32_t wait_result;
    uint32_t wait_events;
    int32_t wait_fd;
    MsNode wait_node; /* this task's waiter node on wait_fd */
    void *watch;            /* see ms_task_set_watch */
    int64_t defer_at;       /* deadline of the deferred promise this task runs, 0 when none */
    uint32_t started_head;  /* first promise this task started (row + 1), 0 for none */
    uint32_t segment; /* the segment the task runs on: 0 is the home slot, k is segments[k - 1] */
    uint8_t state;
    uint8_t outcome;
    uint8_t flags;
#if defined(_WIN32)
    uintptr_t teb[MS_CTX_TEB_WORDS]; /* the TEB stack words while switched out */
#endif
} MsTask;

typedef struct MsTaskSlot {
    MsTask *task; /* NULL while the slot is free */
    uint32_t generation;
} MsTaskSlot;

/* A task parked on a descriptor. */
typedef struct MsWaiter {
    uint64_t owner;  /* the task's handle */
    uint32_t events; /* MS_WAIT_READ, MS_WAIT_WRITE, MS_WAIT_KEEP */
    int32_t fd;
    MsNode next; /* toward the newest, or the next free node */
    MsNode prev; /* toward the oldest */
} MsWaiter;

typedef struct MsFdQueue {
    MsNode oldest;
    MsNode newest;
} MsFdQueue;

/* One-shot park slot; its id is `isolate << 52 | generation << 32 | (index + 1)`. */
typedef struct MsToken {
    uint64_t waiter; /* handle of the task parked on it, or 0 */
    uint64_t value;  /* a delivered post the waiter has not taken yet (valid when has_post) */
    uint32_t generation;
    bool live;
    bool remote; /* expects a post from another thread that has not arrived */
    bool peer;   /* the pending post comes from another isolate */
    bool has_post;
} MsToken;

#define MS_TOKEN_GENERATION_MASK 0xfffffu /* 20 bits; the id's top 12 name the isolate */
#define MS_TOKEN_ISOLATE_SHIFT 52

typedef struct MsSched {
    MsSchedHooks hooks;
    MsPollOps poll;
    MsTask *current;
    MsTask *main_task;
    uint32_t isolate; /* registry index carried in token ids */
    _Atomic uint8_t stop_request; /* a stop aimed at this scheduler, 0 when none; set from any thread */
    _Atomic(MsTaskHdr *) published_hdr; /* the running task's header, for a stop raised from another thread */
    bool cancel_edges;            /* the program's modules branch on `unwinding` after a call that can park */

    MsTaskSlot *slots; /* the handle table */
    size_t slot_count;
    size_t slot_capacity;
    uint32_t *free_slots; /* indices of free slots */
    size_t free_slot_count;
    size_t free_slot_capacity;
    size_t live;          /* tasks that exist */
    size_t waiting_roots; /* flows that only wait for the isolate's main task */

    uint64_t *ready; /* ring buffer of runnable handles */
    size_t ready_head;
    size_t ready_length;
    size_t ready_capacity;

    MsTimers timers; /* parks with a deadline */
    MsTimers kills;  /* tasks with a time limit */
    MsTimers external; /* entries of other tables (promise sleeps and limits) */
    size_t external_limit;
    size_t timer_limit;
    size_t kill_limit;
    size_t timer_round; /* switches left in the round that began at the last timer check */
    uint32_t switches_since_poll;

    MsFdQueue *fd_queues; /* by descriptor */
    size_t fd_queue_count;
    size_t fd_queue_capacity;
    MsWaiter *waiters;
    size_t waiter_count;
    size_t waiter_capacity;
    MsNode waiter_free; /* head of the free node list */
    size_t fd_waiting;  /* tasks parked on a descriptor */

    MsStacks stacks;
    uint8_t *zombie_stack; /* the finished task's stack, released once its successor runs */
    size_t zombie_stack_length;
    MsTask *zombie_task;   /* the finished task's record, freed the same way */

    MsToken *tokens;
    size_t token_count;
    size_t token_capacity;
    uint32_t *free_tokens;
    size_t free_token_count;
    size_t free_token_capacity;
    size_t remote_tokens; /* live tokens still expecting a post from another thread */
    size_t peer_tokens;   /* those another isolate will post */

    bool timed_out; /* the last join found the task cancelled for running too long */
    MsFaultText guard_message; /* the fault message ms_guard_leave hands to the landing of ms_guard_call */
} MsSched;

/* This thread's scheduler, created on first use. */
MsSched *ms_sched(void) MS_RETURNS_NONNULL;
/* This thread's scheduler if one exists, else NULL. */
MsSched *ms_sched_if_any(void);
/* The running task; creates the record of the thread's own flow on first use. */
MsTask *ms_task_running(void) MS_RETURNS_NONNULL;
/* Frees a record, its segments and buffers; its stacks go to the pool. The slot is the caller's to clear. */
void ms_task_destroy(MsSched *sched, MsTask *task) MS_NONNULL;
/* The record behind `handle`, or NULL. */
MsTask *ms_task_lookup(const MsSched *sched, MsTaskHandle handle);
/* Makes `task` the running task's header a remote stop raises its cancel flag on (see ms_sched_stop_remote), then
 * applies a stop that arrived since the flag was last refreshed. */
void ms_sched_publish(MsSched *sched, MsTask *task) MS_NONNULL;
/* The stack window (low, high, chain) of the task the stop target runs, for the profiler's sampler on any thread or in
 * a signal handler. False when no task is published. */
bool ms_sched_sample_window(uintptr_t window[3]);
/* The stop request aimed at this thread's scheduler (SIGINT, SIGTERM, a parent's cancel), 0 when none. */
uint8_t ms_sched_stop_request(void);

/* Whether `task` is inside a cancellation shield: a cancel then leaves it parked. */
static inline bool ms_task_shielded(const MsTask *task) {
    return atomic_load_explicit(&task->unwind.hdr.shield, memory_order_relaxed) > 0;
}
/* Whether `task` holds a stop shield, which keeps SIGINT and SIGTERM from waking it. */
static inline bool ms_task_stop_shielded(const MsTask *task) {
    return atomic_load_explicit(&task->unwind.hdr.stop_shield, memory_order_relaxed) > 0;
}

/* ---- park.c: waiting, timers, wake-ups ---- */

/* Marks a waiting task runnable with the park result. */
void ms_park_wake(MsSched *sched, MsTask *task, uint32_t result);
/* Arms the timer of a park ending at `at_ns` (MS_NO_DEADLINE: never), limited by the task's read limit. */
void ms_park_set_deadline(MsSched *sched, MsTask *task, int64_t at_ns);
/* Registers the running task as a waiter of `fd` for `events`; false when `fd` cannot be waited on. On true,
 * `*ready_now` says it is ready at once and nothing was registered. */
/* Handles the mail queued for this isolate; true when it made a task ready. */
bool ms_park_drain_mail(MsSched *sched);
MS_NODISCARD bool ms_park_watch(MsSched *sched, MsTask *task, int fd, uint32_t events, bool *ready_now);
/* Cancels tasks whose time limit passed and wakes timers that expired. */
void ms_park_expire(MsSched *sched, int64_t now);
/* Wakes every waiting task that is not shielded with MS_WAIT_CANCELLED, the main task first. */
bool ms_park_cancel_all(MsSched *sched);
/* Delivers descriptor readiness, waiting at most `timeout_ns` (0 never blocks, negative waits for an event). */
void ms_park_poll(MsSched *sched, int64_t timeout_ns);
/* Blocks until at least one task is runnable (the idle path of the scheduler). */
void ms_park_idle(MsSched *sched);
/* Re-registers `fd` for what its waiters still ask. */
void ms_park_rearm(MsSched *sched, int fd);
/* Releases every table of park.c. */
void ms_park_free(MsSched *sched);
/* The running task's time limit: arms `at_ns` on the kill heap. */
void ms_park_arm_kill(MsSched *sched, MsTask *task, int64_t at_ns);

/* ---- token.c ---- */

/* Clears the wait a task leaves when its park is abandoned by a fault. */
void ms_token_abandon(MsSched *sched, MsTask *task);
void ms_token_free_all(MsSched *sched);
/* Whether the token `id` is live and expects a post from another thread. */
bool ms_token_is_remote(const MsSched *sched, uint64_t id);

/* ---- task.c ---- */

/* Runs the next runnable task; returns when the calling task is scheduled again. The caller has set its state
 * (Ready and queued, Waiting, or Done). */
void ms_task_switch_away(MsSched *sched);
void ms_task_enqueue(MsSched *sched, MsTask *task);
size_t ms_task_ready_count(const MsSched *sched);

#endif