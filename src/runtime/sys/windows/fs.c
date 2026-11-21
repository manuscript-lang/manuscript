/* The file-system calls libuv cannot make exactly (sys/fs.h). */
#include <uv.h>

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
