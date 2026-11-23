/* Directory cursors and scoped temporary directories of @std/fs: handles the program closes, or drops. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "base/alloc.h"
#include "runtime/std/fs_job.h"

/* ---- directory cursors ---- */

typedef struct MsFsDirectory {
  MsObj header;
  uv_dir_t *dir; /* NULL once closed */
  uv_dirent_t entry;
  MsString path;
} MsFsDirectory;

static void directory_close_now(MsFsDirectory *handle) {
  if (handle->dir != NULL) {
    uv_fs_t request;
    (void)uv_fs_closedir(NULL, &request, handle->dir, NULL);
    uv_fs_req_cleanup(&request);
    handle->dir = NULL;
  }
}

static void directory_drop(MsObj *object) {
  MsFsDirectory *handle = (MsFsDirectory *)object;
  directory_close_now(handle);
  ms_string_release(&handle->path);
  ms_free(handle);
}

/* Opens the job's path; anything but a directory is invalid input. The directory is left in `*dir`. */
static void directory_open_job(void *data) {
  MsFsJob *job = data;
  MsOsText path;
  if (!ms_fs_open_path(job, job->path, &path)) {
    return;
  }
  uv_stat_t stat;
  int code = ms_fs_stat_path(path.ptr, true, &stat);
  if (code != 0) {
    ms_fs_job_fail(job, code, "open", job->path);
  } else if (!ms_fs_is_directory(&stat)) {
    ms_fail_status(&job->fail, MS_STATUS_INVALID_INPUT);
  } else {
    uv_fs_t request;
    code = uv_fs_opendir(NULL, &request, path.ptr, NULL);
    if (code != 0) {
      ms_fs_job_fail(job, code, "fdopendir", job->path);
    } else {
      job->handle = request.ptr;
    }
    uv_fs_req_cleanup(&request);
  }
  ms_os_text_free(&path);
}

uint8_t msstd_fs_directory_open(const MsString *path, MsObj **out, MsString *err) {
  MsFsJob job = ms_fs_job(path);
  ms_fs_run(&job, directory_open_job);
  if (!ms_fail_failed(&job.fail)) {
    MsFsDirectory *handle = ms_alloc_zeroed(sizeof *handle);
    handle->header.drop = directory_drop;
    handle->dir = job.handle;
    handle->path = ms_string_clone(path);
    handle->dir->dirents = &handle->entry;
    handle->dir->nentries = 1;
    *out = &handle->header;
  }
  const uint8_t status = ms_fs_job_finish(&job, job.path, err);
  return status;
}

/* Reads one entry; `found` says whether there was one. */
static void directory_read_job(void *data) {
  MsFsJob *job = data;
  MsFsDirectory *cursor = job->handle;
  uv_fs_t request;
  const int code = uv_fs_readdir(NULL, &request, cursor->dir, NULL);
  if (code < 0) {
    ms_fs_job_fail(job, code, "readdirent", ms_string_span(&cursor->path));
  } else if (code > 0) {
    job->found = true;
    ms_strbuild_append_text(&job->text, cursor->entry.name);
    job->number = cursor->entry.type;
  }
  uv_fs_req_cleanup(&request);
}

uint8_t msstd_fs_directory_read(MsObj *handle, MsFsEntry *out, MsString *err) {
  MsFsDirectory *cursor = (MsFsDirectory *)handle;
  if (cursor->dir == NULL) {
    *err = ms_string_empty();
    return MS_STATUS_CLOSED;
  }
  MsFsJob job = ms_fs_job(&cursor->path);
  job.handle = cursor;
  if (!ms_fail_poll_cancel(&job.fail)) {
    ms_fs_run(&job, directory_read_job);
  }
  uint8_t status = MS_STATUS_OK;
  if (!ms_fail_failed(&job.fail) && !job.found) {
    status = MS_STATUS_NONE;
  } else if (!ms_fail_failed(&job.fail)) {
    bool directory = false;
    bool symlink = false;
    ms_fs_entry_kind(ms_string_span(&cursor->path), ms_strbuild_span(&job.text), (int)job.number, &directory, &symlink);
    MsStrBuild name = ms_strbuild_new();
    ms_fs_append_lossy(&name, ms_strbuild_span(&job.text));
    out->name = ms_strbuild_finish(&name);
    ms_strbuild_free(&name);
    out->directory = directory ? 1 : 0;
    out->symlink = symlink ? 1 : 0;
  }
  const uint8_t finished = ms_fs_job_finish(&job, ms_span_of(NULL, 0), err);
  return finished != MS_STATUS_OK ? finished : status;
}

void msstd_fs_directory_close(MsObj *handle) { directory_close_now((MsFsDirectory *)handle); }

void msstd_fs_directory_path(const MsObj *handle, MsString *out) {
  *out = ms_string_clone(&((const MsFsDirectory *)(const void *)handle)->path);
}

/* ---- temporary directories ---- */

typedef struct MsFsTemporary {
  MsObj header;
  MsString path;
  bool closed;
} MsFsTemporary;

static void temporary_drop(MsObj *object) {
  MsFsTemporary *handle = (MsFsTemporary *)object;
  ms_string_release(&handle->path);
  ms_free(handle);
}

uint8_t msstd_fs_temporary_open(const MsString *prefix, MsObj **out, MsString *err) {
  MsFail fail = ms_fail_new();
  MsStrBuild path = ms_strbuild_new();
  if (ms_fs_make_temporary_directory(&fail, ms_string_span(prefix), &path)) {
    MsFsTemporary *handle = ms_alloc_zeroed(sizeof *handle);
    handle->header.drop = temporary_drop;
    handle->path = ms_strbuild_finish(&path);
    *out = &handle->header;
  }
  ms_strbuild_free(&path);
  return ms_fail_finish(&fail, err);
}

void msstd_fs_temporary_path(const MsObj *handle, MsString *out) {
  *out = ms_string_clone(&((const MsFsTemporary *)(const void *)handle)->path);
}

static void remove_tree_job(void *data) {
  MsFsJob *job = data;
  ms_fs_remove_tree(&job->fail, job->path);
}

uint8_t msstd_fs_temporary_close(MsObj *handle, MsString *err) {
  MsFsTemporary *temporary = (MsFsTemporary *)handle;
  MsFsJob job = ms_fs_job(&temporary->path);
  if (!temporary->closed) {
    ms_fs_run(&job, remove_tree_job);
    if (!ms_fail_failed(&job.fail)) {
      temporary->closed = true;
    }
  }
  const uint8_t status = ms_fs_job_finish(&job, ms_span_of(NULL, 0), err);
  return status;
}
