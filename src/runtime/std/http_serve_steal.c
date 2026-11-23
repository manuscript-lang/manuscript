/* runtime/std/http_serve_steal.c: a computing handler holds its thread, so the connections that wait for a request
 * on that thread would wait too. A connection between requests is only a socket, so another thread of the same
 * server can take it: a connection task that waits for the first byte of a request lists itself; the watcher
 * (core/watch.h) finds a thread that stopped turning, and a resting thread of the same server takes the listed
 * connections whose read has finished, and serves them in tasks of its own. A task never moves; the task that waited
 * ends without closing the socket. A TLS connection moves with its session: the take claims the bytes the net layer
 * already decrypted, and the new task skips the handshake. */
#include <stdatomic.h>

#include "base/alloc.h"
#include "runtime/core/isolate.h"
#include "runtime/core/watch.h"
#include "runtime/std/http_serve_internal.h"

enum { EMPTY_BACKOFF_TICKS = 20 }; /* an empty take waits two milliseconds before the next */

struct MsServeIdle {
  atomic_int refs; /* the worker, the registry and each take in flight */
  MsServeShared *shared;
  uint32_t isolate;
  atomic_int lock;               /* a spin lock over the fields below */
  MsServeWorker *worker;         /* NULL once the worker closed */
  MsServeConn **listed;
  size_t count;
  size_t capacity;
  atomic_size_t waiting;         /* `count`, readable without the lock */
  atomic_bool taking;            /* a take from this list is in flight */
  atomic_bool found_last;        /* the last take found connections */
  atomic_uint_fast64_t not_before; /* the watcher's clock before which no take is sent (an empty take backs off) */
};

static void lock(MsServeIdle *idle) {
  while (atomic_exchange_explicit(&idle->lock, 1, memory_order_acquire) != 0) {
  }
}

static void unlock(MsServeIdle *idle) { atomic_store_explicit(&idle->lock, 0, memory_order_release); }

static void idle_release(MsServeIdle *idle) {
  if (atomic_fetch_sub(&idle->refs, 1) != 1) {
    return;
  }
  ms_free(idle->listed);
  ms_free(idle);
}

/* ---- the registry: every open list, for the watcher ---- */

static struct {
  atomic_int lock;
  MsServeIdle **all;
  size_t count;
  size_t capacity;
} registry;

static void registry_lock(void) {
  while (atomic_exchange_explicit(&registry.lock, 1, memory_order_acquire) != 0) {
  }
}

static void registry_unlock(void) { atomic_store_explicit(&registry.lock, 0, memory_order_release); }

/* ---- a take: runs as a task on the resting thread ---- */

typedef struct Taken {
  MsWsTransport io;
  MsBytes first;
} Taken;

typedef struct Take {
  MsServeIdle *from;
  MsServeIdle *to;
} Take;

static void take_entry(void *argument) {
  Take *take = argument;
  MsServeIdle *from = take->from;
  MsServeIdle *to = take->to;
  ms_free(take);

  Taken *batch = NULL;
  size_t found = 0;
  lock(from);
  batch = ms_alloc((from->count > 0 ? from->count : 1) * sizeof *batch);
  for (size_t i = 0; i < from->count;) {
    MsServeConn *conn = from->listed[i];
    MsBytes first = {0};
    if (!conn->io.steal_read(conn->io.context, &first)) {
      i++;
      continue;
    }
    conn->taken = true;
    conn->listed = false;
    batch[found++] = (Taken){.io = conn->io, .first = first};
    from->count--;
    if (i < from->count) {
      from->listed[i] = from->listed[from->count]; /* the last takes its place; look at it next */
      from->listed[i]->listed_at = i;
    }
  }
  atomic_store(&from->waiting, from->count);
  unlock(from);

  /* This task runs on the thread of `to`, which closes its worker only from a task of its own, so the worker is
   * not freed while this task runs without waiting. */
  lock(to);
  MsServeWorker *worker = to->worker;
  unlock(to);
  for (size_t i = 0; i < found; i++) {
    if (worker == NULL || !ms_serve_worker_resume(worker, &batch[i].io, batch[i].first)) {
      ms_bytes_free(&batch[i].first);
      if (batch[i].io.close != NULL) {
        batch[i].io.close(batch[i].io.context);
      }
      if (batch[i].io.release != NULL) {
        batch[i].io.release(batch[i].io.context);
      }
    }
  }
  ms_free(batch);
  atomic_store(&from->found_last, found > 0);
  atomic_store(&from->not_before, ms_watch_epoch() + (found > 0 ? 0 : EMPTY_BACKOFF_TICKS));
  atomic_store(&from->taking, false);
  idle_release(from);
  idle_release(to);
}

static void take_mail(MsMail *mail) {
  Take *take = ms_alloc(sizeof *take);
  take->from = mail->p;
  take->to = (MsServeIdle *)(uintptr_t)(const void *)mail->q;
  ms_free(mail);
  MsTaskStatus status = MS_TASK_OK;
  if (ms_task_spawn(take_entry, take, MS_SPAWN_DETACHED, 0, &status) == 0) {
    atomic_store(&take->from->taking, false);
    idle_release(take->from);
    idle_release(take->to);
    ms_free(take);
  }
}

static void take_discard(MsMail *mail) {
  MsServeIdle *from = mail->p;
  atomic_store(&from->taking, false);
  idle_release(from);
  idle_release((MsServeIdle *)(uintptr_t)(const void *)mail->q);
}

/* ---- the watcher's hook ---- */

static MsServeIdle *resting_peer(const MsServeIdle *held, uint64_t resting) {
  for (size_t i = 0; i < registry.count; i++) {
    MsServeIdle *peer = registry.all[i];
    if (peer != held && peer->shared == held->shared && (resting >> peer->isolate & 1) != 0) {
      return peer;
    }
  }
  return NULL;
}

/* A thread that has not turned since the last look and has connections waiting: sends a resting thread of the same
 * server to take them. Asks the watcher to look often after that, because the held thread may stay held. */
static bool steal_hook(MsWatchLook look, uint64_t resting) {
  bool asked = false;
  registry_lock();
  for (size_t i = 0; i < registry.count; i++) {
    MsServeIdle *held = registry.all[i];
    if (atomic_load(&held->waiting) == 0 || atomic_load(&held->taking) || !ms_watch_held_up(look, resting, held->isolate) ||
        look.now < atomic_load(&held->not_before)) {
      continue;
    }
    MsServeIdle *peer = resting_peer(held, resting);
    if (peer == NULL) {
      continue;
    }
    MsMail *mail = ms_alloc_zeroed(sizeof *mail);
    mail->kind = MS_MAIL_IDLE;
    mail->p = held;
    mail->q = peer;
    atomic_fetch_add(&held->refs, 1);
    atomic_fetch_add(&peer->refs, 1);
    atomic_store(&held->taking, true);
    if (ms_isolate_post(peer->isolate, mail)) {
      asked = asked || atomic_load(&held->found_last); /* look often only while takes keep finding connections */
      continue;
    }
    atomic_store(&held->taking, false);
    idle_release(held);
    idle_release(peer);
    ms_free(mail);
  }
  registry_unlock();
  return asked;
}

/* ---- the lists ---- */

static atomic_int installed;

static void install(void) {
  int expected = 0;
  if (!atomic_compare_exchange_strong(&installed, &expected, 1)) {
    return;
  }
  static const MsMailKindOps ops = {.handle = take_mail, .discard = take_discard};
  ms_isolate_set_mail_kind(MS_MAIL_IDLE, &ops);
  (void)ms_watch_add_hook(steal_hook);
}

MsServeIdle *ms_serve_idle_open(MsServeWorker *worker) {
  const uint32_t isolate = ms_isolate_self();
  if (isolate >= MS_MAX_ISOLATES) {
    return NULL;
  }
  install();
  MsServeIdle *idle = ms_alloc_zeroed(sizeof *idle);
  atomic_init(&idle->refs, 2); /* the worker's and the registry's */
  atomic_init(&idle->lock, 0);
  atomic_init(&idle->waiting, 0);
  atomic_init(&idle->taking, false);
  idle->shared = worker->shared;
  idle->isolate = isolate;
  idle->worker = worker;
  registry_lock();
  if (registry.count == registry.capacity) {
    registry.capacity = registry.capacity == 0 ? 8 : registry.capacity * 2;
    registry.all = ms_realloc(registry.all, registry.capacity * sizeof *registry.all);
  }
  registry.all[registry.count++] = idle;
  registry_unlock();
  return idle;
}

void ms_serve_idle_close(MsServeIdle *idle) {
  registry_lock();
  for (size_t i = 0; i < registry.count; i++) {
    if (registry.all[i] == idle) {
      registry.all[i] = registry.all[--registry.count];
      break;
    }
  }
  registry_unlock();
  lock(idle);
  idle->worker = NULL;
  unlock(idle);
  idle_release(idle); /* the registry's */
  idle_release(idle); /* the worker's */
}

void ms_serve_idle_list(MsServeConn *conn) {
  MsServeIdle *idle = conn->worker->idle;
  if (idle == NULL || conn->io.steal_read == NULL || conn->h2 || conn->listed) {
    return;
  }
  lock(idle);
  if (idle->count == idle->capacity) {
    idle->capacity = idle->capacity == 0 ? 16 : idle->capacity * 2;
    idle->listed = ms_realloc(idle->listed, idle->capacity * sizeof *idle->listed);
  }
  conn->listed_at = idle->count;
  idle->listed[idle->count++] = conn;
  conn->listed = true;
  atomic_store(&idle->waiting, idle->count);
  unlock(idle);
}

bool ms_serve_idle_unlist(MsServeConn *conn) {
  MsServeIdle *idle = conn->worker->idle;
  if (idle == NULL) {
    return false;
  }
  lock(idle);
  if (conn->listed) {
    idle->count--;
    idle->listed[conn->listed_at] = idle->listed[idle->count];
    idle->listed[conn->listed_at]->listed_at = conn->listed_at;
    conn->listed = false;
    atomic_store(&idle->waiting, idle->count);
  }
  const bool taken = conn->taken;
  unlock(idle);
  return taken;
}

bool ms_serve_idle_taken(MsServeConn *conn) {
  MsServeIdle *idle = conn->worker->idle;
  if (idle == NULL) {
    return false;
  }
  lock(idle);
  const bool taken = conn->taken;
  unlock(idle);
  return taken;
}
