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


/* ---- descriptors (libuv's file numbers: CRT descriptors on Windows) ---- */

/* The same as ms_sys_fs_set_times, on an open descriptor. */
int ms_sys_fs_set_times_fd(int fd, int64_t accessed_seconds, int64_t accessed_nanos, int64_t modified_seconds,
                           int64_t modified_nanos);
/* Moves the file position: `origin` is 0 (start), 1 (current) or 2 (end). Returns 0 and the new position, or a status. */
int ms_sys_fs_seek(int fd, int64_t offset, int origin, int64_t *position);
/* A second descriptor of the same open file, closed on its own and not inherited: its number, or a negative status. */
int ms_sys_fs_dup(int fd);
/* An advisory lock on the whole file, without waiting: *taken says whether it was granted. */
int ms_sys_fs_try_lock(int fd, bool exclusive, bool *taken);
int ms_sys_fs_unlock(int fd);
/* Whether the scheduler can wait for `fd` to become ready (a pipe, a terminal, a socket), as opposed to a descriptor whose
 * reads must run on the blocking pool (a regular file, anything on Windows). */
bool ms_sys_fs_waitable(int fd);

#endif
