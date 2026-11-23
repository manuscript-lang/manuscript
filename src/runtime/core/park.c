/* Waiting: descriptors, timers, time limits, wake-ups and the idle path. See scheduler.h and task.h.
 *
 * A task parked on a descriptor is a node in that descriptor's list; the poller watches the union of what the
 * list's tasks ask for. A woken task unlinks its own node in constant time, and only the descriptor it waited
 * on is looked at again. Timers are a heap with lazy deletion (timers.h).
 */
#include "base/alloc.h"
#include "runtime/core/isolate.h"
#include "runtime/core/scheduler.h"
#include "runtime/core/stats.h"
#include "runtime/core/watch.h"

enum {
  READY_BATCH = 64, /* descriptor events taken from the poller at once */
  MIN_TIMER_LIMIT = 1024,
  IDLE_TRIM_WARM = 256, /* pooled stacks kept with their pages when the scheduler idles */
};

static const char deadlock_message[] =
  "deadlock: every task is waiting and nothing can wake them; a wait has no matching completion, timer, "
  "I/O or cancellation";

/* ---- waiter nodes ---- */

static MsNode node_alloc(MsSched *sched) {
  if (sched->waiter_free != 0) {
    const MsNode node = sched->waiter_free;
    sched->waiter_free = sched->waiters.ptr[node - 1].next;
    return node;
  }
  ms_waiter_list_push(&sched->waiters, (MsWaiter){0});
  return (MsNode)sched->waiters.len;
}

static void node_free(MsSched *sched, MsNode node) {
  sched->waiters.ptr[node - 1].next = sched->waiter_free;
  sched->waiter_free = node;
}

/* The queue of `fd`, growing the table to hold it; it is the table's entry, valid until the next growth. */
static MsFdQueue *queue_of(MsSched *sched, int fd) {
  const size_t index = (size_t)fd;
  while (index >= sched->fd_queues.len) {
    ms_fd_queue_list_push(&sched->fd_queues, (MsFdQueue){0});
  }
  return &sched->fd_queues.ptr[index];
}

static void append_node(MsSched *sched, MsFdQueue *queue, MsNode node) {
  MsWaiter *const waiter = &sched->waiters.ptr[node - 1];
  waiter->next = 0;
  waiter->prev = queue->newest;
  if (queue->newest != 0) {
    sched->waiters.ptr[queue->newest - 1].next = node;
  } else {
    queue->oldest = node;
  }
  queue->newest = node;
}

static void unlink_node(MsSched *sched, MsFdQueue *queue, MsNode node) {
  const MsWaiter waiter = sched->waiters.ptr[node - 1];
  if (waiter.prev != 0) {
    sched->waiters.ptr[waiter.prev - 1].next = waiter.next;
  } else {
    queue->oldest = waiter.next;
  }
  if (waiter.next != 0) {
    sched->waiters.ptr[waiter.next - 1].prev = waiter.prev;
  } else {
    queue->newest = waiter.prev;
  }
}

/* What the poller must watch for `fd` given `asked` and what the queue's waiters ask: a descriptor is kept only
 * if every waiter keeps it. */
static uint32_t combined_events(const MsSched *sched, const MsFdQueue *queue, uint32_t asked) {
  for (MsNode node = queue->oldest; node != 0; node = sched->waiters.ptr[node - 1].next) {
    const uint32_t other = sched->waiters.ptr[node - 1].events & ~(uint32_t)MS_WAIT_PROMISE;
    asked = ((asked | other) & ~MS_WAIT_KEEP) | (asked & other & MS_WAIT_KEEP);
  }
  return asked;
}

void ms_park_rearm(MsSched *sched, int fd) {
  const MsFdQueue *const queue = &sched->fd_queues.ptr[fd];
  uint32_t asked = 0;
  uint32_t keep = MS_WAIT_KEEP;
  for (MsNode node = queue->oldest; node != 0; node = sched->waiters.ptr[node - 1].next) {
    const uint32_t events = sched->waiters.ptr[node - 1].events;
    if (events != 0) {
      asked |= events & (MS_WAIT_READ | MS_WAIT_WRITE);
      keep &= events;
    }
  }
  if (asked == 0) {
    asked = MS_WAIT_READ;
  }
  /* A registration that cannot be renewed leaves its tasks to their timeouts. */
  (void)sched->poll.watch(fd, asked | keep);
}

bool ms_park_watch(MsSched *sched, MsTask *task, int fd, uint32_t events, bool *ready_now) {
  MsFdQueue *const queue = queue_of(sched, fd);
  *ready_now = false;
  const int armed = sched->poll.watch(fd, combined_events(sched, queue, events));
  if (armed == MS_POLL_ALWAYS) {
    *ready_now = true;
    return true;
  }
  if (armed != MS_POLL_ARMED) {
    return false;
  }
  const MsNode node = node_alloc(sched);
  sched->waiters.ptr[node - 1] = (MsWaiter){.owner = task->handle, .events = events, .fd = fd};
  append_node(sched, queue, node);
  task->wait_node = node;
  task->wait_fd = fd;
  task->wait_events = events;
  sched->fd_waiting++;
  return true;
}

/* ---- wake-ups ---- */

/* Removes a waiter node, leaving the poller watching what the other waiters still ask. */
static void leave_node(MsSched *sched, int fd, MsNode node) {
  MsFdQueue *const queue = &sched->fd_queues.ptr[fd];
  unlink_node(sched, queue, node);
  node_free(sched, node);
  sched->fd_waiting--;
  if (queue->oldest == 0) {
    sched->poll.unwatch(fd);
  } else {
    ms_park_rearm(sched, fd);
  }
}

/* Ends the descriptor wait of a task. */
static void leave_descriptor(MsSched *sched, MsTask *task) {
  leave_node(sched, task->wait_fd, task->wait_node);
  task->wait_node = 0;
  task->wait_fd = -1;
}

int ms_sched_fd_wait_begin(uint64_t id, int fd, uint32_t events) {
  MsSched *const sched = ms_sched();
  MsFdQueue *const queue = queue_of(sched, fd);
  const int armed = sched->poll.watch(fd, combined_events(sched, queue, events));
  if (armed != MS_POLL_ARMED) {
    return armed;
  }
  const MsNode node = node_alloc(sched);
  sched->waiters.ptr[node - 1] = (MsWaiter){.owner = id, .events = events | MS_WAIT_PROMISE, .fd = fd};
  append_node(sched, queue, node);
  sched->fd_waiting++;
  return MS_POLL_ARMED;
}

void ms_sched_fd_wait_end(uint64_t id, int fd) {
  MsSched *const sched = ms_sched();
  if (fd < 0 || (size_t)fd >= sched->fd_queues.len) {
    return;
  }
  for (MsNode node = sched->fd_queues.ptr[fd].oldest; node != 0; node = sched->waiters.ptr[node - 1].next) {
    const MsWaiter *const waiter = &sched->waiters.ptr[node - 1];
    if (waiter->owner == id && (waiter->events & MS_WAIT_PROMISE) != 0) {
      leave_node(sched, fd, node);
      return;
    }
  }
}

void ms_park_wake(MsSched *sched, MsTask *task, uint32_t result) {
  if (task->state != MS_STATE_WAITING) {
    return;
  }
  if (task->wait_fd >= 0) {
    leave_descriptor(sched, task);
  }
  ms_token_abandon(sched, task);
  task->deadline = MS_NO_DEADLINE;
  task->wait_result = result;
  task->state = MS_STATE_READY;
  ms_task_enqueue(sched, task);
}

/* ---- timers ---- */

/* Whether a heap entry still means something: its task is parked and waits for exactly that deadline, or is
 * the task that is about to park (`own`, `fresh`). */
typedef struct DeadlineCheck {
  const MsSched *sched;
  uint64_t own;
  int64_t fresh;
} DeadlineCheck;

static bool timer_live(void *context, MsTimer timer) {
  const DeadlineCheck *const check = context;
  if (timer.handle == check->own && timer.deadline == check->fresh) {
    return true;
  }
  const MsTask *const task = ms_task_lookup(check->sched, timer.handle);
  return task != NULL && task->state == MS_STATE_WAITING && task->deadline == timer.deadline;
}

void ms_park_set_deadline(MsSched *sched, MsTask *task, int64_t at_ns) {
  task->deadline = MS_NO_DEADLINE;
  int64_t at = at_ns < 0 ? MS_NO_DEADLINE : at_ns;
  if (task->read_limit < at) {
    at = task->read_limit; /* a bounded read: no park outlasts the limit */
  }
  if (at == MS_NO_DEADLINE) {
    return;
  }
  task->deadline = at;
  ms_timers_push(&sched->timers, (MsTimer){.deadline = at, .handle = task->handle});
  if (sched->timers.heap.len > sched->timer_limit) {
    /* A task woken by its descriptor leaves its entry until the deadline; a loop of short waits with long
     * timeouts must not grow the heap without bound. */
    DeadlineCheck check = {.sched = sched, .own = task->handle, .fresh = at};
    ms_timers_retain(&sched->timers, timer_live, &check);
    const size_t doubled = sched->timers.heap.len * 2;
    sched->timer_limit = doubled > MIN_TIMER_LIMIT ? doubled : MIN_TIMER_LIMIT;
  }
}

static bool kill_live(void *context, MsTimer timer) {
  const MsSched *const sched = context;
  const MsTask *const task = ms_task_lookup(sched, timer.handle);
  return task != NULL && task->state != MS_STATE_DONE && task->kill_at == timer.deadline;
}

void ms_park_arm_kill(MsSched *sched, MsTask *task, int64_t at_ns) {
  task->kill_at = at_ns;
  ms_timers_push(&sched->kills, (MsTimer){.deadline = at_ns, .handle = task->handle});
  if (sched->kills.heap.len > sched->kill_limit) {
    /* Completed tasks leave future deadlines behind. Compact geometrically, so repeated short tasks with long
     * limits retain space proportional to live work. */
    ms_timers_retain(&sched->kills, kill_live, sched);
    const size_t doubled = sched->kills.heap.len * 2;
    sched->kill_limit = doubled > MIN_TIMER_LIMIT ? doubled : MIN_TIMER_LIMIT;
  }
}

static bool external_live(void *context, MsTimer timer) {
  const MsSched *const sched = context;
  return sched->hooks.timer_live(timer.handle, timer.deadline);
}

void ms_sched_arm(uint64_t id, int64_t at_ns) {
  MsSched *const sched = ms_sched();
  ms_timers_push(&sched->external, (MsTimer){.deadline = at_ns, .handle = id});
  if (sched->external.heap.len > sched->external_limit) {
    ms_timers_retain(&sched->external, external_live, sched);
    const size_t doubled = sched->external.heap.len * 2;
    sched->external_limit = doubled > MIN_TIMER_LIMIT ? doubled : MIN_TIMER_LIMIT;
  }
}

void ms_park_expire(MsSched *sched, int64_t now) {
  MsTimer entry = {0};
  while (ms_timers_peek(&sched->external, &entry) && entry.deadline <= now) {
    ms_timers_pop(&sched->external);
    if (sched->hooks.timer_live(entry.handle, entry.deadline)) {
      sched->hooks.timer_fire(entry.handle, entry.deadline);
    }
  }
  MsTimer due = {0};
  while (ms_timers_peek(&sched->kills, &due) && due.deadline <= now) {
    ms_timers_pop(&sched->kills);
    MsTask *const task = ms_task_lookup(sched, due.handle);
    if (task != NULL && task->state != MS_STATE_DONE && task->kill_at == due.deadline) {
      task->flags |= MS_TASK_FLAG_TIMED_OUT;
      ms_task_cancel(due.handle);
    }
  }
  while (ms_timers_peek(&sched->timers, &due) && due.deadline <= now) {
    ms_timers_pop(&sched->timers);
    MsTask *const task = ms_task_lookup(sched, due.handle);
    if (task != NULL && task->state == MS_STATE_WAITING && task->deadline == due.deadline) {
      ms_park_wake(sched, task, MS_WAIT_TIMEOUT);
    }
  }
}

/* ---- cancelling every waiter ---- */

static bool cancellable(const MsTask *task) {
  return task != NULL && task->state == MS_STATE_WAITING && !ms_task_shielded(task) && !ms_task_stop_shielded(task);
}

bool ms_park_cancel_all(MsSched *sched) {
  bool woke = false;
  if (cancellable(sched->main_task)) {
    ms_park_wake(sched, sched->main_task, MS_WAIT_CANCELLED);
    woke = true;
  }
  for (size_t i = 0; i < sched->slots.len; i++) {
    MsTask *const task = sched->slots.ptr[i].task;
    if (cancellable(task)) {
      ms_park_wake(sched, task, MS_WAIT_CANCELLED);
      woke = true;
    }
  }
  return woke;
}

/* ---- descriptor readiness ---- */

/* Wakes the waiters of `fd` that the event concerns; the one that gets the resource proceeds and the others wait
 * again (ms_park_wake re-arms for those that stay). */
static void deliver(MsSched *sched, int fd, uint32_t bits) {
  MsNode node = sched->fd_queues.ptr[fd].oldest;
  while (node != 0) {
    const MsWaiter waiter = sched->waiters.ptr[node - 1];
    const MsNode this_node = node;
    node = waiter.next;
    if ((waiter.events & MS_WAIT_PROMISE) != 0) {
      const uint32_t wanted = bits & (waiter.events | MS_WAIT_HUP) & ~(uint32_t)MS_WAIT_PROMISE;
      if (wanted != 0 && sched->hooks.fd_ready(waiter.owner, wanted)) {
        leave_node(sched, fd, this_node);
      }
      continue;
    }
    MsTask *const task = ms_task_lookup(sched, waiter.owner);
    if (task == NULL) {
      continue;
    }
    const uint32_t woken = bits & (task->wait_events | MS_WAIT_HUP);
    if (woken != 0) {
      ms_park_wake(sched, task, woken);
    }
  }
  if (sched->fd_queues.ptr[fd].oldest != 0) {
    /* The registration is one-shot: waiters the event did not concern need it again. */
    ms_park_rearm(sched, fd);
  }
}

void ms_park_poll(MsSched *sched, int64_t timeout_ns) {
  MsPollReady ready[READY_BATCH];
  const long count = sched->poll.wait(timeout_ns, ready, MS_COUNT_OF(ready));
  ms_watch_turn();
  for (long i = 0; i < count; i++) {
    if (ready[i].fd < sched->fd_queues.len) {
      deliver(sched, (int)ready[i].fd, ready[i].bits);
    }
  }
}

/* ---- the idle path ---- */

/* The time until the next timer that still means something, dropping dead entries; -1 when none. */
static int64_t next_timeout(MsSched *sched, int64_t now) {
  MsTimer top = {0};
  int64_t timeout_ns = -1;
  while (ms_timers_peek(&sched->timers, &top)) {
    const MsTask *const task = ms_task_lookup(sched, top.handle);
    if (task == NULL || task->state != MS_STATE_WAITING || task->deadline != top.deadline) {
      ms_timers_pop(&sched->timers);
      continue;
    }
    timeout_ns = top.deadline > now ? top.deadline - now : 0;
    break;
  }
  while (ms_timers_peek(&sched->kills, &top)) {
    const MsTask *const task = ms_task_lookup(sched, top.handle);
    if (task == NULL || task->state == MS_STATE_DONE || task->kill_at != top.deadline) {
      ms_timers_pop(&sched->kills);
      continue;
    }
    const int64_t until = top.deadline > now ? top.deadline - now : 0;
    timeout_ns = timeout_ns < 0 || until < timeout_ns ? until : timeout_ns;
    break;
  }
  while (ms_timers_peek(&sched->external, &top)) {
    if (!sched->hooks.timer_live(top.handle, top.deadline)) {
      ms_timers_pop(&sched->external);
      continue;
    }
    const int64_t until = top.deadline > now ? top.deadline - now : 0;
    timeout_ns = timeout_ns < 0 || until < timeout_ns ? until : timeout_ns;
    break;
  }
  return timeout_ns;
}

/* Ends the wait the scheduler is about to fault out of. Cleanup may park again, and a contained fault must leave
 * both its token and any joined task available to later waiters. */
static void abandon_wait(MsSched *sched) {
  MsTask *const current = sched->current;
  if (current == NULL || current->state != MS_STATE_WAITING) {
    return;
  }
  ms_token_abandon(sched, current);
  /* A join has no token: release its claim before fault cleanup can join the target. */
  for (size_t i = 0; i < sched->slots.len; i++) {
    MsTask *const task = sched->slots.ptr[i].task;
    if (task != NULL && task->joiner == current->handle) {
      task->joiner = 0;
    }
  }
  current->deadline = MS_NO_DEADLINE;
  current->state = MS_STATE_RUNNING;
}

bool ms_park_drain_mail(MsSched *sched) {
  MsMail *mail = ms_isolate_take();
  const size_t before = sched->ready_len;
  bool stopped = false;
  while (mail != NULL) {
    MsMail *const next = mail->next;
    if (mail->kind == MS_MAIL_TOKEN) {
      ms_token_post(mail->a, mail->b);
      ms_free(mail);
    } else if (mail->kind == MS_MAIL_STOP) {
      ms_sched_stop((uint8_t)mail->a);
      stopped = true;
      ms_free(mail);
    } else if (ms_isolate_mail_kind(mail->kind) != NULL) {
      ms_isolate_mail_kind(mail->kind)->handle(mail);
    } else if (sched->hooks.mail != NULL) {
      sched->hooks.mail(mail);
    } else {
      ms_free(mail);
    }
    mail = next;
  }
  return stopped || sched->ready_len != before; /* a stop request is acted on by the idle loop's next turn */
}

void ms_park_idle(MsSched *sched) {
  for (;;) {
    /* Tasks in a shielded cleanup keep waiting; they see the stop request afterwards. */
    if (ms_sched_stop_request() != 0 && ms_park_cancel_all(sched)) {
      return;
    }
    const bool timed = sched->timers.heap.len != 0 || sched->kills.heap.len != 0 || sched->external.heap.len != 0;
    const int64_t now = timed ? ms_sched_now() : 0;
    if (timed) {
      ms_park_expire(sched, now);
    }
    if (sched->ready_len != 0) {
      return;
    }
    if (ms_isolate_has_mail() && ms_park_drain_mail(sched)) {
      return;
    }
    int64_t timeout_ns = timed ? next_timeout(sched, now) : -1;
    if (sched->hooks.idle != NULL) {
      int64_t wait_ns = -1;
      if (sched->hooks.idle(&wait_ns)) {
        return;
      }
      if (wait_ns >= 0 && (timeout_ns < 0 || wait_ns < timeout_ns)) {
        timeout_ns = wait_ns;
      }
    }
    if (timeout_ns < 0 && sched->fd_waiting == 0 && sched->remote_tokens == 0 && !sched->hooks.service) {
      abandon_wait(sched);
      sched->hooks.fault(MS_FAULT_KIND_DEADLOCK, deadlock_message);
    }
    ms_stacks_trim(&sched->stacks, IDLE_TRIM_WARM);
    if (sched->hooks.flush_output != NULL) {
      sched->hooks.flush_output();
    }
    if (!ms_isolate_idle_enter()) {
      continue; /* mail arrived since the look above */
    }
    if (sched->hooks.pending != NULL && sched->hooks.pending()) {
      ms_isolate_idle_leave();
      continue; /* work was queued after the look above, and its pusher saw us awake */
    }
    ms_park_poll(sched, timeout_ns);
    ms_isolate_idle_leave();
  }
}

/* ---- parking on a descriptor or a timer ---- */

uint32_t ms_task_wait_fd_at(int fd, uint32_t events, int64_t at_ns) {
  MsSched *const sched = ms_sched();
  MsTask *const task = ms_task_running();
  if (ms_cancel_flag() != 0 || ms_stats_park()) {
    return MS_WAIT_CANCELLED;
  }
  if (fd >= 0) {
    bool ready_now = false;
    if (!ms_park_watch(sched, task, fd, events, &ready_now)) {
      return MS_WAIT_FAILED;
    }
    if (ready_now) {
      return events & (MS_WAIT_READ | MS_WAIT_WRITE);
    }
  }
  task->wait_events = events;
  ms_park_set_deadline(sched, task, at_ns);
  task->state = MS_STATE_WAITING;
  ms_task_switch_away(sched);
  return task->wait_result;
}

uint32_t ms_task_wait_fd(int fd, uint32_t events, int64_t timeout_ns) {
  return ms_task_wait_fd_at(fd, events, ms_sched_deadline_after(timeout_ns));
}

uint32_t ms_task_sleep(int64_t ns) { return ms_task_wait_fd(-1, 0, ns > 0 ? ns : 0); }

void ms_task_forget_fd(int fd) { ms_sched()->poll.forget(fd); }

void ms_park_free(MsSched *sched) {
  ms_timers_free(&sched->timers);
  ms_timers_free(&sched->kills);
  ms_timers_free(&sched->external);
  ms_fd_queue_list_free(&sched->fd_queues);
  ms_waiter_list_free(&sched->waiters);
}
