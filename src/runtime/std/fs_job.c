/* The shared parts of the @std/fs natives (fs_job.h): the job record, the pool wrapper, validated paths and the text of
 * names. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "runtime/core/fault_abi.h"
#include "runtime/std/fs_job.h"

#include "base/utf8.h"
#include "runtime/core/task.h"
#include "runtime/core/unwind.h"
#include "runtime/io/pool.h"

MsFsJob ms_fs_job(const MsString *path) {
  MsFsJob job = {.path = ms_string_span(path), .fail = ms_fail_new(), .text = ms_strbuild_new()};
  return job;
}

static void ms_fs_job_free(MsFsJob *job) {
  ms_fail_free(&job->fail);
  ms_strbuild_free(&job->text);
  ms_bytes_free(&job->data);
}

uint8_t ms_fs_job_finish(MsFsJob *job, MsSpan detail, MsString *err) {
  MsFail fail = job->fail;
  job->fail = ms_fail_new();
  ms_fs_job_free(job);
  return ms_fail_finish_at(&fail, detail, err);
}

uint8_t ms_fs_job_finish_pair(MsFsJob *job, MsString *err) {
  MsStrBuild both = ms_strbuild_new();
  ms_strbuild_append(&both, job->path);
  ms_strbuild_append_text(&both, " -> ");
  ms_strbuild_append(&both, job->other);
  MsFail fail = job->fail;
  job->fail = ms_fail_new();
  ms_fs_job_free(job);
  const uint8_t status = ms_fail_finish_at(&fail, ms_strbuild_span(&both), err);
  ms_strbuild_free(&both);
  return status;
}

void ms_fs_run(MsFsJob *job, void (*run)(void *job)) {
  /* The only task has nothing to keep running while the call blocks, and handing the job to the pool and back
   * costs two thread wake-ups (about 50 microseconds, most of a small file read). */
  if (ms_pool_on_thread() || ms_task_count() <= 1) {
    run(job);
    return;
  }
  if (ms_pool_run_shielded(run, job) != MS_POOL_DONE) {
    ms_fail_text(&job->fail, "cancelled");
  }
}

bool ms_fs_open_path(MsFsJob *job, MsSpan path, MsOsText *out) {
  size_t at = 0;
  if (path.len == 0 || ms_span_find(path, ms_span_of((const uint8_t *)"\0", 1), &at)) {
    ms_fail_status(&job->fail, MS_STATUS_INVALID_INPUT);
    return false;
  }
  *out = ms_os_text_new(path);
  return true;
}

void ms_fs_job_fail(MsFsJob *job, int code, const char *operation, MsSpan path) {
  ms_fail_uv(&job->fail, code, operation, path);
}

bool ms_fs_text_ok(MsSpan bytes) { return ms_utf8_is_valid(bytes.ptr, bytes.len); }

void ms_fs_append_lossy(MsStrBuild *out, MsSpan bytes) {
  size_t at = 0;
  while (at < bytes.len) {
    const MsRune rune = ms_utf8_decode(bytes.ptr + at, bytes.len - at);
    if (rune.rune == MS_RUNE_ERROR && !(rune.width == 3 && bytes.ptr[at] == 0xEF)) {
      ms_strbuild_append_utf8(out, MS_RUNE_ERROR);
    } else {
      ms_strbuild_append(out, ms_span_of(bytes.ptr + at, rune.width));
    }
    at += rune.width;
  }
}

bool ms_fs_limit(uint8_t present, int64_t value, int64_t *out) {
  if (present == 0) {
    *out = MS_FS_UNLIMITED;
    return true;
  }
  *out = value;
  return value >= 0;
}

/* ---- blocking-pool admission ---- */


uint8_t msstd_fs_admit(int64_t bytes) {
  bool cancelled = false;
  const bool held = ms_pool_admit(bytes > 0 ? (size_t)bytes : 0, &cancelled);
  if (cancelled) {
    ms_cancel_deliver();
    return 0;
  }
  return held ? 1 : 0;
}

void msstd_fs_release(void) { ms_pool_release(); }
