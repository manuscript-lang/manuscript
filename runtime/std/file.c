/* @std/fs file handles: open, positioned and vectored transfers, seek, sync, locks, permissions and line reads over
 * the host stream of stream.c. A handle is also the `reader()` / `writer()` view of @std/io. Operations on a regular
 * file run on the blocking pool when other tasks could use the time; each failure is the OS failure of the operation
 * on the path the file was opened with. */
#include <stdlib.h>
#include <string.h>

#include "ms_rt/fs.h"
#include "stream.h"

enum {
    FILE_CHUNK = 65536,
    FILE_MAX_PERMISSIONS = 07777,
    FILE_VECTOR_ITEM_LIMIT = 65536,
    FILE_VECTOR_TOTAL_LIMIT = 16 * 1024 * 1024,
    FILE_MAX_OWNER = 2147483647
};

static void fail_memory(MsFsFail *fail) { ms_fs_fail_text(fail, "out of memory"); }

static void fail_invalid(MsFsFail *fail) { ms_fs_fail_status(fail, STATUS_INVALID_INPUT); }

/* An OS failure of `operation` on the file's path. */
static void fail_file(const MsStream *stream, MsFsFail *fail, const char *operation, MsSysError error) {
    ms_fs_fail_errno_at(fail, error, operation, ms_stream_name(stream));
}

/* ---- opening ---- */

/* The host flags of a mode string of `open`; false for an unknown mode. */
static bool flags_of_mode(MsBytes mode, int32_t *flags) {
    static const struct {
        const char *text;
        int32_t flags;
    } modes[] = {
        {"r", MS_SYS_O_READ},
        {"r+", MS_SYS_O_READ_WRITE},
        {"w", MS_SYS_O_WRITE | MS_SYS_O_CREATE | MS_SYS_O_TRUNCATE},
        {"wx", MS_SYS_O_WRITE | MS_SYS_O_CREATE | MS_SYS_O_EXCLUSIVE},
        {"w+", MS_SYS_O_READ_WRITE | MS_SYS_O_CREATE | MS_SYS_O_TRUNCATE},
        {"wx+", MS_SYS_O_READ_WRITE | MS_SYS_O_CREATE | MS_SYS_O_EXCLUSIVE},
        {"a", MS_SYS_O_WRITE | MS_SYS_O_CREATE | MS_SYS_O_APPEND},
        {"ax", MS_SYS_O_WRITE | MS_SYS_O_CREATE | MS_SYS_O_APPEND | MS_SYS_O_EXCLUSIVE},
        {"a+", MS_SYS_O_READ_WRITE | MS_SYS_O_CREATE | MS_SYS_O_APPEND},
        {"ax+", MS_SYS_O_READ_WRITE | MS_SYS_O_CREATE | MS_SYS_O_APPEND | MS_SYS_O_EXCLUSIVE},
    };
    for (size_t i = 0; i < sizeof modes / sizeof modes[0]; i++) {
        const size_t length = strlen(modes[i].text);
        if (mode.len == length && memcmp(mode.ptr, modes[i].text, length) == 0) {
            *flags = modes[i].flags;
            return true;
        }
    }
    return false;
}

/* Opens `path`. A named pipe opened for reading would block in open(2) until a writer arrives, so it is opened
 * without waiting and then switched back to blocking mode; reads wait for data. */
static MsSysError open_without_waiting(const char *text, bool is_fifo, int32_t flags, uint32_t mode, MsSysFd *fd) {
    if (!is_fifo) {
        return ms_sys_fs_open(text, flags, mode, fd);
    }
    const MsSysError error = ms_sys_fs_open(text, flags | MS_SYS_O_NONBLOCK, mode, fd);
    if (error == 0) {
        ms_sys_fs_set_blocking(*fd);
    }
    return error;
}

static uint8_t open_file(MsBytes path, int32_t flags, int64_t mode, MsStream **out, MsFsFail *fail) {
    MsFsPath text;
    if (mode < 0 || mode > FILE_MAX_PERMISSIONS || !ms_fs_path_init(&text, path)) {
        fail_invalid(fail);
        return fail->status;
    }
    MsSysStat info;
    const bool is_fifo = (flags & MS_SYS_O_ACCESS_MASK) == MS_SYS_O_READ && ms_sys_fs_stat(text.text, true, &info) == 0 &&
                         (info.mode & MS_SYS_S_IFMT) == MS_SYS_S_IFIFO;
    MsSysFd fd = MS_SYS_FD_INVALID;
    const MsSysError error = open_without_waiting(text.text, is_fifo, flags, (uint32_t)mode, &fd);
    ms_fs_path_free(&text);
    if (error != 0) {
        ms_fs_fail_errno_at(fail, error, "open", path);
        return fail->status;
    }
    MsStream *stream = ms_stream_file(fd, flags, path);
    if (stream == NULL) {
        const MsSysError closed = ms_sys_fs_close(fd);
        (void)closed;
        fail_memory(fail);
        return fail->status;
    }
    *out = stream;
    return STATUS_OK;
}

uint8_t msstd_fs_open(const MsStr *path, const MsStr *mode_text, int64_t mode, void **out, MsStr *err) {
    MsFsFail fail = {0};
    int32_t flags = 0;
    MsStream *stream = NULL;
    if (!flags_of_mode(msrt_str_bytes(mode_text), &flags)) {
        fail_invalid(&fail);
    } else {
        (void)open_file(msrt_str_bytes(path), flags, mode, &stream, &fail);
    }
    if (stream != NULL) {
        *out = stream;
    }
    return ms_fs_finish_at(&fail, msrt_str_bytes(path), err);
}

uint8_t msstd_fs_file_clone(const void *handle, void **out, MsStr *err) {
    const MsStream *stream = handle;
    MsFsFail fail = {0};
    MsStream *copy = NULL;
    if (stream->closed) {
        ms_fs_fail_status(&fail, STATUS_CLOSED);
    } else if (ms_stream_duplicate(stream, &copy, &fail)) {
        *out = copy;
    }
    return ms_fs_finish(&fail, err);
}

/* ---- positioned and vectored transfers ---- */

typedef struct TransferJob {
    MsSysFd fd;
    uint8_t *buffer;       /* a positioned read fills it */
    const uint8_t *data;   /* a positioned write sends it */
    size_t length;
    int64_t offset;
    size_t done;
    MsSysError error;
    bool write;
} TransferJob;

/* Reads until the buffer is full or the file ends, or writes all of the data: positioned transfers need a seekable
 * file, so they always run where a short transfer is retried. */
static void transfer_job(void *data) {
    TransferJob *job = data;
    while (job->done < job->length && job->error == 0) {
        const size_t step = job->length - job->done < FILE_CHUNK ? job->length - job->done : FILE_CHUNK;
        size_t count = 0;
        const int64_t at = job->offset + (int64_t)job->done;
        job->error = job->write ? ms_sys_fs_pwrite(job->fd, job->data + job->done, step, at, &count)
                                : ms_sys_fs_pread(job->fd, job->buffer + job->done, step, at, &count);
        if (job->error == 0 && count == 0) {
            if (job->write) {
                job->error = ms_sys_fs_error_of(MS_SYS_ERR_IO);
            }
            return;
        }
        job->done += count;
    }
}

/* Runs a positioned transfer on the pool; on failure `fail` is the OS failure of `operation`. */
static bool run_transfer(const MsStream *stream, TransferJob *job, const char *operation, MsFsFail *fail) {
    job->fd = stream->fd;
    ms_fs_run(transfer_job, job, fail);
    if (ms_fs_failed(fail)) {
        return false;
    }
    if (job->error != 0) {
        fail_file(stream, fail, operation, job->error);
        return false;
    }
    return true;
}

/* The bytes of `max` (at most one chunk) read at `offset`. */
static bool pread_chunk(const MsStream *stream, int64_t offset, size_t capacity, MsFsBuffer *out, MsFsFail *fail) {
    uint8_t *buffer = malloc(capacity == 0 ? 1 : capacity);
    if (buffer == NULL) {
        fail_memory(fail);
        return false;
    }
    TransferJob job = {.buffer = buffer, .length = capacity, .offset = offset};
    if (!run_transfer(stream, &job, "read", fail)) {
        free(buffer);
        return false;
    }
    out->data = buffer;
    out->length = job.done;
    out->capacity = capacity;
    return true;
}

static void write_bytes_out(MsVec *out, const MsFsBuffer *data) { msrt_write_bytes(out, data->data, data->length); }

uint8_t msstd_fs_file_read_at(void *handle, int64_t offset, uint8_t has_max, int64_t max, MsVec *out, MsStr *err) {
    MsStream *stream = handle;
    MsFsFail fail = {0};
    MsFsBuffer data = {0};
    if (has_max && max <= 0) {
        fail_invalid(&fail);
    } else if (ms_stream_admit(stream, MS_STREAM_READ, &fail)) {
        if (offset < 0) {
            fail_invalid(&fail);
        } else if (pread_chunk(stream, offset, !has_max || max > FILE_CHUNK ? FILE_CHUNK : (size_t)max, &data, &fail)) {
            write_bytes_out(out, &data);
        }
    }
    ms_fs_buffer_free(&data);
    return ms_fs_finish(&fail, err);
}

uint8_t msstd_fs_file_write_at(void *handle, int64_t offset, const MsVec *data, MsStr *err) {
    MsStream *stream = handle;
    MsFsFail fail = {0};
    if (ms_stream_admit(stream, MS_STREAM_WRITE, &fail)) {
        if (offset < 0 || stream->append) {
            fail_invalid(&fail);
        } else {
            TransferJob job = {.data = data->ptr, .length = data->len, .offset = offset, .write = true};
            (void)run_transfer(stream, &job, "write", &fail);
        }
    }
    return ms_fs_finish(&fail, err);
}

/* Reads to the end of the file from the current position, failing past `max` bytes. */
typedef struct ReadFileJob {
    MsSysFd fd;
    int64_t max;
    MsFsBuffer data;
    MsFsFail fail;
} ReadFileJob;

static void read_file_job(void *data) {
    ReadFileJob *job = data;
    MsSysStat stat;
    const bool have_stat = ms_sys_fs_fstat(job->fd, &stat) == 0;
    ms_fs_read_limited(job->fd, job->max, false, have_stat ? &stat : NULL, &job->data, &job->fail);
}

static bool read_to_end(MsStream *stream, int64_t max, MsFsBuffer *out, MsFsFail *fail) {
    if (!ms_stream_admit(stream, MS_STREAM_READ, fail)) {
        return false;
    }
    if (ms_stream_regular(stream)) {
        ReadFileJob job = {.fd = stream->fd, .max = max};
        ms_fs_run(read_file_job, &job, fail);
        if (!ms_fs_failed(fail) && ms_fs_failed(&job.fail)) {
            *fail = job.fail;
            job.fail = (MsFsFail){0};
        }
        ms_fs_fail_free(&job.fail);
        if (ms_fs_failed(fail)) {
            ms_fs_buffer_free(&job.data);
            return false;
        }
        *out = job.data;
    } else {
        MsSysStat stat;
        const bool have_stat = ms_sys_fs_fstat(stream->fd, &stat) == 0;
        ms_fs_read_limited(stream->fd, max, true, have_stat ? &stat : NULL, out, fail);
        if (ms_fs_failed(fail)) {
            return false;
        }
    }
    if (stream->closed) {
        ms_fs_buffer_free(out);
        ms_fs_fail_status(fail, STATUS_CLOSED);
        return false;
    }
    return true;
}

uint8_t msstd_fs_file_read_file(void *handle, uint8_t has_max, int64_t max, MsVec *out, MsStr *err) {
    MsStream *stream = handle;
    MsFsFail fail = {0};
    MsFsBuffer data = {0};
    int64_t limit = 0;
    if (!ms_fs_limit(has_max, max, &limit)) {
        fail_invalid(&fail);
    } else if (read_to_end(stream, limit, &data, &fail)) {
        write_bytes_out(out, &data);
    }
    ms_fs_buffer_free(&data);
    return ms_fs_finish(&fail, err);
}

/* Checks the sizes of a vectored read: each within a part's limit and all within the total. */
static bool sizes_valid(const MsVec *sizes) {
    const int64_t *items = sizes->ptr;
    int64_t total = 0;
    for (size_t i = 0; i < sizes->len; i++) {
        const int64_t size = items[i];
        if (size < 0 || size > FILE_VECTOR_ITEM_LIMIT || total > FILE_VECTOR_TOTAL_LIMIT - size) {
            return false;
        }
        total += size;
    }
    return true;
}

/* One part of a vectored read, at the current position (offset -1) or at `*offset`, which then moves on. */
static bool read_part(MsStream *stream, size_t size, int64_t *offset, MsFsBuffer *out, MsFsFail *fail) {
    if (*offset >= 0) {
        if (!pread_chunk(stream, *offset, size, out, fail)) {
            return false;
        }
        *offset += (int64_t)out->length;
        return true;
    }
    uint8_t *buffer = malloc(size == 0 ? 1 : size);
    if (buffer == NULL) {
        fail_memory(fail);
        return false;
    }
    size_t count = 0;
    if (!ms_stream_read_raw(stream, buffer, size, &count, fail)) {
        free(buffer);
        return false;
    }
    out->data = buffer;
    out->length = count;
    out->capacity = size;
    return true;
}

uint8_t msstd_fs_file_read_vectors(void *handle, const MsVec *sizes, int64_t offset, MsVec *out, MsStr *err) {
    MsStream *stream = handle;
    MsFsFail fail = {0};
    MsVec parts = {0};
    bool started = false;
    if (ms_stream_admit(stream, MS_STREAM_READ, &fail)) {
        if (offset < -1 || !sizes_valid(sizes)) {
            fail_invalid(&fail);
        } else {
            msrt_list_with_capacity(&msrt_desc_bytes, (int64_t)sizes->len, &parts);
            started = true;
        }
    }
    const int64_t *items = sizes->ptr;
    for (size_t i = 0; started && i < sizes->len && !ms_fs_failed(&fail); i++) {
        MsFsBuffer part = {0};
        if (ms_fs_poll_cancel(&fail) || !read_part(stream, (size_t)items[i], &offset, &part, &fail)) {
            ms_fs_buffer_free(&part);
            break;
        }
        MsVec bytes;
        write_bytes_out(&bytes, &part);
        ms_fs_buffer_free(&part);
        msrt_list_push(&parts, &msrt_desc_bytes, &bytes);
    }
    if (started && ms_fs_failed(&fail)) {
        msrt_list_drop(&parts, &msrt_desc_bytes);
    } else if (started) {
        *out = parts;
    }
    return ms_fs_finish(&fail, err);
}

/* Writes all of `data` at the current position: on the pool for a regular file, with a stop check between steps
 * otherwise. */
typedef struct WriteJob {
    MsSysFd fd;
    const uint8_t *data;
    size_t length;
    MsSysError error;
} WriteJob;

static MsSysError write_steps(MsSysFd fd, const uint8_t *data, size_t length, bool cancellable, MsFsFail *fail) {
    size_t done = 0;
    while (done < length) {
        if (cancellable && ms_fs_poll_cancel(fail)) {
            return 0;
        }
        const size_t step = length - done < FILE_CHUNK ? length - done : FILE_CHUNK;
        size_t count = 0;
        const MsSysError error = ms_sys_fs_write(fd, data + done, step, &count);
        if (error != 0) {
            return error;
        }
        if (count == 0) {
            return ms_sys_fs_error_of(MS_SYS_ERR_IO);
        }
        done += count;
    }
    return 0;
}

static void write_job(void *data) {
    WriteJob *job = data;
    MsFsFail unused = {0};
    job->error = write_steps(job->fd, job->data, job->length, false, &unused);
}

static bool write_at_position(const MsStream *stream, const uint8_t *data, size_t length, MsFsFail *fail) {
    MsSysError error = 0;
    if (ms_stream_regular(stream)) {
        WriteJob job = {.fd = stream->fd, .data = data, .length = length};
        ms_fs_run(write_job, &job, fail);
        error = job.error;
    } else {
        error = write_steps(stream->fd, data, length, true, fail);
    }
    if (ms_fs_failed(fail)) {
        return false;
    }
    if (error != 0) {
        fail_file(stream, fail, "write", error);
        return false;
    }
    return true;
}

uint8_t msstd_fs_file_write_vectors(void *handle, const MsVec *buffers, int64_t offset, MsStr *err) {
    MsStream *stream = handle;
    MsFsFail fail = {0};
    const MsVec *items = buffers->ptr;
    if (ms_stream_admit(stream, MS_STREAM_WRITE, &fail)) {
        if (offset < -1 || (offset >= 0 && stream->append)) {
            fail_invalid(&fail);
        }
    }
    for (size_t i = 0; !ms_fs_failed(&fail) && i < buffers->len; i++) {
        if (offset == -1) {
            (void)write_at_position(stream, items[i].ptr, items[i].len, &fail);
        } else {
            TransferJob job = {.data = items[i].ptr, .length = items[i].len, .offset = offset, .write = true};
            (void)run_transfer(stream, &job, "write", &fail);
            offset += (int64_t)items[i].len;
        }
    }
    return ms_fs_finish(&fail, err);
}

/* ---- position, size, metadata ---- */

uint8_t msstd_fs_file_seek(void *handle, int64_t offset, int64_t origin, int64_t *out, MsStr *err) {
    MsStream *stream = handle;
    MsFsFail fail = {0};
    if (ms_stream_admit(stream, MS_STREAM_ANY, &fail)) {
        int64_t position = 0;
        if (origin < 0 || origin > 2 || (offset < 0 && origin == 0)) {
            fail_invalid(&fail);
        } else {
            const MsSysError error = ms_sys_fs_seek(stream->fd, offset, (int32_t)origin, &position);
            if (error != 0) {
                fail_file(stream, &fail, "seek", error);
            } else {
                *out = position;
            }
        }
    }
    return ms_fs_finish(&fail, err);
}

uint8_t msstd_fs_file_stat(void *handle, MsFsInfo *out, MsStr *err) {
    MsStream *stream = handle;
    MsFsFail fail = {0};
    if (ms_stream_admit(stream, MS_STREAM_ANY, &fail)) {
        MsSysStat stat;
        const MsSysError error = ms_sys_fs_fstat(stream->fd, &stat);
        const MsBytes base = ms_fs_path_base(ms_stream_name(stream));
        if (error != 0) {
            fail_file(stream, &fail, "stat", error);
        } else if (!ms_fs_valid_utf8(base)) {
            ms_fs_fail_status(&fail, STATUS_UNSUPPORTED);
        } else {
            ms_fs_info_fill(out, &stat);
            ms_fs_write_string(&out->name, base.ptr, base.len);
        }
    }
    return ms_fs_finish(&fail, err);
}

uint8_t msstd_fs_file_truncate(void *handle, int64_t size, MsStr *err) {
    MsStream *stream = handle;
    MsFsFail fail = {0};
    if (ms_stream_admit(stream, MS_STREAM_WRITE, &fail)) {
        const MsSysError error = size < 0 ? 0 : ms_sys_fs_truncate_fd(stream->fd, size);
        if (size < 0) {
            fail_invalid(&fail);
        } else if (error != 0) {
            fail_file(stream, &fail, "truncate", error);
        }
    }
    return ms_fs_finish(&fail, err);
}

/* Runs a call over the descriptor of an admitted stream. */
typedef MsSysError (*DescriptorCall)(MsSysFd fd);

static uint8_t simple_call(void *handle, DescriptorCall call, const char *operation, MsStr *err) {
    MsStream *stream = handle;
    MsFsFail fail = {0};
    if (ms_stream_admit(stream, MS_STREAM_ANY, &fail)) {
        const MsSysError error = call(stream->fd);
        if (error != 0) {
            fail_file(stream, &fail, operation, error);
        }
    }
    return ms_fs_finish(&fail, err);
}

uint8_t msstd_fs_file_sync(void *handle, MsStr *err) { return simple_call(handle, ms_sys_fs_sync, "sync", err); }

uint8_t msstd_fs_file_data_sync(void *handle, MsStr *err) { return simple_call(handle, ms_sys_fs_data_sync, "sync", err); }

uint8_t msstd_fs_file_unlock(void *handle, MsStr *err) { return simple_call(handle, ms_sys_fs_unlock, "unlock", err); }

/* Tries an advisory lock on the whole file; 0 in `*out` when another handle holds a conflicting one. */
uint8_t msstd_fs_file_try_lock(void *handle, uint8_t exclusive, int64_t *out, MsStr *err) {
    MsStream *stream = handle;
    MsFsFail fail = {0};
    if (ms_stream_admit(stream, MS_STREAM_ANY, &fail)) {
        bool taken = false;
        const MsSysError error = ms_sys_fs_try_lock(stream->fd, exclusive != 0, &taken);
        if (error != 0) {
            fail_file(stream, &fail, "lock", error);
        } else {
            *out = taken ? 1 : 0;
        }
    }
    return ms_fs_finish(&fail, err);
}

uint8_t msstd_fs_file_chmod(void *handle, int64_t mode, MsStr *err) {
    MsStream *stream = handle;
    MsFsFail fail = {0};
    if (ms_stream_admit(stream, MS_STREAM_ANY, &fail)) {
        if (mode < 0 || mode > FILE_MAX_PERMISSIONS) {
            fail_invalid(&fail);
        } else {
            const MsSysError error = ms_sys_fs_chmod_fd(stream->fd, (uint32_t)mode);
            if (error != 0) {
                fail_file(stream, &fail, "chmod", error);
            }
        }
    }
    return ms_fs_finish(&fail, err);
}

uint8_t msstd_fs_file_chown(void *handle, int64_t uid, int64_t gid, MsStr *err) {
    MsStream *stream = handle;
    MsFsFail fail = {0};
    if (ms_stream_admit(stream, MS_STREAM_ANY, &fail)) {
        if (uid < -1 || gid < -1 || uid > FILE_MAX_OWNER || gid > FILE_MAX_OWNER) {
            fail_invalid(&fail);
        } else {
            const MsSysError error = ms_sys_fs_chown_fd(stream->fd, uid, gid);
            if (error != 0) {
                fail_file(stream, &fail, "chown", error);
            }
        }
    }
    return ms_fs_finish(&fail, err);
}

uint8_t msstd_fs_file_set_times(void *handle, const MsFsTimestamp *accessed, const MsFsTimestamp *modified, MsStr *err) {
    MsStream *stream = handle;
    MsFsFail fail = {0};
    if (ms_stream_admit(stream, MS_STREAM_ANY, &fail)) {
        const MsSysTime access_time = {accessed->seconds, accessed->nanos};
        const MsSysTime modify_time = {modified->seconds, modified->nanos};
        const MsSysError error = ms_sys_fs_set_times_fd(stream->fd, access_time, modify_time);
        if (error != 0) {
            fail_file(stream, &fail, "chtimes", error);
        }
    }
    return ms_fs_finish(&fail, err);
}

/* ---- lines ---- */

/* The remaining text split on `\n`, a trailing `\r` removed from each terminated line; a final unterminated segment
 * keeps a trailing `\r` as content. Counts the lines first so a limit fails before anything is built. */
static size_t count_lines(MsBytes data, bool *terminated) {
    size_t lines = 0;
    size_t start = 0;
    *terminated = true;
    for (size_t i = 0; i < data.len; i++) {
        if (data.ptr[i] == '\n') {
            lines += 1;
            start = i + 1;
        }
    }
    if (start < data.len) {
        lines += 1;
        *terminated = false;
    }
    return lines;
}

static void write_lines(MsBytes data, bool terminated, MsVec *out) {
    size_t start = 0;
    for (size_t i = 0; i <= data.len; i++) {
        const bool at_newline = i < data.len && data.ptr[i] == '\n';
        if (!at_newline && i < data.len) {
            continue;
        }
        if (!at_newline && start == data.len) {
            break;
        }
        size_t end = i;
        if (at_newline || terminated) {
            if (end > start && data.ptr[end - 1] == '\r') {
                end -= 1;
            }
        }
        MsStr line;
        msrt_string_from_bytes(data.ptr + start, end - start, &line);
        msrt_list_push(out, &msrt_desc_string, &line);
        start = i + 1;
    }
}

uint8_t msstd_fs_file_read_lines(void *handle, int64_t max_bytes, int64_t max_lines, MsVec *out, MsStr *err) {
    MsStream *stream = handle;
    MsFsFail fail = {0};
    MsFsBuffer data = {0};
    if (max_bytes < 0 || max_lines < 0) {
        fail_invalid(&fail);
    } else if (read_to_end(stream, max_bytes, &data, &fail)) {
        const MsBytes text = ms_fs_buffer_view(&data);
        bool terminated = true;
        const size_t lines = count_lines(text, &terminated);
        if (!ms_fs_valid_utf8(text)) {
            ms_fs_fail_status(&fail, STATUS_INVALID_DATA);
        } else if ((int64_t)lines > max_lines) {
            ms_fs_fail_status(&fail, STATUS_LIMIT_EXCEEDED);
        } else {
            msrt_list_with_capacity(&msrt_desc_string, (int64_t)lines, out);
            write_lines(text, terminated, out);
        }
    }
    ms_fs_buffer_free(&data);
    return ms_fs_finish(&fail, err);
}
