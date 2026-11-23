/* Whole-file @std/fs natives: read_file, write_file and append_file. A regular file is read or written on the blocking
 * pool; anything else (a FIFO, a device, a directory) on the runtime thread, where waiting for data can be cancelled. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include <limits.h>

#include "base/alloc.h"
#include "runtime/core/task.h"
#include "runtime/io/pool.h"
#include "runtime/std/fs_job.h"

enum { READ_CHUNK = 32 * 1024, READ_LARGEST = 1 << 20, READ_KNOWN_LIMIT = 1 << 28, WRITE_STEP = 65536, WRITE_JOB_STEP = 1 << 20 };

/* ---- libuv calls, run to their end ---- */

static int open_file(const char *path, int flags, int mode) {
  uv_fs_t request;
  const int fd = uv_fs_open(NULL, &request, path, flags, mode, NULL);
  uv_fs_req_cleanup(&request);
  return fd;
}

static int close_file(uv_file fd) {
  uv_fs_t request;
  const int code = uv_fs_close(NULL, &request, fd, NULL);
  uv_fs_req_cleanup(&request);
  return code;
}

int ms_fs_fstat(uv_file fd, uv_stat_t *out) {
  uv_fs_t request;
  const int code = uv_fs_fstat(NULL, &request, fd, NULL);
  if (code == 0) {
    *out = request.statbuf;
  }
  uv_fs_req_cleanup(&request);
  return code;
}

/* A read or write of up to `size` bytes at `at` (-1: the descriptor's own position): the count, or a negative
 * status. */
static int64_t transfer(uv_file fd, uint8_t *bytes, size_t size, bool writing, int64_t at) {
  const unsigned count = size > (size_t)INT_MAX ? (unsigned)INT_MAX : (unsigned)size;
  const uv_buf_t buffer = uv_buf_init((char *)bytes, count);
  uv_fs_t request;
  const int64_t done =
      writing ? uv_fs_write(NULL, &request, fd, &buffer, 1, at, NULL) : uv_fs_read(NULL, &request, fd, &buffer, 1, at, NULL);
  uv_fs_req_cleanup(&request);
  return done;
}

bool ms_fs_is_regular(const uv_stat_t *stat) { return (stat->st_mode & 0170000u) == 0100000u; }
bool ms_fs_is_directory(const uv_stat_t *stat) { return (stat->st_mode & 0170000u) == 0040000u; }

/* ---- reading ---- */

/* Parks until `fd` can be read, so a pipe with no data yet neither stalls the other tasks nor ignores a stop request. */
static bool wait_readable(uv_file fd, MsFail *fail) {
#ifdef _WIN32
  (void)fd;
  (void)fail;
  return true;
#else
  if ((ms_task_wait_fd(fd, MS_WAIT_READ, -1) & MS_WAIT_CANCELLED) != 0) {
    ms_fail_text(fail, "cancelled");
    return false;
  }
  return true;
#endif
}

/* Called before each park of a wait that loops: a stop request fails, and so does a bounded read whose time has passed,
 * because a park past that limit returns at once and a loop that only retried would spin. */
static bool check_wait(MsFail *fail) {
  if (ms_fail_poll_cancel(fail)) {
    return false;
  }
  if (ms_task_read_limit_passed()) {
    ms_fail_status(fail, MS_STATUS_TIMED_OUT);
    return false;
  }
  return true;
}

/* The first buffer size: what a regular file says it holds, within the limits, plus the byte that detects excess. */
static size_t first_capacity(const uv_stat_t *stat, size_t max_size) {
  size_t first = 0;
  if (stat != NULL && ms_fs_is_regular(stat)) {
    const size_t known = stat->st_size > 0 ? (size_t)stat->st_size : 0;
    first = known < max_size ? known : max_size;
    first = first < READ_KNOWN_LIMIT ? first : READ_KNOWN_LIMIT;
  } else {
    first = max_size < READ_CHUNK - 1 ? max_size : READ_CHUNK - 1;
  }
  return first + 1;
}

void ms_fs_read_limited(uv_file fd, int64_t max, bool cancellable, const uv_stat_t *stat, int64_t *at, MsBytes *out,
                        MsFail *fail) {
  const size_t max_size = max > (int64_t)(SIZE_MAX / 2) ? SIZE_MAX / 2 : (size_t)max;
  size_t capacity = first_capacity(stat, max_size);
  uint8_t *buffer = ms_alloc(capacity);
  size_t filled = 0;
  const bool waits = cancellable && stat != NULL && !ms_fs_is_regular(stat);
  for (;;) {
    if (cancellable && !check_wait(fail)) {
      break;
    }
    if (waits && !wait_readable(fd, fail)) {
      break;
    }
    const int64_t remaining = max - (int64_t)filled;
    if (filled == capacity) {
      /* Full and not at the end: double, within the one byte past `max` that detects excess. */
      size_t grown = capacity * 2 > READ_CHUNK ? capacity * 2 : READ_CHUNK;
      if (grown > max_size + 1) {
        grown = max_size + 1;
      }
      buffer = ms_realloc(buffer, grown);
      capacity = grown;
    }
    size_t room = capacity - filled;
    room = room < READ_LARGEST ? room : READ_LARGEST;
    const size_t want = remaining < (int64_t)room ? (size_t)remaining + 1 : room;
    const int64_t count = transfer(fd, buffer + filled, want, false, at == NULL ? -1 : *at);
    if (count < 0) {
      ms_fail_status(fail, MS_STATUS_INVALID_DATA);
      break;
    }
    if (count > remaining) {
      ms_fail_status(fail, MS_STATUS_LIMIT_EXCEEDED);
      break;
    }
    if (count == 0) {
      *out = (MsBytes){.ptr = buffer, .len = filled, .cap = capacity};
      return;
    }
    filled += (size_t)count;
    if (at != NULL) {
      *at += count;
    }
  }
  ms_free(buffer);
}

/* Opens `path` for a pool job and says when it is not a regular file, which the caller then runs on the runtime
 * thread, where a wait can be cancelled. */
static bool open_regular(MsFsJob *job, int flags, uv_file *fd, uv_stat_t *stat) {
  MsOsText path;
  if (!ms_fs_open_path(job, job->path, &path)) {
    return false;
  }
  const int opened = open_file(path.ptr, flags | UV_FS_O_NONBLOCK, 0600);
  ms_os_text_free(&path);
  if (opened == UV_ENXIO) { /* a FIFO without a reader */
    job->not_regular = true;
    return false;
  }
  if (opened < 0) {
    ms_fs_job_fail(job, opened, "open", job->path);
    return false;
  }
  *fd = opened;
  if (ms_fs_fstat(*fd, stat) == 0 && ms_fs_is_regular(stat)) {
    return true;
  }
  (void)close_file(*fd);
  job->not_regular = true;
  return false;
}

static void read_whole_job(void *data) {
  MsFsJob *job = data;
  uv_file fd = -1;
  uv_stat_t stat;
  if (!open_regular(job, UV_FS_O_RDONLY, &fd, &stat)) {
    return;
  }
  ms_fs_read_limited(fd, job->number, false, &stat, NULL, &job->data, &job->fail);
  (void)close_file(fd);
}

/* The same read on the runtime thread, for anything but a regular file. */
static void read_whole_here(MsFsJob *job) {
  MsOsText path;
  if (!ms_fs_open_path(job, job->path, &path)) {
    return;
  }
  /* A named pipe opened for reading would block in open until a writer arrives, so it is opened without waiting;
   * reads wait for data through wait_readable. */
  const int fd = open_file(path.ptr, UV_FS_O_RDONLY | UV_FS_O_NONBLOCK, 0);
  ms_os_text_free(&path);
  if (fd < 0) {
    ms_fs_job_fail(job, fd, "open", job->path);
    return;
  }
  uv_stat_t stat;
  const bool have_stat = ms_fs_fstat(fd, &stat) == 0;
  if (have_stat && ms_fs_is_directory(&stat)) {
    ms_fail_status(&job->fail, MS_STATUS_INVALID_INPUT);
  } else {
    ms_fs_read_limited(fd, job->number, true, have_stat ? &stat : NULL, NULL, &job->data, &job->fail);
  }
  (void)close_file(fd);
}

uint8_t msstd_fs_read_file(const MsString *path, uint8_t has_max, int64_t max, MsBytes *out, MsString *err) {
  MsFsJob job = ms_fs_job(path);
  if (!ms_fs_limit(has_max, max, &job.number)) {
    ms_fail_status(&job.fail, MS_STATUS_INVALID_INPUT);
  } else if (!ms_pool_on_thread()) {
    ms_fs_run(&job, read_whole_job);
    if (job.not_regular && !ms_fail_failed(&job.fail)) {
      read_whole_here(&job);
    }
  } else {
    read_whole_here(&job);
  }
  if (!ms_fail_failed(&job.fail)) {
    *out = job.data;
    job.data = (MsBytes){0};
  }
  const uint8_t status = ms_fs_job_finish(&job, job.path, err);
  return status;
}

/* ---- writing ---- */

/* Writes all of `data`, in small steps when cancellable so a stop request is seen between them. */
static void write_all(uv_file fd, MsSpan data, MsSpan path, bool cancellable, MsFail *fail) {
  const size_t step = cancellable ? WRITE_STEP : WRITE_JOB_STEP;
  size_t done = 0;
  while (done < data.len) {
    if (cancellable && ms_fail_poll_cancel(fail)) {
      return;
    }
    const size_t end = data.len - done < step ? data.len - done : step;
    const int64_t count = transfer(fd, (uint8_t *)(uintptr_t)data.ptr + done, end, true, -1);
    if (count < 0) {
      ms_fail_uv(fail, (int)count, "write", path);
      return;
    }
    if (count == 0) {
      ms_fail_text(fail, "short write");
      return;
    }
    done += (size_t)count;
  }
}

/* Closes after a write: the write's own failure wins over a failed close. */
static void close_after_write(uv_file fd, MsSpan path, MsFail *fail) {
  const int code = close_file(fd);
  if (code != 0 && !ms_fail_failed(fail)) {
    ms_fail_uv(fail, code, "close", path);
  }
}

static void write_whole_job(void *data) {
  MsFsJob *job = data;
  uv_file fd = -1;
  uv_stat_t stat;
  if (!open_regular(job, UV_FS_O_WRONLY | UV_FS_O_CREAT | (int)job->number, &fd, &stat)) {
    return;
  }
  write_all(fd, job->other, job->path, false, &job->fail);
  close_after_write(fd, job->path, &job->fail);
}

static void write_whole_here(MsFsJob *job) {
  MsOsText path;
  if (!ms_fs_open_path(job, job->path, &path)) {
    return;
  }
  const int fd = open_file(path.ptr, UV_FS_O_WRONLY | UV_FS_O_CREAT | (int)job->number, 0600);
  ms_os_text_free(&path);
  if (fd < 0) {
    ms_fs_job_fail(job, fd, "open", job->path);
    return;
  }
  write_all(fd, job->other, job->path, true, &job->fail);
  close_after_write(fd, job->path, &job->fail);
}

static uint8_t write_with(const MsString *path, const MsBytes *data, int flags, MsString *err) {
  MsFsJob job = ms_fs_job(path);
  job.other = ms_bytes_span(data);
  job.number = flags;
  if (!ms_pool_on_thread()) {
    ms_fs_run(&job, write_whole_job);
    if (job.not_regular && !ms_fail_failed(&job.fail)) {
      write_whole_here(&job);
    }
  } else {
    write_whole_here(&job);
  }
  const uint8_t status = ms_fs_job_finish(&job, job.path, err);
  return status;
}

uint8_t msstd_fs_write_file(const MsString *path, const MsBytes *data, uint8_t replace, MsString *err) {
  return write_with(path, data, replace != 0 ? UV_FS_O_TRUNC : UV_FS_O_EXCL, err);
}

uint8_t msstd_fs_append_file(const MsString *path, const MsBytes *data, MsString *err) {
  return write_with(path, data, UV_FS_O_APPEND, err);
}
