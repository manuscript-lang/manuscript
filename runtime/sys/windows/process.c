/* Process state on Windows: no user or group ids and no umask, so those report unsupported; the title is the console
 * title. A process without a console keeps the title it was given in memory, as a program expects get_title to
 * return what set_title stored. */
#include <windows.h>

#include <stdlib.h>
#include <string.h>

#include "ms_rt/sys_process.h"

enum { TITLE_UNITS = 32768 };

static SRWLOCK title_lock = SRWLOCK_INIT;
static char *stored_title; /* malloc'd; guarded by title_lock */
static size_t stored_length;

static MsSysError unsupported(void) { return ms_sys_fs_error_of(MS_SYS_ERR_UNSUPPORTED); }

int64_t ms_sys_process_identity(MsSysIdentity which) {
    (void)which;
    return -1;
}

MsSysError ms_sys_process_umask(uint32_t mask, uint32_t *previous) {
    (void)mask;
    (void)previous;
    return unsupported();
}

MsSysError ms_sys_process_groups(int64_t **list, size_t *count) {
    (void)list;
    (void)count;
    return unsupported();
}

MsSysError ms_sys_process_set_groups(const int64_t *list, size_t count) {
    (void)list;
    (void)count;
    return unsupported();
}

MsSysError ms_sys_process_set_identity(MsSysIdentity which, uint32_t id) {
    (void)which;
    (void)id;
    return unsupported();
}

MsSysError ms_sys_process_user_groups(const char *name, int64_t **list, size_t *count) {
    (void)name;
    (void)list;
    (void)count;
    return unsupported();
}

static MsSysError utf8_of(const wchar_t *wide, int units, char **text, size_t *length) {
    const int needed = WideCharToMultiByte(CP_UTF8, 0, wide, units, NULL, 0, NULL, NULL);
    if (needed < 0) {
        return GetLastError();
    }
    char *bytes = malloc((size_t)needed + 1);
    if (bytes == NULL) {
        return ERROR_NOT_ENOUGH_MEMORY;
    }
    if (needed > 0 && WideCharToMultiByte(CP_UTF8, 0, wide, units, bytes, needed, NULL, NULL) == 0) {
        const MsSysError error = GetLastError();
        free(bytes);
        return error;
    }
    *text = bytes;
    *length = (size_t)needed;
    return 0;
}

/* The executable's base name, the title of a process that has no console. */
static MsSysError executable_name(char **text, size_t *length) {
    wchar_t path[MAX_PATH];
    const DWORD units = GetModuleFileNameW(NULL, path, MAX_PATH);
    if (units == 0 || units >= MAX_PATH) {
        return GetLastError();
    }
    const wchar_t *base = path;
    for (const wchar_t *p = path; *p != 0; p++) {
        if (*p == L'\\' || *p == L'/') {
            base = p + 1;
        }
    }
    return utf8_of(base, (int)wcslen(base), text, length);
}

MsSysError ms_sys_process_title(char **text, size_t *length) {
    AcquireSRWLockShared(&title_lock);
    if (stored_title != NULL) {
        char *copy = malloc(stored_length + 1);
        if (copy != NULL) {
            memcpy(copy, stored_title, stored_length);
            *text = copy;
            *length = stored_length;
        }
        ReleaseSRWLockShared(&title_lock);
        return copy != NULL ? 0 : ERROR_NOT_ENOUGH_MEMORY;
    }
    ReleaseSRWLockShared(&title_lock);
    wchar_t *wide = malloc(TITLE_UNITS * sizeof *wide);
    if (wide == NULL) {
        return ERROR_NOT_ENOUGH_MEMORY;
    }
    SetLastError(0);
    const DWORD units = GetConsoleTitleW(wide, TITLE_UNITS);
    MsSysError error = 0;
    if (units == 0 && GetLastError() != 0) {
        error = executable_name(text, length);
    } else {
        error = utf8_of(wide, (int)units, text, length);
    }
    free(wide);
    return error;
}

MsSysError ms_sys_process_set_title(const char *text, size_t length) {
    const int units = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, (int)length, NULL, 0);
    if (units < 0 || (units == 0 && length > 0)) {
        return ERROR_NO_UNICODE_TRANSLATION;
    }
    wchar_t *wide = malloc(((size_t)units + 1) * sizeof *wide);
    if (wide == NULL) {
        return ERROR_NOT_ENOUGH_MEMORY;
    }
    if (units > 0) {
        (void)MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, (int)length, wide, units);
    }
    wide[units] = 0;
    const BOOL set = SetConsoleTitleW(wide);
    const DWORD error = set ? 0 : GetLastError();
    free(wide);
    if (!set && error != ERROR_INVALID_HANDLE) {
        return error;
    }
    char *copy = malloc(length + 1);
    if (copy == NULL) {
        return ERROR_NOT_ENOUGH_MEMORY;
    }
    memcpy(copy, text, length);
    AcquireSRWLockExclusive(&title_lock);
    free(stored_title);
    stored_title = copy;
    stored_length = length;
    ReleaseSRWLockExclusive(&title_lock);
    return 0;
}
