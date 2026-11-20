/* ms_rt/sys_process.h: process state the OS layer owns and libuv does not wrap: the file-creation mask, user and group
 * identity, and the process title. Implemented per platform: sys/posix/process.c and sys/windows/process.c (which
 * report MS_SYS_ERR_UNSUPPORTED for what the platform lacks).
 *
 * A function returns 0 or the host's error code, read through ms_sys_fs_error_kind as in ms_rt/sys_fs.h. A list or
 * text it returns is allocated with malloc and the caller frees it: these functions are not told which thread
 * calls them.
 */
#ifndef MS_RT_SYS_PROCESS_H
#define MS_RT_SYS_PROCESS_H

#include "ms_rt/base.h"
#include "ms_rt/safe.h"
#include "ms_rt/sys_fs.h"

typedef enum { MS_SYS_ID_UID, MS_SYS_ID_GID, MS_SYS_ID_EUID, MS_SYS_ID_EGID } MsSysIdentity;

/* The process's user or group id, or -1 on a platform that has none. */
int64_t ms_sys_process_identity(MsSysIdentity which);
/* Sets the file-creation mask and reports the previous one. */
MS_NODISCARD MsSysError ms_sys_process_umask(uint32_t mask, uint32_t *previous);
/* The supplementary groups of the process. */
MS_NODISCARD MsSysError ms_sys_process_groups(int64_t **list, size_t *count);
MS_NODISCARD MsSysError ms_sys_process_set_groups(const int64_t *list, size_t count);
MS_NODISCARD MsSysError ms_sys_process_set_identity(MsSysIdentity which, uint32_t id);
/* The group ids of user `name` (its primary group included); MS_SYS_ERR_NOT_FOUND for an unknown user. */
MS_NODISCARD MsSysError ms_sys_process_user_groups(const char *name, int64_t **list, size_t *count);

/* The process title: the short command name on Linux (/proc comm), the console title on Windows, unsupported
 * elsewhere. Text is not NUL-terminated. */
MS_NODISCARD MsSysError ms_sys_process_title(char **text, size_t *length);
MS_NODISCARD MsSysError ms_sys_process_set_title(const char *text, size_t length);

#endif
