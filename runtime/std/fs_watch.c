/* fs_watch.c: the @std/fs file watchers. A native watcher runs libuv's uv_fs_event on a thread of its own with a loop
 * of its own (inotify, FSEvents, ReadDirectoryChangesW underneath); a polling watcher compares snapshots on the
 * runtime thread. The watching thread touches no runtime state: it queues events under a mutex and posts the token
 * the waiting task parks on. Linux has no recursive watch, so a recursive watcher there holds one handle per
 * directory and adds one the moment a directory appears; macOS and Windows watch the root recursively. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c11 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <uv.h>

#include "fs_support.h"
#include "fs_tree.h"

enum {
    DEFAULT_EVENT_CAPACITY = 128,
    MAX_EVENT_CAPACITY = 1048576,
    MAX_DEPTH = 4096,
    FIRST_ENTRIES = 64,
};

/* One FileEvent as compiled code lays the record out: the path, then `rename` or `change`. */
typedef struct MsFsEventOut {
    MsStr path;
    MsStr kind;
} MsFsEventOut;

static void event_out_drop(const uint8_t *slot) {
    MsFsEventOut event;
    memcpy(&event, slot, sizeof event);
    msrt_string_free(&event.path);
    msrt_string_free(&event.kind);
}

static void event_out_copy(const uint8_t *source, uint8_t *destination) {
    MsFsEventOut event;
    memcpy(&event, source, sizeof event);
    MsFsEventOut copy = event;
    msrt_string_clone(&event.path, &copy.path);
    msrt_string_clone(&event.kind, &copy.kind);
    memcpy(destination, &copy, sizeof copy);
}

static const MsTypeDesc event_out_desc = {
    .size = sizeof(MsFsEventOut),
    .align = _Alignof(MsFsEventOut),
    .kind = MS_TYPE_KIND_CUSTOM,
    .drop = event_out_drop,
    .copy = event_out_copy,
};

static void push_event_out(MsVec *list, const uint8_t *path, size_t length, bool rename) {
    MsFsEventOut event;
    msrt_string_from_bytes(path, length, &event.path);
    const char *kind = rename ? "rename" : "change";
    msrt_string_from_bytes((const uint8_t *)kind, strlen(kind), &event.kind);
    msrt_list_push(list, &event_out_desc, &event);
}

/* ---- snapshots (polling) ---- */

typedef struct SnapEntry {
    uint8_t *path; /* owned (malloc) */
    size_t length;
    uint32_t mode;
    int64_t size;
    int64_t seconds;
    int64_t nanos;
} SnapEntry;

typedef struct Snapshot {
    SnapEntry *items; /* owned */
    size_t count;
    size_t capacity;
} Snapshot;

static void snapshot_free(Snapshot *snapshot) {
    for (size_t i = 0; i < snapshot->count; i++) {
        free(snapshot->items[i].path);
    }
    free(snapshot->items);
    *snapshot = (Snapshot){0};
}

static bool snapshot_push(Snapshot *snapshot, MsBytes path, const MsSysStat *stat) {
    if (snapshot->count == snapshot->capacity) {
        const size_t capacity = snapshot->capacity == 0 ? FIRST_ENTRIES : snapshot->capacity * 2;
        size_t bytes = 0;
        if (capacity <= snapshot->count || !ms_size_mul(capacity, sizeof(SnapEntry), &bytes)) {
            return false;
        }
        SnapEntry *grown = realloc(snapshot->items, bytes);
        if (grown == NULL) {
            return false;
        }
        snapshot->items = grown;
        snapshot->capacity = capacity;
    }
    uint8_t *copy = malloc(path.len + 1);
    if (copy == NULL) {
        return false;
    }
    memcpy(copy, path.ptr, path.len);
    snapshot->items[snapshot->count++] = (SnapEntry){
        .path = copy,
        .length = path.len,
        .mode = stat->mode,
        .size = stat->size,
        .seconds = stat->modified.seconds,
        .nanos = stat->modified.nanos,
    };
    return true;
}

static int entry_compare(const void *a, const void *b) {
    const SnapEntry *left = a;
    const SnapEntry *right = b;
    const size_t common = left->length < right->length ? left->length : right->length;
    const int order = common == 0 ? 0 : memcmp(left->path, right->path, common);
    if (order != 0) {
        return order;
    }
    if (left->length == right->length) {
        return 0;
    }
    return left->length < right->length ? -1 : 1;
}

static void fail_memory(MsFsFail *fail) { ms_fs_fail_text(fail, "out of memory"); }

static bool snapshot_visit(MsBytes path, size_t depth, bool recursive, int64_t max, Snapshot *snapshot, MsFsFail *fail) {
    if (ms_fs_poll_cancel(fail)) {
        return false;
    }
    if ((int64_t)snapshot->count >= max || depth > MAX_DEPTH) {
        ms_fs_fail_status(fail, STATUS_LIMIT_EXCEEDED);
        return false;
    }
    if (!ms_fs_valid_utf8(path)) {
        ms_fs_fail_status(fail, STATUS_UNSUPPORTED);
        return false;
    }
    MsSysStat stat;
    const MsSysError error = ms_fs_stat_bytes(path, false, &stat);
    if (error != 0) {
        ms_fs_fail_errno_at(fail, error, "lstat", path);
        return false;
    }
    if (!snapshot_push(snapshot, path, &stat)) {
        fail_memory(fail);
        return false;
    }
    if (!ms_fs_stat_is_directory(&stat) || (depth > 0 && !recursive)) {
        return true;
    }
    MsFsBuffer names = {0};
    bool ok = ms_fs_names_read(path, &names, fail);
    size_t cursor = 0;
    MsBytes name;
    while (ok && ms_fs_names_next(&names, &cursor, &name)) {
        MsFsBuffer child = {0};
        ok = ms_fs_path_join(path, name, &child);
        if (!ok) {
            fail_memory(fail);
        } else {
            ok = snapshot_visit(ms_fs_buffer_view(&child), depth + 1, recursive, max, snapshot, fail);
        }
        ms_fs_buffer_free(&child);
    }
    ms_fs_buffer_free(&names);
    return ok;
}

static bool snapshot_take(MsBytes root, bool recursive, int64_t max, Snapshot *snapshot, MsFsFail *fail) {
    if (!snapshot_visit(root, 0, recursive, max, snapshot, fail)) {
        snapshot_free(snapshot);
        return false;
    }
    qsort(snapshot->items, snapshot->count, sizeof(SnapEntry), entry_compare);
    return true;
}

static bool same_stamp(const SnapEntry *a, const SnapEntry *b) {
    return a->mode == b->mode && a->size == b->size && a->seconds == b->seconds && a->nanos == b->nanos;
}

/* What differs between two snapshots, sorted by path: `rename` for an entry that appeared or disappeared, otherwise
 * a change. */
static void snapshot_diff(const Snapshot *before, const Snapshot *now, MsVec *out) {
    msrt_list_with_capacity(&event_out_desc, 0, out);
    size_t i = 0;
    size_t j = 0;
    while (i < before->count && j < now->count) {
        const SnapEntry *old = &before->items[i];
        const SnapEntry *fresh = &now->items[j];
        const int order = entry_compare(old, fresh);
        if (order < 0) {
            push_event_out(out, old->path, old->length, true);
            i++;
        } else if (order > 0) {
            push_event_out(out, fresh->path, fresh->length, true);
            j++;
        } else {
            if (!same_stamp(old, fresh)) {
                push_event_out(out, fresh->path, fresh->length, false);
            }
            i++;
            j++;
        }
    }
    for (; i < before->count; i++) {
        push_event_out(out, before->items[i].path, before->items[i].length, true);
    }
    for (; j < now->count; j++) {
        push_event_out(out, now->items[j].path, now->items[j].length, true);
    }
}

/* ---- the watcher ---- */

typedef struct WatchEvent {
    uint8_t *path; /* owned (malloc) */
    size_t length;
    bool rename;
} WatchEvent;

typedef struct WatchRow WatchRow;

struct WatchRow {
    uv_fs_event_t handle;
    WatchRow *next;     /* owned; the watcher's list */
    struct MsFsWatcher *owner;
    char *path;         /* owned (malloc), NUL-terminated */
    size_t length;
    bool is_directory;
};

typedef struct MsFsWatcher {
    MsObj header;
    uint64_t token;
    int64_t interval_ns; /* polling */
    int64_t max;         /* polling */
    Snapshot before;     /* polling */
    uv_mutex_t lock;
    WatchEvent *queue; /* owned ring */
    size_t head;
    size_t count;
    size_t capacity;
    char *terminal_text; /* owned (malloc) */
    uv_loop_t loop;
    uv_async_t stop;
    uv_thread_t thread;
    WatchRow *rows; /* owned; only the watching thread touches it while it runs */
    char *root;     /* owned (malloc) */
    size_t root_length;
    uint8_t terminal; /* a failure for the next `next`; STATUS_OK while none */
    bool polling;
    bool recursive;
    bool closed;
    bool ended; /* the root is gone: the stream ends once the queue drains */
    bool gone;  /* polling: the root vanished and was reported */
    bool lock_ready;
    bool ignore_overflow;
    bool loop_ready;
    bool stop_ready;
    bool thread_started;
    bool ready; /* macOS: the event stream has seen the readiness file */
} MsFsWatcher;

static void watcher_lock(MsFsWatcher *watcher) { uv_mutex_lock(&watcher->lock); }
static void watcher_unlock(MsFsWatcher *watcher) { uv_mutex_unlock(&watcher->lock); }

/* Records a failure for `next` unless one is already waiting. Pool and watch threads call this. */
static void set_terminal(MsFsWatcher *watcher, uint8_t status, const char *text) {
    watcher_lock(watcher);
    if (watcher->terminal == STATUS_OK) {
        watcher->terminal = status;
        if (text != NULL) {
            size_t size = strlen(text) + 1;
            watcher->terminal_text = malloc(size);
            if (watcher->terminal_text != NULL) {
                memcpy(watcher->terminal_text, text, size);
            }
        }
    }
    watcher_unlock(watcher);
    msrt_token_post_remote(watcher->token, 1);
}

static void queue_event(MsFsWatcher *watcher, const uint8_t *path, size_t length, bool rename) {
    uint8_t *copy = malloc(length + 1);
    if (copy == NULL) {
        set_terminal(watcher, STATUS_FAILED, "out of memory");
        return;
    }
    memcpy(copy, path, length);
    watcher_lock(watcher);
    if (watcher->count >= watcher->capacity) {
        if (!watcher->ignore_overflow && watcher->terminal == STATUS_OK) {
            watcher->terminal = STATUS_LIMIT_EXCEEDED;
        }
        watcher_unlock(watcher);
        free(copy);
        msrt_token_post_remote(watcher->token, 1);
        return;
    }
    const size_t slot = (watcher->head + watcher->count) % watcher->capacity;
    watcher->queue[slot] = (WatchEvent){.path = copy, .length = length, .rename = rename};
    watcher->count++;
    watcher_unlock(watcher);
    msrt_token_post_remote(watcher->token, 1);
}

static void mark_ended(MsFsWatcher *watcher) {
    watcher_lock(watcher);
    watcher->ended = true;
    watcher_unlock(watcher);
    msrt_token_post_remote(watcher->token, 1);
}

/* ---- handles (native) ---- */

#if defined(__APPLE__) || defined(_WIN32)
#define WATCH_RECURSIVE_HANDLE 1
#else
#define WATCH_RECURSIVE_HANDLE 0
#endif

static void row_closed(uv_handle_t *handle) {
    WatchRow *row = (WatchRow *)handle;
    free(row->path);
    free(row);
}

static void row_close(WatchRow *row) {
    uv_fs_event_stop(&row->handle);
    uv_close((uv_handle_t *)&row->handle, row_closed);
}

static MsBytes row_bytes(const WatchRow *row) { return ms_bytes_of((const uint8_t *)row->path, row->length); }

static bool row_path_is(const WatchRow *row, MsBytes path) {
    return row->length == path.len && memcmp(row->path, path.ptr, path.len) == 0;
}

/* Whether `row` is `path` or lies below it. */
static bool row_within(const WatchRow *row, MsBytes path) {
    if (row_path_is(row, path)) {
        return true;
    }
    return row->length > path.len && memcmp(row->path, path.ptr, path.len) == 0 && ms_fs_is_separator((uint8_t)row->path[path.len]);
}

static void watch_event(uv_fs_event_t *handle, const char *filename, int events, int status);

/* Starts a handle on `path`. Recursive handles cover the subtree on the hosts that can. */
static void row_add(MsFsWatcher *watcher, MsBytes path, bool is_directory, MsFsFail *fail) {
    WatchRow *row = calloc(1, sizeof *row);
    char *text = malloc(path.len + 1);
    if (row == NULL || text == NULL) {
        free(row);
        free(text);
        fail_memory(fail);
        return;
    }
    memcpy(text, path.ptr, path.len);
    text[path.len] = '\0';
    row->path = text;
    row->length = path.len;
    row->owner = watcher;
    row->is_directory = is_directory;
    int code = uv_fs_event_init(&watcher->loop, &row->handle);
    if (code != 0) {
        free(text);
        free(row);
        ms_fs_fail_uv(fail, code, "watch", path);
        return;
    }
    const unsigned flags = (WATCH_RECURSIVE_HANDLE && watcher->recursive && is_directory) ? UV_FS_EVENT_RECURSIVE : 0;
    code = uv_fs_event_start(&row->handle, watch_event, text, flags);
    if (code != 0) {
        uv_close((uv_handle_t *)&row->handle, row_closed);
        ms_fs_fail_uv(fail, code, "watch", path);
        return;
    }
    row->next = watcher->rows;
    watcher->rows = row;
}

static WatchRow *row_find(MsFsWatcher *watcher, MsBytes path) {
    for (WatchRow *row = watcher->rows; row != NULL; row = row->next) {
        if (row_path_is(row, path)) {
            return row;
        }
    }
    return NULL;
}

/* Closes every row at or below `path`. */
static void rows_remove(MsFsWatcher *watcher, MsBytes path) {
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

/* Watches `path`, and on hosts without a recursive watch every directory below it. */
static void tree_add(MsFsWatcher *watcher, MsBytes path, size_t depth, MsFsFail *fail) {
    MsSysStat stat;
    const MsSysError error = ms_fs_stat_bytes(path, false, &stat);
    if (error != 0) {
        ms_fs_fail_errno_at(fail, error, "lstat", path);
        return;
    }
    const bool is_directory = ms_fs_stat_is_directory(&stat);
    if (depth > 0 && !is_directory) {
        return;
    }
    if (row_find(watcher, path) == NULL) {
        row_add(watcher, path, is_directory, fail);
        if (ms_fs_failed(fail)) {
            return;
        }
    }
    if (!is_directory || !watcher->recursive || WATCH_RECURSIVE_HANDLE || depth > MAX_DEPTH) {
        return;
    }
    MsFsBuffer names = {0};
    bool ok = ms_fs_names_read(path, &names, fail);
    size_t cursor = 0;
    MsBytes name;
    while (ok && ms_fs_names_next(&names, &cursor, &name)) {
        MsFsBuffer child = {0};
        if (!ms_fs_path_join(path, name, &child)) {
            fail_memory(fail);
            ok = false;
        } else {
            tree_add(watcher, ms_fs_buffer_view(&child), depth + 1, fail);
            ok = !ms_fs_failed(fail);
        }
        ms_fs_buffer_free(&child);
    }
    ms_fs_buffer_free(&names);
}

/* Queues a `rename` event for everything already inside the new directory `directory`. */
static void report_existing(MsFsWatcher *watcher, MsBytes directory, size_t depth) {
    MsFsFail ignored = {0};
    MsFsBuffer names = {0};
    if (depth <= MAX_DEPTH && ms_fs_names_read(directory, &names, &ignored)) {
        size_t cursor = 0;
        MsBytes name;
        while (ms_fs_names_next(&names, &cursor, &name)) {
            MsFsBuffer child = {0};
            if (!ms_fs_path_join(directory, name, &child)) {
                ms_fs_buffer_free(&child);
                break;
            }
            const MsBytes full = ms_fs_buffer_view(&child);
            if (ms_fs_valid_utf8(full)) {
                queue_event(watcher, full.ptr, full.len, true);
                MsSysStat stat;
                if (ms_fs_stat_bytes(full, false, &stat) == 0 && ms_fs_stat_is_directory(&stat)) {
                    report_existing(watcher, full, depth + 1);
                }
            }
            ms_fs_buffer_free(&child);
        }
    }
    ms_fs_buffer_free(&names);
    ms_fs_fail_free(&ignored);
}

/* The path a callback names: the row's own path for an event on the row itself, otherwise the entry below it. */
static bool event_path(const WatchRow *row, const char *filename, bool *self, MsFsBuffer *out) {
    *self = !row->is_directory || filename == NULL || filename[0] == '\0';
#ifdef __APPLE__
    /* FSEvents names a change to the watched directory itself by the directory's own name. */
    if (!*self) {
        const MsBytes base = ms_fs_path_base(row_bytes(row));
        if (strlen(filename) == base.len && memcmp(filename, base.ptr, base.len) == 0) {
            MsFsBuffer child = {0};
            MsSysStat stat;
            const bool joined = ms_fs_path_join(row_bytes(row), ms_bytes_of((const uint8_t *)filename, strlen(filename)), &child);
            *self = joined && ms_fs_stat_bytes(ms_fs_buffer_view(&child), false, &stat) != 0;
            ms_fs_buffer_free(&child);
        }
    }
#endif
    if (!*self && !WATCH_RECURSIVE_HANDLE) {
        /* inotify reports an event on the watched directory itself under its own name. */
        const MsBytes base = ms_fs_path_base(row_bytes(row));
        if (strlen(filename) == base.len && memcmp(filename, base.ptr, base.len) == 0) {
            MsSysStat stat;
            *self = ms_fs_stat_bytes(row_bytes(row), false, &stat) != 0;
        }
    }
    if (*self) {
        return ms_fs_buffer_append(out, (const uint8_t *)row->path, row->length);
    }
    return ms_fs_path_join(row_bytes(row), ms_bytes_of((const uint8_t *)filename, strlen(filename)), out);
}

/* FSEvents (macOS) starts its stream after uv_fs_event_start returns, so a change made right after the watch is
 * created can be missed. Creation therefore touches a file with this prefix until the stream reports it; the file is
 * removed again and its events are never queued. */
#ifdef __APPLE__
static const char ready_prefix[] = ".ms-watch-ready-";
static bool is_ready_file(const char *filename) {
    return filename != NULL && strncmp(filename, ready_prefix, sizeof ready_prefix - 1) == 0;
}
#else
static bool is_ready_file(const char *filename) {
    (void)filename;
    return false;
}
#endif

static void watch_event(uv_fs_event_t *handle, const char *filename, int events, int status) {
    WatchRow *row = (WatchRow *)handle;
    MsFsWatcher *watcher = row->owner;
    if (status < 0) {
        set_terminal(watcher, STATUS_FAILED, uv_strerror(status));
        return;
    }
    if (is_ready_file(filename)) {
        watcher_lock(watcher);
        watcher->ready = true;
        watcher_unlock(watcher);
        msrt_token_post_remote(watcher->token, 1);
        return;
    }
    MsFsBuffer full_buffer = {0};
    bool self = false;
    if (!event_path(row, filename, &self, &full_buffer)) {
        ms_fs_buffer_free(&full_buffer);
        set_terminal(watcher, STATUS_FAILED, "out of memory");
        return;
    }
    const MsBytes full = ms_fs_buffer_view(&full_buffer);
    if (!ms_fs_valid_utf8(full)) {
        ms_fs_buffer_free(&full_buffer);
        set_terminal(watcher, STATUS_UNSUPPORTED, NULL);
        return;
    }
    const bool rename = (events & UV_RENAME) != 0;
    MsSysStat stat;
    const bool exists = ms_fs_stat_bytes(full, false, &stat) == 0;
    bool fresh = false;
    if (rename && !WATCH_RECURSIVE_HANDLE) {
        if (!exists) {
            rows_remove(watcher, full);
        } else if (watcher->recursive && ms_fs_stat_is_directory(&stat)) {
            MsFsFail fail = {0};
            tree_add(watcher, full, 1, &fail);
            fresh = !ms_fs_failed(&fail);
            if (ms_fs_failed(&fail) && fail.status != STATUS_NOT_FOUND) {
                set_terminal(watcher, fail.status, fail.message);
            }
            ms_fs_fail_free(&fail);
        }
    } else if (rename && exists && watcher->recursive && ms_fs_stat_is_directory(&stat)) {
        fresh = true;
    }
#ifdef __APPLE__
    /* The ready file of native_wait_ready changes the root's modification time: not an event of the user's. */
    if (self && exists && row->is_directory && filename != NULL && filename[0] != '\0') {
        ms_fs_buffer_free(&full_buffer);
        return;
    }
#endif
    queue_event(watcher, full.ptr, full.len, rename);
    /* What was created before the watch existed raised no event of its own. */
    if (fresh) {
        report_existing(watcher, full, 0);
    }
    if (self && !exists && watcher->root_length == full.len && memcmp(watcher->root, full.ptr, full.len) == 0) {
        mark_ended(watcher);
    }
    ms_fs_buffer_free(&full_buffer);
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

/* Ends the loop: closes every handle, so uv_run returns. */
static void close_loop_handles(MsFsWatcher *watcher) {
    close_rows(watcher);
    if (watcher->stop_ready) {
        watcher->stop_ready = false;
        uv_close((uv_handle_t *)&watcher->stop, stop_closed);
    }
}

static void stop_requested(uv_async_t *handle) {
    MsFsWatcher *watcher = handle->data;
    close_loop_handles(watcher);
}

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
        free(watcher->queue[(watcher->head + i) % watcher->capacity].path);
    }
    free(watcher->queue);
    free(watcher->terminal_text);
    free(watcher->root);
    snapshot_free(&watcher->before);
    if (watcher->lock_ready) {
        uv_mutex_destroy(&watcher->lock);
    }
    if (watcher->token != 0) {
        msrt_token_free(watcher->token);
    }
    msrt_free(watcher);
}

static MsFsWatcher *watcher_new(void) {
    MsFsWatcher *watcher = msrt_alloc_zeroed(sizeof *watcher);
    watcher->header.clone = NULL;
    watcher->header.drop = watcher_drop;
    return watcher;
}

/* ---- creating watchers ---- */

static bool watcher_init_common(MsFsWatcher *watcher) {
    watcher->token = msrt_token_new(1);
    if (uv_mutex_init(&watcher->lock) != 0) {
        return false;
    }
    watcher->lock_ready = true;
    return true;
}

uint8_t msstd_fs_watch(const MsStr *path, uint8_t recursive, int64_t interval_ns, uint8_t has_max, int64_t max, void **out, MsStr *err) {
    MsFsFail fail = {0};
    const MsBytes root = msrt_str_bytes(path);
    int64_t limit = MS_FS_UNLIMITED;
    if (!ms_fs_limit(has_max, max, &limit) || interval_ns <= 0 || root.len == 0) {
        ms_fs_fail_status(&fail, STATUS_INVALID_INPUT);
        return ms_fs_finish_at(&fail, root, err);
    }
    Snapshot before = {0};
    if (snapshot_take(root, recursive != 0, limit, &before, &fail)) {
        MsFsWatcher *watcher = watcher_new();
        if (!watcher_init_common(watcher)) {
            snapshot_free(&before);
            watcher_drop(&watcher->header);
            ms_fs_fail_text(&fail, "watch: cannot initialise");
        } else {
            watcher->polling = true;
            watcher->recursive = recursive != 0;
            watcher->interval_ns = interval_ns;
            watcher->max = limit;
            watcher->before = before;
            watcher->root = malloc(root.len + 1);
            watcher->root_length = root.len;
            memcpy(watcher->root, root.ptr, root.len);
            *out = watcher;
        }
    }
    return ms_fs_finish_at(&fail, root, err);
}

static bool native_arguments_valid(MsBytes root, int64_t max, int64_t events, MsBytes overflow) {
    const bool overflow_known = (overflow.len == 5 && memcmp(overflow.ptr, "error", 5) == 0) ||
                                (overflow.len == 6 && memcmp(overflow.ptr, "ignore", 6) == 0);
    return root.len != 0 && max > 0 && events > 0 && events <= MAX_EVENT_CAPACITY && overflow_known;
}

#ifdef __APPLE__
enum { READY_TRIES = 50, READY_SLICE_NS = 100000000 };

/* Waits until the event stream of a directory root is live (see is_ready_file). Best effort: a root that cannot be
 * written to is watched without the guarantee. */
static void native_wait_ready(MsFsWatcher *watcher, MsBytes root) {
    MsSysStat stat;
    if (ms_fs_stat_bytes(root, false, &stat) != 0 || !ms_fs_stat_is_directory(&stat)) {
        return;
    }
    char name[64];
    (void)snprintf(name, sizeof name, "%s%d-%p", ready_prefix, (int)uv_os_getpid(), (void *)watcher);
    MsFsBuffer path = {0};
    if (!ms_fs_path_join(root, ms_bytes_of((const uint8_t *)name, strlen(name)), &path) || !ms_fs_buffer_push(&path, 0)) {
        ms_fs_buffer_free(&path);
        return;
    }
    for (int attempt = 0; attempt < READY_TRIES; attempt++) {
        uv_fs_t request;
        const int file = uv_fs_open(NULL, &request, (const char *)path.data, UV_FS_O_CREAT | UV_FS_O_WRONLY, 0600, NULL);
        uv_fs_req_cleanup(&request);
        if (file < 0) {
            break;
        }
        (void)uv_fs_close(NULL, &request, (uv_file)file, NULL);
        uv_fs_req_cleanup(&request);
        uint64_t value = 0;
        const uint32_t result = msrt_token_park(watcher->token, READY_SLICE_NS, &value);
        watcher_lock(watcher);
        const bool ready = watcher->ready;
        watcher_unlock(watcher);
        if (ready || (result & MS_WAIT_CANCELLED) != 0) {
            break;
        }
    }
    uv_fs_t request;
    (void)uv_fs_unlink(NULL, &request, (const char *)path.data, NULL);
    uv_fs_req_cleanup(&request);
    ms_fs_buffer_free(&path);
}
#endif

/* Registers every handle and starts the thread. Failures leave `watcher` to be dropped by the caller. */
static void native_start(MsFsWatcher *watcher, MsBytes root, MsFsFail *fail) {
    if (uv_loop_init(&watcher->loop) != 0) {
        ms_fs_fail_text(fail, "watch: cannot create an event loop");
        return;
    }
    watcher->loop_ready = true;
    watcher->stop.data = watcher;
    if (uv_async_init(&watcher->loop, &watcher->stop, stop_requested) != 0) {
        ms_fs_fail_text(fail, "watch: cannot create an event loop");
        return;
    }
    watcher->stop_ready = true;
    tree_add(watcher, root, 0, fail);
    if (ms_fs_failed(fail)) {
        return;
    }
    if (uv_thread_create(&watcher->thread, watch_thread, watcher) != 0) {
        ms_fs_fail_status(fail, STATUS_UNSUPPORTED);
        return;
    }
    watcher->thread_started = true;
#ifdef __APPLE__
    native_wait_ready(watcher, root);
#endif
}

uint8_t msstd_fs_watch_native(const MsStr *path, uint8_t recursive, uint8_t has_max, int64_t max, uint8_t has_events, int64_t events,
                              const MsStr *overflow, void **out, MsStr *err) {
    MsFsFail fail = {0};
    const MsBytes root = msrt_str_bytes(path);
    int64_t limit = MS_FS_UNLIMITED;
    const int64_t capacity = has_events != 0 ? events : DEFAULT_EVENT_CAPACITY;
    if (!ms_fs_limit(has_max, max, &limit) || !native_arguments_valid(root, has_max != 0 ? limit : MS_FS_UNLIMITED, capacity, msrt_str_bytes(overflow))) {
        ms_fs_fail_status(&fail, STATUS_INVALID_INPUT);
        return ms_fs_finish_at(&fail, root, err);
    }
    /* The bound on paths is checked once at the start, as for the polling watcher. */
    Snapshot counted = {0};
    if (!snapshot_take(root, recursive != 0, limit, &counted, &fail)) {
        return ms_fs_finish_at(&fail, root, err);
    }
    snapshot_free(&counted);
    MsFsWatcher *watcher = watcher_new();
    bool ready = watcher_init_common(watcher);
    if (ready) {
        watcher->recursive = recursive != 0;
        watcher->capacity = (size_t)capacity;
        watcher->ignore_overflow = msrt_str_bytes(overflow).len == 6;
        watcher->queue = calloc(watcher->capacity, sizeof(WatchEvent));
        watcher->root = malloc(root.len + 1);
        ready = watcher->queue != NULL && watcher->root != NULL;
    }
    if (!ready) {
        fail_memory(&fail);
    } else {
        memcpy(watcher->root, root.ptr, root.len);
        watcher->root_length = root.len;
        native_start(watcher, root, &fail);
    }
    if (ms_fs_failed(&fail)) {
        watcher_drop(&watcher->header);
    } else {
        *out = watcher;
    }
    return ms_fs_finish_at(&fail, root, err);
}

/* ---- waiting ---- */

/* A wait that parks until the watcher is woken or closed. False when a stop request ended it. */
static bool wait_for_wake(const MsFsWatcher *watcher, int64_t timeout_ns, uint32_t *result) {
    uint64_t value = 0;
    *result = msrt_token_park(watcher->token, timeout_ns, &value);
    return (*result & MS_WAIT_CANCELLED) == 0;
}

static uint8_t next_polling(MsFsWatcher *watcher, MsVec *out, MsFsFail *fail) {
    if (watcher->gone) {
        return STATUS_NONE;
    }
    for (;;) {
        if (ms_fs_poll_cancel(fail)) {
            return STATUS_FAILED;
        }
        if (ms_sched_read_limit_passed()) {
            return STATUS_TIMED_OUT;
        }
        uint32_t result = 0;
        if (!wait_for_wake(watcher, watcher->interval_ns, &result)) {
            ms_fs_fail_text(fail, "cancelled");
            return STATUS_FAILED;
        }
        if (watcher->closed) {
            return STATUS_CLOSED;
        }
        if ((result & MS_WAIT_TIMEOUT) == 0 || ms_sched_read_limit_passed()) {
            continue; /* the limit, if it passed, is reported at the top */
        }
        MsBytes root = ms_bytes_of((const uint8_t *)watcher->root, watcher->root_length);
        Snapshot now = {0};
        MsFsFail taken = {0};
        if (!snapshot_take(root, watcher->recursive, watcher->max, &now, &taken)) {
            if (taken.status == STATUS_NOT_FOUND) {
                watcher->gone = true;
                ms_fs_fail_free(&taken);
            } else {
                *fail = taken;
                return taken.status;
            }
        }
        MsVec events;
        snapshot_diff(&watcher->before, &now, &events);
        snapshot_free(&watcher->before);
        watcher->before = now;
        if (events.len != 0) {
            *out = events;
            return STATUS_OK;
        }
        msrt_list_drop(&events, &event_out_desc);
        if (watcher->gone) {
            return STATUS_NONE;
        }
    }
}

static uint8_t next_native(MsFsWatcher *watcher, MsVec *out, MsFsFail *fail) {
    for (;;) {
        watcher_lock(watcher);
        if (watcher->closed) {
            watcher_unlock(watcher);
            return STATUS_CLOSED;
        }
        if (watcher->terminal != STATUS_OK) {
            const uint8_t status = watcher->terminal;
            char *text = watcher->terminal_text;
            watcher->terminal = STATUS_OK;
            watcher->terminal_text = NULL;
            watcher_unlock(watcher);
            if (status == STATUS_FAILED) {
                ms_fs_fail_text(fail, text != NULL ? text : "watch failed");
            } else {
                ms_fs_fail_status(fail, status);
            }
            free(text);
            return status;
        }
        if (watcher->count > 0) {
            WatchEvent event = watcher->queue[watcher->head];
            watcher->head = (watcher->head + 1) % watcher->capacity;
            watcher->count--;
            watcher_unlock(watcher);
            msrt_list_with_capacity(&event_out_desc, 1, out);
            push_event_out(out, event.path, event.length, event.rename);
            free(event.path);
            return STATUS_OK;
        }
        if (watcher->ended) {
            watcher_unlock(watcher);
            return STATUS_NONE;
        }
        watcher_unlock(watcher);
        if (ms_fs_poll_cancel(fail)) {
            return STATUS_FAILED;
        }
        if (ms_sched_read_limit_passed()) {
            return STATUS_TIMED_OUT;
        }
        uint32_t result = 0;
        if (!wait_for_wake(watcher, -1, &result)) {
            ms_fs_fail_text(fail, "cancelled");
            return STATUS_FAILED;
        }
    }
}

uint8_t msstd_fs_watch_next(void *handle, MsVec *out, MsStr *err) {
    MsFsWatcher *watcher = handle;
    MsFsFail fail = {0};
    if (watcher->closed) {
        return STATUS_CLOSED;
    }
    const uint8_t status = watcher->polling ? next_polling(watcher, out, &fail) : next_native(watcher, out, &fail);
    if (status == STATUS_OK || status == STATUS_NONE || status == STATUS_CLOSED) {
        ms_fs_fail_free(&fail);
        msrt_string_empty(err);
        return status;
    }
    if (fail.status == STATUS_OK) {
        ms_fs_fail_status(&fail, status);
    }
    return ms_fs_finish(&fail, err);
}

void msstd_fs_watch_close(void *handle) {
    MsFsWatcher *watcher = handle;
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
    msrt_token_post_remote(watcher->token, 1);
    native_shutdown(watcher);
}
