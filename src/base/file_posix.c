/* The directory operations of base/file.h on POSIX hosts. */
#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#if defined(__APPLE__)
#define _DARWIN_C_SOURCE
#endif
#include <dirent.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>

#include "base/file.h"
#include "base/ostext.h"

enum { MAX_PATH_BYTES = 4096, DIRECTORY_MODE = 0777 };

static bool stat_mode(MsSpan path, mode_t *mode) {
  MsOsText name = ms_os_text_new(path);
  struct stat info;
  bool ok = stat(name.ptr, &info) == 0;
  ms_os_text_free(&name);
  if (ok) {
    *mode = info.st_mode;
  }
  return ok;
}

bool ms_file_is_regular(MsSpan path) {
  mode_t mode = 0;
  return stat_mode(path, &mode) && S_ISREG(mode);
}

bool ms_dir_exists(MsSpan path) {
  mode_t mode = 0;
  return stat_mode(path, &mode) && S_ISDIR(mode);
}

static bool make_one(MsSpan path) {
  MsOsText name = ms_os_text_new(path);
  bool ok = mkdir(name.ptr, DIRECTORY_MODE) == 0 || errno == EEXIST;
  ms_os_text_free(&name);
  return ok;
}

bool ms_dir_make_all(MsSpan path) {
  if (path.len >= MAX_PATH_BYTES) {
    return false;
  }
  for (size_t end = 1; end <= path.len; end++) {
    if (end != path.len && path.ptr[end] != '/') {
      continue;
    }
    if (!make_one(ms_span_of(path.ptr, end))) {
      return false;
    }
  }
  return true;
}

bool ms_dir_make_temp(MsSpan parent, MsSpan prefix, MsString *path) {
  MsStrBuild pattern = ms_strbuild_new();
  ms_strbuild_append(&pattern, parent);
  ms_strbuild_append_byte(&pattern, '/');
  ms_strbuild_append(&pattern, prefix);
  ms_strbuild_append_text(&pattern, "XXXXXX");
  MsString text = ms_strbuild_finish(&pattern);
  MsOsText name = ms_os_text_new(ms_string_span(&text));
  bool ok = mkdtemp(name.ptr) != NULL;
  if (ok) {
    ms_string_release(path);
    *path = ms_string_from_span(ms_span_of_text(name.ptr));
  }
  ms_os_text_free(&name);
  ms_string_release(&text);
  return ok;
}

bool ms_file_rename(MsSpan from, MsSpan to) {
  MsOsText source = ms_os_text_new(from);
  MsOsText target = ms_os_text_new(to);
  bool ok = rename(source.ptr, target.ptr) == 0;
  ms_os_text_free(&source);
  ms_os_text_free(&target);
  return ok;
}

void ms_path_remove(MsSpan path) {
  MsOsText name = ms_os_text_new(path);
  if (unlink(name.ptr) != 0) {
    (void)rmdir(name.ptr);
  }
  ms_os_text_free(&name);
}

static bool skips(const char *entry_name) {
  MsSpan text = ms_span_of_text(entry_name);
  return ms_span_is_text(text, ".") || ms_span_is_text(text, "..");
}

static void remove_child(MsSpan parent, const char *entry_name) {
  MsStrBuild child = ms_strbuild_new();
  ms_strbuild_append(&child, parent);
  ms_strbuild_append_byte(&child, '/');
  ms_strbuild_append_text(&child, entry_name);
  MsString text = ms_strbuild_finish(&child);
  MsOsText name = ms_os_text_new(ms_string_span(&text));
  struct stat info;
  if (lstat(name.ptr, &info) == 0 && S_ISDIR(info.st_mode)) {
    ms_path_remove_tree(ms_string_span(&text));
  } else {
    (void)unlink(name.ptr);
  }
  ms_os_text_free(&name);
  ms_string_release(&text);
}

void ms_path_remove_tree(MsSpan path) {
  MsOsText name = ms_os_text_new(path);
  DIR *directory = opendir(name.ptr);
  if (directory != NULL) {
    // NOLINTNEXTLINE(concurrency-mt-unsafe): one stream per call
    for (const struct dirent *entry = readdir(directory); entry != NULL; entry = readdir(directory)) { // NOLINT(concurrency-mt-unsafe)
      if (!skips(entry->d_name)) {
        remove_child(path, entry->d_name);
      }
    }
    (void)closedir(directory);
  }
  if (rmdir(name.ptr) != 0) {
    (void)unlink(name.ptr);
  }
  ms_os_text_free(&name);
}

#endif
