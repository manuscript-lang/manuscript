/* runtime/sys/fs.h: the file-system calls libuv cannot make exactly. Errors are libuv statuses (0 or a negative UV_E*
 * code). */
#ifndef MS_RUNTIME_SYS_FS_H
#define MS_RUNTIME_SYS_FS_H

#include <stdbool.h>
#include <stdint.h>

/* Sets the access and modification times of `path` (of the link itself unless `follow`) to the nanosecond: libuv's
 * doubles cannot hold them. Windows keeps its 100 ns ticks. */
int ms_sys_fs_set_times(const char *path, int64_t accessed_seconds, int64_t accessed_nanos, int64_t modified_seconds,
                        int64_t modified_nanos, bool follow);

/* Changes the permission bits of a symbolic link itself: UV_ENOTSUP where the host cannot. */
int ms_sys_fs_chmod_link(const char *path, uint32_t mode);

#endif
