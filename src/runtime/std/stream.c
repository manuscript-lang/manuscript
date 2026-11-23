/* The host stream over a file descriptor (stream.h). */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "runtime/std/stream.h"

#include <limits.h>

#include "base/alloc.h"
#include "runtime/core/task.h"
#include "runtime/io/pool.h"
#include "runtime/io/stdout.h"
#include "runtime/std/fs_job.h"
#include "runtime/sys/fs.h"

static void stream_drop(MsObj *object) {
  MsStream *stream = (MsStream *)object;
  MsFail ignored = ms_fail_new();
  (void)ms_stream_close(stream, &ignored);
  ms_fail_free(&ignored);
  ms_string_release(&stream->name);
  ms_free(stream);
}

MsStream *ms_stream_new(uv_file fd, bool owned, MsSpan name) {
  MsStream *stream = ms_alloc_zeroed(sizeof *stream);
  stream->header.drop = stream_drop;
  stream->fd = fd;
  stream->owned = owned;
  stream->waitable = ms_sys_fs_waitable(fd);
  stream->name = ms_string_from_span(name);
  return stream;
}

MsStream *ms_stream_file(uv_file fd, int flags, MsSpan name) {
  MsStream *stream = ms_stream_new(fd, true, name);
  const int access = flags & (UV_FS_O_WRONLY | UV_FS_O_RDWR);
  stream->no_read = access == UV_FS_O_WRONLY;
  stream->no_write = access == 0;
  stream->append = (flags & UV_FS_O_APPEND) != 0;
  uv_stat_t stat;
  stream->file = ms_alloc_zeroed(sizeof *stream->file);
  stream->file->tracked = ms_fs_fstat(fd, &stat) == 0 && ms_fs_is_regular(&stat);
  atomic_store(&stream->file->references, 1);
  return stream;
}

bool ms_stream_duplicate(const MsStream *stream, MsStream **out, MsFail *fail) {
  if (stream->file == NULL || stream->closed) {
    ms_fail_status(fail, stream->closed ? MS_STATUS_CLOSED : MS_STATUS_UNSUPPORTED);
    return false;
  }
  MsStream *copy = ms_stream_new(stream->fd, true, ms_string_span(&stream->name));
  copy->waitable = stream->waitable;
  copy->no_read = stream->no_read;
  copy->no_write = stream->no_write;
  copy->append = stream->append;
  copy->file = stream->file;
  atomic_fetch_add(&copy->file->references, 1);
  *out = copy;
  return true;
}

bool ms_stream_close(MsStream *stream, MsFail *fail) {
  if (stream->closed) {
    return true;
  }
  stream->closed = true;
  if (!stream->owned) {
    return true;
  }
  if (stream->file != NULL) {
    MsOpenFile *const file = stream->file;
    stream->file = NULL;
    if (atomic_fetch_sub(&file->references, 1) != 1) {
      return true; /* another stream still uses the descriptor */
    }
    ms_free(file);
  }
  uv_fs_t request;
  const int code = uv_fs_close(NULL, &request, stream->fd, NULL);
  uv_fs_req_cleanup(&request);
  if (code != 0) {
    ms_fail_uv_text(fail, code, "close", ms_string_span(&stream->name));
    return false;
  }
  return true;
}

bool ms_stream_admit(const MsStream *stream, MsStreamAccess access, MsFail *fail) {
  if (stream->closed) {
    ms_fail_status(fail, MS_STATUS_CLOSED);
    return false;
  }
  if (ms_fail_poll_cancel(fail)) {
    return false;
  }
  if ((access == MS_STREAM_READ && stream->no_read) || (access == MS_STREAM_WRITE && stream->no_write)) {
    ms_fail_status(fail, MS_STATUS_INVALID_INPUT);
    return false;
  }
  return true;
}

/* ---- transfers ---- */

typedef struct RawJob {
  uv_file fd;
  int64_t at;          /* the offset, or -1 for the descriptor's own position */
  uint8_t *buffer;     /* for a read */
  const uint8_t *data; /* for a write */
  size_t length;       /* capacity of the buffer, or bytes of data */
  int64_t result;      /* the count, or a negative libuv status */
  bool write;
} RawJob;

enum { STREAM_CHUNK = 64 * 1024 }; /* the most a read takes and a write sends at once */

static void raw_job(void *data) {
  RawJob *job = data;
  const unsigned size = job->length > (size_t)INT_MAX ? (unsigned)INT_MAX : (unsigned)job->length;
  const uv_buf_t buffer = uv_buf_init(job->write ? (char *)(uintptr_t)job->data : (char *)job->buffer, size);
  uv_fs_t request;
  job->result = job->write ? uv_fs_write(NULL, &request, job->fd, &buffer, 1, job->at, NULL)
                           : uv_fs_read(NULL, &request, job->fd, &buffer, 1, job->at, NULL);
  uv_fs_req_cleanup(&request);
}

/* Parks until the descriptor is ready. Ready, hung up or failed all return: the next transfer reports the details. */
static bool wait_ready(const MsStream *stream, bool for_write, MsFail *fail) {
  if (!stream->waitable) {
    return !ms_fail_poll_cancel(fail);
  }
  const uint32_t got = ms_task_wait_fd(stream->fd, for_write ? MS_WAIT_WRITE : MS_WAIT_READ, -1);
  if ((got & MS_WAIT_CANCELLED) != 0) {
    ms_fail_text(fail, "cancelled");
    return false;
  }
  return true;
}

bool ms_stream_tracked(const MsStream *stream) { return stream->file != NULL && stream->file->tracked; }

int64_t ms_stream_offset(const MsStream *stream) {
  return ms_stream_tracked(stream) ? atomic_load(&stream->file->at) : -1;
}

void ms_stream_advance(const MsStream *stream, int64_t offset, int64_t count, bool write) {
  if (!ms_stream_tracked(stream)) {
    return;
  }
  int64_t end = offset + count;
  if (write && stream->append) {
    uv_stat_t stat;
    if (ms_fs_fstat(stream->fd, &stat) == 0) {
      end = (int64_t)stat.st_size;
    }
  }
  atomic_store(&stream->file->at, end);
}

static bool transfer(const MsStream *stream, RawJob *job, const char *operation, size_t *count, MsFail *fail) {
  job->fd = stream->fd;
  const int64_t offset = ms_stream_offset(stream);
  job->at = job->write && stream->append ? -1 : offset;
  do {
    if (!wait_ready(stream, job->write, fail)) {
      return false;
    }
    if (!stream->waitable && !ms_pool_on_thread()) {
      if (ms_pool_run_shielded(raw_job, job) != MS_POOL_DONE) {
        ms_fail_text(fail, "cancelled");
        return false;
      }
    } else {
      raw_job(job);
    }
  } while (job->result == UV_EAGAIN); /* a non-blocking descriptor that was not ready after all */
  if (job->result < 0) {
    ms_fail_uv_text(fail, (int)job->result, operation, ms_string_span(&stream->name));
    return false;
  }
  *count = (size_t)job->result;
  ms_stream_advance(stream, offset, job->result, job->write);
  return true;
}

bool ms_stream_read_raw(const MsStream *stream, uint8_t *buffer, size_t length, size_t *count, MsFail *fail) {
  RawJob job = {.buffer = buffer, .length = length};
  return transfer(stream, &job, "read", count, fail);
}

bool ms_stream_write_raw(const MsStream *stream, const uint8_t *data, size_t length, size_t *count, MsFail *fail) {
  RawJob job = {.data = data, .length = length, .write = true};
  return transfer(stream, &job, "write", count, fail);
}

bool ms_stream_read(MsStream *stream, bool has_max, int64_t max, MsBytes *out, bool *eof, MsFail *fail) {
  if (!ms_stream_admit(stream, MS_STREAM_READ, fail)) {
    return false;
  }
  if (has_max && max <= 0) {
    ms_fail_status(fail, MS_STATUS_INVALID_INPUT);
    return false;
  }
  const size_t wanted = !has_max || max > STREAM_CHUNK ? STREAM_CHUNK : (size_t)max;
  uint8_t *buffer = ms_alloc(wanted);
  size_t count = 0;
  if (!ms_stream_read_raw(stream, buffer, wanted, &count, fail)) {
    ms_free(buffer);
    return false;
  }
  *eof = count == 0;
  *out = ms_bytes_from_span(ms_span_of(buffer, count));
  ms_free(buffer);
  return true;
}

bool ms_stream_write(MsStream *stream, MsSpan data, MsFail *fail) {
  if (!ms_stream_admit(stream, MS_STREAM_WRITE, fail)) {
    return false;
  }
  if (stream->fd >= 1 && stream->fd <= 2) {
    ms_stdout_flush(); /* what the program printed comes first */
  }
  size_t done = 0;
  while (done < data.len) {
    size_t count = 0;
    const size_t step = data.len - done < STREAM_CHUNK ? data.len - done : STREAM_CHUNK;
    if (!ms_stream_write_raw(stream, data.ptr + done, step, &count, fail)) {
      return false;
    }
    if (count == 0) {
      ms_fail_text(fail, "short write");
      return false;
    }
    done += count;
  }
  return true;
}
