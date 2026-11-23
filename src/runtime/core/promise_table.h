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
  uint64_t token; /* the waiter's wait word (the parked task, or a token for a wait on several), or 0 */
} Hot;

/* Words of a result kept in the row: an Int, a Float, a String or a small Result needs no heap block. */
enum { PROMISE_SMALL_WORDS = 3 };

typedef struct Cold {
  uint8_t *result;            /* heap block holding an owned value of `desc`, or NULL */
  uint64_t small[PROMISE_SMALL_WORDS]; /* the owned value itself when `small_result` (it fits: no block) */
  bool small_result;
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
  uint64_t queue_sequence;    /* where the queued work sits in this isolate's queue (FLAG_QUEUED) */
  uint32_t next_started;      /* row + 1 of the creator's next older started promise, 0 ends the list */
  uint32_t prev_started;
  uint32_t runner;            /* the isolate that took the work (FLAG_REMOTE), once it said so */
  MsTaskHandle runner_task;   /* the task running it there, or 0 */
  /* The program line that started the work, as a fault report shows a frame (`file:line in function`), or empty.
   * The compiler passes it to the start as a literal, so a start pays nothing for it. */
  MsString started;
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

/* The isolate tag of this thread's ids. Read each time: a scheduler learns its isolate after its table may exist. */
static inline uint64_t promise_own_isolate(void) { return (uint64_t)(ms_sched()->isolate & 0x3fu); }

/* Whether `id` belongs to another isolate's table. */
static inline bool promise_is_foreign(MsPromise id) { return ((uint64_t)id >> ISOLATE_SHIFT) != promise_own_isolate(); }

/* The row of `id`, or -1 for a stale, closed or foreign id. */
static inline ptrdiff_t promise_row_of(MsPromise id) {
  const uint64_t low = (uint64_t)id & 0xffffffffu;
  if (promise_is_foreign(id) || low == 0 || low > promise_table.hot.len) {
    return -1;
  }
  const Hot *const hot = &promise_table.hot.ptr[low - 1];
  if (hot->state == STATE_FREE || (uint64_t)hot->generation != (((uint64_t)id >> 32) & GENERATION_MASK)) {
    return -1;
  }
  return (ptrdiff_t)low - 1;
}

static inline MsPromise promise_make_id(size_t row) {
  return (MsPromise)(promise_own_isolate() << ISOLATE_SHIFT | (uint64_t)promise_table.hot.ptr[row].generation << 32 |
                     (uint64_t)(row + 1));
}

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
static inline void promise_release_started(Cold *cold) { ms_string_release(&cold->started); }
void promise_release_result(size_t row);
/* The stored result's bytes, or NULL when the row holds none. */
static inline uint8_t *promise_result_bytes(Cold *cold) {
  return cold->small_result ? (uint8_t *)cold->small : cold->result;
}
bool promise_ended_without_value(uint8_t state);
void promise_post_watches(size_t row);
void promise_leave_fd(MsPromise id, size_t row);
void promise_stop(MsPromise id);

#endif
