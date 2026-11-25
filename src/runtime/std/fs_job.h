/* runtime/std/fs_job.h: what the @std/fs natives share. Each native fills an MsFsJob, runs one function over it on the
 * blocking pool (ms_fs_run) and turns the outcome into a status plus text. A job runs where the scheduler is off limits,
 * so it works on its own data and the native copies the result into runtime values afterwards. Borrowed arguments are
 * safe in a job: the wait is shielded. Host errors are libuv statuses. */
#ifndef MS_RUNTIME_STD_FS_JOB_H
#define MS_RUNTIME_STD_FS_JOB_H

#include <uv.h>

#include "base/path.h"
#include "base/ostext.h"
#include "base/strbuild.h"
#include "runtime/std/fail.h"
#include "runtime/std/fs.h"

typedef struct MsFsJob {
  MsSpan path;
  MsSpan other; /* a second path, a link target or the bytes to write */
  int64_t number;
  int64_t second_number;
  uint8_t flag;
  MsFsTimestamp times[2]; /* accessed, modified */
  MsFail fail;
  /* results */
  MsStrBuild text;
  MsBytes data; /* a whole file read */
  uv_stat_t stat;
  uv_statfs_t filesystem;
  bool found;
  bool not_regular; /* a whole-file job found something that is not a regular file */
  void *handle;     /* what a handle operation works on */
} MsFsJob;

MsFsJob ms_fs_job(const MsString *path);
/* Ends a native: frees the job, then returns its status with `err` filled (ms_fail_finish_at). A stop request is
 * delivered by unwinding, which never returns, so the job is freed first; the caller must not touch it afterwards. */
uint8_t ms_fs_job_finish(MsFsJob *job, MsSpan detail, MsString *err);
/* The same for an operation on two paths: a status that names them reports `a -> b`. */
uint8_t ms_fs_job_finish_pair(MsFsJob *job, MsString *err);

/* Runs `run(job)` on the blocking pool (inline on a pool thread). The wait is shielded, so `job` may live on the
 * caller's stack; a stop request takes effect once the job is done and is reported as a failure of the job. */
void ms_fs_run(MsFsJob *job, void (*run)(void *job));

/* `path` as OS text: non-empty and without a NUL. Otherwise the job fails as invalid and false is returned. */
MS_NODISCARD bool ms_fs_open_path(MsFsJob *job, MsSpan path, MsOsText *out);

/* The job fails with a libuv status of `operation` on `path`. */
void ms_fs_job_fail(MsFsJob *job, int code, const char *operation, MsSpan path);

/* Appends `bytes` with every invalid UTF-8 sequence replaced by U+FFFD, so one odd name does not make its directory
 * unlistable. */
void ms_fs_append_lossy(MsStrBuild *out, MsSpan bytes);

/* A String made of `text`, or the failure of a name that is not UTF-8. */
MS_NODISCARD bool ms_fs_text_ok(MsSpan bytes);

/* ---- operations the fs files share ---- */

/* The kind bits of a FileInfo and the fill of one (everything but the name) from a stat. */
void ms_fs_info_fill(MsFsInfo *out, const uv_stat_t *stat);
bool ms_fs_is_directory(const uv_stat_t *stat);
bool ms_fs_is_regular(const uv_stat_t *stat);
bool ms_fs_is_link(const uv_stat_t *stat);
bool ms_fs_same_file(const uv_stat_t *a, const uv_stat_t *b);

/* Runs one libuv call to its end: a synchronous request, cleaned up. Each returns 0 or a negative UV_* code. */
int ms_fs_stat_path(const char *path, bool follow, uv_stat_t *out);
/* The same for a path as bytes: UV_EINVAL for an empty path or one with a NUL. */
int ms_fs_stat_bytes(MsSpan path, bool follow, uv_stat_t *out);
int ms_fs_fstat(uv_file fd, uv_stat_t *out);
int ms_fs_remove_one(const char *path);
/* A directory with permissions 0700. */
int ms_fs_make_directory(const char *path);
int ms_fs_realpath(const char *path, MsStrBuild *out);

/* Removes the tree at `path` without following links; a missing path is already removed. */
void ms_fs_remove_tree(MsFail *fail, MsSpan path);
/* A new directory in the temporary directory named from `pattern` (a `*` marks the random digits); its path is left in
 * `out`. */
bool ms_fs_make_temporary_directory(MsFail *fail, MsSpan pattern, MsStrBuild *out);

/* Reads to the end of `fd` into `out`, failing with MS_STATUS_LIMIT_EXCEEDED past `max` bytes. A cancellable read checks
 * for a stop request between reads (a pool thread must not) and waits for a pipe or device to be readable. `at` is the
 * offset to read from, advanced by what is read; NULL reads from the descriptor's own position. */
void ms_fs_read_limited(uv_file fd, int64_t max, bool cancellable, const uv_stat_t *stat, int64_t *at, MsBytes *out,
                        MsFail *fail);

/* An optional size limit: unset is unlimited, a negative one invalid. */
MS_NODISCARD bool ms_fs_limit(uint8_t present, int64_t value, int64_t *out);

#define MS_FS_UNLIMITED INT64_MAX

/* Whether a listing entry (its name, and the libuv `type` the listing gave) is a directory or a symbolic link: its own
 * kind, or an lstat of `directory`/name when the filesystem gives none. */
void ms_fs_entry_kind(MsSpan directory, MsSpan name, int type, bool *is_directory, bool *is_symlink);

#endif
