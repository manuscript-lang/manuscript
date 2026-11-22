/* The metadata @std/fs natives: stat, exists, stat_filesystem and list. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include <stdlib.h>
#include <string.h>

#include "base/alloc.h"
#include "runtime/std/fs_job.h"

/* ---- libuv calls, run to their end ---- */

int ms_fs_stat_path(const char *path, bool follow, uv_stat_t *out) {
  uv_fs_t request;
  const int code = follow ? uv_fs_stat(NULL, &request, path, NULL) : uv_fs_lstat(NULL, &request, path, NULL);
  if (code == 0) {
    *out = request.statbuf;
  }
  uv_fs_req_cleanup(&request);
  return code;
}

bool ms_fs_is_link(const uv_stat_t *stat) { return (stat->st_mode & 0170000u) == 0120000u; }
bool ms_fs_same_file(const uv_stat_t *a, const uv_stat_t *b) { return a->st_dev == b->st_dev && a->st_ino == b->st_ino; }

/* ---- FileInfo ---- */

enum {
  KIND_DIRECTORY = 1,
  KIND_SYMLINK = 2,
  KIND_REGULAR = 4,
  KIND_FIFO = 8,
  KIND_SOCKET = 16,
  KIND_BLOCK_DEVICE = 32,
  KIND_CHAR_DEVICE = 64
};

static int64_t kinds_of(uint64_t mode) {
  switch (mode & 0170000u) {
    case 0040000u:
      return KIND_DIRECTORY;
    case 0120000u:
      return KIND_SYMLINK;
    case 0100000u:
      return KIND_REGULAR;
    case 0010000u:
      return KIND_FIFO;
    case 0140000u:
      return KIND_SOCKET;
    case 0060000u:
      return KIND_BLOCK_DEVICE;
    case 0020000u:
      return KIND_CHAR_DEVICE;
    default:
      return 0;
  }
}

/* Seconds and nanoseconds with the nanoseconds in 0..999999999, whatever the sign of the host's. */
static void split_time(const uv_timespec_t *time, int64_t *seconds, int64_t *nanos) {
  int64_t whole = (int64_t)time->tv_sec + (int64_t)time->tv_nsec / 1000000000;
  int64_t rest = (int64_t)time->tv_nsec % 1000000000;
  if (rest < 0) {
    rest += 1000000000;
    whole -= 1;
  }
  *seconds = whole;
  *nanos = rest;
}

/* Fills `out` (the name is written separately) from a stat; unsigned host counters carry their bits. */
void ms_fs_info_fill(MsFsInfo *out, const uv_stat_t *stat) {
  out->size = (int64_t)stat->st_size;
  out->mode = (int64_t)(stat->st_mode & 0177777u);
  out->permissions = (int64_t)(stat->st_mode & 07777u);
  split_time(&stat->st_mtim, &out->modified_seconds, &out->modified_nanos);
  split_time(&stat->st_atim, &out->accessed_seconds, &out->accessed_nanos);
  split_time(&stat->st_ctim, &out->changed_seconds, &out->changed_nanos);
  out->created_seconds = 0;
  out->created_nanos = 0;
  out->created_present = stat->st_birthtim.tv_sec != 0 || stat->st_birthtim.tv_nsec != 0 ? 1 : 0;
  if (out->created_present != 0) {
    split_time(&stat->st_birthtim, &out->created_seconds, &out->created_nanos);
  }
  out->kinds = kinds_of(stat->st_mode);
  out->block_size = (int64_t)stat->st_blksize;
  out->blocks = (int64_t)stat->st_blocks;
  out->rdev = (int64_t)stat->st_rdev;
  out->device = (int64_t)stat->st_dev;
  out->inode = (int64_t)stat->st_ino;
  out->links = (int64_t)stat->st_nlink;
  out->uid = (int64_t)stat->st_uid;
  out->gid = (int64_t)stat->st_gid;
}

static const char *stat_operation(bool follow) { return follow ? "stat" : "lstat"; }

static void stat_job(void *data) {
  MsFsJob *job = data;
  MsOsText path;
  if (!ms_fs_open_path(job, job->path, &path)) {
    return;
  }
  const int code = ms_fs_stat_path(path.ptr, job->flag != 0, &job->stat);
  ms_os_text_free(&path);
  if (code != 0) {
    ms_fs_job_fail(job, code, stat_operation(job->flag != 0), job->path);
    return;
  }
  /* The name is the last element of the path, as text. */
  ms_fs_append_lossy(&job->text, ms_path_base(job->path));
}

uint8_t msstd_fs_stat(const MsString *path, uint8_t follow, MsFsInfo *out, MsString *err) {
  MsFsJob job = ms_fs_job(path);
  job.flag = follow;
  ms_fs_run(&job, stat_job);
  if (!ms_fail_failed(&job.fail)) {
    ms_fs_info_fill(out, &job.stat);
    out->name = ms_string_from_span(ms_strbuild_span(&job.text));
  }
  const uint8_t status = ms_fail_finish_at(&job.fail, job.path, err);
  ms_fs_job_free(&job);
  return status;
}

static void exists_job(void *data) {
  MsFsJob *job = data;
  MsOsText path;
  if (!ms_fs_open_path(job, job->path, &path)) {
    return;
  }
  const int code = ms_fs_stat_path(path.ptr, job->flag != 0, &job->stat);
  ms_os_text_free(&path);
  if (code == 0) {
    job->found = true;
  } else if (code != UV_ENOENT && code != UV_ENOTDIR) {
    ms_fs_job_fail(job, code, stat_operation(job->flag != 0), job->path);
  }
}

/* 1 when `path` names anything, 0 when it or a directory part is missing; any other failure is an error, so a
 * permission error is not mistaken for absence. */
uint8_t msstd_fs_exists(const MsString *path, uint8_t follow, int64_t *out, MsString *err) {
  MsFsJob job = ms_fs_job(path);
  job.flag = follow;
  ms_fs_run(&job, exists_job);
  if (!ms_fail_failed(&job.fail)) {
    *out = job.found ? 1 : 0;
  }
  const uint8_t status = ms_fail_finish_at(&job.fail, job.path, err);
  ms_fs_job_free(&job);
  return status;
}

static void filesystem_job(void *data) {
  MsFsJob *job = data;
  MsOsText path;
  if (!ms_fs_open_path(job, job->path, &path)) {
    return;
  }
  uv_fs_t request;
  const int code = uv_fs_statfs(NULL, &request, path.ptr, NULL);
  ms_os_text_free(&path);
  if (code == 0) {
    job->filesystem = *(const uv_statfs_t *)request.ptr;
  } else {
    ms_fs_job_fail(job, code, "statfs", job->path);
  }
  uv_fs_req_cleanup(&request);
}

uint8_t msstd_fs_stat_filesystem(const MsString *path, MsFsFilesystem *out, MsString *err) {
  MsFsJob job = ms_fs_job(path);
  ms_fs_run(&job, filesystem_job);
  if (!ms_fail_failed(&job.fail)) {
    out->kind = (int64_t)job.filesystem.f_type;
    out->block_size = (int64_t)job.filesystem.f_bsize;
    out->blocks = (int64_t)job.filesystem.f_blocks;
    out->blocks_free = (int64_t)job.filesystem.f_bfree;
    out->blocks_available = (int64_t)job.filesystem.f_bavail;
    out->files = (int64_t)job.filesystem.f_files;
    out->files_free = (int64_t)job.filesystem.f_ffree;
  }
  const uint8_t status = ms_fail_finish_at(&job.fail, job.path, err);
  ms_fs_job_free(&job);
  return status;
}

/* ---- listing ---- */

typedef struct ListJob {
  MsFsJob base;
  MsList entries; /* of MsFsEntry */
} ListJob;

static void entries_free(MsList *entries) {
  MsFsEntry *items = (MsFsEntry *)(void *)entries->ptr;
  for (size_t i = 0; i < entries->len; i++) {
    ms_string_release(&items[i].name);
  }
  ms_list_free(entries);
}

static int compare_entries(const void *left, const void *right) {
  const MsFsEntry *a = left;
  const MsFsEntry *b = right;
  return ms_string_compare(&a->name, &b->name);
}

void ms_fs_entry_kind(MsSpan directory, MsSpan name, int type, bool *is_directory, bool *is_symlink) {
  *is_directory = type == UV_DIRENT_DIR;
  *is_symlink = type == UV_DIRENT_LINK;
  if (type != UV_DIRENT_UNKNOWN) {
    return;
  }
  MsStrBuild full = ms_strbuild_new();
  ms_path_join(directory, name, &full);
  MsOsText text = ms_os_text_new(ms_strbuild_span(&full));
  uv_stat_t stat;
  if (ms_fs_stat_path(text.ptr, false, &stat) == 0) {
    *is_directory = ms_fs_is_directory(&stat);
    *is_symlink = ms_fs_is_link(&stat);
  }
  ms_os_text_free(&text);
  ms_strbuild_free(&full);
}

/* Adds one directory entry to the job's list, or fails the job: the kind comes from the listing, or from an lstat
 * where the filesystem reports none. */
static void list_add(ListJob *job, const uv_dirent_t *entry) {
  if ((int64_t)job->entries.len >= job->base.number) {
    ms_fail_status(&job->base.fail, MS_STATUS_LIMIT_EXCEEDED);
    return;
  }
  MsFsEntry item = {0};
  bool directory = false;
  bool symlink = false;
  ms_fs_entry_kind(job->base.path, ms_span_of_text(entry->name), (int)entry->type, &directory, &symlink);
  item.directory = directory ? 1 : 0;
  item.symlink = symlink ? 1 : 0;
  MsStrBuild name = ms_strbuild_new();
  ms_fs_append_lossy(&name, ms_span_of_text(entry->name));
  item.name = ms_strbuild_finish(&name);
  ms_strbuild_free(&name);
  ms_list_push(&job->entries, sizeof item, &item);
}

static void list_job(void *data) {
  ListJob *job = data;
  MsOsText path;
  if (!ms_fs_open_path(&job->base, job->base.path, &path)) {
    return;
  }
  uv_stat_t stat;
  int code = ms_fs_stat_path(path.ptr, true, &stat);
  if (code != 0) {
    ms_fs_job_fail(&job->base, code, "open", job->base.path);
  } else if (!ms_fs_is_directory(&stat)) {
    ms_fail_status(&job->base.fail, MS_STATUS_INVALID_INPUT);
  } else {
    uv_fs_t request;
    code = uv_fs_scandir(NULL, &request, path.ptr, 0, NULL);
    if (code < 0) {
      ms_fs_job_fail(&job->base, code, "readdirent", job->base.path);
    } else {
      uv_dirent_t entry;
      while (!ms_fail_failed(&job->base.fail) && uv_fs_scandir_next(&request, &entry) != UV_EOF) {
        list_add(job, &entry);
      }
    }
    uv_fs_req_cleanup(&request);
  }
  ms_os_text_free(&path);
  if (!ms_fail_failed(&job->base.fail) && job->entries.len > 1) {
    qsort(job->entries.ptr, job->entries.len, sizeof(MsFsEntry), compare_entries);
  }
}

uint8_t msstd_fs_list(const MsString *path, uint8_t has_limit, int64_t limit, MsList *out, MsString *err) {
  ListJob job = {.base = ms_fs_job(path)};
  if (!ms_fs_limit(has_limit, limit, &job.base.number)) {
    ms_fail_status(&job.base.fail, MS_STATUS_INVALID_INPUT);
  } else {
    ms_fs_run(&job.base, list_job);
  }
  if (!ms_fail_failed(&job.base.fail)) {
    *out = job.entries;
    job.entries = (MsList){0};
  }
  const uint8_t status = ms_fail_finish_at(&job.base.fail, job.base.path, err);
  entries_free(&job.entries);
  ms_fs_job_free(&job.base);
  return status;
}
