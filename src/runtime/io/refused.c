/* Descriptors libuv refuses to poll (a named pipe on macOS: kqueue does not report its last writer going away).
 *
 * One thread per reactor blocks in poll(2) over all of them plus a wake-up pipe, so a task waiting on such a pipe
 * costs no latency and no timer ticks. When a descriptor is ready the thread queues its number and signals an async
 * handle, and the loop reports it through `ready` like any other. Every watch is one-shot, like the rows the reactor
 * keeps for sockets: a descriptor leaves the thread's table when it is reported or removed.
 *
 * Removal waits until the thread is out of the poll that named the descriptor, so the caller may close it at once.
 */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "runtime/io/refused.h"

#include "base/alloc.h"
#include "base/list.h"
#include "runtime/sys/sys.h"

typedef struct Entry {
  int fd;
  bool writes;
} Entry;

MS_LIST_DEFINE(EntryList, entry_list, Entry)
MS_LIST_DEFINE(FdList, fd_list, int)

struct MsIoRefused {
  uv_async_t async; /* closed through the loop; the memory is freed by its close callback */
  uv_mutex_t lock;
  uv_cond_t left_poll;
  uv_thread_t thread;
  bool thread_started;
  int wake[2];
  MsIoRefusedReady ready;
  void *context;
  EntryList watching; /* guarded by `lock` */
  FdList reported;    /* descriptors found ready, not yet handed to `ready`; guarded by `lock` */
  bool polling;       /* the thread is inside poll(2) */
  uint64_t rounds;    /* polls the thread has finished */
  bool stop;
};

static size_t find(const MsIoRefused *refused, int fd) {
  for (size_t i = 0; i < refused->watching.len; i++) {
    if (refused->watching.ptr[i].fd == fd) {
      return i;
    }
  }
  return refused->watching.len;
}

static void drop_watch(MsIoRefused *refused, size_t index) {
  refused->watching.ptr[index] = refused->watching.ptr[--refused->watching.len];
}

/* The thread: wait for the table or the wake-up pipe, move what is ready to `reported`, tell the loop. */
static void run(void *argument) {
  MsIoRefused *refused = argument;
  uv_mutex_lock(&refused->lock);
  while (!refused->stop) {
    const size_t count = refused->watching.len + 1;
    MsSysFdWait *waits = ms_alloc(count * sizeof *waits);
    waits[0] = (MsSysFdWait){.fd = refused->wake[0], .wants = MS_SYS_WAIT_READ};
    for (size_t i = 0; i < refused->watching.len; i++) {
      const Entry *entry = &refused->watching.ptr[i];
      waits[i + 1] = (MsSysFdWait){.fd = entry->fd, .wants = entry->writes ? MS_SYS_WAIT_WRITE : MS_SYS_WAIT_READ};
    }
    refused->polling = true;
    uv_mutex_unlock(&refused->lock);
    const bool waited = ms_sys_fd_wait_any(waits, count);
    uv_mutex_lock(&refused->lock);
    refused->polling = false;
    refused->rounds++;
    uv_cond_broadcast(&refused->left_poll);
    if (!waited) {
      ms_free(waits);
      break;
    }
    if (waits[0].got != 0) {
      ms_sys_wake_drain(refused->wake[0]);
    }
    bool any = false;
    for (size_t i = 1; i < count; i++) {
      const size_t at = waits[i].got != 0 ? find(refused, waits[i].fd) : refused->watching.len;
      if (at == refused->watching.len) {
        continue;
      }
      fd_list_push(&refused->reported, waits[i].fd);
      drop_watch(refused, at);
      any = true;
    }
    ms_free(waits);
    if (any) {
      (void)uv_async_send(&refused->async);
    }
  }
  uv_mutex_unlock(&refused->lock);
}

static void on_async(uv_async_t *handle) {
  MsIoRefused *refused = uv_handle_get_data((uv_handle_t *)handle);
  for (;;) {
    uv_mutex_lock(&refused->lock);
    const int fd = refused->reported.len > 0 ? refused->reported.ptr[refused->reported.len - 1] : -1;
    uv_mutex_unlock(&refused->lock);
    if (fd < 0) {
      return;
    }
    if (!refused->ready(refused->context, fd)) {
      (void)uv_async_send(&refused->async); /* no room now: the next pass of the loop tries again */
      return;
    }
    uv_mutex_lock(&refused->lock);
    for (size_t i = refused->reported.len; i > 0; i--) { /* the thread may have appended meanwhile */
      if (refused->reported.ptr[i - 1] == fd) {
        refused->reported.ptr[i - 1] = refused->reported.ptr[--refused->reported.len];
        break;
      }
    }
    uv_mutex_unlock(&refused->lock);
  }
}

static void on_closed(uv_handle_t *handle) {
  MsIoRefused *refused = uv_handle_get_data(handle);
  entry_list_free(&refused->watching);
  fd_list_free(&refused->reported);
  uv_cond_destroy(&refused->left_poll);
  uv_mutex_destroy(&refused->lock);
  ms_free(refused);
}

void ms_io_refused_close(MsIoRefused *refused) {
  if (refused->thread_started) {
    uv_mutex_lock(&refused->lock);
    refused->stop = true;
    uv_mutex_unlock(&refused->lock);
    ms_sys_wake_send(refused->wake[1]);
    (void)uv_thread_join(&refused->thread);
  }
  ms_sys_wake_close(refused->wake);
  uv_close((uv_handle_t *)&refused->async, on_closed); /* the loop frees the rest when it has finished closing */
}

MsIoRefused *ms_io_refused_open(uv_loop_t *loop, MsIoRefusedReady ready, void *context) {
  int wake[2] = {-1, -1};
  if (!ms_sys_wake_open(wake)) {
    return NULL;
  }
  MsIoRefused *refused = ms_alloc_zeroed(sizeof *refused);
  refused->ready = ready;
  refused->context = context;
  refused->wake[0] = wake[0];
  refused->wake[1] = wake[1];
  if (uv_mutex_init(&refused->lock) != 0 || uv_cond_init(&refused->left_poll) != 0 ||
      uv_async_init(loop, &refused->async, on_async) != 0) {
    ms_sys_wake_close(refused->wake);
    ms_free(refused);
    return NULL;
  }
  uv_handle_set_data((uv_handle_t *)&refused->async, refused);
  refused->thread_started = uv_thread_create(&refused->thread, run, refused) == 0;
  if (!refused->thread_started) {
    ms_io_refused_close(refused);
    return NULL;
  }
  return refused;
}

void ms_io_refused_add(MsIoRefused *refused, int fd, bool writes) {
  uv_mutex_lock(&refused->lock);
  if (find(refused, fd) == refused->watching.len) {
    entry_list_push(&refused->watching, (Entry){.fd = fd, .writes = writes});
  }
  uv_mutex_unlock(&refused->lock);
  ms_sys_wake_send(refused->wake[1]);
}

void ms_io_refused_remove(MsIoRefused *refused, int fd) {
  uv_mutex_lock(&refused->lock);
  const size_t at = find(refused, fd);
  if (at != refused->watching.len) {
    drop_watch(refused, at);
  }
  for (size_t i = 0; i < refused->reported.len; i++) {
    if (refused->reported.ptr[i] == fd) {
      refused->reported.ptr[i] = refused->reported.ptr[--refused->reported.len];
      break;
    }
  }
  if (refused->polling) {
    const uint64_t seen = refused->rounds;
    ms_sys_wake_send(refused->wake[1]);
    while (refused->polling && refused->rounds == seen) {
      uv_cond_wait(&refused->left_poll, &refused->lock);
    }
  }
  uv_mutex_unlock(&refused->lock);
}
