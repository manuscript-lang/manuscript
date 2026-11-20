/* signals.c: `watch_signals` for @std/process. A watcher buffers up to `capacity` signal numbers; the platform layer
 * (ms_rt/sys_signal.h) says when one may be waiting, and `next` parks until it is. Observers keep no thread of their
 * own: a task waiting on a watcher parks on the platform's wake-up. */
#define _POSIX_C_SOURCE 200809L

#include <stdatomic.h>
#include <stdlib.h>

#include "ms_rt/signals.h"
#include "ms_rt/sys_signal.h"
#include "ms_sched.h"

#include "fs_support.h"

enum { MAX_CAPACITY = 1048576, DEFAULT_CAPACITY = 128, DRAIN = 256 };

typedef struct MsSignalWatcher {
    MsObj header;
    MsSysSignals *observer;
    uint8_t *queue; /* a ring of `capacity` signal numbers */
    size_t capacity, head, count;
    bool closed;
    atomic_uint_least64_t parked; /* the token of the task waiting where there is no descriptor; 0 when none */
} MsSignalWatcher;

static void watcher_drop(MsObj *object) {
    MsSignalWatcher *watcher = (MsSignalWatcher *)object;
    if (watcher->observer != NULL) {
        ms_sys_signals_destroy(watcher->observer);
    }
    free(watcher->queue);
    msrt_free(watcher);
}

/* Wakes the task parked on a token, once: the token is taken before it is posted. May run on an OS thread. */
static void notify(void *context) {
    MsSignalWatcher *watcher = context;
    const uint64_t token = atomic_exchange(&watcher->parked, 0);
    if (token != 0) {
        msrt_token_post_remote(token, 1);
    }
}

/* Parks the task until a signal may be waiting or the watcher is closed. Returns the MS_WAIT_* bits of the wake. */
static uint32_t wait_for_signal(MsSignalWatcher *watcher) {
    const int fd = ms_sys_signals_fd(watcher->observer);
    if (fd >= 0) {
        return msrt_task_wait_fd(fd, MS_WAIT_READ, -1);
    }
    /* A fresh token per park: a remote token counts as a pending wake-up only until its first post. */
    const uint64_t token = msrt_token_new(1);
    atomic_store(&watcher->parked, token);
    /* The platform counts before it notifies, and this stores the token before it re-reads the counts, so one of the
     * two sees the other. */
    uint32_t result = 0;
    if (!watcher->closed && !ms_sys_signals_pending(watcher->observer)) {
        uint64_t value = 0;
        result = msrt_token_park(token, -1, &value);
    }
    atomic_store(&watcher->parked, 0);
    msrt_token_free(token);
    return result;
}

static uint8_t finish_status(uint8_t status, MsStr *err) {
    MsFsFail fail = {0};
    ms_fs_fail_status(&fail, status);
    return ms_fs_finish(&fail, err);
}

void msstd_process_stop_hold(void) { ms_sched_stop_hold(); }

void msstd_process_stop_release(void) { ms_sched_stop_release(); }

uint8_t msstd_process_watch_signals(const MsVec *signals, uint8_t has_capacity, int64_t capacity, MsObj **out, MsStr *err) {
    const int64_t size = has_capacity != 0 ? capacity : DEFAULT_CAPACITY;
    if (signals->len == 0 || size < 1 || size > MAX_CAPACITY) {
        return finish_status(STATUS_INVALID_INPUT, err);
    }
    uint64_t mask = 0;
    const int64_t *list = signals->ptr;
    for (size_t i = 0; i < signals->len; i++) {
        if (!ms_sys_signal_valid(list[i])) {
            return finish_status(STATUS_INVALID_INPUT, err);
        }
        mask |= UINT64_C(1) << (list[i] - 1);
    }
    MsFsFail fail = {0};
    MsSignalWatcher *watcher = msrt_alloc_zeroed(sizeof *watcher);
    watcher->header.clone = NULL;
    watcher->header.drop = watcher_drop;
    watcher->capacity = (size_t)size;
    watcher->queue = malloc(watcher->capacity);
    if (watcher->queue == NULL) {
        ms_fs_fail_text(&fail, "out of memory");
    } else {
        const MsSysError error = ms_sys_signals_open(mask, watcher->capacity, notify, watcher, &watcher->observer);
        if (error == MS_SYS_SIGNALS_FULL) {
            ms_fs_fail_status(&fail, STATUS_LIMIT_EXCEEDED);
        } else if (error != 0) {
            ms_fs_fail_errno(&fail, error, "signal", NULL, 0);
        }
    }
    if (ms_fs_failed(&fail)) {
        watcher_drop(&watcher->header);
    } else {
        *out = &watcher->header;
    }
    return ms_fs_finish(&fail, err);
}

/* Moves the signals the platform holds into the ring; those beyond `capacity` are dropped, as a full pipe drops them. */
static void fill(MsSignalWatcher *watcher) {
    uint8_t buffer[DRAIN];
    size_t taken;
    while ((taken = ms_sys_signals_take(watcher->observer, buffer, sizeof buffer)) > 0) {
        for (size_t i = 0; i < taken && watcher->count < watcher->capacity; i++) {
            watcher->queue[(watcher->head + watcher->count++) % watcher->capacity] = buffer[i];
        }
    }
}

uint8_t msstd_process_signal_next(MsObj *object, int64_t *out, MsStr *err) {
    MsSignalWatcher *watcher = (MsSignalWatcher *)object;
    for (;;) {
        if (watcher->closed) {
            return STATUS_CLOSED;
        }
        fill(watcher);
        if (watcher->count > 0) {
            *out = watcher->queue[watcher->head];
            watcher->head = (watcher->head + 1) % watcher->capacity;
            watcher->count--;
            return STATUS_OK;
        }
        MsFsFail fail = {0};
        if (ms_fs_poll_cancel(&fail)) {
            return ms_fs_finish(&fail, err);
        }
        if (ms_sched_read_limit_passed()) {
            return finish_status(STATUS_TIMED_OUT, err);
        }
        if ((wait_for_signal(watcher) & MS_WAIT_CANCELLED) != 0) {
            ms_fs_fail_text(&fail, "cancelled");
            return ms_fs_finish(&fail, err);
        }
    }
}

void msstd_process_signal_close(MsObj *object) {
    MsSignalWatcher *watcher = (MsSignalWatcher *)object;
    if (!watcher->closed) {
        watcher->closed = true;
        ms_sys_signals_stop(watcher->observer);
    }
}
