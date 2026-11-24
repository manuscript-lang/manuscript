/* The file-system calls libuv cannot make exactly (sys/fs.h). */
#include <errno.h>
#include <fcntl.h>
#include <io.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <uv.h>
#include <windows.h>

#include "base/ostext.h"
#include "base/strbuild.h"
#include "runtime/sys/fs.h"

static double seconds_of(int64_t seconds, int64_t nanos) { return (double)seconds + (double)nanos / 1e9; }

int ms_sys_fs_set_times(const char *path, int64_t accessed_seconds, int64_t accessed_nanos, int64_t modified_seconds,
                        int64_t modified_nanos, bool follow) {
  uv_fs_t request;
  const double accessed = seconds_of(accessed_seconds, accessed_nanos);
  const double modified = seconds_of(modified_seconds, modified_nanos);
  const int code = follow ? uv_fs_utime(NULL, &request, path, accessed, modified, NULL)
                          : uv_fs_lutime(NULL, &request, path, accessed, modified, NULL);
  uv_fs_req_cleanup(&request);
  return code;
}

int ms_sys_fs_chmod_link(const char *path, uint32_t mode) {
  (void)path;
  (void)mode;
  return UV_ENOTSUP;
}

int ms_sys_fs_set_times_fd(int fd, int64_t accessed_seconds, int64_t accessed_nanos, int64_t modified_seconds,
                           int64_t modified_nanos) {
  uv_fs_t request;
  const int code = uv_fs_futime(NULL, &request, fd, seconds_of(accessed_seconds, accessed_nanos),
                                seconds_of(modified_seconds, modified_nanos), NULL);
  uv_fs_req_cleanup(&request);
  return code;
}

int ms_sys_fs_try_lock(int fd, bool exclusive, bool *taken) {
  const HANDLE handle = (HANDLE)uv_get_osfhandle(fd);
  if (handle == INVALID_HANDLE_VALUE) {
    return UV_EBADF;
  }
  OVERLAPPED range = {0};
  const DWORD flags = LOCKFILE_FAIL_IMMEDIATELY | (exclusive ? LOCKFILE_EXCLUSIVE_LOCK : 0);
  if (LockFileEx(handle, flags, 0, MAXDWORD, MAXDWORD, &range)) {
    *taken = true;
    return 0;
  }
  const DWORD error = GetLastError();
  if (error == ERROR_LOCK_VIOLATION) {
    *taken = false;
    return 0;
  }
  return uv_translate_sys_error((int)error);
}

int ms_sys_fs_unlock(int fd) {
  const HANDLE handle = (HANDLE)uv_get_osfhandle(fd);
  if (handle == INVALID_HANDLE_VALUE) {
    return UV_EBADF;
  }
  OVERLAPPED range = {0};
  return UnlockFileEx(handle, 0, MAXDWORD, MAXDWORD, &range) ? 0 : uv_translate_sys_error((int)GetLastError());
}

bool ms_sys_fs_waitable(int fd) {
  (void)fd;
  return false;
}

int ms_sys_fs_clone_file(int output, int input) {
  (void)output;
  (void)input;
  return UV_ENOTSUP;
}

bool ms_sys_fs_watch_recursive(void) {
  return true;
}

bool ms_sys_fs_watch_names_self(void) {
  return false;
}

bool ms_sys_fs_watch_drops_batches(void) {
  return true;
}

const char *ms_sys_fs_watch_ready_prefix(void) {
  return "";
}

int ms_sys_fs_redirect_null(int which) {
  const int null = _open("NUL", _O_RDWR);
  if (null < 0) {
    return uv_translate_sys_error((int)GetLastError());
  }
  const int moved = _dup2(null, which);
  const int code = moved < 0 ? uv_translate_sys_error((int)GetLastError()) : 0;
  (void)_close(null);
  return code;
}

/* NTFS and ReFS name components hold 255 UTF-16 units; libuv maps ERROR_FILENAME_EXCED_RANGE to UV_ENOENT. */
enum { COMPONENT_LIMIT = 255 };

int ms_sys_fs_refine_error(int code, const char *path, size_t length) {
  if (code != UV_ENOENT) {
    return code;
  }
  size_t units = 0;
  for (size_t at = 0; at < length; at++) {
    const unsigned char byte = (unsigned char)path[at];
    if (byte == '/' || byte == '\\') {
      units = 0;
    } else if ((byte & 0xC0) != 0x80) { /* a lead byte starts a code point; a 4-byte one is two UTF-16 units */
      units += byte >= 0xF0 ? 2 : 1;
    }
    if (units > COMPONENT_LIMIT) {
      return UV_ENAMETOOLONG;
    }
  }
  return code;
}

/* Whether `target`, as a link at `path` would resolve it, is a directory. */
static bool names_directory(const char *target, const char *path) {
  const bool rooted = target[0] == '/' || target[0] == '\\' || (target[0] != '\0' && target[1] == ':');
  const char *separator = NULL;
  for (const char *at = path; *at != '\0'; at++) {
    if (*at == '/' || *at == '\\') {
      separator = at;
    }
  }
  MsStrBuild joined = ms_strbuild_new();
  MsOsText text = {0};
  const char *resolved = target;
  if (!rooted && separator != NULL) {
    ms_strbuild_append(&joined, ms_span_of((const uint8_t *)path, (size_t)(separator - path) + 1));
    ms_strbuild_append_text(&joined, target);
    text = ms_os_text_new(ms_strbuild_span(&joined));
    resolved = text.ptr;
  }
  uv_fs_t request;
  const bool directory = uv_fs_stat(NULL, &request, resolved, NULL) == 0 && (request.statbuf.st_mode & 0170000u) == 0040000u;
  uv_fs_req_cleanup(&request);
  if (resolved != target) {
    ms_os_text_free(&text);
  }
  ms_strbuild_free(&joined);
  return directory;
}

int ms_sys_fs_symlink(const char *target, const char *path) {
  uv_fs_t request;
  const int flags = names_directory(target, path) ? UV_FS_SYMLINK_DIR : 0;
  const int code = uv_fs_symlink(NULL, &request, target, path, flags, NULL);
  uv_fs_req_cleanup(&request);
  return code;
}
