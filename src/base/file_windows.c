/* The directory operations of base/file.h on Windows. Paths are UTF-8 and may use `/`. */
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#define NOGDI
#define NOUSER
#include <windows.h>

#include "base/file.h"
#include "base/ostext.h"

enum { MAX_PATH_UNITS = 4096, TEMP_ATTEMPTS = 100, SUFFIX_DIGITS = 6 };

static DWORD attributes(MsSpan path) {
  MsOsWide wide = ms_os_wide_new(path, true);
  DWORD result = INVALID_FILE_ATTRIBUTES;
  if (wide.ptr != NULL) {
    result = GetFileAttributesW((const WCHAR *)wide.ptr);
  }
  ms_os_wide_free(&wide);
  return result;
}

bool ms_file_is_regular(MsSpan path) {
  DWORD found = attributes(path);
  return found != INVALID_FILE_ATTRIBUTES && (found & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

bool ms_dir_exists(MsSpan path) {
  DWORD found = attributes(path);
  return found != INVALID_FILE_ATTRIBUTES && (found & FILE_ATTRIBUTE_DIRECTORY) != 0;
}

static bool make_one(MsSpan path) {
  MsOsWide wide = ms_os_wide_new(path, true);
  bool ok = wide.ptr != NULL &&
            (CreateDirectoryW((const WCHAR *)wide.ptr, NULL) || GetLastError() == ERROR_ALREADY_EXISTS);
  ms_os_wide_free(&wide);
  return ok;
}

bool ms_dir_make_all(MsSpan path) {
  if (path.len >= MAX_PATH_UNITS) {
    return false;
  }
  for (size_t end = 1; end <= path.len; end++) {
    bool separator = end != path.len && (path.ptr[end] == '/' || path.ptr[end] == '\\');
    if (end != path.len && !separator) {
      continue;
    }
    bool drive = end == 2 && path.ptr[1] == ':';
    if (!drive && !make_one(ms_span_of(path.ptr, end))) {
      return false;
    }
  }
  return true;
}

static uint32_t suffix_seed(uint32_t attempt) {
  return (uint32_t)GetCurrentProcessId() * 131u + attempt * 7919u + (uint32_t)GetTickCount();
}

bool ms_dir_make_temp(MsSpan parent, MsSpan prefix, MsString *path) {
  for (uint32_t attempt = 0; attempt < TEMP_ATTEMPTS; attempt++) {
    MsStrBuild name = ms_strbuild_new();
    ms_strbuild_append(&name, parent);
    ms_strbuild_append_byte(&name, '/');
    ms_strbuild_append(&name, prefix);
    uint32_t value = suffix_seed(attempt) & 0xffffffu;
    for (uint32_t shift = 20;; shift -= 4) {
      ms_strbuild_append_u64_radix(&name, (value >> shift) & 15u, 16);
      if (shift == 0) {
        break;
      }
    }
    MsString text = ms_strbuild_finish(&name);
    MsOsWide wide = ms_os_wide_new(ms_string_span(&text), true);
    bool created = wide.ptr != NULL && CreateDirectoryW((const WCHAR *)wide.ptr, NULL);
    ms_os_wide_free(&wide);
    if (created) {
      ms_string_release(path);
      *path = text;
      return true;
    }
    ms_string_release(&text);
  }
  return false;
}

bool ms_file_rename(MsSpan from, MsSpan to) {
  MsOsWide source = ms_os_wide_new(from, true);
  MsOsWide target = ms_os_wide_new(to, true);
  bool ok = source.ptr != NULL && target.ptr != NULL &&
            MoveFileExW((const WCHAR *)source.ptr, (const WCHAR *)target.ptr, MOVEFILE_REPLACE_EXISTING);
  ms_os_wide_free(&source);
  ms_os_wide_free(&target);
  return ok;
}

void ms_path_remove(MsSpan path) {
  MsOsWide wide = ms_os_wide_new(path, true);
  if (wide.ptr != NULL) {
    (void)SetFileAttributesW((const WCHAR *)wide.ptr, FILE_ATTRIBUTE_NORMAL);
    if (!DeleteFileW((const WCHAR *)wide.ptr)) {
      (void)RemoveDirectoryW((const WCHAR *)wide.ptr);
    }
  }
  ms_os_wide_free(&wide);
}

static void remove_found(MsSpan parent, const WIN32_FIND_DATAW *found) {
  char name[1024];
  if (WideCharToMultiByte(CP_UTF8, 0, found->cFileName, -1, name, sizeof name, NULL, NULL) <= 0) {
    return;
  }
  MsSpan text = ms_span_of_text(name);
  if (ms_span_is_text(text, ".") || ms_span_is_text(text, "..")) {
    return;
  }
  MsStrBuild child = ms_strbuild_new();
  ms_strbuild_append(&child, parent);
  ms_strbuild_append_byte(&child, '/');
  ms_strbuild_append(&child, text);
  MsString path = ms_strbuild_finish(&child);
  bool directory = (found->dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0 &&
                   (found->dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) == 0;
  if (directory) {
    ms_path_remove_tree(ms_string_span(&path));
  } else {
    ms_path_remove(ms_string_span(&path));
  }
  ms_string_release(&path);
}

void ms_path_remove_tree(MsSpan path) {
  MsStrBuild pattern = ms_strbuild_new();
  ms_strbuild_append(&pattern, path);
  ms_strbuild_append_text(&pattern, "/*");
  MsString text = ms_strbuild_finish(&pattern);
  MsOsWide wide = ms_os_wide_new(ms_string_span(&text), true);
  WIN32_FIND_DATAW found;
  HANDLE handle = wide.ptr == NULL ? INVALID_HANDLE_VALUE : FindFirstFileW((const WCHAR *)wide.ptr, &found);
  if (handle != INVALID_HANDLE_VALUE) {
    do {
      remove_found(path, &found);
    } while (FindNextFileW(handle, &found));
    (void)FindClose(handle);
  }
  ms_os_wide_free(&wide);
  ms_string_release(&text);
  ms_path_remove(path);
}

#endif
