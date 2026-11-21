/* The directory listing and path classification of base/dir.h, on libuv. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "base/dir.h"

#include <uv.h>

#include "base/ostext.h"

static MsPathKind kind_of_mode(uint64_t mode) {
  switch (mode & S_IFMT) {
  case S_IFREG:
    return MS_PATH_FILE;
  case S_IFDIR:
    return MS_PATH_DIRECTORY;
  case S_IFLNK:
    return MS_PATH_SYMLINK;
  default:
    return MS_PATH_OTHER;
  }
}

MsPathKind ms_path_kind(MsSpan path) {
  MsOsText name = ms_os_text_new(path);
  uv_fs_t request;
  const bool ok = uv_fs_lstat(NULL, &request, name.ptr, NULL) == 0;
  const MsPathKind kind = ok ? kind_of_mode(request.statbuf.st_mode) : MS_PATH_MISSING;
  uv_fs_req_cleanup(&request);
  ms_os_text_free(&name);
  return kind;
}

static MsPathKind kind_of_entry(MsSpan directory, const uv_dirent_t *entry) {
  switch (entry->type) {
  case UV_DIRENT_FILE:
    return MS_PATH_FILE;
  case UV_DIRENT_DIR:
    return MS_PATH_DIRECTORY;
  case UV_DIRENT_LINK:
    return MS_PATH_SYMLINK;
  case UV_DIRENT_UNKNOWN: {
    /* The file system did not say: ask it. */
    MsStrBuild full = ms_strbuild_new();
    ms_strbuild_append(&full, directory);
    ms_strbuild_append_byte(&full, '/');
    ms_strbuild_append_text(&full, entry->name);
    const MsPathKind kind = ms_path_kind(ms_strbuild_span(&full));
    ms_strbuild_free(&full);
    return kind;
  }
  default:
    return MS_PATH_OTHER;
  }
}

bool ms_dir_list(MsSpan path, MsDirEntryList *out) {
  MsOsText name = ms_os_text_new(path);
  uv_fs_t request;
  const int count = uv_fs_scandir(NULL, &request, name.ptr, 0, NULL);
  ms_os_text_free(&name);
  if (count < 0) {
    uv_fs_req_cleanup(&request);
    return false;
  }
  uv_dirent_t entry;
  while (uv_fs_scandir_next(&request, &entry) == 0) { /* "." and ".." are never listed */
    ms_dir_entry_list_push(
        out, (MsDirEntry){.name = ms_string_from_span(ms_span_of_text(entry.name)), .kind = kind_of_entry(path, &entry)});
  }
  uv_fs_req_cleanup(&request);
  return true;
}

void ms_dir_entries_free(MsDirEntryList *entries) {
  for (size_t i = 0; i < entries->len; i++) {
    ms_string_release(&entries->ptr[i].name);
  }
  ms_dir_entry_list_free(entries);
}
