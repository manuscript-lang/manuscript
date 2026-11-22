/* The whole-file and directory operations of base/file.h, on libuv's synchronous file-system calls so every host takes
 * the same code. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "base/file.h"

#include <uv.h>

#include "base/dir.h"
#include "base/ostext.h"

enum { READ_CHUNK = 16384, FILE_MODE = 0666, DIRECTORY_MODE = 0777, MS_PATH_BUFFER = 4096 };

/* Runs one synchronous call and cleans its request up; the result is the libuv status (negative on failure). */
#define FS_CALL(call, name, ...)                                                                                      \
  do {                                                                                                                \
    MsOsText text_ = ms_os_text_new(name);                                                                            \
    uv_fs_t request_;                                                                                                 \
    result_ = call(NULL, &request_, text_.ptr, __VA_ARGS__);                                                          \
    uv_fs_req_cleanup(&request_);                                                                                     \
    ms_os_text_free(&text_);                                                                                          \
  } while (0)

static int open_file(MsSpan path, int flags, int mode) {
  MsOsText name = ms_os_text_new(path);
  uv_fs_t request;
  const int fd = uv_fs_open(NULL, &request, name.ptr, flags, mode, NULL);
  uv_fs_req_cleanup(&request);
  ms_os_text_free(&name);
  return fd;
}

static void close_file(int fd) {
  uv_fs_t request;
  (void)uv_fs_close(NULL, &request, fd, NULL);
  uv_fs_req_cleanup(&request);
}

bool ms_file_read(MsSpan path, MsBytes *out) {
  const int fd = open_file(path, UV_FS_O_RDONLY, 0);
  if (fd < 0) {
    return false;
  }
  MsBytes bytes = {0};
  int count = 0;
  do {
    uint8_t *room = ms_list_extend(&bytes, 1, READ_CHUNK);
    uv_buf_t buffer = uv_buf_init((char *)room, READ_CHUNK);
    uv_fs_t request;
    count = (int)uv_fs_read(NULL, &request, fd, &buffer, 1, -1, NULL);
    uv_fs_req_cleanup(&request);
    bytes.len -= READ_CHUNK - (count > 0 ? (size_t)count : 0);
  } while (count > 0);
  close_file(fd);
  if (count < 0) {
    ms_bytes_free(&bytes);
    return false;
  }
  ms_bytes_free(out);
  *out = bytes;
  return true;
}

bool ms_file_write(MsSpan path, MsSpan data) {
  const int fd = open_file(path, UV_FS_O_WRONLY | UV_FS_O_CREAT | UV_FS_O_TRUNC, FILE_MODE);
  if (fd < 0) {
    return false;
  }
  size_t written = 0;
  bool ok = true;
  while (ok && written < data.len) {
    uv_buf_t buffer = uv_buf_init((char *)(uintptr_t)(data.ptr + written), (unsigned int)(data.len - written));
    uv_fs_t request;
    const int count = (int)uv_fs_write(NULL, &request, fd, &buffer, 1, -1, NULL);
    uv_fs_req_cleanup(&request);
    ok = count > 0;
    written += ok ? (size_t)count : 0;
  }
  close_file(fd);
  return ok;
}

/* The mode of `path`, following links; false when it does not exist. */
static bool stat_mode(MsSpan path, uint64_t *mode) {
  MsOsText name = ms_os_text_new(path);
  uv_fs_t request;
  const bool ok = uv_fs_stat(NULL, &request, name.ptr, NULL) == 0;
  *mode = ok ? request.statbuf.st_mode : 0;
  uv_fs_req_cleanup(&request);
  ms_os_text_free(&name);
  return ok;
}

bool ms_file_is_regular(MsSpan path) {
  uint64_t mode = 0;
  return stat_mode(path, &mode) && (mode & S_IFMT) == S_IFREG;
}

bool ms_dir_exists(MsSpan path) {
  uint64_t mode = 0;
  return stat_mode(path, &mode) && (mode & S_IFMT) == S_IFDIR;
}

static bool make_one(MsSpan path) {
  int result_ = 0;
  FS_CALL(uv_fs_mkdir, path, DIRECTORY_MODE, NULL);
  return result_ == 0 || result_ == UV_EEXIST;
}

bool ms_dir_make_all(MsSpan path) {
  for (size_t end = 1; end <= path.len; end++) {
    if (end != path.len && path.ptr[end] != '/') {
      continue;
    }
    const bool drive = end == 2 && path.ptr[1] == ':'; /* "C:" names a drive, not a directory */
    if (!drive && !make_one(ms_span_of(path.ptr, end))) {
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
  uv_fs_t request;
  const bool ok = uv_fs_mkdtemp(NULL, &request, name.ptr, NULL) == 0;
  if (ok) {
    ms_string_release(path);
    *path = ms_string_from_span(ms_span_of_text(request.path));
  }
  uv_fs_req_cleanup(&request);
  ms_os_text_free(&name);
  ms_string_release(&text);
  return ok;
}

bool ms_file_rename(MsSpan from, MsSpan to) {
  MsOsText source = ms_os_text_new(from);
  MsOsText target = ms_os_text_new(to);
  uv_fs_t request;
  const bool ok = uv_fs_rename(NULL, &request, source.ptr, target.ptr, NULL) == 0;
  uv_fs_req_cleanup(&request);
  ms_os_text_free(&source);
  ms_os_text_free(&target);
  return ok;
}

void ms_path_remove(MsSpan path) {
  int result_ = 0;
  FS_CALL(uv_fs_unlink, path, NULL);
  if (result_ != 0) {
    FS_CALL(uv_fs_rmdir, path, NULL);
  }
  (void)result_;
}

void ms_path_remove_tree(MsSpan path) {
  MsDirEntryList entries = {0};
  if (ms_dir_list(path, &entries)) {
    for (size_t index = 0; index < entries.len; index++) {
      MsStrBuild child = ms_strbuild_new();
      ms_strbuild_append(&child, path);
      ms_strbuild_append_byte(&child, '/');
      ms_strbuild_append(&child, ms_string_span(&entries.ptr[index].name));
      if (entries.ptr[index].kind == MS_PATH_DIRECTORY) {
        ms_path_remove_tree(ms_strbuild_span(&child));
      } else {
        ms_path_remove(ms_strbuild_span(&child));
      }
      ms_strbuild_free(&child);
    }
  }
  ms_dir_entries_free(&entries);
  ms_path_remove(path);
}

/* Paths are '/'-separated inside the toolchain; Windows reports them with '\\'. */
static void slash_separators(char *text, size_t size) {
#ifdef _WIN32
  for (size_t at = 0; at < size; at++) {
    text[at] = text[at] == '\\' ? '/' : text[at];
  }
#else
  (void)text;
  (void)size;
#endif
}

bool ms_file_real_path(MsSpan path, MsString *out) {
  MsOsText name = ms_os_text_new(path);
  uv_fs_t request;
  const bool ok = uv_fs_realpath(NULL, &request, name.ptr, NULL) == 0;
  if (ok) {
    const MsSpan real = ms_span_of_text(request.ptr);
    slash_separators(request.ptr, real.len);
    ms_string_release(out);
    *out = ms_string_from_span(real);
  }
  uv_fs_req_cleanup(&request);
  ms_os_text_free(&name);
  return ok;
}

bool ms_dir_current(MsString *path) {
  char buffer[MS_PATH_BUFFER];
  size_t size = sizeof buffer;
  if (uv_cwd(buffer, &size) != 0) {
    return false;
  }
  slash_separators(buffer, size);
  ms_string_release(path);
  *path = ms_string_from_span(ms_span_of((const uint8_t *)buffer, size));
  return true;
}

MsString ms_temp_dir(void) {
  char buffer[MS_PATH_BUFFER];
  size_t size = sizeof buffer;
  if (uv_os_tmpdir(buffer, &size) != 0) {
    return ms_string_from_span(ms_span_of_text("/tmp"));
  }
  return ms_string_from_span(ms_span_of((const uint8_t *)buffer, size));
}
