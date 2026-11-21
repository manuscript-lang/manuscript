/* Descriptors libuv refuses to poll (a named pipe on macOS: kqueue does not report its last writer going away).
 *
 * One thread per reactor blocks in poll(2) over all of them plus a wake-up pipe, so a task waiting on such a pipe
 * costs no latency and no timer ticks. When a descriptor is ready the thread queues its number and signals an
 * async handle, and the loop reports it through `ready` like any other. Every watch is one-shot, like the rows the
 * reactor keeps for sockets: a descriptor leaves the thread's table when it is reported or removed.
 *
 * Removal waits until the thread is out of the poll that named the descriptor, so the caller may close it at once. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c11 */

#ifndef _WIN32

#include "refused.h"

#include <string.h>

#include "ms_rt/safe.h"
#include "ms_rt/sys.h"

enum { FIRST_CAPACITY = 8 };

typedef struct Entry {
    int fd;
    bool writes;
} Entry;

struct MsIoRefused {
    uv_async_t async; /* closed through the loop; the memory is freed by its close callback */
    uv_mutex_t lock;
    uv_cond_t left_poll;
    uv_thread_t thread;
    bool thread_started;
    int wake[2];
    MsIoRefusedReady ready;
    void *context;
    Entry *watching; /* owned; guarded by `lock` */
    size_t watching_length, watching_capacity;
    int *reported; /* owned; descriptors found ready, not yet handed to `ready`; guarded by `lock` */
    size_t reported_length, reported_capacity;
    bool polling;    /* the thread is inside poll(2) */
    uint64_t rounds; /* polls the thread has finished */
    bool stop;
};

/* Appends `item` to a growable array. */
MS_NODISCARD static bool grow(void **array, size_t *capacity, size_t length, size_t item_size) {
    if (length < *capacity) {
        return true;
    }
    size_t grown = *capacity == 0 ? FIRST_CAPACITY : *capacity;
    size_t bytes = 0;
    if ((*capacity != 0 && !ms_size_mul(grown, 2, &grown)) || !ms_size_mul(grown, item_size, &bytes)) {
        return false;
    }
    void *replacement = ms_sys_realloc(*array, bytes);
    if (replacement == NULL) {
        return false;
    }
    *array = replacement;
    *capacity = grown;
    return true;
}

static size_t find(const MsIoRefused *refused, int fd) {
    for (size_t i = 0; i < refused->watching_length; i++) {
        if (refused->watching[i].fd == fd) {
            return i;
        }
    }
    return refused->watching_length;
}

static void drop_watch(MsIoRefused *refused, size_t index) {
    refused->watching[index] = refused->watching[--refused->watching_length];
}

/* The thread: wait for the table or the wake-up pipe, move what is ready to `reported`, tell the loop. */
static void run(void *argument) {
    MsIoRefused *refused = argument;
    uv_mutex_lock(&refused->lock);
    while (!refused->stop) {
        const size_t count = refused->watching_length + 1;
        MsSysFdWait *waits = ms_sys_malloc(count * sizeof *waits);
        if (waits == NULL) {
            break; /* the watches stay unreported; the caller's own checks still find ready descriptors */
        }
        waits[0] = (MsSysFdWait){.fd = refused->wake[0], .wants = MS_SYS_WAIT_READ};
        for (size_t i = 0; i < refused->watching_length; i++) {
            waits[i + 1] = (MsSysFdWait){.fd = refused->watching[i].fd,
                                         .wants = refused->watching[i].writes ? MS_SYS_WAIT_WRITE : MS_SYS_WAIT_READ};
        }
        refused->polling = true;
        uv_mutex_unlock(&refused->lock);
        const bool waited = ms_sys_fd_wait_any(waits, count);
        uv_mutex_lock(&refused->lock);
        refused->polling = false;
        refused->rounds++;
        uv_cond_broadcast(&refused->left_poll);
        if (!waited) {
            ms_sys_free(waits);
            break;
        }
        if (waits[0].got != 0) {
            ms_sys_wake_drain(refused->wake[0]);
        }
        bool any = false;
        for (size_t i = 1; i < count; i++) {
            const size_t at = waits[i].got != 0 ? find(refused, waits[i].fd) : refused->watching_length;
            if (at == refused->watching_length || !grow((void **)&refused->reported, &refused->reported_capacity,
                                                         refused->reported_length, sizeof *refused->reported)) {
                continue;
            }
            refused->reported[refused->reported_length++] = waits[i].fd;
            drop_watch(refused, at);
            any = true;
        }
        ms_sys_free(waits);
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
        const int fd = refused->reported_length > 0 ? refused->reported[refused->reported_length - 1] : -1;
        uv_mutex_unlock(&refused->lock);
        if (fd < 0) {
            return;
        }
        if (!refused->ready(refused->context, fd)) {
            (void)uv_async_send(&refused->async); /* no room now: the next pass of the loop tries again */
            return;
        }
        uv_mutex_lock(&refused->lock);
        for (size_t i = refused->reported_length; i > 0; i--) { /* the thread may have appended meanwhile */
            if (refused->reported[i - 1] == fd) {
                refused->reported[i - 1] = refused->reported[--refused->reported_length];
                break;
            }
        }
        uv_mutex_unlock(&refused->lock);
    }
}

MsIoRefused *ms_io_refused_open(uv_loop_t *loop, MsIoRefusedReady ready, void *context) {
    MsIoRefused *refused = ms_sys_malloc(sizeof *refused);
    if (refused == NULL) {
        return NULL;
    }
    *refused = (MsIoRefused){.ready = ready, .context = context, .wake = {-1, -1}};
    if (!ms_sys_wake_open(refused->wake)) {
        ms_sys_free(refused);
        return NULL;
    }
    if (uv_mutex_init(&refused->lock) != 0) {
        ms_sys_wake_close(refused->wake);
        ms_sys_free(refused);
        return NULL;
    }
    if (uv_cond_init(&refused->left_poll) != 0 || uv_async_init(loop, &refused->async, on_async) != 0) {
        uv_mutex_destroy(&refused->lock);
        ms_sys_wake_close(refused->wake);
        ms_sys_free(refused);
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

bool ms_io_refused_add(MsIoRefused *refused, int fd, bool writes) {
    uv_mutex_lock(&refused->lock);
    bool stored = find(refused, fd) != refused->watching_length;
    if (!stored && grow((void **)&refused->watching, &refused->watching_capacity, refused->watching_length,
                        sizeof *refused->watching)) {
        refused->watching[refused->watching_length++] = (Entry){.fd = fd, .writes = writes};
        stored = true;
    }
    uv_mutex_unlock(&refused->lock);
    if (stored) {
        ms_sys_wake_send(refused->wake[1]);
    }
    return stored;
}

void ms_io_refused_remove(MsIoRefused *refused, int fd) {
    uv_mutex_lock(&refused->lock);
    const size_t at = find(refused, fd);
    if (at != refused->watching_length) {
        drop_watch(refused, at);
    }
    for (size_t i = 0; i < refused->reported_length; i++) {
        if (refused->reported[i] == fd) {
            refused->reported[i] = refused->reported[--refused->reported_length];
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

static void on_closed(uv_handle_t *handle) {
    MsIoRefused *refused = uv_handle_get_data(handle);
    ms_sys_free(refused->watching);
    ms_sys_free(refused->reported);
    uv_cond_destroy(&refused->left_poll);
    uv_mutex_destroy(&refused->lock);
    ms_sys_free(refused);
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

#else

/* Windows: libuv polls every socket, so nothing is ever refused; these are here to link. */
#include "refused.h"

MsIoRefused *ms_io_refused_open(uv_loop_t *loop, MsIoRefusedReady ready, void *context) {
    (void)loop;
    (void)ready;
    (void)context;
    return NULL;
}
bool ms_io_refused_add(MsIoRefused *refused, int fd, bool writes) {
    (void)refused;
    (void)fd;
    (void)writes;
    return false;
}
void ms_io_refused_remove(MsIoRefused *refused, int fd) {
    (void)refused;
    (void)fd;
}
void ms_io_refused_close(MsIoRefused *refused) { (void)refused; }

#endif
