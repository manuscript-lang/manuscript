/* @std/fs file handles: open, positioned and vectored transfers, seek, sync, locks, permissions and line reads over the
 * host stream of stream.c. Operations on a regular file run on the blocking pool; each failure is the OS failure of the
 * operation on the path the file was opened with. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include <string.h>

#include "base/alloc.h"
#include "base/utf8.h"
#include "runtime/core/unwind.h"
#include "runtime/io/pool.h"
#include "runtime/std/fs_job.h"
#include "runtime/std/stream.h"
#include "runtime/sys/fs.h"

enum {
  FILE_CHUNK = 65536,
  FILE_MAX_PERMISSIONS = 07777,
  FILE_VECTOR_ITEM_LIMIT = 65536,
  FILE_VECTOR_TOTAL_LIMIT = 16 * 1024 * 1024,
  FILE_MAX_OWNER = 2147483647
};

static MsStream *stream_of(MsObj *handle) { return (MsStream *)handle; }

/* An OS failure of `operation` on the file's path. */
static void fail_file(const MsStream *stream, MsFail *fail, const char *operation, int code) {
  ms_fail_uv(fail, code, operation, ms_string_span(&stream->name));
}

/* ---- opening ---- */

/* The libuv flags of a mode string of `open`; false for an unknown mode. */
static bool flags_of_mode(MsSpan mode, int *flags) {
  static const struct {
    const char *text;
    int flags;
  } modes[] = {
      {"r", UV_FS_O_RDONLY},
      {"r+", UV_FS_O_RDWR},
      {"w", UV_FS_O_WRONLY | UV_FS_O_CREAT | UV_FS_O_TRUNC},
      {"wx", UV_FS_O_WRONLY | UV_FS_O_CREAT | UV_FS_O_EXCL},
      {"w+", UV_FS_O_RDWR | UV_FS_O_CREAT | UV_FS_O_TRUNC},
      {"wx+", UV_FS_O_RDWR | UV_FS_O_CREAT | UV_FS_O_EXCL},
      {"a", UV_FS_O_WRONLY | UV_FS_O_CREAT | UV_FS_O_APPEND},
      {"ax", UV_FS_O_WRONLY | UV_FS_O_CREAT | UV_FS_O_APPEND | UV_FS_O_EXCL},
      {"a+", UV_FS_O_RDWR | UV_FS_O_CREAT | UV_FS_O_APPEND},
      {"ax+", UV_FS_O_RDWR | UV_FS_O_CREAT | UV_FS_O_APPEND | UV_FS_O_EXCL},
  };
  for (size_t i = 0; i < sizeof modes / sizeof modes[0]; i++) {
    if (ms_span_is_text(mode, modes[i].text)) {
      *flags = modes[i].flags;
      return true;
    }
  }
  return false;
}

static int open_path_fd(const char *path, int flags, int mode) {
  uv_fs_t request;
  const int fd = uv_fs_open(NULL, &request, path, flags, mode, NULL);
  uv_fs_req_cleanup(&request);
  return fd;
}

/* Opens the job's path with the flags and permissions in `number` and `second_number`. A named pipe opened for reading
 * would block in open until a writer arrives, so it is opened without waiting; reads wait for data. */
static void open_job(void *data) {
  MsFsJob *job = data;
  MsOsText path;
  if (!ms_fs_open_path(job, job->path, &path)) {
    return;
  }
  const int flags = (int)job->number;
  uv_stat_t info;
  const bool reading = (flags & (UV_FS_O_WRONLY | UV_FS_O_RDWR)) == 0;
  const bool is_fifo = reading && ms_fs_stat_path(path.ptr, true, &info) == 0 && (info.st_mode & 0170000u) == 0010000u;
  const int fd = open_path_fd(path.ptr, is_fifo ? flags | UV_FS_O_NONBLOCK : flags, (int)job->second_number);
  ms_os_text_free(&path);
  if (fd < 0) {
    ms_fs_job_fail(job, fd, "open", job->path);
    return;
  }
  job->handle = (void *)(intptr_t)fd;
  job->found = true;
}

uint8_t msstd_fs_open(const MsString *path, const MsString *mode_text, int64_t mode, MsObj **out, MsString *err) {
  MsFsJob job = ms_fs_job(path);
  int flags = 0;
  if (!flags_of_mode(ms_string_span(mode_text), &flags) || mode < 0 || mode > FILE_MAX_PERMISSIONS) {
    ms_fail_status(&job.fail, MS_STATUS_INVALID_INPUT);
  } else {
    job.number = flags;
    job.second_number = mode;
    ms_fs_run(&job, open_job);
  }
  if (job.found && !ms_fail_failed(&job.fail)) {
    *out = &ms_stream_file((uv_file)(intptr_t)job.handle, flags, job.path)->header;
  }
  const uint8_t status = ms_fail_finish_at(&job.fail, job.path, err);
  ms_fs_job_free(&job);
  return status;
}

uint8_t msstd_fs_file_clone(const MsObj *handle, MsObj **out, MsString *err) {
  const MsStream *stream = (const MsStream *)(const void *)handle;
  MsFail fail = ms_fail_new();
  MsStream *copy = NULL;
  if (stream->closed) {
    ms_fail_status(&fail, MS_STATUS_CLOSED);
  } else if (ms_stream_duplicate(stream, &copy, &fail)) {
    *out = &copy->header;
  }
  return ms_fail_finish(&fail, err);
}

/* ---- positioned and vectored transfers ---- */

typedef struct TransferJob {
  uv_file fd;
  uint8_t *buffer;     /* a positioned read fills it */
  const uint8_t *data; /* a positioned write sends it */
  size_t length;
  int64_t offset;
  size_t done;
  int error; /* a libuv status; 0 when none */
  bool write;
} TransferJob;

/* Reads until the buffer is full or the file ends, or writes all of the data: positioned transfers need a seekable file,
 * so they always run where a short transfer is retried. */
static void transfer_job(void *data) {
  TransferJob *job = data;
  while (job->done < job->length && job->error == 0) {
    const size_t step = job->length - job->done < FILE_CHUNK ? job->length - job->done : FILE_CHUNK;
    const int64_t at = job->offset + (int64_t)job->done;
    const uv_buf_t buffer = uv_buf_init(job->write ? (char *)(uintptr_t)(job->data + job->done) : (char *)(job->buffer + job->done),
                                        (unsigned)step);
    uv_fs_t request;
    const int64_t count = job->write ? uv_fs_write(NULL, &request, job->fd, &buffer, 1, at, NULL)
                                     : uv_fs_read(NULL, &request, job->fd, &buffer, 1, at, NULL);
    uv_fs_req_cleanup(&request);
    if (count < 0) {
      job->error = (int)count;
    } else if (count == 0) {
      if (job->write) {
        job->error = UV_EIO;
      }
      return;
    } else {
      job->done += (size_t)count;
    }
  }
}

/* Runs a positioned transfer on the pool; on failure `fail` is the OS failure of `operation`. */
static bool run_transfer(const MsStream *stream, TransferJob *job, const char *operation, MsFail *fail) {
  job->fd = stream->fd;
  if (ms_pool_on_thread()) {
    transfer_job(job);
  } else if (ms_pool_run_shielded(transfer_job, job) != MS_POOL_DONE) {
    ms_fail_text(fail, "cancelled");
    return false;
  }
  if (job->error != 0) {
    fail_file(stream, fail, operation, job->error);
    return false;
  }
  return true;
}

/* The bytes of at most one chunk read at `offset`, into `out`. */
static bool pread_chunk(const MsStream *stream, int64_t offset, size_t capacity, MsBytes *out, MsFail *fail) {
  uint8_t *buffer = ms_alloc(capacity == 0 ? 1 : capacity);
  TransferJob job = {.buffer = buffer, .length = capacity, .offset = offset};
  if (!run_transfer(stream, &job, "read", fail)) {
    ms_free(buffer);
    return false;
  }
  *out = (MsBytes){.ptr = buffer, .len = job.done, .cap = capacity == 0 ? 1 : capacity};
  return true;
}

uint8_t msstd_fs_file_read_at(MsObj *handle, int64_t offset, uint8_t has_max, int64_t max, MsBytes *out, MsString *err) {
  MsStream *stream = stream_of(handle);
  MsFail fail = ms_fail_new();
  if (has_max && max <= 0) {
    ms_fail_status(&fail, MS_STATUS_INVALID_INPUT);
  } else if (ms_stream_admit(stream, MS_STREAM_READ, &fail)) {
    if (offset < 0) {
      ms_fail_status(&fail, MS_STATUS_INVALID_INPUT);
    } else {
      (void)pread_chunk(stream, offset, !has_max || max > FILE_CHUNK ? FILE_CHUNK : (size_t)max, out, &fail);
    }
  }
  return ms_fail_finish(&fail, err);
}

uint8_t msstd_fs_file_write_at(MsObj *handle, int64_t offset, const MsBytes *data, MsString *err) {
  MsStream *stream = stream_of(handle);
  MsFail fail = ms_fail_new();
  if (ms_stream_admit(stream, MS_STREAM_WRITE, &fail)) {
    if (offset < 0 || stream->append) {
      ms_fail_status(&fail, MS_STATUS_INVALID_INPUT);
    } else {
      TransferJob job = {.data = data->ptr, .length = data->len, .offset = offset, .write = true};
      (void)run_transfer(stream, &job, "write", &fail);
    }
  }
  return ms_fail_finish(&fail, err);
}

/* Reads to the end of the file from the current position, failing past `max` bytes. */
typedef struct ReadFileJob {
  uv_file fd;
  int64_t at; /* the tracked position, or -1 */
  int64_t max;
  MsBytes data;
  MsFail fail;
} ReadFileJob;

static void read_file_job(void *data) {
  ReadFileJob *job = data;
  uv_stat_t stat;
  const bool have_stat = ms_fs_fstat(job->fd, &stat) == 0;
  ms_fs_read_limited(job->fd, job->max, false, have_stat ? &stat : NULL, job->at < 0 ? NULL : &job->at, &job->data,
                     &job->fail);
}

static bool read_to_end(MsStream *stream, int64_t max, MsBytes *out, MsFail *fail) {
  if (!ms_stream_admit(stream, MS_STREAM_READ, fail)) {
    return false;
  }
  if (!stream->waitable) {
    ReadFileJob job = {.fd = stream->fd, .at = ms_stream_offset(stream), .max = max, .fail = ms_fail_new()};
    if (ms_pool_on_thread()) {
      read_file_job(&job);
    } else if (ms_pool_run_shielded(read_file_job, &job) != MS_POOL_DONE) {
      ms_fail_text(&job.fail, "cancelled");
    }
    if (job.at >= 0) {
      atomic_store(&stream->file->at, job.at);
    }
    if (ms_fail_failed(&job.fail)) {
      *fail = job.fail;
      ms_bytes_free(&job.data);
      return false;
    }
    *out = job.data;
  } else {
    uv_stat_t stat;
    const bool have_stat = ms_fs_fstat(stream->fd, &stat) == 0;
    int64_t at = ms_stream_offset(stream);
    ms_fs_read_limited(stream->fd, max, true, have_stat ? &stat : NULL, at < 0 ? NULL : &at, out, fail);
    if (at >= 0) {
      atomic_store(&stream->file->at, at);
    }
    if (ms_fail_failed(fail)) {
      return false;
    }
  }
  if (stream->closed) {
    ms_bytes_free(out);
    ms_fail_status(fail, MS_STATUS_CLOSED);
    return false;
  }
  return true;
}

uint8_t msstd_fs_file_read_file(MsObj *handle, uint8_t has_max, int64_t max, MsBytes *out, MsString *err) {
  MsFail fail = ms_fail_new();
  int64_t limit = 0;
  if (!ms_fs_limit(has_max, max, &limit)) {
    ms_fail_status(&fail, MS_STATUS_INVALID_INPUT);
  } else {
    (void)read_to_end(stream_of(handle), limit, out, &fail);
  }
  return ms_fail_finish(&fail, err);
}

/* Checks the sizes of a vectored read: each within a part's limit and all within the total. */
static bool sizes_valid(const MsList *sizes) {
  const int64_t *items = (const int64_t *)(const void *)sizes->ptr;
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
static bool read_part(MsStream *stream, size_t size, int64_t *offset, MsBytes *out, MsFail *fail) {
  if (*offset >= 0) {
    if (!pread_chunk(stream, *offset, size, out, fail)) {
      return false;
    }
    *offset += (int64_t)out->len;
    return true;
  }
  uint8_t *buffer = ms_alloc(size == 0 ? 1 : size);
  size_t count = 0;
  if (!ms_stream_read_raw(stream, buffer, size, &count, fail)) {
    ms_free(buffer);
    return false;
  }
  *out = (MsBytes){.ptr = buffer, .len = count, .cap = size == 0 ? 1 : size};
  return true;
}

static void parts_free(MsList *parts) {
  MsBytes *items = (MsBytes *)(void *)parts->ptr;
  for (size_t i = 0; i < parts->len; i++) {
    ms_bytes_free(&items[i]);
  }
  ms_list_free(parts);
}

uint8_t msstd_fs_file_read_vectors(MsObj *handle, const MsList *sizes, int64_t offset, MsList *out, MsString *err) {
  MsStream *stream = stream_of(handle);
  MsFail fail = ms_fail_new();
  MsList parts = {0};
  bool started = false;
  if (ms_stream_admit(stream, MS_STREAM_READ, &fail)) {
    if (offset < -1 || !sizes_valid(sizes)) {
      ms_fail_status(&fail, MS_STATUS_INVALID_INPUT);
    } else {
      ms_list_reserve(&parts, sizeof(MsBytes), sizes->len);
      started = true;
    }
  }
  const int64_t *items = (const int64_t *)(const void *)sizes->ptr;
  for (size_t i = 0; started && i < sizes->len && !ms_fail_failed(&fail); i++) {
    MsBytes part = {0};
    if (ms_fail_poll_cancel(&fail) || !read_part(stream, (size_t)items[i], &offset, &part, &fail)) {
      break;
    }
    ms_list_push(&parts, sizeof part, &part);
  }
  if (started && ms_fail_failed(&fail)) {
    parts_free(&parts);
  } else if (started) {
    *out = parts;
  }
  return ms_fail_finish(&fail, err);
}

/* Writes all of `data` at the current position: on the pool for a file that cannot be waited on, with a stop check
 * between steps otherwise. */
typedef struct WriteJob {
  uv_file fd;
  int64_t at; /* the tracked position, advanced by what was written; -1: the descriptor's own */
  const uint8_t *data;
  size_t length;
  int error;
} WriteJob;

static int write_steps(uv_file fd, const uint8_t *data, size_t length, int64_t *at, bool cancellable, MsFail *fail) {
  size_t done = 0;
  while (done < length) {
    if (cancellable && ms_fail_poll_cancel(fail)) {
      return 0;
    }
    const size_t step = length - done < FILE_CHUNK ? length - done : FILE_CHUNK;
    const uv_buf_t buffer = uv_buf_init((char *)(uintptr_t)(data + done), (unsigned)step);
    uv_fs_t request;
    const int64_t count = uv_fs_write(NULL, &request, fd, &buffer, 1, *at, NULL);
    uv_fs_req_cleanup(&request);
    if (count < 0) {
      return (int)count;
    }
    if (count == 0) {
      return UV_EIO;
    }
    done += (size_t)count;
    if (*at >= 0) {
      *at += count;
    }
  }
  return 0;
}

static void write_job(void *data) {
  WriteJob *job = data;
  MsFail unused = ms_fail_new();
  job->error = write_steps(job->fd, job->data, job->length, &job->at, false, &unused);
}

static bool write_at_position(const MsStream *stream, const uint8_t *data, size_t length, MsFail *fail) {
  int error = 0;
  const int64_t start = ms_stream_offset(stream);
  int64_t at = stream->append ? -1 : start;
  if (!stream->waitable) {
    WriteJob job = {.fd = stream->fd, .at = at, .data = data, .length = length};
    if (ms_pool_on_thread()) {
      write_job(&job);
    } else if (ms_pool_run_shielded(write_job, &job) != MS_POOL_DONE) {
      ms_fail_text(fail, "cancelled");
      return false;
    }
    error = job.error;
    at = job.at;
  } else {
    error = write_steps(stream->fd, data, length, &at, true, fail);
  }
  ms_stream_advance(stream, start, stream->append ? 0 : at - start, true);
  if (ms_fail_failed(fail)) {
    return false;
  }
  if (error != 0) {
    fail_file(stream, fail, "write", error);
    return false;
  }
  return true;
}

uint8_t msstd_fs_file_write_vectors(MsObj *handle, const MsList *buffers, int64_t offset, MsString *err) {
  MsStream *stream = stream_of(handle);
  MsFail fail = ms_fail_new();
  const MsBytes *items = (const MsBytes *)(const void *)buffers->ptr;
  if (ms_stream_admit(stream, MS_STREAM_WRITE, &fail)) {
    if (offset < -1 || (offset >= 0 && stream->append)) {
      ms_fail_status(&fail, MS_STATUS_INVALID_INPUT);
    }
  }
  for (size_t i = 0; !ms_fail_failed(&fail) && i < buffers->len; i++) {
    if (offset == -1) {
      (void)write_at_position(stream, items[i].ptr, items[i].len, &fail);
    } else {
      TransferJob job = {.data = items[i].ptr, .length = items[i].len, .offset = offset, .write = true};
      (void)run_transfer(stream, &job, "write", &fail);
      offset += (int64_t)items[i].len;
    }
  }
  return ms_fail_finish(&fail, err);
}

/* ---- position, size, metadata ---- */

/* Moves the tracked position: `origin` is 0 (start), 1 (current) or 2 (end). A descriptor without one cannot seek. */
static int seek_position(const MsStream *stream, int64_t offset, int origin, int64_t *out) {
  if (!ms_stream_tracked(stream)) {
    return UV_ESPIPE;
  }
  int64_t base = 0;
  if (origin == 1) {
    base = atomic_load(&stream->file->at);
  } else if (origin == 2) {
    uv_stat_t stat;
    const int code = ms_fs_fstat(stream->fd, &stat);
    if (code != 0) {
      return code;
    }
    base = (int64_t)stat.st_size;
  }
  if ((offset > 0 && base > INT64_MAX - offset) || base + offset < 0) {
    return UV_EINVAL;
  }
  *out = base + offset;
  atomic_store(&stream->file->at, *out);
  return 0;
}

uint8_t msstd_fs_file_seek(MsObj *handle, int64_t offset, int64_t origin, int64_t *out, MsString *err) {
  MsStream *stream = stream_of(handle);
  MsFail fail = ms_fail_new();
  if (ms_stream_admit(stream, MS_STREAM_ANY, &fail)) {
    if (origin < 0 || origin > 2 || (offset < 0 && origin == 0)) {
      ms_fail_status(&fail, MS_STATUS_INVALID_INPUT);
    } else {
      const int code = seek_position(stream, offset, (int)origin, out);
      if (code != 0) {
        fail_file(stream, &fail, "seek", code);
      }
    }
  }
  return ms_fail_finish(&fail, err);
}

uint8_t msstd_fs_file_stat(MsObj *handle, MsFsInfo *out, MsString *err) {
  MsStream *stream = stream_of(handle);
  MsFail fail = ms_fail_new();
  if (ms_stream_admit(stream, MS_STREAM_ANY, &fail)) {
    uv_stat_t stat;
    const int code = ms_fs_fstat(stream->fd, &stat);
    const MsSpan base = ms_path_base(ms_string_span(&stream->name));
    if (code != 0) {
      fail_file(stream, &fail, "stat", code);
    } else if (!ms_fs_text_ok(base)) {
      ms_fail_status(&fail, MS_STATUS_UNSUPPORTED);
    } else {
      ms_fs_info_fill(out, &stat);
      out->name = ms_string_from_span(base);
    }
  }
  return ms_fail_finish(&fail, err);
}

uint8_t msstd_fs_file_truncate(MsObj *handle, int64_t size, MsString *err) {
  MsStream *stream = stream_of(handle);
  MsFail fail = ms_fail_new();
  if (ms_stream_admit(stream, MS_STREAM_WRITE, &fail)) {
    if (size < 0) {
      ms_fail_status(&fail, MS_STATUS_INVALID_INPUT);
    } else {
      uv_fs_t request;
      const int code = uv_fs_ftruncate(NULL, &request, stream->fd, size, NULL);
      uv_fs_req_cleanup(&request);
      if (code != 0) {
        fail_file(stream, &fail, "truncate", code);
      }
    }
  }
  return ms_fail_finish(&fail, err);
}

/* Runs a call over the descriptor of an admitted stream. */
typedef int (*DescriptorCall)(uv_file fd);

static int sync_call(uv_file fd) {
  uv_fs_t request;
  const int code = uv_fs_fsync(NULL, &request, fd, NULL);
  uv_fs_req_cleanup(&request);
  return code;
}

static int data_sync_call(uv_file fd) {
  uv_fs_t request;
  const int code = uv_fs_fdatasync(NULL, &request, fd, NULL);
  uv_fs_req_cleanup(&request);
  return code;
}

static uint8_t simple_call(MsObj *handle, DescriptorCall call, const char *operation, MsString *err) {
  MsStream *stream = stream_of(handle);
  MsFail fail = ms_fail_new();
  if (ms_stream_admit(stream, MS_STREAM_ANY, &fail)) {
    const int code = call(stream->fd);
    if (code != 0) {
      fail_file(stream, &fail, operation, code);
    }
  }
  return ms_fail_finish(&fail, err);
}

uint8_t msstd_fs_file_sync(MsObj *handle, MsString *err) { return simple_call(handle, sync_call, "sync", err); }

uint8_t msstd_fs_file_data_sync(MsObj *handle, MsString *err) {
  return simple_call(handle, data_sync_call, "sync", err);
}

uint8_t msstd_fs_file_unlock(MsObj *handle, MsString *err) {
  return simple_call(handle, ms_sys_fs_unlock, "unlock", err);
}

/* Tries an advisory lock on the whole file; 0 in `*out` when another handle holds a conflicting one. */
uint8_t msstd_fs_file_try_lock(MsObj *handle, uint8_t exclusive, int64_t *out, MsString *err) {
  MsStream *stream = stream_of(handle);
  MsFail fail = ms_fail_new();
  if (ms_stream_admit(stream, MS_STREAM_ANY, &fail)) {
    bool taken = false;
    const int code = ms_sys_fs_try_lock(stream->fd, exclusive != 0, &taken);
    if (code != 0) {
      fail_file(stream, &fail, "lock", code);
    } else {
      *out = taken ? 1 : 0;
    }
  }
  return ms_fail_finish(&fail, err);
}

uint8_t msstd_fs_file_chmod(MsObj *handle, int64_t mode, MsString *err) {
  MsStream *stream = stream_of(handle);
  MsFail fail = ms_fail_new();
  if (ms_stream_admit(stream, MS_STREAM_ANY, &fail)) {
    if (mode < 0 || mode > FILE_MAX_PERMISSIONS) {
      ms_fail_status(&fail, MS_STATUS_INVALID_INPUT);
    } else {
      uv_fs_t request;
      const int code = uv_fs_fchmod(NULL, &request, stream->fd, (int)mode, NULL);
      uv_fs_req_cleanup(&request);
      if (code != 0) {
        fail_file(stream, &fail, "chmod", code);
      }
    }
  }
  return ms_fail_finish(&fail, err);
}

uint8_t msstd_fs_file_chown(MsObj *handle, int64_t uid, int64_t gid, MsString *err) {
  MsStream *stream = stream_of(handle);
  MsFail fail = ms_fail_new();
  if (ms_stream_admit(stream, MS_STREAM_ANY, &fail)) {
    if (uid < -1 || gid < -1 || uid > FILE_MAX_OWNER || gid > FILE_MAX_OWNER) {
      ms_fail_status(&fail, MS_STATUS_INVALID_INPUT);
    } else {
      uv_fs_t request;
      const int code = uv_fs_fchown(NULL, &request, stream->fd, (uv_uid_t)uid, (uv_gid_t)gid, NULL);
      uv_fs_req_cleanup(&request);
      if (code != 0) {
        fail_file(stream, &fail, "chown", code);
      }
    }
  }
  return ms_fail_finish(&fail, err);
}

uint8_t msstd_fs_file_set_times(MsObj *handle, const MsFsTimestamp *accessed, const MsFsTimestamp *modified,
                                MsString *err) {
  MsStream *stream = stream_of(handle);
  MsFail fail = ms_fail_new();
  if (ms_stream_admit(stream, MS_STREAM_ANY, &fail)) {
    const int code =
        ms_sys_fs_set_times_fd(stream->fd, accessed->seconds, accessed->nanos, modified->seconds, modified->nanos);
    if (code != 0) {
      fail_file(stream, &fail, "chtimes", code);
    }
  }
  return ms_fail_finish(&fail, err);
}

/* ---- lines ---- */

/* The remaining text split on `\n`, a trailing `\r` removed from each terminated line; a final unterminated segment
 * keeps a trailing `\r` as content. Counts the lines first so a limit fails before anything is built. */
static size_t count_lines(MsSpan data, bool *terminated) {
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

static void write_lines(MsSpan data, bool terminated, MsList *out) {
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
    if ((at_newline || terminated) && end > start && data.ptr[end - 1] == '\r') {
      end -= 1;
    }
    const MsString line = ms_string_from_span(ms_span_of(data.ptr + start, end - start));
    ms_list_push(out, sizeof line, &line);
    start = i + 1;
  }
}

uint8_t msstd_fs_file_read_lines(MsObj *handle, int64_t max_bytes, int64_t max_lines, MsList *out, MsString *err) {
  MsFail fail = ms_fail_new();
  MsBytes data = {0};
  if (max_bytes < 0 || max_lines < 0) {
    ms_fail_status(&fail, MS_STATUS_INVALID_INPUT);
  } else if (read_to_end(stream_of(handle), max_bytes, &data, &fail)) {
    const MsSpan text = ms_bytes_span(&data);
    bool terminated = true;
    const size_t lines = count_lines(text, &terminated);
    if (!ms_fs_text_ok(text)) {
      ms_fail_status(&fail, MS_STATUS_INVALID_DATA);
    } else if ((int64_t)lines > max_lines) {
      ms_fail_status(&fail, MS_STATUS_LIMIT_EXCEEDED);
    } else {
      ms_list_reserve(out, sizeof(MsString), lines);
      write_lines(text, terminated, out);
    }
  }
  ms_bytes_free(&data);
  return ms_fail_finish(&fail, err);
}
