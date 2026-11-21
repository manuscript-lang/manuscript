/* Tasks: records and handles, spawning, switching, joining and cancelling. See task.h and scheduler.h.
 *
 * A task runs on its own stack from a pool (stack.c). `ms_task_switch_away` is the one place a switch happens:
 * it first gives timers, descriptors and stop requests their turn (cheaply: a busy queue checks timers once
 * per round and polls once per POLL_EVERY switches), then runs the next ready task, or idles when none is.
 */
#include "runtime/core/scheduler.h"

#include "base/alloc.h"
#include "runtime/core/context.h"
#include "runtime/sys/sys.h"

enum {
  MIN_READY = 16,            /* slots of the ready ring at first */
  POLL_EVERY = 32,           /* task switches between non-blocking descriptor polls */
  UNWIND_ROUNDS = 1000,      /* yields ms_task_unwind_others gives tasks that will not end */
  STOPPED_LOOK = 4,          /* tasks ms_task_others_stalled is willing to inspect */
  OUTCOME_RETURNED = 0,
  OUTCOME_FAULTED = 1,
  OUTCOME_CANCELLED = 2,
};

/* ---- records and handles ---- */

MsTask *ms_task_lookup(const MsSched *sched, MsTaskHandle handle) {
  const size_t index = (size_t)(handle & 0xffffffffu);
  if (index == 0 || index > sched->slots.len) {
    return NULL;
  }
  const MsTaskSlot slot = sched->slots.ptr[index - 1];
  return slot.generation == (uint32_t)(handle >> 32) ? slot.task : NULL;
}

/* A slot for a new record: a free one with its generation advanced, else a new one. */
static void take_slot(MsSched *sched, size_t *index, uint32_t *generation) {
  if (sched->free_slots.len > 0) {
    *index = sched->free_slots.ptr[--sched->free_slots.len];
    MsTaskSlot *const slot = &sched->slots.ptr[*index];
    slot->generation = (slot->generation + 1) & 0x7fffffffu;
    if (slot->generation == 0) {
      slot->generation = 1;
    }
    *generation = slot->generation;
    return;
  }
  *index = sched->slots.len;
  ms_slot_list_push(&sched->slots, (MsTaskSlot){.task = NULL, .generation = 1});
  *generation = 1;
}

/* A fresh record in the handle table, READY, with no stack. */
static MsTask *new_task(MsSched *sched) {
  size_t index = 0;
  uint32_t generation = 0;
  take_slot(sched, &index, &generation);
  MsTask *const task = ms_alloc_zeroed(sizeof *task);
  task->handle = (uint64_t)generation << 32 | (uint64_t)(index + 1);
  task->state = MS_STATE_READY;
  task->wait_fd = -1;
  task->deadline = MS_NO_DEADLINE;
  task->read_limit = MS_NO_DEADLINE;
  task->kill_at = MS_NO_DEADLINE;
  sched->slots.ptr[index].task = task;
  sched->live++;
  return task;
}

/* Clears a record's slot and frees it. */
static void free_task(MsSched *sched, MsTask *task) {
  const size_t index = (size_t)(task->handle & 0xffffffffu) - 1;
  sched->slots.ptr[index].task = NULL;
  ms_index_list_push(&sched->free_slots, (uint32_t)index);
  ms_task_destroy(sched, task);
  sched->live--;
}

/* The record of the thread's own flow of control, created on first use: it runs on the thread's stack, so it
 * has none to prepare. */
MsTask *ms_task_running(void) {
  MsSched *const sched = ms_sched();
  if (sched->current == NULL) {
    MsTask *const task = new_task(sched);
    task->state = MS_STATE_RUNNING;
    task->flags |= MS_TASK_FLAG_THREAD;
    sched->current = task;
    sched->main_task = task;
    ms_sched_publish(sched, task);
  }
  return sched->current;
}

/* How far below the stack's lowest usable address a fault still counts as overflow; a frame bigger than the guard
 * can skip past it. */
enum { OVERFLOW_REACH = 1 << 20, GUARD_PAGE = 4096 };

bool ms_task_stack_overflow_at(uintptr_t address) {
  const MsSched *const sched = ms_sched_if_any();
  if (sched == NULL || sched->current == NULL) {
    return false;
  }
  const uintptr_t low = sched->current->unwind.stack_low;
  return low != 0 && address < low + GUARD_PAGE && address + OVERFLOW_REACH >= low;
}

/* ---- the ready ring ---- */

void ms_task_enqueue(MsSched *sched, MsTask *task) {
  if (sched->ready_len == sched->ready_cap) {
    /* The ring is full: double it and move the wrapped entries behind the old end. */
    const size_t old_capacity = sched->ready_cap;
    sched->ready_cap = old_capacity == 0 ? MIN_READY : old_capacity * 2;
    sched->ready = ms_realloc(sched->ready, sched->ready_cap * sizeof *sched->ready);
    for (size_t i = 0; i < sched->ready_head; i++) {
      sched->ready[old_capacity + i] = sched->ready[i];
    }
  }
  sched->ready[(sched->ready_head + sched->ready_len) % sched->ready_cap] = task->handle;
  sched->ready_len++;
}

static bool dequeue(MsSched *sched, MsTaskHandle *handle) {
  if (sched->ready_len == 0) {
    return false;
  }
  *handle = sched->ready[sched->ready_head];
  sched->ready_head = (sched->ready_head + 1) % sched->ready_cap;
  sched->ready_len--;
  return true;
}

size_t ms_task_ready_count(const MsSched *sched) { return sched->ready_len; }

/* ---- switching ---- */

/* Frees what a finished task left behind; runs on the stack of a task that is still alive. */
static void reap(MsSched *sched) {
  if (sched->zombie_stack != NULL) {
    ms_stacks_release(&sched->stacks, sched->zombie_stack, sched->zombie_stack_length);
    sched->zombie_stack = NULL;
    sched->zombie_stack_length = 0;
  }
  if (sched->zombie_task != NULL) {
    MsTask *const task = sched->zombie_task;
    sched->zombie_task = NULL;
    free_task(sched, task);
  }
}

/* The cancel flag of a task about to run: a stop request or a cancel aimed at it, unless shielded. */
static void refresh_cancel(const MsSched *sched, MsTask *task) {
  MsUnwind *const unwind = &task->unwind;
  uint8_t flag = 0;
  if (atomic_load_explicit(&unwind->hdr.shield, memory_order_relaxed) == 0) {
    const bool stop_held = atomic_load_explicit(&unwind->hdr.stop_shield, memory_order_relaxed) > 0;
    const uint8_t stop = stop_held ? 0 : ms_sched_stop_request();
    flag = stop > unwind->task_cancel ? stop : unwind->task_cancel;
  }
  (void)sched;
  atomic_store_explicit(&unwind->hdr.cancel, flag, memory_order_relaxed);
}

/* Where the stack of segment `k` of `task` begins: the home slot, or a grown one. */
static uint8_t *segment_base(const MsTask *task, uint32_t k) {
  return k == 0 ? task->stack : task->extra->segments.ptr[k - 1];
}

/* Points every region the task's segments live in at its header, so code running there finds it. */
static void publish_region(MsTask *task) {
  if (task->stack == NULL) {
    return;
  }
  for (uint32_t k = 0; k <= task->segment; k++) {
    uint8_t *const base = segment_base(task, k);
    uintptr_t limit = task->unwind.hdr.limit;
    if (k != task->segment) {
      const uintptr_t top = k == 0 ? ms_stack_top(base, task->stack_length) : (uintptr_t)base + MS_STACK_SLOT;
      limit = ms_stack_limit((uintptr_t)base + MS_STACK_GUARD, top);
    }
    ms_stack_publish(base, &task->unwind.hdr, limit);
  }
}

/* The TEB stack words to install when switching to `task`: its own on Windows, zeros elsewhere. */
static const uintptr_t *teb_of(const MsTask *task) { return task->teb; }

static void save_teb(MsTask *task) { ms_ctx_teb_stack(task->teb); }

/* Gives timers, stop requests and descriptors their turn before the next switch, without paying for a clock
 * read or a system call when nothing needs one. */
static void service(MsSched *sched) {
  if (ms_sched_stop_request() != 0) {
    (void)ms_park_cancel_all(sched);
  }
  if (sched->kills.heap.len != 0 || sched->timers.heap.len != 0 || sched->external.heap.len != 0) {
    /* Timers are checked once per round: a pass over the tasks that were ready when the last check ran. A
     * due timer therefore waits at most one round, as a task at the back of the queue does; a lone task
     * yielding to itself is a round of one and checks on every switch. */
    if (sched->timer_round > sched->ready_len) {
      sched->timer_round = sched->ready_len;
    }
    sched->timer_round = sched->timer_round > 0 ? sched->timer_round - 1 : 0;
    if (sched->timer_round == 0) {
      ms_park_expire(sched, ms_sched_now());
      sched->timer_round = sched->ready_len;
    }
  }
  /* A poll is a system call: a busy queue polls once per POLL_EVERY switches, an empty queue blocks in the idle
   * path, which polls. */
  if (ms_isolate_has_mail()) {
    (void)ms_park_drain_mail(sched);
  }
  sched->switches_since_poll++;
  if (sched->fd_waiting != 0 && sched->switches_since_poll >= POLL_EVERY) {
    sched->switches_since_poll = 0;
    ms_park_poll(sched, 0);
  }
}

void ms_task_switch_away(MsSched *sched) {
  MsTask *const current = sched->current;
  service(sched);
  for (;;) {
    MsTaskHandle handle = 0;
    if (!dequeue(sched, &handle)) {
      ms_park_idle(sched);
      continue;
    }
    MsTask *const next = ms_task_lookup(sched, handle);
    if (next == NULL || next->state != MS_STATE_READY) {
      continue;
    }
    next->state = MS_STATE_RUNNING;
    if (next == current) {
      return;
    }
    publish_region(next);
    refresh_cancel(sched, next);
    sched->current = next;
    ms_sched_publish(sched, next);
    save_teb(current);
    ms_ctx_switch(&current->sp, next->sp, teb_of(next));
    reap(sched);
    return;
  }
}

void ms_task_yield(void) {
  MsSched *const sched = ms_sched();
  MsTask *const current = ms_task_running();
  current->state = MS_STATE_READY;
  ms_task_enqueue(sched, current);
  ms_task_switch_away(sched);
}

/* ---- the first code of a task ---- */

/* Hands a faulted task's report to the fatal-fault hook after the guard caught it. */
static void report_fatal(MsSched *sched, MsTask *task) {
  if (sched->hooks.task_fault != NULL) {
    sched->hooks.task_fault(&task->message);
  }
}

/* Runs the task's entry: guarded unless detached, where a fault ends the process. */
static void run_entry(MsSched *sched, MsTask *task) {
  const MsTaskEntry entry = task->entry;
  task->entry = NULL;
  if ((task->flags & MS_TASK_FLAG_DETACHED) != 0) {
    entry(task->argument);
    return;
  }
  const MsGuardStatus status = ms_guard_call(entry, task->argument, &task->message);
  task->outcome = (uint8_t)status;
  if (status == MS_GUARD_FAULT && (task->flags & MS_TASK_FLAG_FATAL) != 0) {
    report_fatal(sched, task);
  }
}

/* Ends the running task: its stack becomes the zombie stack (released by the next task to run), its joiner wakes,
 * and the scheduler runs something else for good. */
static void finish(MsSched *sched, MsTask *task) {
  task->state = MS_STATE_DONE;
  sched->zombie_stack = task->stack;
  sched->zombie_stack_length = task->stack_length;
  task->stack = NULL;
  /* A task ends on its home segment; the ones it grew into are free now. */
  if (task->extra != NULL) {
    for (size_t i = 0; i < task->extra->segments.len; i++) {
      ms_stacks_release(&sched->stacks, task->extra->segments.ptr[i], MS_STACK_SLOT);
    }
    task->extra->segments.len = 0;
  }
  if ((task->flags & MS_TASK_FLAG_DETACHED) != 0) {
    sched->zombie_task = task;
  } else if (task->joiner != 0) {
    MsTask *const joiner = ms_task_lookup(sched, task->joiner);
    if (joiner != NULL) {
      ms_park_wake(sched, joiner, 0);
    }
  }
  ms_task_switch_away(sched);
}

/* First code run on a new task's stack (the trampoline calls it). */
static void task_main(void) {
  MsSched *const sched = ms_sched();
  reap(sched);
  MsTask *const task = sched->current;
  run_entry(sched, task);
  finish(sched, task);
  /* A finished task is never resumed: nothing queues a Done task. */
  sched->hooks.fault(MS_FAULT_KIND_FAULT, "runtime invariant: a finished task was resumed");
  for (;;) {
    /* The hook never returns. */
  }
}

/* ---- spawning ---- */

MsTaskHandle ms_task_spawn(MsTaskEntry entry, void *arg, uint32_t flags, size_t stack_bytes, MsTaskStatus *status) {
  MsSched *const sched = ms_sched();
  MsTask *const spawner = ms_task_running();
  const uint64_t capture = spawner->capture;
  const bool born_shielded = ms_task_shielded(spawner);
  const size_t length = stack_bytes == MS_TASK_ROOT_STACK ? MS_STACK_REGION : MS_STACK_SLOT;
  uint8_t *base = NULL;
  MsStackBounds bounds = {0};
  if (!ms_stacks_acquire(&sched->stacks, length, &base)) {
    *status = MS_TASK_NO_STACK;
    return 0;
  }
  if (!ms_stack_prepare(base, length, task_main, &bounds)) {
    ms_stacks_release(&sched->stacks, base, length);
    *status = MS_TASK_NO_STACK;
    return 0;
  }
  MsTask *const task = new_task(sched);
  task->stack = base;
  task->stack_length = length;
  task->entry = entry;
  task->argument = arg;
  task->capture = capture;
  task->sp = bounds.sp;
  task->unwind.stack_low = bounds.low;
  task->unwind.stack_high = bounds.high;
  task->unwind.hdr.limit = ms_stack_limit(bounds.low, bounds.high);
  if ((flags & MS_SPAWN_DETACHED) != 0) {
    task->flags |= MS_TASK_FLAG_DETACHED;
  }
  if ((flags & MS_SPAWN_FATAL) != 0) {
    task->flags |= MS_TASK_FLAG_FATAL;
  }
  if (born_shielded) {
    task->flags |= MS_TASK_FLAG_BORN_SHIELDED;
  }
  task->teb[0] = bounds.high;
  task->teb[1] = bounds.high - MS_STACK_INITIAL_COMMIT;
  task->teb[2] = (uintptr_t)base;
  ms_task_enqueue(sched, task);
  *status = MS_TASK_OK;
  return task->handle;
}

uint64_t ms_task_capture(void) { return ms_task_running()->capture; }

void ms_task_set_capture(uint64_t capture) { ms_task_running()->capture = capture; }

MsTaskHandle ms_task_current(void) { return ms_task_running()->handle; }

size_t ms_task_count(void) {
  MsSched *const sched = ms_sched();
  (void)ms_task_running();
  return sched->live - sched->waiting_roots;
}

/* ---- cancelling and joining ---- */

void ms_task_cancel(MsTaskHandle handle) {
  MsSched *const sched = ms_sched();
  MsTask *const current = ms_task_running();
  MsTask *const task = ms_task_lookup(sched, handle);
  if (task == NULL || task->state == MS_STATE_DONE) {
    return;
  }
  if (task == current) {
    ms_cancel_set_task(1);
  } else {
    task->unwind.task_cancel = 1;
    refresh_cancel(sched, task);
  }
  if (task->state == MS_STATE_WAITING && !ms_task_shielded(task)) {
    ms_park_wake(sched, task, MS_WAIT_CANCELLED);
  }
}

MsTaskStatus ms_task_join(MsTaskHandle handle, uint8_t *outcome, MsFaultText *message) {
  MsSched *const sched = ms_sched();
  MsTask *const current = ms_task_running();
  sched->timed_out = false;
  *message = (MsFaultText){0};
  MsTask *const task = ms_task_lookup(sched, handle);
  if (task == NULL) {
    return MS_TASK_NO_SUCH_TASK;
  }
  if ((task->flags & MS_TASK_FLAG_DETACHED) != 0) {
    return MS_TASK_DETACHED;
  }
  if (task == current) {
    return MS_TASK_SELF;
  }
  if (task->joiner != 0) {
    return MS_TASK_ALREADY_JOINED;
  }
  if (task->state != MS_STATE_DONE) {
    if (ms_cancel_flag() != 0) {
      *outcome = OUTCOME_CANCELLED;
      return MS_TASK_OK;
    }
    task->joiner = current->handle;
    current->wait_events = 0;
    current->state = MS_STATE_WAITING;
    ms_task_switch_away(sched);
    task->joiner = 0;
    if (current->wait_result == MS_WAIT_CANCELLED && task->state != MS_STATE_DONE) {
      *outcome = OUTCOME_CANCELLED;
      return MS_TASK_OK;
    }
  }
  *outcome = task->outcome;
  sched->timed_out = (task->flags & MS_TASK_FLAG_TIMED_OUT) != 0 && task->outcome == OUTCOME_CANCELLED;
  *message = task->message;
  task->message = (MsFaultText){0};
  free_task(sched, task);
  return MS_TASK_OK;
}

bool ms_task_timed_out(void) { return ms_sched()->timed_out; }

/* ---- limits ---- */

int64_t ms_task_read_limit(int64_t timeout_ns) {
  MsTask *const task = ms_task_running();
  const int64_t previous = task->read_limit;
  const int64_t add = timeout_ns > 0 ? timeout_ns : 0;
  const int64_t now = ms_sched_now();
  const int64_t limit = now > INT64_MAX - add ? INT64_MAX : now + add;
  task->read_limit = limit < previous ? limit : previous;
  return previous;
}

void ms_task_read_limit_restore(int64_t previous) { ms_task_running()->read_limit = previous; }

bool ms_task_read_limit_passed(void) { return ms_task_running()->read_limit <= ms_sched_now(); }

void ms_task_limit_current_at(int64_t at_ns) {
  MsTask *const task = ms_task_running();
  task->kill_at = MS_NO_DEADLINE;
  if (at_ns >= 0) {
    ms_park_arm_kill(ms_sched(), task, at_ns);
  }
}

void ms_task_limit_current(int64_t limit_ns) {
  MsTask *const task = ms_task_running();
  task->kill_at = MS_NO_DEADLINE;
  if (limit_ns < 0) {
    return;
  }
  const int64_t now = ms_sched_now();
  ms_park_arm_kill(ms_sched(), task, now > INT64_MAX - limit_ns ? INT64_MAX : now + limit_ns);
}

/* ---- inspection ---- */

/* Whether `task` waits only for something that this thread's own tasks produce. */
static bool task_stalled(const MsSched *sched, const MsTask *task) {
  if (task->state == MS_STATE_DONE) {
    return true;
  }
  if (task->state != MS_STATE_WAITING) {
    return false;
  }
  if (task->deadline != MS_NO_DEADLINE || task->kill_at != MS_NO_DEADLINE) {
    return false;
  }
  if (task->wait_token == 0) {
    return task->wait_events == 0;
  }
  /* A token another thread may post could wake the task while this thread is blocked. */
  return !ms_token_is_remote(sched, task->wait_token);
}

bool ms_task_others_stalled(void) {
  MsSched *const sched = ms_sched();
  const MsTask *const current = ms_task_running();
  if (sched->live - sched->waiting_roots > STOPPED_LOOK) {
    return false;
  }
  for (size_t i = 0; i < sched->slots.len; i++) {
    const MsTask *const task = sched->slots.ptr[i].task;
    if (task == NULL || task == current) {
      continue;
    }
    if (!task_stalled(sched, task)) {
      return false;
    }
  }
  return true;
}

MS_LIST_DEFINE(HandleList, handle_list, MsTaskHandle)

/* Adds the handles of every task but the running and main ones that has not finished. */
static void collect_live(const MsSched *sched, HandleList *handles) {
  for (size_t i = 0; i < sched->slots.len; i++) {
    const MsTask *const task = sched->slots.ptr[i].task;
    if (task == NULL || task == sched->current || task == sched->main_task ||
        (task->flags & MS_TASK_FLAG_THREAD) != 0 || task->state == MS_STATE_DONE) {
      continue;
    }
    handle_list_push(handles, task->handle);
  }
}

void ms_task_unwind_others(void) {
  MsSched *const sched = ms_sched();
  (void)ms_task_running();
  for (unsigned round = 0; round < UNWIND_ROUNDS; round++) {
    HandleList handles = {0};
    collect_live(sched, &handles);
    if (handles.len == 0) {
      handle_list_free(&handles);
      return;
    }
    for (size_t i = 0; i < handles.len; i++) {
      ms_task_cancel(handles.ptr[i]);
    }
    handle_list_free(&handles);
    ms_task_yield();
  }
}

/* ---- the main task ---- */

MsTaskStatus ms_task_run_main(MsTaskEntry entry, void *arg, uint32_t flags, uint8_t *outcome, MsFaultText *message) {
  MsSched *const sched = ms_sched();
  (void)ms_task_running();
  MsTaskStatus status = MS_TASK_OK;
  const MsTaskHandle handle = ms_task_spawn(entry, arg, flags, MS_TASK_ROOT_STACK, &status);
  if (handle == 0) {
    return status;
  }
  sched->main_task = ms_task_lookup(sched, handle);
  ms_shield_enter();
  sched->waiting_roots++;
  status = ms_task_join(handle, outcome, message);
  sched->waiting_roots--;
  ms_shield_exit();
  return status;
}

uint32_t ms_task_started_head(MsTaskHandle handle) {
  const MsTask *const task = ms_task_lookup(ms_sched(), handle);
  return task == NULL ? 0 : task->started_head;
}

uint32_t ms_task_started_swap(MsTaskHandle handle, uint32_t head) {
  MsTask *const task = ms_task_lookup(ms_sched(), handle);
  if (task == NULL) {
    return 0;
  }
  const uint32_t previous = task->started_head;
  task->started_head = head;
  return previous;
}

int64_t ms_task_defer_deadline(void) {
  const MsTask *const task = ms_sched()->current;
  return task == NULL || task->defer_at == 0 ? MS_NO_DEADLINE : task->defer_at;
}

int64_t ms_task_set_defer_deadline(int64_t at_ns) {
  MsTask *const task = ms_sched()->current;
  if (task == NULL) {
    return MS_NO_DEADLINE;
  }
  const int64_t previous = task->defer_at == 0 ? MS_NO_DEADLINE : task->defer_at;
  task->defer_at = at_ns == MS_NO_DEADLINE ? 0 : at_ns;
  return previous;
}

void *ms_task_watch(void) { return ms_sched()->current == NULL ? NULL : ms_sched()->current->watch; }

void *ms_task_set_watch(void *watch) {
  MsTask *const task = ms_sched()->current;
  if (task == NULL) {
    return NULL;
  }
  void *const previous = task->watch;
  task->watch = watch;
  return previous;
}
