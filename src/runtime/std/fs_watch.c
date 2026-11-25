/* The @std/fs file watchers. A native watcher runs libuv's uv_fs_event on a thread of its own with a loop of its own
 * (inotify, FSEvents, ReadDirectoryChangesW underneath); a polling watcher compares snapshots on the runtime thread. The
 * watching thread touches no scheduler state: it queues events under a mutex and posts the token the waiting task parks
 * on. Linux has no recursive watch, so a recursive watcher there holds one handle per directory and adds one the moment a
 * directory appears; macOS and Windows watch the root recursively. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include <stdlib.h>

#include "base/alloc.h"
#include "runtime/core/isolate.h"
#include "runtime/core/task.h"
#include "runtime/std/fs.h"
#include "runtime/std/fs_tree.h"
#include "runtime/sys/fs.h"

enum {
  DEFAULT_EVENT_CAPACITY = 128,
  MAX_EVENT_CAPACITY = 1048576,
  MAX_DEPTH = 4096,
};

static void event_push(MsList *list, MsSpan path, bool rename) {
  const MsFsEvent event = {.path = ms_string_from_span(path),
                           .kind = ms_string_from_span(ms_span_of_text(rename ? "rename" : "change"))};
  ms_list_push(list, sizeof event, &event);
}

/* ---- snapshots (polling) ---- */

typedef struct SnapEntry {
  MsString path;
  uint64_t mode;
  int64_t size;
  int64_t seconds;
  int64_t nanos;
} SnapEntry;

MS_LIST_DEFINE(Snapshot, snapshot, SnapEntry)

static void snapshot_release(Snapshot *snapshot) {
  for (size_t i = 0; i < snapshot->len; i++) {
    ms_string_release(&snapshot->ptr[i].path);
  }
  snapshot_free(snapshot);
}

static int entry_compare(const void *a, const void *b) {
  return ms_string_compare(&((const SnapEntry *)a)->path, &((const SnapEntry *)b)->path);
}

static bool snapshot_visit(MsSpan path, size_t depth, bool recursive, int64_t max, Snapshot *snapshot, MsFail *fail) {
  if (ms_fail_poll_cancel(fail)) {
    return false;
  }
  if ((int64_t)snapshot->len >= max || depth > MAX_DEPTH) {
    ms_fail_status(fail, MS_STATUS_LIMIT_EXCEEDED);
    return false;
  }
  if (!ms_fs_text_ok(path)) {
    ms_fail_status(fail, MS_STATUS_UNSUPPORTED);
    return false;
  }
  MsOsText text = ms_os_text_new(path);
  uv_stat_t stat;
  const int code = ms_fs_stat_path(text.ptr, false, &stat);
  ms_os_text_free(&text);
  if (code != 0) {
    ms_fail_uv(fail, code, "lstat", path);
    return false;
  }
  snapshot_push(snapshot, (SnapEntry){.path = ms_string_from_span(path),
                                      .mode = stat.st_mode,
                                      .size = (int64_t)stat.st_size,
                                      .seconds = (int64_t)stat.st_mtim.tv_sec,
                                      .nanos = (int64_t)stat.st_mtim.tv_nsec});
  if (!ms_fs_is_directory(&stat) || (depth > 0 && !recursive)) {
    return true;
  }
  MsStrBuild names = ms_strbuild_new();
  bool ok = ms_fs_names_read(path, &names, fail);
  size_t cursor = 0;
  MsSpan name;
  while (ok && ms_fs_names_next(ms_strbuild_span(&names), &cursor, &name)) {
    MsStrBuild child = ms_strbuild_new();
    ms_path_join(path, name, &child);
    ok = snapshot_visit(ms_strbuild_span(&child), depth + 1, recursive, max, snapshot, fail);
    ms_strbuild_free(&child);
  }
  ms_strbuild_free(&names);
  return ok;
}

static bool snapshot_take(MsSpan root, bool recursive, int64_t max, Snapshot *snapshot, MsFail *fail) {
  if (!snapshot_visit(root, 0, recursive, max, snapshot, fail)) {
    snapshot_release(snapshot);
    return false;
  }
  if (snapshot->len > 1) {
    qsort(snapshot->ptr, snapshot->len, sizeof(SnapEntry), entry_compare);
  }
  return true;
}

static bool same_stamp(const SnapEntry *a, const SnapEntry *b) {
  return a->mode == b->mode && a->size == b->size && a->seconds == b->seconds && a->nanos == b->nanos;
}

/* What differs between two snapshots, sorted by path: `rename` for an entry that appeared or disappeared, otherwise a
 * change. */
static void snapshot_diff(const Snapshot *before, const Snapshot *now, MsList *out) {
  size_t i = 0;
  size_t j = 0;
  while (i < before->len && j < now->len) {
    const SnapEntry *old = &before->ptr[i];
    const SnapEntry *fresh = &now->ptr[j];
    const int order = entry_compare(old, fresh);
    if (order < 0) {
      event_push(out, ms_string_span(&old->path), true);
      i++;
    } else if (order > 0) {
      event_push(out, ms_string_span(&fresh->path), true);
      j++;
    } else {
      if (!same_stamp(old, fresh)) {
        event_push(out, ms_string_span(&fresh->path), false);
      }
      i++;
      j++;
    }
  }
  for (; i < before->len; i++) {
    event_push(out, ms_string_span(&before->ptr[i].path), true);
  }
  for (; j < now->len; j++) {
    event_push(out, ms_string_span(&now->ptr[j].path), true);
  }
}

/* ---- the watcher ---- */

typedef struct WatchEvent {
  MsString path;
  bool rename;
} WatchEvent;

typedef struct WatchRow WatchRow;

struct WatchRow {
  uv_fs_event_t handle;
  WatchRow *next; /* the watcher's list */
  struct MsFsWatcher *owner;
  MsString path;
  bool is_directory;
  bool rescan; /* a dropped batch asked for the directory to be read again */
};

typedef struct MsFsWatcher {
  MsObj header;
  uint64_t token;      /* the waiting task's token, 0 while none; guarded by `lock` */
  int64_t interval_ns; /* polling */
  int64_t max;         /* polling */
  Snapshot before;     /* polling */
  uv_mutex_t lock;
  WatchEvent *queue; /* a ring of `capacity` events */
  size_t head;
  size_t count;
  size_t capacity;
  MsString terminal_text; /* the text of a MS_STATUS_FAILED terminal */
  uv_loop_t loop;
  uv_async_t stop;
  uv_async_t rescan;
  uv_thread_t thread;
  WatchRow *rows; /* only the watching thread touches it while it runs */
  MsString root;
  uint8_t terminal; /* a failure for the next `next`; MS_STATUS_OK while none */
  bool polling;
  bool recursive;
  bool closed;
  bool ended; /* the root is gone: the stream ends once the queue drains */
  bool gone;  /* polling: the root vanished and was reported */
  bool lock_ready;
  bool ignore_overflow;
  bool loop_ready;
  bool stop_ready;
  bool rescan_ready;
  bool thread_started;
  bool ready; /* macOS: the event stream has seen the readiness file */
} MsFsWatcher;

static void watcher_lock(MsFsWatcher *watcher) { uv_mutex_lock(&watcher->lock); }
static void watcher_unlock(MsFsWatcher *watcher) { uv_mutex_unlock(&watcher->lock); }

/* A token belongs to the isolate that made it, and a promise task can call `next` on any isolate, so the waiting task
 * makes its own token for each wait: it registers one (with the lock held, so a change cannot slip between its last look
 * and the park), and watching threads wake whichever token is registered. A wake with none registered is not lost, since
 * the waiter looks at the state again before it parks. */
static uint64_t watcher_enter_wait(MsFsWatcher *watcher) {
  watcher->token = ms_token_new(MS_TOKEN_REMOTE);
  return watcher->token;
}

static void watcher_wake(MsFsWatcher *watcher) {
  if (!watcher->lock_ready) {
    return; /* nobody can be waiting yet */
  }
  watcher_lock(watcher);
  if (watcher->token != 0) {
    ms_token_post_remote(watcher->token, 1);
  }
  watcher_unlock(watcher);
}

static void watcher_leave_wait(MsFsWatcher *watcher, uint64_t token) {
  watcher_lock(watcher);
  watcher->token = 0;
  watcher_unlock(watcher);
  (void)ms_token_free(token);
}

/* Parks on `token` (from watcher_enter_wait) until a wake or the timeout, then ends the wait; false when a stop request
 * ended it. */
static bool watcher_park(MsFsWatcher *watcher, uint64_t token, int64_t timeout_ns, uint32_t *result) {
  uint64_t value = 0;
  *result = 0;
  (void)ms_token_park(token, timeout_ns, &value, result);
  watcher_leave_wait(watcher, token);
  return (*result & MS_WAIT_CANCELLED) == 0;
}

/* Records a failure for `next` unless one is already waiting. Watch threads call this. */
static void set_terminal(MsFsWatcher *watcher, uint8_t status, const char *text) {
  watcher_lock(watcher);
  if (watcher->terminal == MS_STATUS_OK) {
    watcher->terminal = status;
    if (text != NULL) {
      watcher->terminal_text = ms_string_from_span(ms_span_of_text(text));
    }
  }
  watcher_unlock(watcher);
  watcher_wake(watcher);
}

/* True when an unread event already says the same: a host that reports every level of a change (Windows: an added
 * entry, then the parent modified, for each directory of a burst) must not fill the queue with repeats. */
static bool queued_already(const MsFsWatcher *watcher, MsSpan path, bool rename) {
  for (size_t i = 0; i < watcher->count; i++) {
    const WatchEvent *event = &watcher->queue[(watcher->head + i) % watcher->capacity];
    if (event->rename == rename && ms_span_equal(ms_string_span(&event->path), path)) {
      return true;
    }
  }
  return false;
}

static void queue_event(MsFsWatcher *watcher, MsSpan path, bool rename) {
  watcher_lock(watcher);
  if (queued_already(watcher, path, rename)) {
    watcher_unlock(watcher);
    return;
  }
  if (watcher->count >= watcher->capacity) {
    if (!watcher->ignore_overflow && watcher->terminal == MS_STATUS_OK) {
      watcher->terminal = MS_STATUS_LIMIT_EXCEEDED;
    }
    watcher_unlock(watcher);
    watcher_wake(watcher);
    return;
  }
  const size_t slot = (watcher->head + watcher->count) % watcher->capacity;
  watcher->queue[slot] = (WatchEvent){.path = ms_string_from_span(path), .rename = rename};
  watcher->count++;
  watcher_unlock(watcher);
  watcher_wake(watcher);
}

static void mark_ended(MsFsWatcher *watcher) {
  watcher_lock(watcher);
  watcher->ended = true;
  watcher_unlock(watcher);
  watcher_wake(watcher);
}

/* ---- handles (native) ---- */

static void row_closed(uv_handle_t *handle) {
  WatchRow *row = (WatchRow *)handle;
  ms_string_release(&row->path);
  ms_free(row);
}

static void row_close(WatchRow *row) {
  uv_fs_event_stop(&row->handle);
  uv_close((uv_handle_t *)&row->handle, row_closed);
}

static bool row_path_is(const WatchRow *row, MsSpan path) { return ms_span_equal(ms_string_span(&row->path), path); }

/* Whether `row` is `path` or lies below it. */
static bool row_within(const WatchRow *row, MsSpan path) {
  const MsSpan own = ms_string_span(&row->path);
  return row_path_is(row, path) || (own.len > path.len && ms_span_starts_with(own, path) && ms_path_is_separator(own.ptr[path.len]));
}

static void watch_event(uv_fs_event_t *handle, const char *filename, int events, int status);

static bool is_ready_file(const char *filename) {
  const char *prefix = ms_sys_fs_watch_ready_prefix();
  return filename != NULL && prefix[0] != '\0' && ms_span_starts_with_text(ms_span_of_text(filename), prefix);
}

/* Starts a handle on `path`. Recursive handles cover the subtree on the hosts that can. */
static void row_add(MsFsWatcher *watcher, MsSpan path, bool is_directory, MsFail *fail) {
  WatchRow *row = ms_alloc_zeroed(sizeof *row);
  row->path = ms_string_from_span(path);
  row->owner = watcher;
  row->is_directory = is_directory;
  MsOsText text = ms_os_text_new(path);
  int code = uv_fs_event_init(&watcher->loop, &row->handle);
  if (code != 0) {
    ms_os_text_free(&text);
    ms_string_release(&row->path);
    ms_free(row);
    ms_fail_uv(fail, code, "watch", path);
    return;
  }
  const unsigned flags = (ms_sys_fs_watch_recursive() && watcher->recursive && is_directory) ? UV_FS_EVENT_RECURSIVE : 0;
  code = uv_fs_event_start(&row->handle, watch_event, text.ptr, flags);
  ms_os_text_free(&text);
  if (code != 0) {
    uv_close((uv_handle_t *)&row->handle, row_closed);
    ms_fail_uv(fail, code, "watch", path);
    return;
  }
  row->next = watcher->rows;
  watcher->rows = row;
}

static WatchRow *row_find(MsFsWatcher *watcher, MsSpan path) {
  for (WatchRow *row = watcher->rows; row != NULL; row = row->next) {
    if (row_path_is(row, path)) {
      return row;
    }
  }
  return NULL;
}

/* Closes every row at or below `path`. */
static void rows_remove(MsFsWatcher *watcher, MsSpan path) {
  WatchRow **link = &watcher->rows;
  while (*link != NULL) {
    WatchRow *row = *link;
    if (row_within(row, path)) {
      *link = row->next;
      row_close(row);
    } else {
      link = &row->next;
    }
  }
}

static int lstat_bytes(MsSpan path, uv_stat_t *out) {
  MsOsText text = ms_os_text_new(path);
  const int code = ms_fs_stat_path(text.ptr, false, out);
  ms_os_text_free(&text);
  return code;
}

/* Watches `path`, and on hosts without a recursive watch every directory below it. */
static void tree_add(MsFsWatcher *watcher, MsSpan path, size_t depth, MsFail *fail) {
  uv_stat_t stat;
  const int code = lstat_bytes(path, &stat);
  if (code != 0) {
    ms_fail_uv(fail, code, "lstat", path);
    return;
  }
  const bool is_directory = ms_fs_is_directory(&stat);
  if (depth > 0 && !is_directory) {
    return;
  }
  if (row_find(watcher, path) == NULL) {
    row_add(watcher, path, is_directory, fail);
    if (ms_fail_failed(fail)) {
      return;
    }
  }
  if (!is_directory || !watcher->recursive || ms_sys_fs_watch_recursive() || depth > MAX_DEPTH) {
    return;
  }
  MsStrBuild names = ms_strbuild_new();
  bool ok = ms_fs_names_read(path, &names, fail);
  size_t cursor = 0;
  MsSpan name;
  while (ok && ms_fs_names_next(ms_strbuild_span(&names), &cursor, &name)) {
    MsStrBuild child = ms_strbuild_new();
    ms_path_join(path, name, &child);
    tree_add(watcher, ms_strbuild_span(&child), depth + 1, fail);
    ok = !ms_fail_failed(fail);
    ms_strbuild_free(&child);
  }
  ms_strbuild_free(&names);
}

/* Queues a `rename` event for everything already inside the new directory `directory`. */
static void report_existing(MsFsWatcher *watcher, MsSpan directory, size_t depth) {
  MsFail ignored = ms_fail_new();
  MsStrBuild names = ms_strbuild_new();
  if (depth <= MAX_DEPTH && ms_fs_names_read(directory, &names, &ignored)) {
    size_t cursor = 0;
    MsSpan name;
    while (ms_fs_names_next(ms_strbuild_span(&names), &cursor, &name)) {
      MsStrBuild child = ms_strbuild_new();
      ms_path_join(directory, name, &child);
      const MsSpan full = ms_strbuild_span(&child);
      if (ms_fs_text_ok(full)) {
        queue_event(watcher, full, true);
        uv_stat_t stat;
        if (lstat_bytes(full, &stat) == 0 && ms_fs_is_directory(&stat)) {
          report_existing(watcher, full, depth + 1);
        }
      }
      ms_strbuild_free(&child);
    }
  }
  ms_strbuild_free(&names);
  ms_fail_free(&ignored);
}

/* The path a callback names: the row's own path for an event on the row itself, otherwise the entry below it. A
 * directory watched without a recursive handle (inotify) and FSEvents both report an event on the watched directory
 * itself under its own name, which is told apart from an entry of that name by whether the entry exists. */
static void event_path(const WatchRow *row, const char *filename, bool *self, MsStrBuild *out) {
  const MsSpan own = ms_string_span(&row->path);
  *self = !row->is_directory || filename == NULL || filename[0] == '\0';
  if (!*self && ms_sys_fs_watch_names_self()) {
    const MsSpan base = ms_path_base(own);
    if (ms_span_equal(ms_span_of_text(filename), base)) {
      MsStrBuild child = ms_strbuild_new();
      ms_path_join(own, base, &child);
      uv_stat_t stat;
      *self = lstat_bytes(ms_strbuild_span(&child), &stat) != 0;
      ms_strbuild_free(&child);
    }
  }
  if (*self) {
    ms_strbuild_append(out, own);
  } else {
    ms_path_join(own, ms_span_of_text(filename), out);
  }
}

static void watch_event(uv_fs_event_t *handle, const char *filename, int events, int status) {
  WatchRow *row = (WatchRow *)handle;
  MsFsWatcher *watcher = row->owner;
  /* libuv reports a dropped batch on Windows either as a change with no name or as ERROR_NOTIFY_ENUM_DIR, which it
   * translates to UV_UNKNOWN; neither ends the watch. */
  const bool dropped = filename == NULL && ms_sys_fs_watch_drops_batches() && (status == 0 || status == UV_UNKNOWN);
  if (status < 0 && !dropped) {
    set_terminal(watcher, MS_STATUS_FAILED, uv_strerror(status));
    return;
  }
  if (dropped) {
    /* The host dropped a batch of changes: what happened is unknown, so report the directory and what it holds. */
    queue_event(watcher, ms_string_span(&row->path), false);
    /* The directory is read again once libuv has queued its next read: a change between reading the directory here and
     * that read would be in neither, and a created directory would never be reported. */
    if (watcher->recursive && row->is_directory) {
      row->rescan = true;
      (void)uv_async_send(&watcher->rescan);
    }
    return;
  }
  if (is_ready_file(filename)) {
    watcher_lock(watcher);
    watcher->ready = true;
    watcher_unlock(watcher);
    watcher_wake(watcher);
    return;
  }
  MsStrBuild full_buffer = ms_strbuild_new();
  bool self = false;
  event_path(row, filename, &self, &full_buffer);
  const MsSpan full = ms_strbuild_span(&full_buffer);
  if (!ms_fs_text_ok(full)) {
    ms_strbuild_free(&full_buffer);
    set_terminal(watcher, MS_STATUS_UNSUPPORTED, NULL);
    return;
  }
  const bool rename = (events & UV_RENAME) != 0;
  uv_stat_t stat;
  const bool exists = lstat_bytes(full, &stat) == 0;
  bool fresh = false;
  if (rename && !ms_sys_fs_watch_recursive()) {
    if (!exists) {
      rows_remove(watcher, full);
    } else if (watcher->recursive && ms_fs_is_directory(&stat)) {
      MsFail fail = ms_fail_new();
      tree_add(watcher, full, 1, &fail);
      fresh = !ms_fail_failed(&fail);
      if (ms_fail_failed(&fail) && fail.status != MS_STATUS_NOT_FOUND) {
        set_terminal(watcher, fail.status, fail.status == MS_STATUS_FAILED ? (const char *)ms_string_span(&fail.message).ptr : NULL);
      }
      ms_fail_free(&fail);
    }
  } else if (rename && exists && watcher->recursive && ms_fs_is_directory(&stat)) {
    fresh = true;
  }
  /* The ready file of native_wait_ready changes the root's modification time: not an event of the user's. */
  if (ms_sys_fs_watch_ready_prefix()[0] != '\0' && self && exists && row->is_directory && filename != NULL &&
      filename[0] != '\0') {
    ms_strbuild_free(&full_buffer);
    return;
  }
  queue_event(watcher, full, rename);
  /* What was created before the watch existed raised no event of its own. */
  if (fresh) {
    report_existing(watcher, full, 0);
  }
  if (self && !exists && ms_span_equal(ms_string_span(&watcher->root), full)) {
    mark_ended(watcher);
  }
  ms_strbuild_free(&full_buffer);
}

static void close_rows(MsFsWatcher *watcher) {
  WatchRow *row = watcher->rows;
  watcher->rows = NULL;
  while (row != NULL) {
    WatchRow *next = row->next;
    row_close(row);
    row = next;
  }
}

static void stop_closed(uv_handle_t *handle) { (void)handle; }

/* Reads again each directory that lost a batch of changes. Runs after the callback that asked, so after libuv has
 * queued the next read of that directory. */
static void rescan_requested(uv_async_t *handle) {
  MsFsWatcher *watcher = handle->data;
  for (WatchRow *row = watcher->rows; row != NULL; row = row->next) {
    if (row->rescan) {
      row->rescan = false;
      report_existing(watcher, ms_string_span(&row->path), 0);
    }
  }
}

/* Ends the loop: closes every handle, so uv_run returns. */
static void close_loop_handles(MsFsWatcher *watcher) {
  close_rows(watcher);
  if (watcher->stop_ready) {
    watcher->stop_ready = false;
    uv_close((uv_handle_t *)&watcher->stop, stop_closed);
  }
  if (watcher->rescan_ready) {
    watcher->rescan_ready = false;
    uv_close((uv_handle_t *)&watcher->rescan, stop_closed);
  }
}

static void stop_requested(uv_async_t *handle) { close_loop_handles(handle->data); }

static void watch_thread(void *argument) {
  MsFsWatcher *watcher = argument;
  (void)uv_run(&watcher->loop, UV_RUN_DEFAULT);
}

/* Ends the watching thread and closes what it held. Safe to repeat. */
static void native_shutdown(MsFsWatcher *watcher) {
  if (watcher->thread_started) {
    (void)uv_async_send(&watcher->stop);
    uv_thread_join(&watcher->thread);
    watcher->thread_started = false;
  } else if (watcher->loop_ready) {
    close_loop_handles(watcher);
    (void)uv_run(&watcher->loop, UV_RUN_DEFAULT);
  }
  if (watcher->loop_ready) {
    (void)uv_loop_close(&watcher->loop);
    watcher->loop_ready = false;
  }
}

static void watcher_drop(MsObj *object) {
  MsFsWatcher *watcher = (MsFsWatcher *)object;
  native_shutdown(watcher);
  for (size_t i = 0; watcher->queue != NULL && i < watcher->count; i++) {
    ms_string_release(&watcher->queue[(watcher->head + i) % watcher->capacity].path);
  }
  ms_free(watcher->queue);
  ms_string_release(&watcher->terminal_text);
  ms_string_release(&watcher->root);
  snapshot_release(&watcher->before);
  if (watcher->lock_ready) {
    uv_mutex_destroy(&watcher->lock);
  }
  ms_free(watcher);
}

static MsFsWatcher *watcher_new(MsSpan root) {
  MsFsWatcher *watcher = ms_alloc_zeroed(sizeof *watcher);
  watcher->header.drop = watcher_drop;
  watcher->terminal_text = ms_string_empty();
  watcher->root = ms_string_from_span(root);
  watcher->lock_ready = uv_mutex_init(&watcher->lock) == 0;
  return watcher;
}

/* ---- creating watchers ---- */

uint8_t msstd_fs_watch(const MsString *path, uint8_t recursive, int64_t interval_ns, uint8_t has_max, int64_t max,
                       MsObj **out, MsString *err) {
  MsFail fail = ms_fail_new();
  const MsSpan root = ms_string_span(path);
  int64_t limit = MS_FS_UNLIMITED;
  if (!ms_fs_limit(has_max, max, &limit) || interval_ns <= 0 || root.len == 0) {
    ms_fail_status(&fail, MS_STATUS_INVALID_INPUT);
    return ms_fail_finish_at(&fail, root, err);
  }
  Snapshot before = {0};
  if (snapshot_take(root, recursive != 0, limit, &before, &fail)) {
    MsFsWatcher *watcher = watcher_new(root);
    if (!watcher->lock_ready) {
      snapshot_release(&before);
      watcher_drop(&watcher->header);
      ms_fail_text(&fail, "watch: cannot initialise");
    } else {
      watcher->polling = true;
      watcher->recursive = recursive != 0;
      watcher->interval_ns = interval_ns;
      watcher->max = limit;
      watcher->before = before;
      *out = &watcher->header;
    }
  }
  return ms_fail_finish_at(&fail, root, err);
}

static bool native_arguments_valid(MsSpan root, int64_t max, int64_t events, MsSpan overflow) {
  const bool overflow_known = ms_span_is_text(overflow, "error") || ms_span_is_text(overflow, "ignore");
  return root.len != 0 && max > 0 && events > 0 && events <= MAX_EVENT_CAPACITY && overflow_known;
}

/* Waits until the event stream of a directory root is live (see ms_sys_fs_watch_is_ready_file): the host touches a file
 * under the root until the stream reports it. Best effort: a root that cannot be written to is watched without the
 * guarantee. */
static void native_wait_ready(MsFsWatcher *watcher, MsSpan root) {
  enum { READY_TRIES = 50, READY_SLICE_NS = 100000000 };
  uv_stat_t stat;
  if (lstat_bytes(root, &stat) != 0 || !ms_fs_is_directory(&stat)) {
    return;
  }
  MsStrBuild name = ms_strbuild_new();
  ms_strbuild_append_text(&name, ms_sys_fs_watch_ready_prefix());
  ms_strbuild_append_u64(&name, (uint64_t)uv_os_getpid());
  MsStrBuild path = ms_strbuild_new();
  ms_path_join(root, ms_strbuild_span(&name), &path);
  MsOsText text = ms_os_text_new(ms_strbuild_span(&path));
  for (int attempt = 0; attempt < READY_TRIES; attempt++) {
    uv_fs_t request;
    const int file = uv_fs_open(NULL, &request, text.ptr, UV_FS_O_CREAT | UV_FS_O_WRONLY, 0600, NULL);
    uv_fs_req_cleanup(&request);
    if (file < 0) {
      break;
    }
    (void)uv_fs_close(NULL, &request, (uv_file)file, NULL);
    uv_fs_req_cleanup(&request);
    watcher_lock(watcher);
    const uint64_t token = watcher->ready ? 0 : watcher_enter_wait(watcher);
    watcher_unlock(watcher);
    if (token == 0) {
      break;
    }
    uint32_t result = 0;
    if (!watcher_park(watcher, token, READY_SLICE_NS, &result)) {
      break;
    }
  }
  uv_fs_t request;
  (void)uv_fs_unlink(NULL, &request, text.ptr, NULL);
  uv_fs_req_cleanup(&request);
  ms_os_text_free(&text);
  ms_strbuild_free(&path);
  ms_strbuild_free(&name);
}

/* Registers every handle and starts the thread. Failures leave `watcher` to be dropped by the caller. */
static void native_start(MsFsWatcher *watcher, MsSpan root, MsFail *fail) {
  if (uv_loop_init(&watcher->loop) != 0) {
    ms_fail_text(fail, "watch: cannot create an event loop");
    return;
  }
  watcher->loop_ready = true;
  watcher->stop.data = watcher;
  if (uv_async_init(&watcher->loop, &watcher->stop, stop_requested) != 0) {
    ms_fail_text(fail, "watch: cannot create an event loop");
    return;
  }
  watcher->stop_ready = true;
  watcher->rescan.data = watcher;
  if (uv_async_init(&watcher->loop, &watcher->rescan, rescan_requested) != 0) {
    ms_fail_text(fail, "watch: cannot create an event loop");
    return;
  }
  watcher->rescan_ready = true;
  tree_add(watcher, root, 0, fail);
  if (ms_fail_failed(fail)) {
    return;
  }
  if (uv_thread_create(&watcher->thread, watch_thread, watcher) != 0) {
    ms_fail_status(fail, MS_STATUS_UNSUPPORTED);
    return;
  }
  watcher->thread_started = true;
  if (ms_sys_fs_watch_ready_prefix()[0] != '\0') {
    native_wait_ready(watcher, root);
  }
}

uint8_t msstd_fs_watch_native(const MsString *path, uint8_t recursive, uint8_t has_max, int64_t max, uint8_t has_events,
                              int64_t events, const MsString *overflow, MsObj **out, MsString *err) {
  MsFail fail = ms_fail_new();
  const MsSpan root = ms_string_span(path);
  int64_t limit = MS_FS_UNLIMITED;
  const int64_t capacity = has_events != 0 ? events : DEFAULT_EVENT_CAPACITY;
  if (!ms_fs_limit(has_max, max, &limit) ||
      !native_arguments_valid(root, has_max != 0 ? limit : MS_FS_UNLIMITED, capacity, ms_string_span(overflow))) {
    ms_fail_status(&fail, MS_STATUS_INVALID_INPUT);
    return ms_fail_finish_at(&fail, root, err);
  }
  /* The bound on paths is checked once at the start, as for the polling watcher. */
  Snapshot counted = {0};
  if (!snapshot_take(root, recursive != 0, limit, &counted, &fail)) {
    return ms_fail_finish_at(&fail, root, err);
  }
  snapshot_release(&counted);
  MsFsWatcher *watcher = watcher_new(root);
  if (!watcher->lock_ready) {
    ms_fail_text(&fail, "watch: cannot initialise");
  } else {
    watcher->recursive = recursive != 0;
    watcher->capacity = (size_t)capacity;
    watcher->ignore_overflow = ms_span_is_text(ms_string_span(overflow), "ignore");
    watcher->queue = ms_alloc_zeroed(watcher->capacity * sizeof(WatchEvent));
    native_start(watcher, root, &fail);
  }
  if (ms_fail_failed(&fail)) {
    watcher_drop(&watcher->header);
  } else {
    *out = &watcher->header;
  }
  return ms_fail_finish_at(&fail, root, err);
}

/* ---- waiting ---- */

/* A wait that parks until the watcher is woken or closed. False when a stop request ended it. */
static bool wait_for_wake(MsFsWatcher *watcher, int64_t timeout_ns, uint32_t *result) {
  watcher_lock(watcher);
  const uint64_t token = watcher_enter_wait(watcher);
  watcher_unlock(watcher);
  return watcher_park(watcher, token, timeout_ns, result);
}

static uint8_t next_polling(MsFsWatcher *watcher, MsList *out, MsFail *fail) {
  if (watcher->gone) {
    return MS_STATUS_NONE;
  }
  for (;;) {
    if (ms_fail_poll_cancel(fail)) {
      return MS_STATUS_FAILED;
    }
    if (ms_task_read_limit_passed()) {
      return MS_STATUS_TIMED_OUT;
    }
    uint32_t result = 0;
    if (!wait_for_wake(watcher, watcher->interval_ns, &result)) {
      ms_fail_text(fail, "cancelled");
      return MS_STATUS_FAILED;
    }
    if (watcher->closed) {
      return MS_STATUS_CLOSED;
    }
    if ((result & MS_WAIT_TIMEOUT) == 0 || ms_task_read_limit_passed()) {
      continue; /* the limit, if it passed, is reported at the top */
    }
    Snapshot now = {0};
    MsFail taken = ms_fail_new();
    if (!snapshot_take(ms_string_span(&watcher->root), watcher->recursive, watcher->max, &now, &taken)) {
      if (taken.status == MS_STATUS_NOT_FOUND) {
        watcher->gone = true;
        ms_fail_free(&taken);
      } else {
        const uint8_t status = taken.status;
        ms_fail_free(fail);
        *fail = taken;
        return status;
      }
    }
    MsList events = {0};
    snapshot_diff(&watcher->before, &now, &events);
    snapshot_release(&watcher->before);
    watcher->before = now;
    if (events.len != 0) {
      *out = events;
      return MS_STATUS_OK;
    }
    ms_list_free(&events);
    if (watcher->gone) {
      return MS_STATUS_NONE;
    }
  }
}

static uint8_t next_native(MsFsWatcher *watcher, MsList *out, MsFail *fail) {
  for (;;) {
    watcher_lock(watcher);
    if (watcher->closed) {
      watcher_unlock(watcher);
      return MS_STATUS_CLOSED;
    }
    if (watcher->terminal != MS_STATUS_OK) {
      const uint8_t status = watcher->terminal;
      MsString text = watcher->terminal_text;
      watcher->terminal = MS_STATUS_OK;
      watcher->terminal_text = ms_string_empty();
      watcher_unlock(watcher);
      if (status == MS_STATUS_FAILED) {
        ms_fail_free(fail);
        fail->status = MS_STATUS_FAILED;
        fail->message = ms_string_is_empty(&text) ? ms_string_from_span(ms_span_of_text("watch failed")) : text;
      } else {
        ms_fail_status(fail, status);
        ms_string_release(&text);
      }
      return status;
    }
    if (watcher->count > 0) {
      WatchEvent event = watcher->queue[watcher->head];
      watcher->head = (watcher->head + 1) % watcher->capacity;
      watcher->count--;
      watcher_unlock(watcher);
      event_push(out, ms_string_span(&event.path), event.rename);
      ms_string_release(&event.path);
      return MS_STATUS_OK;
    }
    if (watcher->ended) {
      watcher_unlock(watcher);
      return MS_STATUS_NONE;
    }
    const uint64_t token = watcher_enter_wait(watcher);
    watcher_unlock(watcher);
    uint32_t result = 0;
    if (ms_fail_poll_cancel(fail)) {
      watcher_leave_wait(watcher, token);
      return MS_STATUS_FAILED;
    }
    if (ms_task_read_limit_passed()) {
      watcher_leave_wait(watcher, token);
      return MS_STATUS_TIMED_OUT;
    }
    if (!watcher_park(watcher, token, -1, &result)) {
      ms_fail_text(fail, "cancelled");
      return MS_STATUS_FAILED;
    }
  }
}

uint8_t msstd_fs_watch_next(MsObj *handle, MsList *out, MsString *err) {
  MsFsWatcher *watcher = (MsFsWatcher *)handle;
  MsFail fail = ms_fail_new();
  if (watcher->closed) {
    *err = ms_string_empty();
    return MS_STATUS_CLOSED;
  }
  const uint8_t status = watcher->polling ? next_polling(watcher, out, &fail) : next_native(watcher, out, &fail);
  if (status == MS_STATUS_OK || status == MS_STATUS_NONE || status == MS_STATUS_CLOSED) {
    ms_fail_free(&fail);
    *err = ms_string_empty();
    return status;
  }
  if (!ms_fail_failed(&fail)) {
    ms_fail_status(&fail, status);
  }
  return ms_fail_finish(&fail, err);
}

void msstd_fs_watch_close(MsObj *handle) {
  MsFsWatcher *watcher = (MsFsWatcher *)handle;
  if (watcher->closed) {
    return;
  }
  if (watcher->lock_ready) {
    watcher_lock(watcher);
    watcher->closed = true;
    watcher_unlock(watcher);
  } else {
    watcher->closed = true;
  }
  watcher_wake(watcher);
  native_shutdown(watcher);
}
