/* Windows console input, which cannot be waited on like a descriptor: the read waits on a pool thread that also
 * watches an event a stop request signals. A pool job outlives a cancelled wait, so each job is shared (reference
 * counted) between the task and the pool, which frees it when both are done. Pipe transfers are in
 * src/runtime/io/windows/sched.c. */
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
} SharedJob;

static void job_release_holder(SharedJob *job) {
    if (atomic_fetch_sub(&job->holders, 1) == 1) {
        if (job->event != MS_SYS_FD_INVALID) {
            ms_sys_fs_event_free(job->event);
        }
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

#endif
