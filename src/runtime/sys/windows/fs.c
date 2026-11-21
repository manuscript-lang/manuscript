/* The file-system calls libuv cannot make exactly (sys/fs.h). */
#include <errno.h>
#include <io.h>
#include <stdio.h>
#include <uv.h>
#include <windows.h>

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

int ms_sys_fs_seek(int fd, int64_t offset, int origin, int64_t *position) {
  static const int whence[] = {SEEK_SET, SEEK_CUR, SEEK_END};
  const int64_t moved = _lseeki64(fd, offset, whence[origin]);
  if (moved < 0) {
    return uv_translate_sys_error(errno);
  }
  *position = (int64_t)moved;
  return 0;
}

int ms_sys_fs_dup(int fd) {
  const int copy = _dup(fd);
  return copy < 0 ? uv_translate_sys_error(errno) : copy;
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

const char *ms_sys_fs_watch_ready_prefix(void) {
  return "";
}
