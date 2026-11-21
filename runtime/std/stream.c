/* The host stream over a file descriptor: a read or write parks the task until the descriptor is ready, so a stop
 * request interrupts it. A regular file cannot be waited on, so its reads and writes run on the blocking pool when
 * other tasks could use the time. Failures of the transfer itself are STATUS_FAILED with their text, as @std/io
 * has always reported them. */
#include <stdlib.h>
#include <string.h>

#include "ms_rt/io.h"
#include "stream.h"

enum { STREAM_DEFAULT_CHUNK = 65536, STREAM_WRITE_STEP = 1 << 20 };

/* ---- the object ---- */

static void stream_drop(MsObj *object) {
    MsStream *stream = (MsStream *)object;
    MsFsFail ignored = {0};
    (void)ms_stream_close(stream, &ignored);
    ms_fs_fail_free(&ignored);
    free(stream->name);
    msrt_free(stream);
}

MsStream *ms_stream_new(MsSysFd fd, bool owned, MsBytes name) {
    MsStream *stream = msrt_alloc_zeroed(sizeof *stream);
    if (stream == NULL) {
        return NULL;
    }
    stream->name = malloc(name.len + 1);
    if (stream->name == NULL) {
        msrt_free(stream);
        return NULL;
    }
    if (name.len > 0) {
        memcpy(stream->name, name.ptr, name.len);
    }
    stream->name[name.len] = '\0';
    stream->name_length = name.len;
    stream->header.drop = stream_drop;
    stream->fd = fd;
    stream->owned = owned;
    stream->kind = ms_sys_fs_fd_kind(fd);
    stream->shares_output = !owned && ms_sys_fs_is_output(fd);
#ifdef _WIN32
    stream->adopted = ms_sched_pipe_is_adopted(fd);
#endif
    return stream;
}

MsStream *ms_stream_file(MsSysFd fd, int32_t flags, MsBytes name) {
    MsStream *stream = ms_stream_new(fd, true, name);
    if (stream != NULL) {
        const int32_t access = flags & MS_SYS_O_ACCESS_MASK;
        stream->no_read = access == MS_SYS_O_WRITE;
        stream->no_write = access == MS_SYS_O_READ;
        stream->append = (flags & MS_SYS_O_APPEND) != 0;
        stream->file = true;
    }
    return stream;
}

bool ms_stream_duplicate(const MsStream *stream, MsStream **out, MsFsFail *fail) {
    MsSysFd fd = MS_SYS_FD_INVALID;
    const MsSysError error = ms_sys_fs_dup(stream->fd, &fd);
    if (error != 0) {
        ms_fs_fail_errno_at(fail, error, "duplicate", ms_stream_name(stream));
        return false;
    }
    MsStream *copy = ms_stream_new(fd, true, ms_stream_name(stream));
    if (copy == NULL) {
        const MsSysError closed = ms_sys_fs_close(fd);
        (void)closed;
        ms_fs_fail_text(fail, "out of memory");
        return false;
    }
    copy->kind = stream->kind;
    copy->no_read = stream->no_read;
    copy->no_write = stream->no_write;
    copy->append = stream->append;
    copy->file = stream->file;
    *out = copy;
    return true;
}

int64_t ms_stream_take_fd(MsStream *stream) {
    if (stream->closed || !stream->owned) {
        return -1;
    }
    stream->closed = true;
    return (int64_t)stream->fd;
}

void ms_stream_retire(MsStream *stream) {
    MsFsFail ignored = {0};
    (void)ms_stream_close(stream, &ignored);
    ms_fs_fail_free(&ignored);
}

bool ms_stream_close(MsStream *stream, MsFsFail *fail) {
    if (stream->closed) {
        return true;
    }
    stream->closed = true;
#ifdef _WIN32
    if (stream->adopted) {
        ms_sched_pipe_close(stream->fd);
        return true;
    }
#endif
    if (!stream->owned) {
        return true;
    }
    const MsSysError error = ms_sys_fs_close(stream->fd);
    if (error != 0) {
        ms_fs_fail_os(fail, error, "close", ms_stream_name(stream));
        return false;
    }
    return true;
}

bool ms_stream_admit(const MsStream *stream, MsStreamAccess access, MsFsFail *fail) {
    if (stream->closed) {
        ms_fs_fail_status(fail, STATUS_CLOSED);
        return false;
    }
    if (ms_fs_poll_cancel(fail)) {
        return false;
    }
    if ((access == MS_STREAM_READ && stream->no_read) || (access == MS_STREAM_WRITE && stream->no_write)) {
        ms_fs_fail_status(fail, STATUS_INVALID_INPUT);
        return false;
    }
    return true;
}

/* ---- waiting ---- */

/* Blocks until the descriptor is ready. The task parks, so other tasks (a server's handlers) keep running, and a
 * stop request ends it. Ready, hung up or failed all return: the next read or write reports the details. */
static bool wait_ready(const MsStream *stream, bool for_write, MsFsFail *fail) {
    if (stream->kind == MS_SYS_FD_FILE) {
        return !ms_fs_poll_cancel(fail);
    }
#ifdef _WIN32
    /* A pipe is read where it blocks; only a console is waited on. */
    if (!for_write && stream->kind == MS_SYS_FD_CONSOLE) {
        return ms_stream_win_wait_console(stream, fail);
    }
    (void)for_write;
    return !ms_fs_poll_cancel(fail);
#else
    const uint32_t events = for_write ? MS_WAIT_WRITE : MS_WAIT_READ;
    const uint32_t got = msrt_task_wait_fd((int32_t)stream->fd, events, -1);
    if ((got & MS_WAIT_CANCELLED) != 0) {
        ms_fs_fail_text(fail, "cancelled");
        return false;
    }
    return true;
#endif
}

/* ---- transfers ---- */

typedef struct RawJob {
    MsSysFd fd;
    uint8_t *buffer;       /* for a read */
    const uint8_t *data;   /* for a write */
    size_t length;         /* capacity of the buffer, or bytes of data */
    size_t count;
    MsSysError error;
    bool write;
} RawJob;

static void raw_job(void *data) {
    RawJob *job = data;
    job->error = job->write ? ms_sys_fs_write(job->fd, job->data, job->length, &job->count)
                            : ms_sys_fs_read(job->fd, job->buffer, job->length, &job->count);
}

static bool raw_transfer(const MsStream *stream, RawJob *job, const char *operation, size_t *count, MsFsFail *fail) {
    job->fd = stream->fd;
    if (ms_stream_regular(stream)) {
        ms_fs_run(raw_job, job, fail);
        if (ms_fs_failed(fail)) {
            return false;
        }
    } else {
        raw_job(job);
    }
    if (job->error != 0) {
        ms_fs_fail_os(fail, job->error, operation, ms_stream_name(stream));
        return false;
    }
    *count = job->count;
    return true;
}

bool ms_stream_read_raw(const MsStream *stream, uint8_t *buffer, size_t capacity, size_t *count, MsFsFail *fail) {
    RawJob job = {.buffer = buffer, .length = capacity};
    return raw_transfer(stream, &job, "read", count, fail);
}

bool ms_stream_write_raw(const MsStream *stream, const uint8_t *data, size_t length, size_t *count, MsFsFail *fail) {
    RawJob job = {.data = data, .length = length, .write = true};
    return raw_transfer(stream, &job, "write", count, fail);
}

/* One read into `buffer`, waiting for the descriptor first where that is possible. */
static bool read_fd(MsStream *stream, uint8_t *buffer, size_t capacity, size_t *count, MsFsFail *fail) {
#ifdef _WIN32
    if (stream->adopted || stream->kind == MS_SYS_FD_PIPE) {
        int32_t os_error = 0;
        const MsPipeStatus status = ms_sched_pipe_read(stream->fd, buffer, capacity, count, &os_error);
        if (status == MS_PIPE_CANCELLED) {
            ms_fs_fail_text(fail, "cancelled");
        } else if (status == MS_PIPE_ERROR) {
            ms_fs_fail_os(fail, os_error, "read", ms_stream_name(stream));
        }
        return status == MS_PIPE_OK;
    }
#endif
    return wait_ready(stream, false, fail) && ms_stream_read_raw(stream, buffer, capacity, count, fail);
}

bool ms_stream_read(MsStream *stream, bool has_max, int64_t max, MsFsBuffer *data, bool *eof, MsFsFail *fail) {
    if (!ms_stream_admit(stream, MS_STREAM_READ, fail)) {
        return false;
    }
    if (has_max && max <= 0) {
        ms_fs_fail_status(fail, STATUS_INVALID_INPUT);
        return false;
    }
    const size_t wanted = !has_max || max > STREAM_DEFAULT_CHUNK ? STREAM_DEFAULT_CHUNK : (size_t)max;
    uint8_t *buffer = malloc(wanted);
    if (buffer == NULL) {
        ms_fs_fail_text(fail, "out of memory");
        return false;
    }
    size_t count = 0;
    const bool ok = read_fd(stream, buffer, wanted, &count, fail);
    if (ok) {
        *eof = count == 0;
        data->data = buffer;
        data->length = count;
        data->capacity = wanted;
    } else {
        free(buffer);
    }
    return ok;
}

bool ms_stream_write(MsStream *stream, MsBytes data, MsFsFail *fail) {
    if (!ms_stream_admit(stream, MS_STREAM_WRITE, fail)) {
        return false;
    }
    if (stream->shares_output) {
        ms_sched_flush_stdout();
    }
#ifdef _WIN32
    if (stream->adopted) {
        int32_t os_error = 0;
        const MsPipeStatus status = ms_sched_pipe_write(stream->fd, data.ptr, data.len, &os_error);
        if (status == MS_PIPE_CANCELLED) {
            ms_fs_fail_text(fail, "cancelled");
        } else if (status == MS_PIPE_ERROR) {
            ms_fs_fail_os(fail, os_error, "write", ms_stream_name(stream));
        }
        return status == MS_PIPE_OK;
    }
#endif
    size_t done = 0;
    while (done < data.len) {
        if (!wait_ready(stream, true, fail)) {
            return false;
        }
        const size_t step = data.len - done < STREAM_WRITE_STEP ? data.len - done : STREAM_WRITE_STEP;
        MsSysError error = 0;
        size_t written = 0;
        RawJob job = {.data = data.ptr + done, .length = step, .write = true};
        job.fd = stream->fd;
        if (ms_stream_regular(stream)) {
            ms_fs_run(raw_job, &job, fail);
            if (ms_fs_failed(fail)) {
                return false;
            }
        } else {
            raw_job(&job);
        }
        error = job.error;
        written = job.count;
        if (error != 0 && ms_sys_fs_error_kind(error) == MS_SYS_ERR_WOULD_BLOCK) {
            continue;
        }
        if (error != 0) {
            ms_fs_fail_os(fail, error, "write", ms_stream_name(stream));
            return false;
        }
        if (written == 0) {
            ms_fs_fail_text(fail, "short write");
            return false;
        }
        done += written;
    }
    return true;
}
