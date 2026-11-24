/* `copy` of @std/fs: a file or a tree under the caller's options, with an optional filter closure asking about each
 * (source, destination). It runs on the runtime thread because the filter is program code; the content of each file is
 * copied on the blocking pool, so other tasks keep running (a stop request takes effect between entries). Everything the
 * copy owns is in one Copier, which a cleanup frees if the filter leaves by a jump. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include <limits.h>

#include "base/alloc.h"
#include "runtime/core/fault_abi.h"
#include "runtime/io/pool.h"
#include "runtime/std/fs_tree.h"
#include "runtime/sys/fs.h"

enum { COPY_CHUNK_BYTES = 1048576, COPY_MAX_DEPTH = 1024, COPY_MODE_MASK = 07777 };

enum {
  FLAG_RECURSIVE = 1,
  FLAG_REPLACE = 2,
  FLAG_ERROR_ON_EXISTS = 4,
  FLAG_DEREFERENCE = 8,
  FLAG_PRESERVE = 16,
  FLAG_VERBATIM = 32
};

typedef enum CloneMode { CLONE_NONE, CLONE_TRY, CLONE_FORCE } CloneMode;

typedef struct Copier {
  MsFail fail;
  int64_t flags;
  CloneMode clone;
  int64_t entries; /* left to copy */
  int64_t bytes;   /* left to copy */
  MsFsClosure *filter;
  MsStrBuild destination; /* the destination root with its existing ancestors resolved through links */
  MsStrBuild ancestors;   /* the canonical source directories being copied, as names */
  MsFsArguments arguments;
} Copier;

static void copier_free(Copier *copier) {
  ms_fail_free(&copier->fail);
  ms_strbuild_free(&copier->destination);
  ms_strbuild_free(&copier->ancestors);
  ms_fs_arguments_free(&copier->arguments);
}

static void copier_cleanup(uint8_t *argument) {
  copier_free((Copier *)__builtin_assume_aligned(argument, _Alignof(Copier)));
}

static bool has_flag(const Copier *copier, int64_t flag) { return (copier->flags & flag) != 0; }

/* ---- failures ---- */

static bool fail_status(Copier *copier, uint8_t status) {
  ms_fail_status(&copier->fail, status);
  return false;
}

static bool fail_at(Copier *copier, int code, const char *operation, MsSpan path) {
  ms_fail_uv(&copier->fail, code, operation, path);
  return false;
}

/* ---- single system calls on a byte path ---- */

/* `path` as OS text, or a failed copier. */
static bool os_path(Copier *copier, MsSpan path, MsOsText *out) {
  size_t at = 0;
  if (path.len == 0 || ms_span_find(path, ms_span_of((const uint8_t *)"\0", 1), &at)) {
    return fail_status(copier, MS_STATUS_INVALID_INPUT);
  }
  *out = ms_os_text_new(path);
  return true;
}

static bool stat_at(Copier *copier, MsSpan path, bool follow, const char *operation, uv_stat_t *out) {
  const int code = ms_fs_stat_bytes(path, follow, out);
  return code == 0 || fail_at(copier, code, operation, path);
}

static bool chmod_path(Copier *copier, MsSpan path, uint64_t mode) {
  MsOsText text;
  if (!os_path(copier, path, &text)) {
    return false;
  }
  uv_fs_t request;
  const int code = uv_fs_chmod(NULL, &request, text.ptr, (int)(mode & COPY_MODE_MASK), NULL);
  uv_fs_req_cleanup(&request);
  ms_os_text_free(&text);
  return code == 0 || fail_at(copier, code, "chmod", path);
}

static bool chtimes(Copier *copier, MsSpan path, const uv_stat_t *info) {
  MsOsText text;
  if (!os_path(copier, path, &text)) {
    return false;
  }
  const int code = ms_sys_fs_set_times(text.ptr, info->st_atim.tv_sec, info->st_atim.tv_nsec, info->st_mtim.tv_sec,
                                       info->st_mtim.tv_nsec, true);
  ms_os_text_free(&text);
  return code == 0 || fail_at(copier, code, "chtimes", path);
}

/* Removes `path`, a path that is already gone being fine. */
static bool remove_ignoring_missing(Copier *copier, MsSpan path) {
  MsOsText text;
  if (!os_path(copier, path, &text)) {
    return false;
  }
  const int code = ms_fs_remove_one(text.ptr);
  ms_os_text_free(&text);
  return code == 0 || code == UV_ENOENT || fail_at(copier, code, "remove", path);
}

static bool canonical_of(Copier *copier, MsSpan path, MsStrBuild *out) {
  MsOsText text;
  if (!os_path(copier, path, &text)) {
    return false;
  }
  const int code = ms_fs_realpath(text.ptr, out);
  ms_os_text_free(&text);
  return code == 0 || fail_at(copier, code, "lstat", path);
}

/* ---- the destination ---- */

/* The canonical form of `directory/name` where `directory` exists: its parent's canonical path and its own name. */
static bool canonical_by_parent(Copier *copier, MsSpan path, MsStrBuild *out) {
  MsStrBuild parent = ms_strbuild_new();
  MsStrBuild real_parent = ms_strbuild_new();
  ms_path_dir(path, &parent);
  bool ok = canonical_of(copier, ms_strbuild_span(&parent), &real_parent);
  if (ok) {
    ms_path_join(ms_strbuild_span(&real_parent), ms_path_base(path), out);
  }
  ms_strbuild_free(&parent);
  ms_strbuild_free(&real_parent);
  return ok;
}

/* The canonical source, where a link that is not followed is its parent's canonical path and its own name. */
static bool source_canonical(Copier *copier, MsSpan source, MsStrBuild *out) {
  uv_stat_t info;
  const bool is_link = !has_flag(copier, FLAG_DEREFERENCE) && ms_fs_stat_bytes(source, false, &info) == 0 && ms_fs_is_link(&info);
  return is_link ? canonical_by_parent(copier, source, out) : canonical_of(copier, source, out);
}

typedef enum Climb { CLIMB_FOUND, CLIMB_UP, CLIMB_FAILED } Climb;

/* Moves `ancestor` one directory up while it does not exist, remembering the names climbed in `suffix`. */
static Climb climb_once(Copier *copier, MsStrBuild *ancestor, MsStrBuild *suffix) {
  const MsSpan current = ms_strbuild_span(ancestor);
  uv_stat_t info;
  const int code = ms_fs_stat_bytes(current, false, &info);
  if (code == 0) {
    return CLIMB_FOUND;
  }
  if (code != UV_ENOENT) {
    fail_at(copier, code, "lstat", current);
    return CLIMB_FAILED;
  }
  MsStrBuild parent = ms_strbuild_new();
  ms_path_dir(current, &parent);
  if (ms_span_equal(ms_strbuild_span(&parent), current)) {
    ms_strbuild_free(&parent);
    fail_status(copier, MS_STATUS_INVALID_INPUT);
    return CLIMB_FAILED;
  }
  MsStrBuild joined = ms_strbuild_new();
  if (ms_strbuild_length(suffix) == 0) {
    ms_strbuild_append(&joined, ms_path_base(current));
  } else {
    ms_path_join(ms_path_base(current), ms_strbuild_span(suffix), &joined);
  }
  ms_strbuild_free(suffix);
  ms_strbuild_free(ancestor);
  *suffix = joined;
  *ancestor = parent;
  return CLIMB_UP;
}

/* The canonical form of the existing `ancestor`; a dangling link is its parent's canonical path and its own name. */
static bool resolve_ancestor(Copier *copier, MsSpan ancestor, MsStrBuild *real) {
  MsOsText text = ms_os_text_new(ancestor);
  const int code = ms_fs_realpath(text.ptr, real);
  ms_os_text_free(&text);
  if (code == 0) {
    return true;
  }
  MsStrBuild parent = ms_strbuild_new();
  ms_path_dir(ancestor, &parent);
  const bool has_parent = code == UV_ENOENT && ms_strbuild_length(&parent) != ancestor.len;
  const bool ok = has_parent ? canonical_by_parent(copier, ancestor, real) : fail_at(copier, code, "lstat", ancestor);
  ms_strbuild_free(&parent);
  return ok;
}

/* `resolveDestination`: the destination with the links of its existing ancestors resolved. */
static bool resolve_destination(Copier *copier, MsSpan destination, MsStrBuild *out) {
  MsStrBuild ancestor = ms_strbuild_new();
  MsStrBuild suffix = ms_strbuild_new();
  ms_strbuild_append(&ancestor, destination);
  Climb climb = CLIMB_UP;
  while (climb == CLIMB_UP) {
    climb = climb_once(copier, &ancestor, &suffix);
  }
  MsStrBuild real = ms_strbuild_new();
  bool ok = climb == CLIMB_FOUND && resolve_ancestor(copier, ms_strbuild_span(&ancestor), &real);
  if (ok && ms_strbuild_length(&suffix) > 0) {
    MsStrBuild whole = ms_strbuild_new();
    ms_path_join(ms_strbuild_span(&real), ms_strbuild_span(&suffix), &whole);
    ms_strbuild_free(&real);
    real = whole;
  }
  if (ok) {
    *out = real;
    real = ms_strbuild_new();
  }
  ms_strbuild_free(&real);
  ms_strbuild_free(&ancestor);
  ms_strbuild_free(&suffix);
  return ok;
}

/* Rejects a destination inside the source and keeps the resolved destination. */
static bool check_destination(Copier *copier, MsSpan source, MsSpan destination) {
  MsStrBuild canonical = ms_strbuild_new();
  bool ok = source_canonical(copier, source, &canonical) && resolve_destination(copier, destination, &copier->destination);
  if (ok && ms_fs_within_path(ms_strbuild_span(&canonical), ms_strbuild_span(&copier->destination))) {
    ok = fail_status(copier, MS_STATUS_INVALID_INPUT);
  }
  ms_strbuild_free(&canonical);
  return ok;
}

/* ---- files ---- */

/* One file's content, copied on the blocking pool: the job owns its failure and reports how many bytes it wrote. */
typedef struct FileJob {
  MsSpan source;
  MsSpan destination;
  uv_stat_t info;  /* what the entry was when it was looked at */
  CloneMode clone;
  int64_t budget;  /* bytes the copy may still use */
  bool exists;     /* something is at the destination: remove it first */
  MsFail fail;
  int64_t copied;
  bool cloned;
} FileJob;

static int open_fd(const char *path, int flags, int mode) {
  uv_fs_t request;
  const int fd = uv_fs_open(NULL, &request, path, flags, mode, NULL);
  uv_fs_req_cleanup(&request);
  return fd;
}

static void close_fd(uv_file fd) {
  uv_fs_t request;
  (void)uv_fs_close(NULL, &request, fd, NULL);
  uv_fs_req_cleanup(&request);
}

/* Copies `input` to `output` inside the kernel where the host can (libuv: copy_file_range or sendfile, else a read and
 * write loop), charging the byte budget one byte past what is left so an excess is seen. */
static void copy_stream(FileJob *job, uv_file input, uv_file output) {
  int64_t offset = 0;
  for (;;) {
    const int64_t room = job->budget - job->copied;
    const size_t want = room < (int64_t)COPY_CHUNK_BYTES ? (size_t)room + 1 : COPY_CHUNK_BYTES;
    uv_fs_t request;
    const int64_t count = uv_fs_sendfile(NULL, &request, output, input, offset, want, NULL);
    uv_fs_req_cleanup(&request);
    if (count < 0) {
      ms_fail_uv(&job->fail, (int)count, "copy", job->destination);
      break;
    }
    if (count == 0) {
      break;
    }
    if (count > room) {
      ms_fail_status(&job->fail, MS_STATUS_LIMIT_EXCEEDED);
      break;
    }
    offset += count;
    job->copied += count;
  }
}

/* Creates the destination, which must not exist, with the source's permission bits. */
static bool create_output(FileJob *job, const char *path, uv_file *output) {
  const int mode = (int)(job->info.st_mode & COPY_MODE_MASK);
  *output = open_fd(path, UV_FS_O_WRONLY | UV_FS_O_CREAT | UV_FS_O_EXCL, mode);
  if (*output < 0) {
    ms_fail_uv(&job->fail, *output, "open", job->destination);
    return false;
  }
  return true;
}

/* Makes the destination share the extents of `input` and charges its size; a failed clone removes the file it
 * created, and a forced one is the copy's failure. Returns whether the content is now there. */
static bool clone_content(FileJob *job, uv_file input, uv_file output, const char *destination_path) {
  const int code = ms_sys_fs_clone_file(output, input);
  uv_stat_t made;
  if (code == 0 && ms_fs_stat_path(destination_path, true, &made) == 0) {
    if ((int64_t)made.st_size > job->budget) {
      ms_fail_status(&job->fail, MS_STATUS_LIMIT_EXCEEDED);
    } else {
      job->copied = (int64_t)made.st_size;
      job->cloned = true;
    }
    return true;
  }
  if (code == 0) {
    ms_fail_text(&job->fail, "cannot stat the clone");
    return true;
  }
  uv_fs_t request;
  (void)uv_fs_unlink(NULL, &request, destination_path, NULL);
  uv_fs_req_cleanup(&request);
  if (job->clone == CLONE_FORCE) {
    ms_fail_uv(&job->fail, code, "ioctl", job->destination);
    return true;
  }
  return false;
}

/* Copies the content of `input` into a new destination: by clone where asked, else by reading and writing. */
static void copy_into_new(FileJob *job, uv_file input, const char *destination_path) {
  uv_file output = -1;
  if (!create_output(job, destination_path, &output)) {
    return;
  }
  bool done = false;
  if (job->clone != CLONE_NONE) {
    done = clone_content(job, input, output, destination_path);
    if (!done) {
      close_fd(output); /* the failed clone took the file with it: make it again */
      if (!create_output(job, destination_path, &output)) {
        return;
      }
    }
  }
  if (!done) {
    copy_stream(job, input, output);
  }
  if (!ms_fail_failed(&job->fail) && !job->cloned) {
    uv_fs_t request;
    const int code = uv_fs_fchmod(NULL, &request, output, (int)(job->info.st_mode & COPY_MODE_MASK), NULL);
    uv_fs_req_cleanup(&request);
    if (code != 0) {
      ms_fail_uv(&job->fail, code, "chmod", job->destination);
    }
  }
  close_fd(output);
}

static void file_job(void *data) {
  FileJob *job = data;
  MsOsText source = ms_os_text_new(job->source);
  MsOsText destination = ms_os_text_new(job->destination);
  const uv_file input = open_fd(source.ptr, UV_FS_O_RDONLY, 0);
  if (input < 0) {
    ms_fail_uv(&job->fail, input, "open", job->source);
  } else {
    uv_stat_t acquired;
    if (ms_fs_fstat(input, &acquired) != 0 || !ms_fs_same_file(&job->info, &acquired)) {
      ms_fail_status(&job->fail, MS_STATUS_INVALID_INPUT);
    } else if (job->exists) {
      const int code = ms_fs_remove_one(destination.ptr);
      if (code != 0 && code != UV_ENOENT) {
        ms_fail_uv(&job->fail, code, "remove", job->destination);
      }
    }
    if (!ms_fail_failed(&job->fail)) {
      copy_into_new(job, input, destination.ptr);
    }
    close_fd(input);
  }
  ms_os_text_free(&source);
  ms_os_text_free(&destination);
}

static bool copy_file(Copier *copier, MsSpan source, MsSpan destination, const uv_stat_t *info, bool exists) {
  FileJob job = {.source = source,
                 .destination = destination,
                 .info = *info,
                 .clone = copier->clone,
                 .budget = copier->bytes,
                 .exists = exists,
                 .fail = ms_fail_new()};
  if (ms_pool_on_thread()) {
    file_job(&job);
  } else if (ms_pool_run_shielded(file_job, &job) != MS_POOL_DONE) {
    ms_fail_text(&job.fail, "cancelled");
  }
  if (ms_fail_failed(&job.fail)) {
    ms_fail_free(&copier->fail);
    copier->fail = job.fail;
    return false;
  }
  copier->bytes -= job.copied;
  return chmod_path(copier, destination, info->st_mode) && (!has_flag(copier, FLAG_PRESERVE) || chtimes(copier, destination, info));
}

/* A symbolic link at `destination` pointing at `link`. */
static bool make_symlink(Copier *copier, MsSpan link, MsSpan destination) {
  MsOsText link_text;
  MsOsText destination_text;
  if (!os_path(copier, link, &link_text)) {
    return false;
  }
  if (!os_path(copier, destination, &destination_text)) {
    ms_os_text_free(&link_text);
    return false;
  }
  const int code = ms_sys_fs_symlink(link_text.ptr, destination_text.ptr);
  ms_os_text_free(&link_text);
  ms_os_text_free(&destination_text);
  if (code != 0) {
    MsStrBuild both = ms_strbuild_new();
    ms_strbuild_append(&both, link);
    ms_strbuild_append_byte(&both, ' ');
    ms_strbuild_append(&both, destination);
    ms_fail_uv(&copier->fail, code, "symlink", ms_strbuild_span(&both));
    ms_strbuild_free(&both);
    return false;
  }
  return true;
}

/* A symbolic link is copied as a link; a relative target is made absolute unless the copy is verbatim. */
static bool copy_link(Copier *copier, MsSpan source, MsSpan destination, bool exists) {
  MsOsText text;
  if (!os_path(copier, source, &text)) {
    return false;
  }
  uv_fs_t request;
  const int code = uv_fs_readlink(NULL, &request, text.ptr, NULL);
  ms_os_text_free(&text);
  if (code != 0) {
    uv_fs_req_cleanup(&request);
    return fail_at(copier, code, "readlink", source);
  }
  MsStrBuild target = ms_strbuild_new();
  ms_strbuild_append_text(&target, (const char *)request.ptr);
  uv_fs_req_cleanup(&request);
  MsStrBuild resolved = ms_strbuild_new();
  MsSpan link = ms_strbuild_span(&target);
  if (!has_flag(copier, FLAG_VERBATIM) && !ms_path_is_absolute(link)) {
    MsStrBuild parent = ms_strbuild_new();
    MsStrBuild absolute_parent = ms_strbuild_new();
    ms_path_dir(source, &parent);
    ms_fs_absolute(ms_strbuild_span(&parent), &absolute_parent);
    ms_path_join(ms_strbuild_span(&absolute_parent), link, &resolved);
    link = ms_strbuild_span(&resolved);
    ms_strbuild_free(&parent);
    ms_strbuild_free(&absolute_parent);
  }
  const bool ok = (!exists || remove_ignoring_missing(copier, destination)) && make_symlink(copier, link, destination);
  ms_strbuild_free(&resolved);
  ms_strbuild_free(&target);
  return ok;
}

/* ---- directories ---- */

static bool copy_entry(Copier *copier, MsSpan source, MsSpan destination, size_t depth);

/* The children of `source`, each copied to the same name under `destination`. */
static bool copy_children(Copier *copier, MsSpan source, MsSpan destination, size_t depth) {
  MsStrBuild names = ms_strbuild_new();
  bool ok = ms_fs_names_read(source, &names, &copier->fail);
  size_t cursor = 0;
  MsSpan name;
  while (ok && ms_fs_names_next(ms_strbuild_span(&names), &cursor, &name)) {
    MsStrBuild from = ms_strbuild_new();
    MsStrBuild to = ms_strbuild_new();
    ms_path_join(source, name, &from);
    ms_path_join(destination, name, &to);
    ok = copy_entry(copier, ms_strbuild_span(&from), ms_strbuild_span(&to), depth + 1);
    ms_strbuild_free(&from);
    ms_strbuild_free(&to);
  }
  ms_strbuild_free(&names);
  return ok;
}

static bool copy_directory_inner(Copier *copier, MsSpan source, MsSpan destination, const uv_stat_t *info, bool exists,
                                 size_t depth) {
  if (!exists) {
    MsOsText text;
    if (!os_path(copier, destination, &text)) {
      return false;
    }
    const int code = ms_fs_make_directory(text.ptr);
    ms_os_text_free(&text);
    if (code != 0) {
      return fail_at(copier, code, "mkdir", destination);
    }
  }
  if (!copy_children(copier, source, destination, depth)) {
    return false;
  }
  if (!exists && !chmod_path(copier, destination, info->st_mode)) {
    return false;
  }
  return !has_flag(copier, FLAG_PRESERVE) || chtimes(copier, destination, info);
}

static bool copy_directory(Copier *copier, MsSpan source, MsSpan destination, const uv_stat_t *info,
                           const uv_stat_t *previous, size_t depth) {
  if (!has_flag(copier, FLAG_RECURSIVE) || (previous != NULL && !ms_fs_is_directory(previous))) {
    return fail_status(copier, MS_STATUS_INVALID_INPUT);
  }
  if (previous != NULL && !has_flag(copier, FLAG_REPLACE) && has_flag(copier, FLAG_ERROR_ON_EXISTS)) {
    return fail_status(copier, MS_STATUS_ALREADY_EXISTS);
  }
  MsStrBuild canonical = ms_strbuild_new();
  bool ok = canonical_of(copier, source, &canonical);
  // A followed link can lead to a directory that holds the destination; copying it would read the tree being written
  // and never end.
  if (ok && (ms_fs_within_path(ms_strbuild_span(&canonical), ms_strbuild_span(&copier->destination)) ||
             ms_fs_names_contain(&copier->ancestors, ms_strbuild_span(&canonical)))) {
    ok = fail_status(copier, MS_STATUS_INVALID_INPUT);
  }
  const size_t mark = ms_strbuild_length(&copier->ancestors);
  if (ok) {
    ms_fs_names_push(&copier->ancestors, ms_strbuild_span(&canonical));
  }
  ms_strbuild_free(&canonical);
  if (!ok) {
    return false;
  }
  ok = copy_directory_inner(copier, source, destination, info, previous != NULL, depth);
  copier->ancestors.bytes.len = mark;
  return ok;
}

/* ---- entries ---- */

/* Asks the filter whether to copy (source, destination); no filter copies everything. */
static bool filter_accepts(Copier *copier, MsSpan source, MsSpan destination) {
  if (copier->filter == NULL) {
    return true;
  }
  MsFsArguments *arguments = &copier->arguments;
  ms_fs_arguments_set(arguments, source, destination);
  const uint8_t keep = copier->filter->code.pair(copier->filter, arguments->first.low_bits, arguments->first.tagged,
                                                 arguments->second.low_bits, arguments->second.tagged);
  ms_fs_arguments_free(arguments);
  return keep != 0;
}

/* What is at the destination: false in `*present` when nothing is. */
static bool destination_state(Copier *copier, MsSpan destination, uv_stat_t *previous, bool *present) {
  const int code = ms_fs_stat_bytes(destination, false, previous);
  *present = code == 0;
  return code == 0 || code == UV_ENOENT || fail_at(copier, code, "lstat", destination);
}

/* Copies a file or link that is not a directory, given the destination's state. */
static bool copy_leaf(Copier *copier, MsSpan source, MsSpan destination, const uv_stat_t *info, bool exists) {
  if (exists && !has_flag(copier, FLAG_REPLACE)) {
    return has_flag(copier, FLAG_ERROR_ON_EXISTS) ? fail_status(copier, MS_STATUS_ALREADY_EXISTS) : true;
  }
  if (ms_fs_is_link(info)) {
    return copy_link(copier, source, destination, exists);
  }
  if (!ms_fs_is_regular(info)) {
    return fail_status(copier, MS_STATUS_INVALID_INPUT);
  }
  if ((int64_t)info->st_size > copier->bytes) {
    return fail_status(copier, MS_STATUS_LIMIT_EXCEEDED);
  }
  return copy_file(copier, source, destination, info, exists);
}

static bool copy_entry(Copier *copier, MsSpan source, MsSpan destination, size_t depth) {
  if (ms_fail_poll_cancel(&copier->fail)) {
    return false;
  }
  if (depth > COPY_MAX_DEPTH || copier->entries <= 0) {
    return fail_status(copier, MS_STATUS_LIMIT_EXCEEDED);
  }
  copier->entries -= 1;
  if (!filter_accepts(copier, source, destination)) {
    return true;
  }
  uv_stat_t info;
  uv_stat_t previous;
  bool present = false;
  const bool follow = has_flag(copier, FLAG_DEREFERENCE);
  bool ok = stat_at(copier, source, false, "lstat", &info) && (!follow || stat_at(copier, source, true, "stat", &info)) &&
            destination_state(copier, destination, &previous, &present);
  if (ok && present && ms_fs_same_file(&info, &previous)) {
    ok = fail_status(copier, MS_STATUS_INVALID_INPUT);
  }
  if (!ok) {
    return false;
  }
  if (ms_fs_is_directory(&info)) {
    return copy_directory(copier, source, destination, &info, present ? &previous : NULL, depth);
  }
  return copy_leaf(copier, source, destination, &info, present);
}

/* ---- the native ---- */

static bool parse_clone(const MsString *text, CloneMode *mode) {
  const MsSpan bytes = ms_string_span(text);
  if (ms_span_is_text(bytes, "none")) {
    *mode = CLONE_NONE;
  } else if (ms_span_is_text(bytes, "try")) {
    *mode = CLONE_TRY;
  } else if (ms_span_is_text(bytes, "force")) {
    *mode = CLONE_FORCE;
  } else {
    return false;
  }
  return true;
}

static uint8_t finish_pair(Copier *copier, MsSpan from, MsSpan to, MsString *err) {
  MsStrBuild both = ms_strbuild_new();
  ms_strbuild_append(&both, from);
  ms_strbuild_append_text(&both, " -> ");
  ms_strbuild_append(&both, to);
  const uint8_t status = ms_fail_finish_at(&copier->fail, ms_strbuild_span(&both), err);
  ms_strbuild_free(&both);
  return status;
}

uint8_t msstd_fs_copy(const MsString *source, const MsString *destination, int64_t flags, const MsString *clone,
                      uint8_t has_entries, int64_t entries, uint8_t has_bytes, int64_t bytes, MsObj *filter,
                      MsString *err) {
  Copier copier = {.flags = flags,
                   .filter = (MsFsClosure *)filter,
                   .fail = ms_fail_new(),
                   .destination = ms_strbuild_new(),
                   .ancestors = ms_strbuild_new()};
  if (!parse_clone(clone, &copier.clone)) {
    *err = ms_string_empty();
    return MS_STATUS_INVALID_INPUT;
  }
  if (!ms_fs_limit(has_entries, entries, &copier.entries) || !ms_fs_limit(has_bytes, bytes, &copier.bytes)) {
    ms_fail_status(&copier.fail, MS_STATUS_INVALID_INPUT);
    return ms_fail_finish(&copier.fail, err);
  }
  const MsSpan from = ms_string_span(source);
  const MsSpan to = ms_string_span(destination);
  const size_t handle = msrt_cleanup_push(copier_cleanup, (uint8_t *)&copier);
  if (check_destination(&copier, from, to)) {
    (void)copy_entry(&copier, from, to, 0);
  }
  msrt_cleanup_discard(handle);
  ms_fs_arguments_free(&copier.arguments);
  ms_strbuild_free(&copier.destination);
  ms_strbuild_free(&copier.ancestors);
  return finish_pair(&copier, from, to, err);
}
