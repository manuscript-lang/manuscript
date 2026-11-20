/* Windows streams over pipes and consoles, which cannot be waited on like a descriptor: a console read waits on a
 * pool thread that also watches an event a stop request signals, and a read of a plain pipe is a blocking read on a
 * pool thread that a stop request fails with CancelIoEx. A pool job outlives a cancelled wait, so each job is shared
 * (reference counted) between the task and the pool, which frees it when both are done. */
#ifdef _WIN32

#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#include "ms_rt/sys.h"
#include "stream.h"

/* A job both the task and the pool hold; freed when the last holder lets go. */
typedef struct SharedJob {
    atomic_int holders;
    MsSysFd fd;
    MsSysFd event;      /* console waits: the event a stop request signals */
    uint8_t *buffer;    /* pipe reads: owned (malloc) */
    size_t capacity;
    size_t count;
    MsSysError error;
    atomic_bool stopped;
    atomic_bool started;
    atomic_bool done;
} SharedJob;

static void job_release_holder(SharedJob *job) {
    if (atomic_fetch_sub(&job->holders, 1) == 1) {
        if (job->event != MS_SYS_FD_INVALID) {
            ms_sys_fs_event_free(job->event);
        }
        free(job->buffer);
        free(job);
    }
}

static void job_released_by_pool(void *data) { job_release_holder(data); }

static SharedJob *job_new(MsSysFd fd) {
    SharedJob *job = calloc(1, sizeof *job);
    if (job != NULL) {
        atomic_init(&job->holders, 2);
        job->fd = fd;
        job->event = MS_SYS_FD_INVALID;
    }
    return job;
}

/* ---- console input ---- */

static void console_job(void *data) {
    SharedJob *job = data;
    (void)ms_sys_fs_wait_console(job->fd, job->event);
}

bool ms_stream_win_wait_console(const MsStream *stream, MsFsFail *fail) {
    SharedJob *job = job_new(stream->fd);
    if (job == NULL || ms_sys_fs_event_new(&job->event) != 0) {
        free(job);
        ms_fs_fail_text(fail, "out of memory");
        return false;
    }
    const MsSchedWait wait = ms_sched_pool_run(console_job, job_released_by_pool, job, -1);
    if (wait == MS_SCHED_DONE) {
        job->holders = 1;
        job_release_holder(job);
        return true;
    }
    ms_sys_fs_event_signal(job->event);
    job_release_holder(job);
    ms_fs_fail_text(fail, "cancelled");
    return false;
}

/* ---- pipe reads ---- */

static void pipe_job(void *data) {
    SharedJob *job = data;
    atomic_store(&job->started, true);
    if (atomic_load(&job->stopped)) {
        job->error = ms_sys_fs_error_of(MS_SYS_ERR_IO);
    } else {
        job->error = ms_sys_fs_read(job->fd, job->buffer, job->capacity, &job->count);
    }
    atomic_store(&job->done, true);
}

/* CancelIoEx does nothing before the read is issued, so the request repeats until the job is done once it has
 * started (a job that has not started sees the flag and returns without reading); the repeat lasts only the few
 * instructions between the job's start and its read. */
static void stop_pipe_read(SharedJob *job) {
    atomic_store(&job->stopped, true);
    while (atomic_load(&job->started) && !atomic_load(&job->done)) {
        ms_sys_fs_cancel_io(job->fd);
        ms_sys_yield();
    }
}

bool ms_stream_win_read_pipe(const MsStream *stream, uint8_t *buffer, size_t capacity, size_t *count, MsFsFail *fail) {
    SharedJob *job = job_new(stream->fd);
    if (job != NULL) {
        job->buffer = malloc(capacity == 0 ? 1 : capacity);
        job->capacity = capacity;
    }
    if (job == NULL || job->buffer == NULL) {
        free(job);
        ms_fs_fail_text(fail, "out of memory");
        return false;
    }
    const MsSchedWait wait = ms_sched_pool_run(pipe_job, job_released_by_pool, job, -1);
    if (wait != MS_SCHED_DONE) {
        stop_pipe_read(job);
        job_release_holder(job);
        ms_fs_fail_text(fail, "cancelled");
        return false;
    }
    const bool ok = job->error == 0;
    if (ok) {
        memcpy(buffer, job->buffer, job->count);
        *count = job->count;
    } else {
        ms_fs_fail_os(fail, job->error, "read", ms_stream_name(stream));
    }
    job->holders = 1;
    job_release_holder(job);
    return ok;
}

#endif
