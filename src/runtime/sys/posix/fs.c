/* The file-system calls libuv cannot make exactly (sys/fs.h). */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */
#define _DARWIN_C_SOURCE        /* utimensat and fchmodat on macOS under -std=c17 */

#include <errno.h>
#include <fcntl.h>
#include <sys/file.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#include <uv.h>

#include "runtime/sys/fs.h"

static struct timespec timespec_of(int64_t seconds, int64_t nanos) {
  if (nanos < 0) {
    nanos = 0;
  } else if (nanos > 999999999) {
    nanos = 999999999;
  }
  return (struct timespec){.tv_sec = (time_t)seconds, .tv_nsec = (long)nanos};
}

int ms_sys_fs_set_times(const char *path, int64_t accessed_seconds, int64_t accessed_nanos, int64_t modified_seconds,
                        int64_t modified_nanos, bool follow) {
  const struct timespec times[2] = {timespec_of(accessed_seconds, accessed_nanos),
                                    timespec_of(modified_seconds, modified_nanos)};
  int result = -1;
  do {
    result = utimensat(AT_FDCWD, path, times, follow ? 0 : AT_SYMLINK_NOFOLLOW);
  } while (result != 0 && errno == EINTR);
  return result == 0 ? 0 : uv_translate_sys_error(errno);
}

int ms_sys_fs_chmod_link(const char *path, uint32_t mode) {
#ifdef __APPLE__
  int result = -1;
  do {
    result = fchmodat(AT_FDCWD, path, (mode_t)mode, AT_SYMLINK_NOFOLLOW);
  } while (result != 0 && errno == EINTR);
  return result == 0 ? 0 : uv_translate_sys_error(errno);
#else
  (void)path;
  (void)mode;
  return UV_ENOTSUP;
#endif
}

int ms_sys_fs_set_times_fd(int fd, int64_t accessed_seconds, int64_t accessed_nanos, int64_t modified_seconds,
                           int64_t modified_nanos) {
  const struct timespec times[2] = {timespec_of(accessed_seconds, accessed_nanos),
                                    timespec_of(modified_seconds, modified_nanos)};
  int result = -1;
  do {
    result = futimens(fd, times);
  } while (result != 0 && errno == EINTR);
  return result == 0 ? 0 : uv_translate_sys_error(errno);
}

int ms_sys_fs_seek(int fd, int64_t offset, int origin, int64_t *position) {
  static const int whence[] = {SEEK_SET, SEEK_CUR, SEEK_END};
  const off_t moved = lseek(fd, (off_t)offset, whence[origin]);
  if (moved < 0) {
    return uv_translate_sys_error(errno);
  }
  *position = (int64_t)moved;
  return 0;
}

int ms_sys_fs_dup(int fd) {
  int copy = -1;
  do {
    copy = fcntl(fd, F_DUPFD_CLOEXEC, 0);
  } while (copy < 0 && errno == EINTR);
  return copy < 0 ? uv_translate_sys_error(errno) : copy;
}

int ms_sys_fs_try_lock(int fd, bool exclusive, bool *taken) {
  int result = -1;
  do {
    result = flock(fd, (exclusive ? LOCK_EX : LOCK_SH) | LOCK_NB);
  } while (result != 0 && errno == EINTR);
  if (result == 0) {
    *taken = true;
    return 0;
  }
  if (errno == EWOULDBLOCK) {
    *taken = false;
    return 0;
  }
  return uv_translate_sys_error(errno);
}

int ms_sys_fs_unlock(int fd) {
  int result = -1;
  do {
    result = flock(fd, LOCK_UN);
  } while (result != 0 && errno == EINTR);
  return result == 0 ? 0 : uv_translate_sys_error(errno);
}

bool ms_sys_fs_waitable(int fd) {
  const uv_handle_type type = uv_guess_handle(fd);
  return type != UV_FILE && type != UV_UNKNOWN_HANDLE;
}

int ms_sys_fs_clone_file(int output, int input) {
#ifdef __linux__
  enum { MS_FICLONE = 0x40049409 }; /* _IOW(0x94, 9, int); the header has no stable spelling under musl */
  return ioctl(output, MS_FICLONE, input) == 0 ? 0 : uv_translate_sys_error(errno);
#else
  (void)output;
  (void)input;
  return UV_ENOTSUP;
#endif
}

bool ms_sys_fs_watch_recursive(void) {
#ifdef __APPLE__
  return true;
#else
  return false;
#endif
}

bool ms_sys_fs_watch_names_self(void) {
  return true;
}

const char *ms_sys_fs_watch_ready_prefix(void) {
#ifdef __APPLE__
  return ".ms-watch-ready-";
#else
  return "";
#endif
}

int ms_sys_fs_redirect_null(int which) {
  const int null = open("/dev/null", O_RDWR | O_CLOEXEC);
  if (null < 0) {
    return uv_translate_sys_error(errno);
  }
  const int moved = dup2(null, which);
  const int code = moved < 0 ? uv_translate_sys_error(errno) : 0;
  (void)close(null);
  return code;
}
