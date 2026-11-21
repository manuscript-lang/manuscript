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

/* ---- running a program to completion ---- */

/* What a program run wrote. `out` and `err` are malloc'd and NUL-terminated (`err` is NULL when the run merged the two);
 * the caller frees them. `code` is the exit status, or -1 when a signal ended the program. */
typedef struct MsSysRun {
    int32_t code;
    char *out;
    size_t out_length;
    char *err;
    size_t err_length;
} MsSysRun;

/* Runs `argv[0]` (looked up on PATH; argv ends with NULL) to completion with no standard input, and captures its
 * output. `env` lists `NAME=value` strings (ending with NULL, or NULL for none) that replace or add to this process's
 * environment in the program's. `cwd` is the working directory, or NULL for this process's. `merge` sends the
 * program's standard error into `out`. Fails when the program cannot be started (MS_SYS_ERR_NOT_FOUND for a missing
 * one); a nonzero exit is not a failure here. */
MS_NODISCARD MsSysError ms_sys_process_run(char *const *argv, char *const *env, const char *cwd, bool merge,
                                           MsSysRun *run);
void ms_sys_process_run_free(MsSysRun *run);

/* The process title: the short command name on Linux (/proc comm), the console title on Windows, unsupported
 * elsewhere. Text is not NUL-terminated. */
MS_NODISCARD MsSysError ms_sys_process_title(char **text, size_t *length);
MS_NODISCARD MsSysError ms_sys_process_set_title(const char *text, size_t length);

#endif
