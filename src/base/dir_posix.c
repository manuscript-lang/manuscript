/* base/dir.h on POSIX hosts. */
#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#if defined(__APPLE__)
#define _DARWIN_C_SOURCE
#endif
#include <dirent.h>
#include <errno.h>
#include <sys/stat.h>

#include "base/dir.h"
#include "base/ostext.h"

static MsPathKind kind_of_mode(mode_t mode) {
  if (S_ISREG(mode)) {
    return MS_PATH_FILE;
  }
  if (S_ISDIR(mode)) {
    return MS_PATH_DIRECTORY;
  }
  return S_ISLNK(mode) ? MS_PATH_SYMLINK : MS_PATH_OTHER;
}

MsPathKind ms_path_kind(MsSpan path) {
  MsOsText name = ms_os_text_new(path);
  struct stat info;
  const bool ok = lstat(name.ptr, &info) == 0;
  ms_os_text_free(&name);
  return ok ? kind_of_mode(info.st_mode) : MS_PATH_MISSING;
}

static MsPathKind entry_kind(MsSpan directory, MsSpan name) {
  MsStrBuild full = ms_strbuild_new();
  ms_strbuild_append(&full, directory);
  ms_strbuild_append_byte(&full, '/');
  ms_strbuild_append(&full, name);
  const MsPathKind kind = ms_path_kind(ms_strbuild_span(&full));
  ms_strbuild_free(&full);
  return kind;
}

bool ms_dir_list(MsSpan path, MsDirEntryList *out) {
  MsOsText name = ms_os_text_new(path);
  DIR *directory = opendir(name.ptr);
  ms_os_text_free(&name);
  if (directory == NULL) {
    return false;
  }
  errno = 0;
  for (struct dirent *entry = readdir(directory); entry != NULL; entry = readdir(directory)) {
    const MsSpan text = ms_span_of_text(entry->d_name);
    if (ms_span_is_text(text, ".") || ms_span_is_text(text, "..")) {
      continue;
    }
    ms_dir_entry_list_push(out, (MsDirEntry){.name = ms_string_from_span(text), .kind = entry_kind(path, text)});
  }
  const int failure = errno;
  (void)closedir(directory);
  errno = failure;
  return failure == 0;
}
#endif
