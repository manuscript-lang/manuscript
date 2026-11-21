/* base/dir.h on Windows. Not yet built or run on Windows. */
#ifdef _WIN32
#include <windows.h>

#include "base/dir.h"
#include "base/ostext.h"

static MsPathKind kind_of_attributes(DWORD attributes) {
  if ((attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
    return MS_PATH_SYMLINK;
  }
  return (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0 ? MS_PATH_DIRECTORY : MS_PATH_FILE;
}

MsPathKind ms_path_kind(MsSpan path) {
  MsOsWide wide = ms_os_wide_new(path, true);
  const DWORD attributes = wide.ptr == NULL ? INVALID_FILE_ATTRIBUTES : GetFileAttributesW((const WCHAR *)wide.ptr);
  ms_os_wide_free(&wide);
  return attributes == INVALID_FILE_ATTRIBUTES ? MS_PATH_MISSING : kind_of_attributes(attributes);
}

static MsString utf8_name(const WCHAR *name) {
  const int size = WideCharToMultiByte(CP_UTF8, 0, name, -1, NULL, 0, NULL, NULL);
  MsStrBuild text = ms_strbuild_new();
  if (size > 1) {
    uint8_t *room = ms_list_extend(&text.bytes, 1, (size_t)size - 1);
    (void)WideCharToMultiByte(CP_UTF8, 0, name, -1, (char *)room, size - 1, NULL, NULL);
  }
  return ms_strbuild_finish(&text);
}

bool ms_dir_list(MsSpan path, MsDirEntryList *out) {
  MsStrBuild pattern = ms_strbuild_new();
  ms_strbuild_append(&pattern, path);
  ms_strbuild_append_text(&pattern, "/*");
  MsOsWide wide = ms_os_wide_new(ms_strbuild_span(&pattern), true);
  ms_strbuild_free(&pattern);
  WIN32_FIND_DATAW data;
  HANDLE find = wide.ptr == NULL ? INVALID_HANDLE_VALUE : FindFirstFileW((const WCHAR *)wide.ptr, &data);
  ms_os_wide_free(&wide);
  if (find == INVALID_HANDLE_VALUE) {
    return false;
  }
  do {
    MsString name = utf8_name(data.cFileName);
    if (ms_span_is_text(ms_string_span(&name), ".") || ms_span_is_text(ms_string_span(&name), "..")) {
      ms_string_release(&name);
      continue;
    }
    ms_dir_entry_list_push(out, (MsDirEntry){.name = name, .kind = kind_of_attributes(data.dwFileAttributes)});
  } while (FindNextFileW(find, &data));
  const bool complete = GetLastError() == ERROR_NO_MORE_FILES;
  FindClose(find);
  return complete;
}
#endif
