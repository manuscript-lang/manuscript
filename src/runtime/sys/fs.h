/* runtime/sys/fs.h: the file-system calls libuv cannot make exactly. Errors are libuv statuses (0 or a negative UV_E*
 * code). */
#ifndef MS_RUNTIME_SYS_FS_H
#define MS_RUNTIME_SYS_FS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Sets the access and modification times of `path` (of the link itself unless `follow`) to the nanosecond: libuv's
 * doubles cannot hold them. Windows keeps its 100 ns ticks. */
int ms_sys_fs_set_times(const char *path, int64_t accessed_seconds, int64_t accessed_nanos, int64_t modified_seconds,
                        int64_t modified_nanos, bool follow);

/* The status libuv reported for an operation on `path`, made as exact as the host allows: Windows reports a name
 * component past its 255-unit limit as UV_ENOENT, and this turns it back into UV_ENAMETOOLONG. */
int ms_sys_fs_refine_error(int code, const char *path, size_t length);

/* Makes the symbolic link `path` name `target`. Windows has file and directory links and libuv does not choose: a
 * target that is a directory (found relative to the link's folder) makes a directory link, which a file link cannot
 * be traversed as. */
int ms_sys_fs_symlink(const char *target, const char *path);

/* Changes the permission bits of a symbolic link itself: UV_ENOTSUP where the host cannot. */
int ms_sys_fs_chmod_link(const char *path, uint32_t mode);


/* ---- descriptors (libuv's file numbers: CRT descriptors on Windows) ---- */

/* The same as ms_sys_fs_set_times, on an open descriptor. */
int ms_sys_fs_set_times_fd(int fd, int64_t accessed_seconds, int64_t accessed_nanos, int64_t modified_seconds,
                           int64_t modified_nanos);
/* An advisory lock on the whole file, without waiting: *taken says whether it was granted. */
int ms_sys_fs_try_lock(int fd, bool exclusive, bool *taken);
int ms_sys_fs_unlock(int fd);
/* Whether the scheduler can wait for `fd` to become ready (a pipe, a terminal, a socket), as opposed to a descriptor whose
 * reads must run on the blocking pool (a regular file, anything on Windows). */
bool ms_sys_fs_waitable(int fd);

/* Makes `output` share the data blocks of `input` (copy on write): UV_ENOTSUP where the filesystem or host cannot. */
int ms_sys_fs_clone_file(int output, int input);

/* File watching (libuv's uv_fs_event underneath). Whether a watch on a directory covers its subtree (macOS, Windows);
 * elsewhere a recursive watcher holds a handle per directory. */
bool ms_sys_fs_watch_recursive(void);
/* Whether the host names a change to a watched directory by the directory's own name (FSEvents, inotify). */
bool ms_sys_fs_watch_names_self(void);
/* Whether the host reports a batch of changes it dropped (its fixed change buffer filled) as one change with no name
 * (Windows, 4 KiB per handle), so the watcher must list the tree again to find what happened. */
bool ms_sys_fs_watch_drops_batches(void);
/* The name prefix of the file a new watcher touches until the host's event stream reports it (FSEvents starts its
 * stream late); empty where watches are live at once. */
const char *ms_sys_fs_watch_ready_prefix(void);

/* Points standard stream `which` (0 input, 1 output, 2 error) at the null device. 0, or a libuv status. */
int ms_sys_fs_redirect_null(int which);

#endif
