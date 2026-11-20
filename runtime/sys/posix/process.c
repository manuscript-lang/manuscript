/* Process state on Linux and macOS: umask, groups, identity and the process title. */
#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <pwd.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include "ms_rt/sys_process.h"

#ifdef __APPLE__
typedef int MsGroupId; /* getgrouplist takes int on macOS */
#else
typedef gid_t MsGroupId;
#endif

enum { FIRST_GROUPS = 32, TITLE_LIMIT = 4096, PASSWD_BUFFER = 1024 };

int64_t ms_sys_process_identity(MsSysIdentity which) {
    switch (which) {
    case MS_SYS_ID_UID: return (int64_t)getuid();
    case MS_SYS_ID_GID: return (int64_t)getgid();
    case MS_SYS_ID_EUID: return (int64_t)geteuid();
    case MS_SYS_ID_EGID: return (int64_t)getegid();
    }
    return -1;
}

MsSysError ms_sys_process_umask(uint32_t mask, uint32_t *previous) {
    *previous = (uint32_t)umask((mode_t)mask);
    return 0;
}

MsSysError ms_sys_process_groups(int64_t **list, size_t *count) {
    const int total = getgroups(0, NULL);
    if (total < 0) {
        return errno;
    }
    gid_t *groups = malloc(((size_t)total + 1) * sizeof *groups);
    int64_t *out = malloc(((size_t)total + 1) * sizeof *out);
    if (groups == NULL || out == NULL) {
        free(groups);
        free(out);
        return ENOMEM;
    }
    const int got = getgroups(total, groups);
    if (got < 0) {
        const int error = errno;
        free(groups);
        free(out);
        return error;
    }
    for (int i = 0; i < got; i++) {
        out[i] = (int64_t)groups[i];
    }
    free(groups);
    *list = out;
    *count = (size_t)got;
    return 0;
}

MsSysError ms_sys_process_set_groups(const int64_t *list, size_t count) {
    gid_t *groups = malloc((count + 1) * sizeof *groups);
    if (groups == NULL) {
        return ENOMEM;
    }
    for (size_t i = 0; i < count; i++) {
        groups[i] = (gid_t)list[i];
    }
    const int status = setgroups(count, groups);
    const int error = status == 0 ? 0 : errno;
    free(groups);
    return error;
}

MsSysError ms_sys_process_set_identity(MsSysIdentity which, uint32_t id) {
    int status = -1;
    switch (which) {
    case MS_SYS_ID_UID:
        status = setuid((uid_t)id);
        break;
    case MS_SYS_ID_GID:
        status = setgid((gid_t)id);
        break;
    case MS_SYS_ID_EUID:
        status = seteuid((uid_t)id);
        break;
    case MS_SYS_ID_EGID:
        status = setegid((gid_t)id);
        break;
    }
    return status == 0 ? 0 : errno;
}

MsSysError ms_sys_process_user_groups(const char *name, int64_t **list, size_t *count) {
    long hint = sysconf(_SC_GETPW_R_SIZE_MAX);
    size_t size = hint > 0 ? (size_t)hint : PASSWD_BUFFER;
    char *text = malloc(size);
    struct passwd record;
    struct passwd *entry = NULL;
    while (text != NULL) {
        const int status = getpwnam_r(name, &record, text, size, &entry);
        if (status != ERANGE) {
            if (status != 0) {
                free(text);
                return status;
            }
            break;
        }
        size *= 2;
        char *grown = realloc(text, size);
        if (grown == NULL) {
            free(text);
            return ENOMEM;
        }
        text = grown;
    }
    if (text == NULL) {
        return ENOMEM;
    }
    const gid_t primary = entry != NULL ? entry->pw_gid : 0;
    free(text);
    if (entry == NULL) {
        return ms_sys_fs_error_of(MS_SYS_ERR_NOT_FOUND);
    }
    int capacity = FIRST_GROUPS;
    MsGroupId *ids = malloc((size_t)capacity * sizeof *ids);
    while (ids != NULL) {
        int found = capacity;
        if (getgrouplist(name, (MsGroupId)primary, ids, &found) >= 0) {
            int64_t *out = malloc(((size_t)found + 1) * sizeof *out);
            if (out == NULL) {
                free(ids);
                return ENOMEM;
            }
            for (int i = 0; i < found; i++) {
                out[i] = (int64_t)ids[i];
            }
            free(ids);
            *list = out;
            *count = (size_t)found;
            return 0;
        }
        capacity = found > capacity ? found : capacity * 2;
        MsGroupId *grown = realloc(ids, (size_t)capacity * sizeof *ids);
        if (grown == NULL) {
            free(ids);
            return ENOMEM;
        }
        ids = grown;
    }
    return ENOMEM;
}

#ifdef __linux__
static const char comm_path[] = "/proc/self/comm";

MsSysError ms_sys_process_title(char **text, size_t *length) {
    const int fd = open(comm_path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        return errno;
    }
    char *buffer = malloc(TITLE_LIMIT);
    if (buffer == NULL) {
        close(fd);
        return ENOMEM;
    }
    const ssize_t got = read(fd, buffer, TITLE_LIMIT);
    const int error = got < 0 ? errno : 0;
    close(fd);
    if (got < 0) {
        free(buffer);
        return error;
    }
    size_t size = (size_t)got;
    if (size > 0 && buffer[size - 1] == '\n') {
        size--;
    }
    *text = buffer;
    *length = size;
    return 0;
}

MsSysError ms_sys_process_set_title(const char *text, size_t length) {
    const int fd = open(comm_path, O_WRONLY | O_TRUNC | O_CLOEXEC);
    if (fd < 0) {
        return errno;
    }
    const ssize_t put = write(fd, text, length);
    const int error = put < 0 ? errno : 0;
    close(fd);
    return error;
}
#else
MsSysError ms_sys_process_title(char **text, size_t *length) {
    (void)text;
    (void)length;
    return ms_sys_fs_error_of(MS_SYS_ERR_UNSUPPORTED);
}

MsSysError ms_sys_process_set_title(const char *text, size_t length) {
    (void)text;
    (void)length;
    return ms_sys_fs_error_of(MS_SYS_ERR_UNSUPPORTED);
}
#endif
