/* The path-changing @std/fs natives: directories, removal, rename, links, canonical paths, temporary directories and
 * attributes. Each validates its arguments, runs its libuv calls on the blocking pool and turns the outcome into a
 * status plus text (fs_job.h). */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include <string.h>

#include "base/alloc.h"
#include "runtime/std/fs_job.h"
#include "runtime/sys/fs.h"

enum { MAX_DEPTH = 4096 };

/* ---- libuv calls, run to their end ---- */

int ms_fs_make_directory(const char *path) {
  uv_fs_t request;
  const int code = uv_fs_mkdir(NULL, &request, path, 0700, NULL);
  uv_fs_req_cleanup(&request);
  return code;
}

static int remove_file(const char *path) {
  uv_fs_t request;
  const int code = uv_fs_unlink(NULL, &request, path, NULL);
  uv_fs_req_cleanup(&request);
  return code;
}

static int remove_directory(const char *path) {
  uv_fs_t request;
  const int code = uv_fs_rmdir(NULL, &request, path, NULL);
  uv_fs_req_cleanup(&request);
  return code;
}

/* os.Remove: the path as a file, then as an empty directory. */
int ms_fs_remove_one(const char *path) {
  const int first = remove_file(path);
  if (first == 0) {
    return 0;
  }
  const int second = remove_directory(path);
  if (second == 0) {
    return 0;
  }
  return second == UV_ENOTDIR ? first : second;
}

/* The absolute, canonical form of an existing path, appended to `out`. */
int ms_fs_realpath(const char *path, MsStrBuild *out) {
  uv_fs_t request;
  const int code = uv_fs_realpath(NULL, &request, path, NULL);
  if (code == 0) {
    ms_strbuild_append_text(out, (const char *)request.ptr);
  }
  uv_fs_req_cleanup(&request);
  return code;
}

/* The working directory, appended to `out`. */
static int working_directory(MsStrBuild *out) {
  char buffer[1024];
  size_t size = sizeof buffer;
  int code = uv_cwd(buffer, &size);
  if (code == 0) {
    ms_strbuild_append(out, ms_span_of((const uint8_t *)buffer, size));
    return 0;
  }
  if (code != UV_ENOBUFS) {
    return code;
  }
  char *big = ms_alloc(size);
  code = uv_cwd(big, &size);
  if (code == 0) {
    ms_strbuild_append(out, ms_span_of((const uint8_t *)big, size));
  }
  ms_free(big);
  return code;
}

/* ---- directories ---- */

static bool is_directory_at(const char *path) {
  uv_stat_t stat;
  return ms_fs_stat_path(path, true, &stat) == 0 && ms_fs_is_directory(&stat);
}

/* Creates `path` and its missing ancestors; an existing directory is not an error. */
static int make_directories(MsSpan path, size_t depth) {
  MsOsText text = ms_os_text_new(path);
  int code = ms_fs_make_directory(text.ptr);
  if (code == UV_ENOENT && depth < MAX_DEPTH) {
    MsStrBuild parent = ms_strbuild_new();
    ms_fs_path_dir(path, &parent);
    const MsSpan up = ms_strbuild_span(&parent);
    if (up.len > 0 && !ms_span_equal(up, path)) {
      code = make_directories(up, depth + 1);
      if (code == 0) {
        code = ms_fs_make_directory(text.ptr);
      }
    }
    ms_strbuild_free(&parent);
  }
  if (code != 0 && code != UV_ENOENT && is_directory_at(text.ptr)) {
    code = 0;
  }
  ms_os_text_free(&text);
  return code;
}

static void create_directory_job(void *data) {
  MsFsJob *job = data;
  MsOsText path;
  if (!ms_fs_open_path(job, job->path, &path)) {
    return;
  }
  const int code = job->flag != 0 ? make_directories(job->path, 0) : ms_fs_make_directory(path.ptr);
  ms_os_text_free(&path);
  if (code != 0) {
    ms_fs_job_fail(job, code, "mkdir", job->path);
  }
}

uint8_t msstd_fs_create_directory(const MsString *path, uint8_t recursive, MsString *err) {
  MsFsJob job = ms_fs_job(path);
  job.flag = recursive;
  ms_fs_run(&job, create_directory_job);
  const uint8_t status = ms_fail_finish_at(&job.fail, job.path, err);
  ms_fs_job_free(&job);
  return status;
}

/* ---- removal ---- */

/* `parent/name`, the child of a directory. */
static void child_path(MsSpan parent, const char *name, MsStrBuild *out) {
  ms_strbuild_append(out, parent);
  if (parent.len == 0 || !ms_fs_is_separator(parent.ptr[parent.len - 1])) {
    ms_strbuild_append_byte(out, ms_fs_separator());
  }
  ms_strbuild_append_text(out, name);
}

static int remove_tree_at(MsSpan path, size_t depth, MsFail *fail);

/* Removes what one directory entry names: a directory with its contents, anything else as a file. */
static int remove_entry(MsSpan directory, const uv_dirent_t *entry, size_t depth, MsFail *fail) {
  MsStrBuild child = ms_strbuild_new();
  child_path(directory, entry->name, &child);
  MsOsText text = ms_os_text_new(ms_strbuild_span(&child));
  uv_stat_t stat;
  int code = ms_fs_stat_path(text.ptr, false, &stat);
  if (code == 0 && ms_fs_is_directory(&stat)) {
    code = depth < MAX_DEPTH ? remove_tree_at(ms_strbuild_span(&child), depth + 1, fail) : UV_EIO;
  } else if (code == 0 || code != UV_ENOENT) {
    code = remove_file(text.ptr);
  } else {
    code = 0;
  }
  ms_os_text_free(&text);
  ms_strbuild_free(&child);
  return code;
}

/* Removes the directory tree at `path` without following links. */
static int remove_tree_at(MsSpan path, size_t depth, MsFail *fail) {
  MsOsText text = ms_os_text_new(path);
  uv_fs_t request;
  int code = uv_fs_scandir(NULL, &request, text.ptr, 0, NULL);
  if (code >= 0) {
    code = 0;
    uv_dirent_t entry;
    while (code == 0 && uv_fs_scandir_next(&request, &entry) != UV_EOF) {
      if (ms_fail_poll_cancel(fail)) {
        code = UV_EIO;
        break;
      }
      code = remove_entry(path, &entry, depth, fail);
    }
  }
  uv_fs_req_cleanup(&request);
  if (code == 0) {
    code = remove_directory(text.ptr);
  }
  ms_os_text_free(&text);
  return code;
}

void ms_fs_remove_tree(MsFail *fail, MsSpan path) {
  if (ms_fail_poll_cancel(fail)) {
    return;
  }
  MsOsText text = ms_os_text_new(path);
  uv_stat_t stat;
  int code = ms_fs_stat_path(text.ptr, false, &stat);
  if (code != 0) {
    ms_os_text_free(&text);
    if (code != UV_ENOENT) {
      ms_fail_uv(fail, code, "lstat", path);
    }
    return;
  }
  code = ms_fs_is_directory(&stat) ? remove_tree_at(path, 0, fail) : remove_file(text.ptr);
  ms_os_text_free(&text);
  if (code != 0 && !ms_fail_failed(fail)) {
    ms_fail_uv(fail, code, "remove", path);
  }
}

/* `given` as an absolute, cleaned path without trailing separators in `joined`; the root itself is refused as invalid. */
static bool removal_candidate(MsSpan given, MsSpan cwd, MsStrBuild *joined, MsFail *fail) {
  MsStrBuild clean = ms_strbuild_new();
  MsStrBuild parent = ms_strbuild_new();
  if (ms_fs_is_absolute(given)) {
    ms_strbuild_append(joined, given);
  } else {
    ms_fs_path_join(cwd, given, joined);
  }
  ms_fs_path_clean(ms_strbuild_span(joined), &clean);
  ms_fs_path_dir(ms_strbuild_span(&clean), &parent);
  bool ok = false;
  if (ms_span_equal(ms_strbuild_span(&parent), ms_strbuild_span(&clean))) {
    ms_fail_status(fail, MS_STATUS_INVALID_INPUT);
  } else {
    while (joined->bytes.len > 1 && ms_fs_is_separator(joined->bytes.ptr[joined->bytes.len - 1])) {
      joined->bytes.len--;
    }
    ok = true;
  }
  ms_strbuild_free(&clean);
  ms_strbuild_free(&parent);
  return ok;
}

/* Fails `fail` as invalid when `info` is the directory at `start` or one of its ancestors. */
static bool refuse_ancestors(const uv_stat_t *info, MsSpan start, MsFail *fail) {
  MsStrBuild ancestor = ms_strbuild_new();
  ms_strbuild_append(&ancestor, start);
  bool ok = true;
  for (;;) {
    MsOsText at = ms_os_text_new(ms_strbuild_span(&ancestor));
    uv_stat_t up;
    const int code = ms_fs_stat_path(at.ptr, true, &up);
    ms_os_text_free(&at);
    if (code != 0) {
      ms_fail_uv(fail, code, "stat", ms_strbuild_span(&ancestor));
      ok = false;
      break;
    }
    if (ms_fs_same_file(info, &up)) {
      ms_fail_status(fail, MS_STATUS_INVALID_INPUT);
      ok = false;
      break;
    }
    MsStrBuild next = ms_strbuild_new();
    ms_fs_path_dir(ms_strbuild_span(&ancestor), &next);
    const bool done = ms_span_equal(ms_strbuild_span(&next), ms_strbuild_span(&ancestor));
    ms_strbuild_free(&ancestor);
    ancestor = next;
    if (done) {
      break;
    }
  }
  ms_strbuild_free(&ancestor);
  return ok;
}

/* The path to remove, in `out`: refuses the working directory, its ancestors and the root before anything is touched. */
static bool removal_path(MsSpan given, MsStrBuild *out, MsFail *fail) {
  const MsSpan base_name = ms_fs_path_base(given);
  if (given.len == 0 || ms_span_is_text(base_name, ".") || ms_span_is_text(base_name, "..")) {
    ms_fail_status(fail, MS_STATUS_INVALID_INPUT);
    return false;
  }
  MsStrBuild cwd = ms_strbuild_new();
  if (working_directory(&cwd) != 0) {
    ms_strbuild_free(&cwd);
    ms_fail_status(fail, MS_STATUS_INVALID_INPUT);
    return false;
  }
  MsStrBuild joined = ms_strbuild_new();
  MsStrBuild canonical = ms_strbuild_new();
  bool ok = removal_candidate(given, ms_strbuild_span(&cwd), &joined, fail);
  if (ok) {
    MsOsText cwd_text = ms_os_text_new(ms_strbuild_span(&cwd));
    const int code = ms_fs_realpath(cwd_text.ptr, &canonical);
    ms_os_text_free(&cwd_text);
    if (code != 0) {
      ms_fail_uv(fail, code, "lstat", ms_strbuild_span(&cwd));
      ok = false;
    }
  }
  if (ok) {
    MsOsText target = ms_os_text_new(ms_strbuild_span(&joined));
    uv_stat_t info;
    const int code = ms_fs_stat_path(target.ptr, false, &info);
    ms_os_text_free(&target);
    if (code != 0 && code != UV_ENOENT) {
      ms_fail_uv(fail, code, "lstat", ms_strbuild_span(&joined));
      ok = false;
    } else if (code == 0 && ms_fs_is_directory(&info)) {
      ok = refuse_ancestors(&info, ms_strbuild_span(&canonical), fail);
    }
  }
  if (ok) {
    *out = joined;
    joined = ms_strbuild_new();
  }
  ms_strbuild_free(&cwd);
  ms_strbuild_free(&joined);
  ms_strbuild_free(&canonical);
  return ok;
}

static void remove_job(void *data) {
  MsFsJob *job = data;
  MsOsText check;
  if (!ms_fs_open_path(job, job->path, &check)) {
    return;
  }
  ms_os_text_free(&check);
  MsStrBuild target = ms_strbuild_new();
  if (!removal_path(job->path, &target, &job->fail)) {
    ms_strbuild_free(&target);
    return;
  }
  if (job->flag != 0) {
    ms_fs_remove_tree(&job->fail, ms_strbuild_span(&target));
  } else {
    MsOsText text = ms_os_text_new(ms_strbuild_span(&target));
    const int code = ms_fs_remove_one(text.ptr);
    ms_os_text_free(&text);
    if (code != 0) {
      ms_fs_job_fail(job, code, "remove", ms_strbuild_span(&target));
    }
  }
  ms_strbuild_free(&target);
}

uint8_t msstd_fs_remove(const MsString *path, uint8_t recursive, MsString *err) {
  MsFsJob job = ms_fs_job(path);
  job.flag = recursive;
  ms_fs_run(&job, remove_job);
  const uint8_t status = ms_fail_finish_at(&job.fail, job.path, err);
  ms_fs_job_free(&job);
  return status;
}

/* ---- rename and links ---- */

typedef int (*PairCall)(const char *first, const char *second);

static int rename_call(const char *source, const char *destination) {
  uv_fs_t request;
  const int code = uv_fs_rename(NULL, &request, source, destination, NULL);
  uv_fs_req_cleanup(&request);
  return code;
}

static int link_call(const char *source, const char *destination) {
  uv_fs_t request;
  const int code = uv_fs_link(NULL, &request, source, destination, NULL);
  uv_fs_req_cleanup(&request);
  return code;
}

/* The link at `path` names `target`. */
static int symlink_call(const char *path, const char *target) {
  uv_fs_t request;
  const int code = uv_fs_symlink(NULL, &request, target, path, 0, NULL);
  uv_fs_req_cleanup(&request);
  return code;
}

/* A two-path operation: `path` and `other` as validated paths, run through `call`. */
static void pair_job(MsFsJob *job, PairCall call, const char *operation, bool swapped_text) {
  MsOsText first;
  MsOsText second;
  if (!ms_fs_open_path(job, job->path, &first)) {
    return;
  }
  if (!ms_fs_open_path(job, job->other, &second)) {
    ms_os_text_free(&first);
    return;
  }
  const int code = call(first.ptr, second.ptr);
  ms_os_text_free(&first);
  ms_os_text_free(&second);
  if (code == 0) {
    return;
  }
  MsStrBuild both = ms_strbuild_new();
  ms_strbuild_append(&both, swapped_text ? job->other : job->path);
  ms_strbuild_append_text(&both, " ");
  ms_strbuild_append(&both, swapped_text ? job->path : job->other);
  ms_fs_job_fail(job, code, operation, ms_strbuild_span(&both));
  ms_strbuild_free(&both);
}

static void rename_job(void *data) { pair_job(data, rename_call, "rename", false); }
static void hard_link_job(void *data) { pair_job(data, link_call, "link", false); }
/* The text reads `symlink <target> <path>`. */
static void create_link_job(void *data) { pair_job(data, symlink_call, "symlink", true); }

/* A pair operation's native: the status, with `a -> b` as the detail of a status that names the paths. */
static uint8_t finish_pair(MsFsJob *job, MsString *err) {
  MsStrBuild both = ms_strbuild_new();
  ms_strbuild_append(&both, job->path);
  ms_strbuild_append_text(&both, " -> ");
  ms_strbuild_append(&both, job->other);
  const uint8_t status = ms_fail_finish_at(&job->fail, ms_strbuild_span(&both), err);
  ms_strbuild_free(&both);
  return status;
}

uint8_t msstd_fs_rename(const MsString *source, const MsString *destination, MsString *err) {
  MsFsJob job = ms_fs_job(source);
  job.other = ms_string_span(destination);
  ms_fs_run(&job, rename_job);
  const uint8_t status = finish_pair(&job, err);
  ms_fs_job_free(&job);
  return status;
}

uint8_t msstd_fs_hard_link(const MsString *source, const MsString *destination, MsString *err) {
  MsFsJob job = ms_fs_job(source);
  job.other = ms_string_span(destination);
  ms_fs_run(&job, hard_link_job);
  const uint8_t status = ms_fail_finish(&job.fail, err);
  ms_fs_job_free(&job);
  return status;
}

uint8_t msstd_fs_create_link(const MsString *path, const MsString *target, MsString *err) {
  MsFsJob job = ms_fs_job(path);
  job.other = ms_string_span(target);
  ms_fs_run(&job, create_link_job);
  const uint8_t status = ms_fail_finish_at(&job.fail, job.path, err);
  ms_fs_job_free(&job);
  return status;
}

static void read_link_job(void *data) {
  MsFsJob *job = data;
  MsOsText path;
  if (!ms_fs_open_path(job, job->path, &path)) {
    return;
  }
  uv_fs_t request;
  const int code = uv_fs_readlink(NULL, &request, path.ptr, NULL);
  ms_os_text_free(&path);
  if (code != 0) {
    ms_fs_job_fail(job, code, "readlink", job->path);
  } else if (!ms_fs_text_ok(ms_span_of_text((const char *)request.ptr))) {
    ms_fail_status(&job->fail, MS_STATUS_UNSUPPORTED);
  } else {
    ms_strbuild_append_text(&job->text, (const char *)request.ptr);
  }
  uv_fs_req_cleanup(&request);
}

uint8_t msstd_fs_read_link(const MsString *path, MsString *out, MsString *err) {
  MsFsJob job = ms_fs_job(path);
  ms_fs_run(&job, read_link_job);
  if (!ms_fail_failed(&job.fail)) {
    *out = ms_string_from_span(ms_strbuild_span(&job.text));
  }
  const uint8_t status = ms_fail_finish_at(&job.fail, job.path, err);
  ms_fs_job_free(&job);
  return status;
}

static void canonicalize_job(void *data) {
  MsFsJob *job = data;
  MsOsText path;
  if (!ms_fs_open_path(job, job->path, &path)) {
    return;
  }
  const int code = ms_fs_realpath(path.ptr, &job->text);
  ms_os_text_free(&path);
  if (code != 0) {
    ms_fs_job_fail(job, code, "lstat", job->path);
  } else if (!ms_fs_text_ok(ms_strbuild_span(&job->text))) {
    ms_fail_status(&job->fail, MS_STATUS_UNSUPPORTED);
  }
}

uint8_t msstd_fs_canonicalize(const MsString *path, MsString *out, MsString *err) {
  MsFsJob job = ms_fs_job(path);
  ms_fs_run(&job, canonicalize_job);
  if (!ms_fail_failed(&job.fail)) {
    *out = ms_string_from_span(ms_strbuild_span(&job.text));
  }
  const uint8_t status = ms_fail_finish_at(&job.fail, job.path, err);
  ms_fs_job_free(&job);
  return status;
}

/* ---- temporary directories ---- */

/* The temporary directory as an absolute path, even when $TMPDIR is relative. False when the host has none. */
static bool temporary_root(MsStrBuild *out) {
  char buffer[1024];
  size_t size = sizeof buffer;
  if (uv_os_tmpdir(buffer, &size) != 0) {
    return false;
  }
  const MsSpan root = ms_span_of((const uint8_t *)buffer, size);
  if (ms_fs_is_absolute(root)) {
    ms_strbuild_append(out, root);
    return true;
  }
  MsStrBuild cwd = ms_strbuild_new();
  if (working_directory(&cwd) == 0) {
    ms_fs_path_join(ms_strbuild_span(&cwd), root, out);
  } else {
    ms_strbuild_append(out, root);
  }
  ms_strbuild_free(&cwd);
  return true;
}

void msstd_fs_temporary_root(MsString *out) {
  MsStrBuild root = ms_strbuild_new();
  if (!temporary_root(&root)) {
    ms_strbuild_clear(&root);
  }
  *out = ms_strbuild_finish(&root);
  ms_strbuild_free(&root);
}

static bool valid_prefix(MsSpan prefix) {
  if (prefix.len == 0) {
    return false;
  }
  for (size_t i = 0; i < prefix.len; i++) {
    if (prefix.ptr[i] == '/' || prefix.ptr[i] == '\\' || prefix.ptr[i] == 0) {
      return false;
    }
  }
  return true;
}

static uint32_t random_digits(void) {
  uint32_t value = 0;
  uv_random_t request;
  if (uv_random(NULL, &request, &value, sizeof value, 0, NULL) != 0) {
    value = (uint32_t)uv_hrtime();
  }
  return value;
}

/* The last `*` of `pattern` marks the random digits: the text before it and after it. */
static void split_pattern(MsSpan pattern, MsSpan *prefix, MsSpan *suffix) {
  size_t star = pattern.len;
  for (size_t i = pattern.len; i > 0; i--) {
    if (pattern.ptr[i - 1] == '*') {
      star = i - 1;
      break;
    }
  }
  *prefix = ms_span_of(pattern.ptr, star);
  *suffix = star < pattern.len ? ms_span_of(pattern.ptr + star + 1, pattern.len - star - 1) : ms_span_of(NULL, 0);
}

bool ms_fs_make_temporary_directory(MsFail *fail, MsSpan pattern, MsStrBuild *out) {
  if (!valid_prefix(pattern)) {
    ms_fail_status(fail, MS_STATUS_INVALID_INPUT);
    return false;
  }
  MsSpan prefix;
  MsSpan suffix;
  split_pattern(pattern, &prefix, &suffix);
  MsStrBuild root = ms_strbuild_new();
  if (!temporary_root(&root)) {
    ms_strbuild_free(&root);
    ms_fail_status(fail, MS_STATUS_UNAVAILABLE);
    return false;
  }
  if (root.bytes.len > 0 && !ms_fs_is_separator(root.bytes.ptr[root.bytes.len - 1])) {
    ms_strbuild_append_byte(&root, ms_fs_separator());
  }
  int code = UV_EEXIST;
  for (int tries = 0; tries < 10000 && code == UV_EEXIST; tries++) {
    MsStrBuild name = ms_strbuild_new();
    ms_strbuild_append(&name, ms_strbuild_span(&root));
    ms_strbuild_append(&name, prefix);
    ms_strbuild_append_u64(&name, random_digits());
    ms_strbuild_append(&name, suffix);
    MsOsText text = ms_os_text_new(ms_strbuild_span(&name));
    code = ms_fs_make_directory(text.ptr);
    ms_os_text_free(&text);
    if (code == 0) {
      ms_strbuild_append(out, ms_strbuild_span(&name));
    } else if (code != UV_EEXIST) {
      ms_fail_uv(fail, code, "mkdir", ms_strbuild_span(&name));
    }
    ms_strbuild_free(&name);
  }
  ms_strbuild_free(&root);
  if (code == UV_EEXIST) {
    ms_fail_uv(fail, code, "mkdirtemp", pattern);
  }
  return code == 0;
}

uint8_t msstd_fs_temporary_directory(const MsString *pattern, MsString *out, MsString *err) {
  MsFail fail = ms_fail_new();
  MsStrBuild path = ms_strbuild_new();
  if (ms_fs_make_temporary_directory(&fail, ms_string_span(pattern), &path)) {
    *out = ms_strbuild_finish(&path);
  }
  ms_strbuild_free(&path);
  return ms_fail_finish(&fail, err);
}

/* ---- attributes ---- */

static void chmod_job(void *data) {
  MsFsJob *job = data;
  MsOsText path;
  if (!ms_fs_open_path(job, job->path, &path)) {
    return;
  }
  if (job->number < 0 || job->number > 07777) {
    ms_fail_status(&job->fail, MS_STATUS_INVALID_INPUT);
  } else {
    int code = 0;
    if (job->flag != 0) {
      uv_fs_t request;
      code = uv_fs_chmod(NULL, &request, path.ptr, (int)job->number, NULL);
      uv_fs_req_cleanup(&request);
    } else {
      code = ms_sys_fs_chmod_link(path.ptr, (uint32_t)job->number);
    }
    if (code != 0) {
      ms_fs_job_fail(job, code, "chmod", job->path);
    }
  }
  ms_os_text_free(&path);
}

uint8_t msstd_fs_chmod(const MsString *path, int64_t mode, uint8_t follow, MsString *err) {
  MsFsJob job = ms_fs_job(path);
  job.number = mode;
  job.flag = follow;
  ms_fs_run(&job, chmod_job);
  const uint8_t status = ms_fail_finish_at(&job.fail, job.path, err);
  ms_fs_job_free(&job);
  return status;
}

static void access_job(void *data) {
  MsFsJob *job = data;
  MsOsText path;
  if (!ms_fs_open_path(job, job->path, &path)) {
    return;
  }
  if (job->number < 0 || job->number > 7) {
    ms_fail_status(&job->fail, MS_STATUS_INVALID_INPUT);
  } else {
    uv_fs_t request;
    const int code = uv_fs_access(NULL, &request, path.ptr, (int)job->number, NULL);
    uv_fs_req_cleanup(&request);
    if (code != 0) {
      ms_fs_job_fail(job, code, "access", job->path);
    }
  }
  ms_os_text_free(&path);
}

uint8_t msstd_fs_access(const MsString *path, int64_t mode, MsString *err) {
  MsFsJob job = ms_fs_job(path);
  job.number = mode;
  ms_fs_run(&job, access_job);
  const uint8_t status = ms_fail_finish_at(&job.fail, job.path, err);
  ms_fs_job_free(&job);
  return status;
}

static void chown_job(void *data) {
  MsFsJob *job = data;
  MsOsText path;
  if (!ms_fs_open_path(job, job->path, &path)) {
    return;
  }
  const int64_t largest = 2147483647;
  if (job->number < -1 || job->second_number < -1 || job->number > largest || job->second_number > largest) {
    ms_fail_status(&job->fail, MS_STATUS_INVALID_INPUT);
  } else {
    uv_fs_t request;
    const uv_uid_t uid = (uv_uid_t)job->number;
    const uv_gid_t gid = (uv_gid_t)job->second_number;
    const int code = job->flag != 0 ? uv_fs_chown(NULL, &request, path.ptr, uid, gid, NULL)
                                    : uv_fs_lchown(NULL, &request, path.ptr, uid, gid, NULL);
    uv_fs_req_cleanup(&request);
    if (code != 0) {
      ms_fs_job_fail(job, code, job->flag != 0 ? "chown" : "lchown", job->path);
    }
  }
  ms_os_text_free(&path);
}

uint8_t msstd_fs_chown(const MsString *path, int64_t uid, int64_t gid, uint8_t follow, MsString *err) {
  MsFsJob job = ms_fs_job(path);
  job.number = uid;
  job.second_number = gid;
  job.flag = follow;
  ms_fs_run(&job, chown_job);
  const uint8_t status = ms_fail_finish_at(&job.fail, job.path, err);
  ms_fs_job_free(&job);
  return status;
}

static void truncate_job(void *data) {
  MsFsJob *job = data;
  MsOsText path;
  if (!ms_fs_open_path(job, job->path, &path)) {
    return;
  }
  if (job->number < 0) {
    ms_fail_status(&job->fail, MS_STATUS_INVALID_INPUT);
  } else {
    uv_fs_t request;
    int code = uv_fs_open(NULL, &request, path.ptr, UV_FS_O_WRONLY, 0, NULL);
    uv_fs_req_cleanup(&request);
    if (code >= 0) {
      const uv_file fd = code;
      code = uv_fs_ftruncate(NULL, &request, fd, job->number, NULL);
      uv_fs_req_cleanup(&request);
      (void)uv_fs_close(NULL, &request, fd, NULL);
      uv_fs_req_cleanup(&request);
    }
    if (code != 0) {
      ms_fs_job_fail(job, code, "truncate", job->path);
    }
  }
  ms_os_text_free(&path);
}

uint8_t msstd_fs_truncate(const MsString *path, int64_t size, MsString *err) {
  MsFsJob job = ms_fs_job(path);
  job.number = size;
  ms_fs_run(&job, truncate_job);
  const uint8_t status = ms_fail_finish_at(&job.fail, job.path, err);
  ms_fs_job_free(&job);
  return status;
}

static void set_times_job(void *data) {
  MsFsJob *job = data;
  MsOsText path;
  if (!ms_fs_open_path(job, job->path, &path)) {
    return;
  }
  const int code = ms_sys_fs_set_times(path.ptr, job->times[0].seconds, job->times[0].nanos, job->times[1].seconds,
                                       job->times[1].nanos, job->flag != 0);
  ms_os_text_free(&path);
  if (code != 0) {
    ms_fs_job_fail(job, code, "chtimes", job->path);
  }
}

uint8_t msstd_fs_set_times(const MsString *path, const MsFsTimestamp *accessed, const MsFsTimestamp *modified,
                           uint8_t follow, MsString *err) {
  MsFsJob job = ms_fs_job(path);
  job.times[0] = *accessed;
  job.times[1] = *modified;
  job.flag = follow;
  ms_fs_run(&job, set_times_job);
  const uint8_t status = ms_fail_finish_at(&job.fail, job.path, err);
  ms_fs_job_free(&job);
  return status;
}
