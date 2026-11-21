/* The Windows half of ms_sched.h: blocking pipes and waitable kernel objects. A pipe transfer runs on the blocking
 * pool and the task parks until it ends, so no thread of the scheduler blocks; a pending stop request ends a call with
 * MS_PIPE_CANCELLED, and the park itself ends on it. Objects go over the reactor's ms_io_object_*
 * (src/runtime/io/windows/platform.c). */
#ifdef _WIN32
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <windows.h>

#include "../reactor.h"
#include "ms_rt/sys.h"
#include "ms_rt/sys_fs.h"
#include "ms_sched.h"

enum { ERROR_NOT_ENOUGH_MEMORY_CODE = 8 };

/* Parks until `key` is ready for `events`; false when a stop request ended the wait. */
static bool park(uintptr_t key, uint32_t events, int64_t timeout_ns, uint32_t *got) {
    *got = msrt_task_wait_fd((int32_t)key, events, timeout_ns);
    return (*got & MS_WAIT_CANCELLED) == 0;
}

/* ---- adopted pipes ---- */

/* The blocking pipe handles the runtime reads and writes for tasks. A task can run on any thread, and an overlapped
 * handle belongs to the one I/O completion port it registers with, so a pipe is a plain blocking handle and each read
 * or write runs on the blocking pool, which any thread's task parks on. */
typedef struct Adopted {
    struct Adopted *next;
    intptr_t handle;
} Adopted;

static SRWLOCK adopted_lock = SRWLOCK_INIT;
static Adopted *adopted_list;

bool ms_sched_pipe_adopt(intptr_t handle) {
    Adopted *const entry = malloc(sizeof *entry);
    if (entry == NULL) {
        return false;
    }
    entry->handle = handle;
    AcquireSRWLockExclusive(&adopted_lock);
    entry->next = adopted_list;
    adopted_list = entry;
    ReleaseSRWLockExclusive(&adopted_lock);
    return true;
}

bool ms_sched_pipe_is_adopted(intptr_t handle) {
    AcquireSRWLockExclusive(&adopted_lock);
    Adopted *entry = adopted_list;
    while (entry != NULL && entry->handle != handle) {
        entry = entry->next;
    }
    ReleaseSRWLockExclusive(&adopted_lock);
    return entry != NULL;
}

static void pipe_forget(intptr_t handle) {
    Adopted *found = NULL;
    AcquireSRWLockExclusive(&adopted_lock);
    Adopted **link = &adopted_list;
    while (*link != NULL && (*link)->handle != handle) {
        link = &(*link)->next;
    }
    if (*link != NULL) {
        found = *link;
        *link = found->next;
    }
    ReleaseSRWLockExclusive(&adopted_lock);
    free(found);
}

/* A transfer the task and the pool both hold: the pool may outlive a cancelled wait, so whichever lets go last frees
 * it. A write owns a copy of its data for the same reason. */
typedef struct PipeJob {
    atomic_int holders;
    MsSysFd fd;
    bool write;
    uint8_t *buffer; /* owned: a read's destination or a write's copy */
    size_t length;   /* a read's capacity, or the bytes to write */
    size_t count;    /* the bytes moved */
    MsSysError error;
    atomic_bool stopped;
    atomic_bool started;
    atomic_bool done;
} PipeJob;

static void job_release(void *data) {
    PipeJob *const job = data;
    if (atomic_fetch_sub(&job->holders, 1) == 1) {
        free(job->buffer);
        free(job);
    }
}

static void pipe_job(void *data) {
    PipeJob *const job = data;
    atomic_store(&job->started, true);
    if (atomic_load(&job->stopped)) {
        job->error = ms_sys_fs_error_of(MS_SYS_ERR_IO);
    } else if (!job->write) {
        job->error = ms_sys_fs_read(job->fd, job->buffer, job->length, &job->count);
    }
    while (job->write && job->error == 0 && job->count < job->length) {
        size_t put = 0;
        job->error = ms_sys_fs_write(job->fd, job->buffer + job->count, job->length - job->count, &put);
        job->count += put;
    }
    atomic_store(&job->done, true);
}

/* CancelIoEx does nothing before the transfer is issued, so the request repeats until the job is done once it has
 * started (a job that has not started sees the flag and returns without transferring); the repeat lasts only the few
 * instructions between the job's start and its call. */
static void job_stop(PipeJob *job) {
    atomic_store(&job->stopped, true);
    while (atomic_load(&job->started) && !atomic_load(&job->done)) {
        ms_sys_fs_cancel_io(job->fd);
        ms_sys_yield();
    }
}

/* Runs the transfer on the pool and parks until it ends: a write sends `from`, a read fills `into`. */
static MsPipeStatus pipe_run(intptr_t handle, const uint8_t *from, uint8_t *into, size_t length, size_t *count,
                             int32_t *os_error) {
    if (ms_sched_cancel_pending()) {
        return MS_PIPE_CANCELLED;
    }
    PipeJob *const job = calloc(1, sizeof *job);
    if (job != NULL) {
        atomic_init(&job->holders, 2);
        job->fd = (MsSysFd)handle;
        job->write = from != NULL;
        job->length = length;
        job->buffer = malloc(length == 0 ? 1 : length);
    }
    if (job == NULL || job->buffer == NULL) {
        free(job);
        *os_error = ERROR_NOT_ENOUGH_MEMORY_CODE;
        return MS_PIPE_ERROR;
    }
    if (job->write) {
        memcpy(job->buffer, from, length);
    }
    if (ms_sched_pool_run(pipe_job, job_release, job, -1) != MS_SCHED_DONE) {
        job_stop(job);
        job_release(job);
        return MS_PIPE_CANCELLED;
    }
    const bool ok = job->error == 0;
    if (!ok) {
        *os_error = (int32_t)job->error;
    } else if (!job->write) {
        memcpy(into, job->buffer, job->count);
        *count = job->count;
    }
    atomic_store(&job->holders, 1);
    job_release(job);
    return ok ? MS_PIPE_OK : MS_PIPE_ERROR;
}

MsPipeStatus ms_sched_pipe_read(intptr_t handle, uint8_t *buffer, size_t capacity, size_t *count, int32_t *os_error) {
    return pipe_run(handle, NULL, buffer, capacity, count, os_error);
}

MsPipeStatus ms_sched_pipe_write(intptr_t handle, const uint8_t *data, size_t length, int32_t *os_error) {
    size_t written = 0;
    return pipe_run(handle, data, NULL, length, &written, os_error);
}

void ms_sched_pipe_close(intptr_t handle) {
    pipe_forget(handle);
    (void)ms_sys_fs_close((MsSysFd)handle);
}

MsObjectWait ms_sched_object_wait(intptr_t handle, int64_t timeout_ns) {
    if (!ms_io_object_watch((uintptr_t)handle)) {
        return MS_OBJECT_UNWATCHABLE;
    }
    uint32_t got = 0;
    if (!park((uintptr_t)handle, MS_WAIT_READ, timeout_ns, &got)) {
        return MS_OBJECT_CANCELLED;
    }
    return (got & MS_WAIT_TIMEOUT) != 0 ? MS_OBJECT_TIMED_OUT : MS_OBJECT_SIGNALLED;
}

void ms_sched_object_forget(intptr_t handle) { ms_io_object_drop((uintptr_t)handle); }
#endif
