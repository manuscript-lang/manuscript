/* promise_table.h: the promise table's rows, shared by promise.c, promise_end.c and promise_wait.c.
 * Nothing outside the promise files includes it; the rest of the runtime uses promise.h.
 */
#ifndef MS_RUNTIME_CORE_PROMISE_TABLE_H
#define MS_RUNTIME_CORE_PROMISE_TABLE_H

#include "runtime/core/promise.h"

#include "base/alloc.h"
#include "runtime/core/obj.h"
#include "runtime/core/scheduler.h"

enum PromiseState {
  STATE_FREE = 0,
  STATE_PENDING,
  STATE_OK,
  STATE_ERROR,
  STATE_FAILED,
  STATE_CANCELLED,
  STATE_TAKEN,
};

enum {
  FLAG_REMOTE_WAKE = 1, /* another thread completes this promise: a waiter's token must be remote */
  FLAG_HELD = 2,        /* the result is stored, but the promise stays pending until its work's task ended */
  FLAG_HELD_ERROR = 4,  /* the held result is the operation's own error */
  FLAG_DEFERRED = 8,    /* no task: the first waiter runs the work on its own stack */
  FLAG_TIMED_OUT = 16,  /* the limit passed and ended it: a wait reports a timeout, not a cancellation */
  FLAG_STOPPED = 32,    /* stop asked the work to cancel; without a result it reads as cancelled */
  FLAG_GROUPED = 64,    /* a wait group member: the group hears when it finishes */
  FLAG_QUEUED = 128,    /* DEFERRED work that is also in this isolate's queue, open to other isolates */
  FLAG_REMOTE = 256,    /* another isolate took the work: it reports by mail, and the closure is its own */
  FLAG_WANT_CANCEL = 512, /* a cancel arrived before the isolate that took the work said which task runs it */
  FLAG_WATCHED = 1024,    /* another isolate asked to be told when it finishes (the watch table) */
};

/* The promise events isolates send each other (MsMail words: a = op | status << 8 | failed << 16, b = id). */
enum PromiseMail {
  MAIL_STARTED = 1, /* to the owner: c = the task running the work (the sender is the isolate) */
  MAIL_DONE,        /* to the owner: p = result block, q = its desc, c = the pipe it came from */
  MAIL_ENDED,       /* to the owner: p = fault report bytes, c = their length; the status is in `a` */
  MAIL_CANCEL,      /* to the runner: b = the task to cancel */
};

#define GENERATION_MASK 0xffffffu /* 24 bits: an id is `isolate << 56 | generation << 32 | (row + 1)` */
#define ISOLATE_SHIFT 56
#define NO_TIME INT64_MAX

typedef struct Hot {
  uint8_t state;
  uint16_t flags;
  uint32_t generation;
  uint64_t token; /* the token a waiter parks on, or 0 */
} Hot;

typedef struct Cold {
  uint8_t *result;            /* heap block holding an owned value of `desc`, or NULL */
  const MsTypeDesc *desc;
  MsObj *closure;             /* the work while its task may still run (or the deferred work), else NULL */
  MsTaskHandle task;          /* the task running the work, else 0 */
  MsTaskHandle creator;       /* the task that started the work, else 0 */
  size_t started_at;          /* the creator's cleanup height when it started the work */
  int64_t deadline;           /* when a sleep ends, or NO_TIME */
  int64_t limit;              /* when the limit ends the promise, or NO_TIME */
  MsPromiseRetry retry;       /* the continuation of an I/O promise */
  uintptr_t retry_state;
  int64_t pipe;               /* the pipe a result block came from, for the unread hook */
  int32_t fd;                 /* the descriptor a readiness wait watches, or -1 */
  uint32_t events;            /* what that wait asks for */
  MsFaultText report;         /* the fault that ended the promise */
  int64_t cancel;             /* the cancel switch the promise listens to, or 0 */
  int64_t drain;              /* the switch fired before the work is cancelled by its owner's end, or 0 */
  int64_t grace;              /* how long the work has after that notice (negative: no limit) */
  uint32_t next_started;      /* row + 1 of the creator's next older started promise, 0 ends the list */
  uint32_t prev_started;
  uint32_t runner;            /* the isolate that took the work (FLAG_REMOTE), once it said so */
  MsTaskHandle runner_task;   /* the task running it there, or 0 */
  uintptr_t *started;         /* return addresses of the code that started the work, for a fault report, or NULL */
  size_t started_count;
} Cold;

/* Remote tokens to post when a promise finishes: (row, generation) entries of promises another isolate waits on. */
typedef struct Watch {
  uint32_t row;
  uint32_t generation;
  uint64_t token;
} Watch;

MS_LIST_DEFINE(WatchList, watch_list, Watch)
MS_LIST_DEFINE(HotList, hot_list, Hot)
MS_LIST_DEFINE(ColdList, cold_list, Cold)
MS_LIST_DEFINE(RowList, row_list, uint32_t)

typedef struct Table {
  WatchList watches;
  HotList hot;
  ColdList cold; /* as long as `hot` */
  RowList free_rows;
} Table;

typedef struct MsClosure {
  MsObj header;
  void (*code)(struct MsClosure *);
} MsClosure;

extern _Thread_local Table promise_table; /* per-thread state, like the scheduler's */

void promise_fail(const char *text);
bool promise_is_foreign(MsPromise id);
ptrdiff_t promise_row_of(MsPromise id);
size_t promise_row_or_fault(MsPromise id);
void promise_wake(size_t row);
bool promise_claim_queued(size_t row);
bool promise_run_deferred(MsPromise id, int64_t deadline, bool guarded);
void promise_request_cancel(size_t row);
uint32_t promise_park_on(MsPromise id, int64_t at_ns);
void promise_end_started(size_t base);
bool promise_timer_live(uint64_t id, int64_t deadline);
void promise_timer_fire(uint64_t id, int64_t deadline);
bool promise_fd_ready(uint64_t id, uint32_t bits);
MsPromise promise_make_id(size_t row);
void promise_release_started(Cold *cold);
void promise_release_result(size_t row);
bool promise_ended_without_value(uint8_t state);
void promise_post_watches(size_t row);
void promise_leave_fd(MsPromise id, size_t row);
void promise_stop(MsPromise id);

#endif
