/* The file-system calls libuv cannot make exactly (sys/fs.h). */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */
#define _DARWIN_C_SOURCE        /* utimensat and fchmodat on macOS under -std=c17 */

#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <time.h>
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
