/* The file calls the project loader makes, over the OS layer (ms_rt/sys_fs.h) so one source serves Linux, macOS and
 * Windows. An error code is the layer's MsSysError (the errno on Unix, the Win32 code on Windows): read it with
 * host_missing and friends, never compare it with ENOENT. */
#ifndef MS_PROJECT_HOST_H
#define MS_PROJECT_HOST_H

#include "ms_rt/sys_fs.h"

static inline bool host_is_dir(const MsSysStat *info) { return (info->mode & MS_SYS_S_IFMT) == MS_SYS_S_IFDIR; }
static inline bool host_is_reg(const MsSysStat *info) { return (info->mode & MS_SYS_S_IFMT) == MS_SYS_S_IFREG; }
static inline bool host_is_link(const MsSysStat *info) { return (info->mode & MS_SYS_S_IFMT) == MS_SYS_S_IFLNK; }

static inline bool host_missing(MsSysError code) { return ms_sys_fs_error_kind(code) == MS_SYS_ERR_NOT_FOUND; }
static inline bool host_exists_error(MsSysError code) { return ms_sys_fs_error_kind(code) == MS_SYS_ERR_EXISTS; }
static inline bool host_denied(MsSysError code) { return ms_sys_fs_error_kind(code) == MS_SYS_ERR_PERMISSION; }

/* The code for "not a directory" that the symlink walk reports (ERROR_DIRECTORY on Windows). */
#ifdef _WIN32
enum { HOST_NOT_DIRECTORY = 267 };
#else
enum { HOST_NOT_DIRECTORY = 20 /* ENOTDIR */ };
#endif

/* Whether `path` names a directory (following links) or a regular file. */
static inline bool host_dir_exists(const char *path) {
    MsSysStat info;
    return ms_sys_fs_stat(path, true, &info) == 0 && host_is_dir(&info);
}
static inline bool host_file_exists(const char *path) {
    MsSysStat info;
    return ms_sys_fs_stat(path, true, &info) == 0 && host_is_reg(&info);
}

#endif
