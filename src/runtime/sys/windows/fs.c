/* Files, directories and paths on Windows: the one place src/runtime/std reaches the Win32 file calls (ms_rt/sys_fs.h).
 * Paths arrive as UTF-8 and are converted to UTF-16 here; every function returns 0 or the Win32 error code. */
#define WIN32_LEAN_AND_MEAN
#define UNICODE
#define _UNICODE
#include <windows.h>
#include <winioctl.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms_rt/sys.h"
#include "ms_rt/sys_fs.h"

/* Win32 codes this file reports itself or reads, spelled out so the header names do not matter. */
enum {
    MS_ERROR_INVALID_PARAMETER = 87,
    MS_ERROR_FILE_EXISTS = 80,
    MS_ERROR_IO_DEVICE = 1117,
    MS_ERROR_INVALID_HANDLE = 6,
    ERROR_BROKEN_PIPE_CODE = 109,
    ERROR_NO_DATA_CODE = 232,
    MS_ERROR_NOT_SUPPORTED = 50,
    MS_ERROR_CANT_RESOLVE_FILENAME = 1921,
    MS_ERROR_NO_UNICODE_TRANSLATION = 1113
};

/* The part of a path that Win32 reads without the verbatim prefix. */
enum { MS_PATH_LIMIT = 240 };

/* ---- errors ---- */

MsSysErrorKind ms_sys_fs_error_kind(MsSysError error) {
    switch ((DWORD)error) {
    case ERROR_FILE_NOT_FOUND:
    case ERROR_PATH_NOT_FOUND:
        return MS_SYS_ERR_NOT_FOUND;
    case ERROR_ALREADY_EXISTS:
    case ERROR_FILE_EXISTS:
        return MS_SYS_ERR_EXISTS;
    case ERROR_DIR_NOT_EMPTY:
        return MS_SYS_ERR_NOT_EMPTY;
    case ERROR_DIRECTORY:
        return MS_SYS_ERR_NOT_DIRECTORY;
    case ERROR_DIRECTORY_NOT_SUPPORTED:
        return MS_SYS_ERR_IS_DIRECTORY;
    case ERROR_INVALID_PARAMETER:
        return MS_SYS_ERR_INVALID;
    case ERROR_ACCESS_DENIED:
        return MS_SYS_ERR_PERMISSION;
    case ERROR_CALL_NOT_IMPLEMENTED:
    case MS_ERROR_NOT_SUPPORTED:
        return MS_SYS_ERR_UNSUPPORTED;
    case MS_ERROR_CANT_RESOLVE_FILENAME:
        return MS_SYS_ERR_LINK_LOOP;
    case MS_ERROR_IO_DEVICE:
        return MS_SYS_ERR_IO;
    case MS_ERROR_INVALID_HANDLE:
        return MS_SYS_ERR_BAD_DESCRIPTOR;
    default:
        return MS_SYS_ERR_OTHER;
    }
}

MsSysError ms_sys_fs_error_of(MsSysErrorKind kind) {
    switch (kind) {
    case MS_SYS_ERR_INVALID:
        return MS_ERROR_INVALID_PARAMETER;
    case MS_SYS_ERR_EXISTS:
        return MS_ERROR_FILE_EXISTS;
    case MS_SYS_ERR_BAD_DESCRIPTOR:
        return MS_ERROR_INVALID_HANDLE;
    case MS_SYS_ERR_UNSUPPORTED:
        return MS_ERROR_NOT_SUPPORTED;
    case MS_SYS_ERR_NOT_FOUND:
        return ERROR_FILE_NOT_FOUND;
    case MS_SYS_ERR_PERMISSION:
        return ERROR_ACCESS_DENIED;
    case MS_SYS_ERR_IO:
    case MS_SYS_ERR_OTHER:
    case MS_SYS_ERR_NOT_EMPTY:
    case MS_SYS_ERR_NOT_DIRECTORY:
    case MS_SYS_ERR_IS_DIRECTORY:
    case MS_SYS_ERR_WOULD_BLOCK:
    case MS_SYS_ERR_LINK_LOOP:
    case MS_SYS_ERR_INTERRUPTED:
    case MS_SYS_ERR_NO_ENTRY_DEVICE:
        break;
    }
    return MS_ERROR_IO_DEVICE;
}

size_t ms_sys_fs_error_text(MsSysError error, char *buffer, size_t capacity) {
    if (capacity == 0) {
        return 0;
    }
    WCHAR wide[512];
    const DWORD units = FormatMessageW(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, NULL,
                                       (DWORD)error, 0, wide, (DWORD)MS_COUNT_OF(wide), NULL);
    int length = 0;
    if (units != 0) {
        length = WideCharToMultiByte(CP_UTF8, 0, wide, (int)units, buffer, (int)(capacity - 1), NULL, NULL);
    }
    if (length <= 0) {
        length = snprintf(buffer, capacity, "os error %lu", (unsigned long)(DWORD)error);
        length = length < 0 ? 0 : length;
    }
    while (length > 0 && (buffer[length - 1] == '\r' || buffer[length - 1] == '\n' || buffer[length - 1] == ' ')) {
        length--;
    }
    buffer[length] = '\0';
    return (size_t)length;
}

/* ---- paths ---- */

static MsSysError last_error(void) { return (MsSysError)GetLastError(); }

/* A UTF-16 path made from UTF-8, owned by the caller (free). */
typedef struct WidePath {
    WCHAR *text; /* owned, NUL-terminated */
    size_t length;
} WidePath;

static MsSysError wide_from_utf8(const char *text, size_t size, WCHAR **out, size_t *length) {
    if (size > (size_t)INT_MAX) {
        return MS_ERROR_INVALID_PARAMETER;
    }
    const int needed = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, (int)size, NULL, 0);
    if (needed <= 0 && size != 0) {
        return MS_ERROR_INVALID_PARAMETER;
    }
    WCHAR *wide = malloc(((size_t)needed + 1) * sizeof *wide);
    if (wide == NULL) {
        return ERROR_NOT_ENOUGH_MEMORY;
    }
    if (needed > 0) {
        (void)MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, (int)size, wide, needed);
    }
    wide[needed] = L'\0';
    *out = wide;
    *length = (size_t)needed;
    return 0;
}

/* Rewrites a path past the classic limit as its verbatim form (\\?\C:\x, \\?\UNC\h\s\x), which the kernel reads
 * without length limits or `/` handling. Shorter paths and paths that are already verbatim stay as they are. */
static MsSysError verbatim_if_long(WCHAR **path, size_t *length) {
    WCHAR *original = *path;
    if (*length < MS_PATH_LIMIT || wcsncmp(original, L"\\\\?\\", 4) == 0) {
        return 0;
    }
    const DWORD needed = GetFullPathNameW(original, 0, NULL, NULL);
    if (needed == 0) {
        return last_error();
    }
    WCHAR *full = malloc(((size_t)needed + 8) * sizeof *full);
    if (full == NULL) {
        return ERROR_NOT_ENOUGH_MEMORY;
    }
    const DWORD written = GetFullPathNameW(original, needed, full, NULL);
    if (written == 0 || written >= needed) {
        free(full);
        return written == 0 ? last_error() : MS_ERROR_INVALID_PARAMETER;
    }
    const bool unc = wcsncmp(full, L"\\\\", 2) == 0;
    const WCHAR *prefix = unc ? L"\\\\?\\UNC\\" : L"\\\\?\\";
    const WCHAR *rest = unc ? full + 2 : full;
    const size_t prefix_length = wcslen(prefix);
    const size_t rest_length = wcslen(rest);
    WCHAR *verbatim = malloc((prefix_length + rest_length + 1) * sizeof *verbatim);
    if (verbatim == NULL) {
        free(full);
        return ERROR_NOT_ENOUGH_MEMORY;
    }
    memcpy(verbatim, prefix, prefix_length * sizeof *prefix);
    memcpy(verbatim + prefix_length, rest, (rest_length + 1) * sizeof *rest);
    free(full);
    free(original);
    *path = verbatim;
    *length = prefix_length + rest_length;
    return 0;
}

/* Converts a UTF-8 path for the wide Win32 calls. The caller frees it. */
static MsSysError open_path(const char *utf8, WidePath *out) {
    WidePath path = {0};
    MsSysError error = wide_from_utf8(utf8, strlen(utf8), &path.text, &path.length);
    if (error == 0) {
        error = verbatim_if_long(&path.text, &path.length);
    }
    if (error != 0) {
        free(path.text);
        return error;
    }
    *out = path;
    return 0;
}

static void close_path(WidePath *path) {
    free(path->text);
    path->text = NULL;
}

/* ---- time ---- */

enum {
    MS_TICKS_PER_SECOND = 10000000,
    MS_NANOS_PER_TICK = 100
};
#define MS_UNIX_EPOCH_TICKS INT64_C(116444736000000000)

static MsSysTime time_of_filetime(FILETIME stamp) {
    const int64_t ticks = (int64_t)(((uint64_t)stamp.dwHighDateTime << 32) | stamp.dwLowDateTime) - MS_UNIX_EPOCH_TICKS;
    int64_t seconds = ticks / MS_TICKS_PER_SECOND;
    int64_t remainder = ticks % MS_TICKS_PER_SECOND;
    if (remainder < 0) {
        remainder += MS_TICKS_PER_SECOND;
        seconds -= 1;
    }
    return (MsSysTime){.seconds = seconds, .nanos = remainder * MS_NANOS_PER_TICK};
}

static bool filetime_of(MsSysTime time, FILETIME *out) {
    int64_t ticks = 0;
    int64_t scaled = 0;
    if (__builtin_mul_overflow(time.seconds, (int64_t)MS_TICKS_PER_SECOND, &scaled) ||
        __builtin_add_overflow(scaled, time.nanos / MS_NANOS_PER_TICK, &ticks) ||
        __builtin_add_overflow(ticks, MS_UNIX_EPOCH_TICKS, &ticks) || ticks < 0) {
        return false;
    }
    out->dwLowDateTime = (DWORD)((uint64_t)ticks & 0xFFFFFFFFu);
    out->dwHighDateTime = (DWORD)((uint64_t)ticks >> 32);
    return true;
}

/* ---- opening and descriptors ---- */

static HANDLE handle_of(MsSysFd fd) { return (HANDLE)fd; }

static bool is_invalid(MsSysFd fd) { return fd == MS_SYS_FD_INVALID || fd == 0; }

/* What an open asks of CreateFileW, worked out from the portable flags the way Go and Rust do. */
typedef struct OpenPlan {
    DWORD access;
    DWORD disposition;
    DWORD attributes;
    bool truncate_after;
} OpenPlan;

static DWORD access_of(int32_t flags, bool append, bool create) {
    const int32_t mode = flags & MS_SYS_O_ACCESS_MASK;
    DWORD access = 0;
    if (mode != MS_SYS_O_WRITE) {
        access |= GENERIC_READ;
    }
    if (mode != MS_SYS_O_READ || create) {
        access |= GENERIC_WRITE;
    }
    if (append && (access & GENERIC_WRITE) != 0) {
        /* Append only: writing at the end, never at an offset. */
        access = (access & ~(DWORD)GENERIC_WRITE) | FILE_GENERIC_WRITE;
        access &= ~(DWORD)FILE_WRITE_DATA;
    }
    return access;
}

static OpenPlan plan_open(int32_t flags, uint32_t mode) {
    const bool create = (flags & MS_SYS_O_CREATE) != 0;
    const bool exclusive = create && (flags & MS_SYS_O_EXCLUSIVE) != 0;
    const bool truncate = (flags & MS_SYS_O_TRUNCATE) != 0;
    const bool append = (flags & MS_SYS_O_APPEND) != 0 && !truncate;
    OpenPlan plan = {.access = access_of(flags, append, create), .disposition = OPEN_EXISTING};
    if (exclusive) {
        plan.disposition = CREATE_NEW;
    } else if (create) {
        /* CREATE_ALWAYS would reset the attributes of an existing file: truncate after opening. */
        plan.disposition = OPEN_ALWAYS;
        plan.truncate_after = truncate;
    } else if (truncate) {
        plan.disposition = TRUNCATE_EXISTING;
    }
    plan.attributes = FILE_ATTRIBUTE_NORMAL;
    if ((mode & 0200u) == 0) {
        plan.attributes = FILE_ATTRIBUTE_READONLY;
    }
    if ((flags & MS_SYS_O_ACCESS_MASK) == MS_SYS_O_READ) {
        plan.attributes |= FILE_FLAG_BACKUP_SEMANTICS; /* a read-only open may name a directory */
    }
    if (exclusive) {
        plan.attributes |= FILE_FLAG_OPEN_REPARSE_POINT; /* never follow a link when creating */
    }
    if ((flags & MS_SYS_O_SYNC) != 0) {
        plan.attributes |= FILE_FLAG_WRITE_THROUGH;
    }
    return plan;
}

static MsSysError truncate_handle(HANDLE handle, int64_t size) {
    FILE_END_OF_FILE_INFO info = {.EndOfFile.QuadPart = size};
    if (!SetFileInformationByHandle(handle, FileEndOfFileInfo, &info, sizeof info)) {
        return last_error();
    }
    return 0;
}

MsSysError ms_sys_fs_open(const char *path, int32_t flags, uint32_t mode, MsSysFd *fd) {
    WidePath wide = {0};
    MsSysError error = open_path(path, &wide);
    if (error != 0) {
        return error;
    }
    const OpenPlan plan = plan_open(flags, mode);
    const DWORD share = FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE;
    const HANDLE handle = CreateFileW(wide.text, plan.access, share, NULL, plan.disposition, plan.attributes, NULL);
    error = handle == INVALID_HANDLE_VALUE ? last_error() : 0;
    close_path(&wide);
    if (error == 0 && plan.truncate_after) {
        error = truncate_handle(handle, 0);
        if (error != 0) {
            (void)CloseHandle(handle);
        }
    }
    if (error == 0) {
        *fd = (MsSysFd)handle;
    }
    return error;
}

MsSysError ms_sys_fs_close(MsSysFd fd) {
    if (is_invalid(fd)) {
        return MS_ERROR_INVALID_HANDLE;
    }
    return CloseHandle(handle_of(fd)) ? 0 : last_error();
}

MsSysError ms_sys_fs_dup(MsSysFd fd, MsSysFd *out) {
    if (is_invalid(fd)) {
        return MS_ERROR_INVALID_HANDLE;
    }
    HANDLE copy = NULL;
    const HANDLE self = GetCurrentProcess();
    if (!DuplicateHandle(self, handle_of(fd), self, &copy, 0, FALSE, DUPLICATE_SAME_ACCESS)) {
        return last_error();
    }
    *out = (MsSysFd)copy;
    return 0;
}

void ms_sys_fs_set_blocking(MsSysFd fd) { (void)fd; }

/* Whether the handle is a console, whose text goes through UTF-16 calls. */
static bool is_console(HANDLE handle) {
    DWORD mode = 0;
    return GetConsoleMode(handle, &mode) != 0;
}

/* Reads console input as UTF-8: as many UTF-16 units as the buffer can certainly hold. */
static MsSysError console_read(HANDLE handle, uint8_t *buffer, size_t capacity, size_t *count) {
    if (capacity < 4) {
        return MS_ERROR_INVALID_PARAMETER;
    }
    WCHAR wide[1024];
    DWORD wanted = (DWORD)((capacity - 1) / 3);
    if (wanted > MS_COUNT_OF(wide) - 1) {
        wanted = (DWORD)(MS_COUNT_OF(wide) - 1);
    }
    DWORD units = 0;
    if (!ReadConsoleW(handle, wide, wanted, &units, NULL)) {
        return last_error();
    }
    if (units > 0 && wide[units - 1] >= 0xD800 && wide[units - 1] <= 0xDBFF) {
        DWORD extra = 0;
        if (ReadConsoleW(handle, wide + units, 1, &extra, NULL)) {
            units += extra;
        }
    }
    const int length = WideCharToMultiByte(CP_UTF8, 0, wide, (int)units, (char *)buffer, (int)capacity, NULL, NULL);
    if (length <= 0 && units != 0) {
        return last_error();
    }
    *count = (size_t)length;
    return 0;
}

/* Writes UTF-8 text to a console: the longest valid prefix goes out, so a split character waits for the next call. */
static MsSysError console_write(HANDLE handle, const uint8_t *data, size_t length, size_t *count) {
    size_t usable = length;
    int units = 0;
    WCHAR *wide = NULL;
    while (usable > 0 && length - usable < 4) {
        units = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (const char *)data, (int)usable, NULL, 0);
        if (units > 0) {
            break;
        }
        usable--;
    }
    if (usable == 0 && length != 0) {
        return MS_ERROR_NO_UNICODE_TRANSLATION;
    }
    wide = malloc(((size_t)units + 1) * sizeof *wide);
    if (wide == NULL) {
        return ERROR_NOT_ENOUGH_MEMORY;
    }
    (void)MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (const char *)data, (int)usable, wide, units);
    DWORD written = 0;
    const BOOL ok = WriteConsoleW(handle, wide, (DWORD)units, &written, NULL);
    const MsSysError error = ok ? 0 : last_error();
    free(wide);
    if (error == 0) {
        *count = usable;
    }
    return error;
}

/* A pipe whose other end closed reads as the end of the stream. */
static bool is_end_of_stream(DWORD error) { return error == ERROR_BROKEN_PIPE || error == ERROR_HANDLE_EOF; }

MsSysError ms_sys_fs_read(MsSysFd fd, uint8_t *buffer, size_t capacity, size_t *count) {
    if (is_invalid(fd)) {
        return MS_ERROR_INVALID_HANDLE;
    }
    const HANDLE handle = handle_of(fd);
    if (is_console(handle)) {
        return console_read(handle, buffer, capacity, count);
    }
    const DWORD wanted = capacity > (size_t)MAXDWORD ? MAXDWORD : (DWORD)capacity;
    DWORD transferred = 0;
    if (!ReadFile(handle, buffer, wanted, &transferred, NULL)) {
        const DWORD error = GetLastError();
        if (!is_end_of_stream(error)) {
            return (MsSysError)error;
        }
        transferred = 0;
    }
    *count = transferred;
    return 0;
}

MsSysError ms_sys_fs_write(MsSysFd fd, const uint8_t *data, size_t length, size_t *count) {
    if (is_invalid(fd)) {
        return MS_ERROR_INVALID_HANDLE;
    }
    const HANDLE handle = handle_of(fd);
    if (is_console(handle)) {
        return console_write(handle, data, length, count);
    }
    const DWORD wanted = length > (size_t)MAXDWORD ? MAXDWORD : (DWORD)length;
    DWORD transferred = 0;
    if (!WriteFile(handle, data, wanted, &transferred, NULL)) {
        return last_error();
    }
    *count = transferred;
    return 0;
}

/* Windows moves the file position on a positioned transfer, so it is put back afterwards. */
static MsSysError positioned(MsSysFd fd, bool write, uint8_t *buffer, size_t length, int64_t offset, size_t *count) {
    if (is_invalid(fd)) {
        return MS_ERROR_INVALID_HANDLE;
    }
    const HANDLE handle = handle_of(fd);
    LARGE_INTEGER saved = {0};
    LARGE_INTEGER none = {0};
    if (!SetFilePointerEx(handle, none, &saved, FILE_CURRENT)) {
        return last_error();
    }
    OVERLAPPED where = {0};
    where.Offset = (DWORD)((uint64_t)offset & 0xFFFFFFFFu);
    where.OffsetHigh = (DWORD)((uint64_t)offset >> 32);
    const DWORD wanted = length > (size_t)MAXDWORD ? MAXDWORD : (DWORD)length;
    DWORD transferred = 0;
    const BOOL ok = write ? WriteFile(handle, buffer, wanted, &transferred, &where)
                          : ReadFile(handle, buffer, wanted, &transferred, &where);
    DWORD error = ok ? 0 : GetLastError();
    if (!SetFilePointerEx(handle, saved, NULL, FILE_BEGIN) && error == 0) {
        error = GetLastError();
    }
    if (error != 0 && !(is_end_of_stream(error) && !write)) {
        return (MsSysError)error;
    }
    *count = error == 0 ? transferred : 0;
    return 0;
}

MsSysError ms_sys_fs_pread(MsSysFd fd, uint8_t *buffer, size_t capacity, int64_t offset, size_t *count) {
    return positioned(fd, false, buffer, capacity, offset, count);
}

MsSysError ms_sys_fs_pwrite(MsSysFd fd, const uint8_t *data, size_t length, int64_t offset, size_t *count) {
    /* The transfer only reads `data`; the shared helper takes a writable pointer for the read direction. */
    return positioned(fd, true, (uint8_t *)(uintptr_t)data, length, offset, count);
}

MsSysError ms_sys_fs_seek(MsSysFd fd, int64_t offset, int32_t origin, int64_t *position) {
    if (is_invalid(fd)) {
        return MS_ERROR_INVALID_HANDLE;
    }
    DWORD method = FILE_BEGIN;
    if (origin == 1) {
        method = FILE_CURRENT;
    } else if (origin == 2) {
        method = FILE_END;
    } else if (origin != 0 || offset < 0) {
        return MS_ERROR_INVALID_PARAMETER;
    }
    LARGE_INTEGER distance = {.QuadPart = offset};
    LARGE_INTEGER now = {0};
    if (!SetFilePointerEx(handle_of(fd), distance, &now, method)) {
        return last_error();
    }
    *position = now.QuadPart;
    return 0;
}

MsSysError ms_sys_fs_truncate_fd(MsSysFd fd, int64_t size) {
    if (is_invalid(fd)) {
        return MS_ERROR_INVALID_HANDLE;
    }
    return truncate_handle(handle_of(fd), size);
}

MsSysError ms_sys_fs_sync(MsSysFd fd) {
    if (is_invalid(fd)) {
        return MS_ERROR_INVALID_HANDLE;
    }
    return FlushFileBuffers(handle_of(fd)) ? 0 : last_error();
}

MsSysError ms_sys_fs_data_sync(MsSysFd fd) { return ms_sys_fs_sync(fd); }

MsSysError ms_sys_fs_try_lock(MsSysFd fd, bool exclusive, bool *taken) {
    if (is_invalid(fd)) {
        return MS_ERROR_INVALID_HANDLE;
    }
    OVERLAPPED range = {0};
    const DWORD flags = LOCKFILE_FAIL_IMMEDIATELY | (exclusive ? LOCKFILE_EXCLUSIVE_LOCK : 0);
    if (LockFileEx(handle_of(fd), flags, 0, MAXDWORD, MAXDWORD, &range)) {
        *taken = true;
        return 0;
    }
    const DWORD error = GetLastError();
    if (error == ERROR_LOCK_VIOLATION) {
        *taken = false;
        return 0;
    }
    return (MsSysError)error;
}

MsSysError ms_sys_fs_unlock(MsSysFd fd) {
    if (is_invalid(fd)) {
        return MS_ERROR_INVALID_HANDLE;
    }
    OVERLAPPED range = {0};
    return UnlockFileEx(handle_of(fd), 0, MAXDWORD, MAXDWORD, &range) ? 0 : last_error();
}

/* ---- file information ---- */

/* Whether the attributes and reparse tag make this a symbolic link or a mount point (a "name surrogate"). */
static bool is_link(DWORD attributes, DWORD tag) {
    return (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0 && (tag & 0x20000000u) != 0;
}

static void fill_mode(const BY_HANDLE_FILE_INFORMATION *info, DWORD tag, MsSysStat *out) {
    uint32_t permissions = (info->dwFileAttributes & FILE_ATTRIBUTE_READONLY) != 0 ? 0444u : 0666u;
    uint32_t kind = MS_SYS_S_IFREG;
    if (is_link(info->dwFileAttributes, tag)) {
        kind = MS_SYS_S_IFLNK;
    } else if ((info->dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
        kind = MS_SYS_S_IFDIR;
        permissions |= 0111u;
    }
    out->mode = kind | permissions;
}

/* Describes an open disk file: attributes and times from the handle, plus the volume, file index and link count. */
static MsSysError stat_disk(HANDLE handle, MsSysStat *out) {
    BY_HANDLE_FILE_INFORMATION info;
    if (!GetFileInformationByHandle(handle, &info)) {
        return last_error();
    }
    DWORD tag = 0;
    if ((info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
        FILE_ATTRIBUTE_TAG_INFO tag_info;
        if (GetFileInformationByHandleEx(handle, FileAttributeTagInfo, &tag_info, sizeof tag_info)) {
            tag = tag_info.ReparseTag;
        }
    }
    *out = (MsSysStat){0};
    fill_mode(&info, tag, out);
    out->size = (int64_t)(((uint64_t)info.nFileSizeHigh << 32) | info.nFileSizeLow);
    out->modified = time_of_filetime(info.ftLastWriteTime);
    out->accessed = time_of_filetime(info.ftLastAccessTime);
    out->changed = out->modified;
    out->created = time_of_filetime(info.ftCreationTime);
    out->has_created = true;
    out->device = info.dwVolumeSerialNumber;
    out->inode = ((uint64_t)info.nFileIndexHigh << 32) | info.nFileIndexLow;
    out->links = info.nNumberOfLinks;
    return 0;
}

MsSysError ms_sys_fs_fstat(MsSysFd fd, MsSysStat *out) {
    if (is_invalid(fd)) {
        return MS_ERROR_INVALID_HANDLE;
    }
    const HANDLE handle = handle_of(fd);
    *out = (MsSysStat){0};
    switch (GetFileType(handle)) {
    case FILE_TYPE_CHAR:
        out->mode = MS_SYS_S_IFCHR | 0666u;
        return 0;
    case FILE_TYPE_PIPE:
        out->mode = MS_SYS_S_IFIFO | 0666u;
        return 0;
    case FILE_TYPE_DISK:
        return stat_disk(handle, out);
    default:
        return last_error();
    }
}

/* ---- changing files by descriptor ---- */

/* Sets or clears the read-only attribute from the owner write bit of `mode`. */
static MsSysError set_readonly(HANDLE handle, uint32_t mode) {
    FILE_BASIC_INFO info;
    if (!GetFileInformationByHandleEx(handle, FileBasicInfo, &info, sizeof info)) {
        return last_error();
    }
    if ((mode & 0200u) == 0) {
        info.FileAttributes |= FILE_ATTRIBUTE_READONLY;
    } else {
        info.FileAttributes &= ~(DWORD)FILE_ATTRIBUTE_READONLY;
    }
    if (info.FileAttributes == 0) {
        info.FileAttributes = FILE_ATTRIBUTE_NORMAL;
    }
    return SetFileInformationByHandle(handle, FileBasicInfo, &info, sizeof info) ? 0 : last_error();
}

MsSysError ms_sys_fs_chmod_fd(MsSysFd fd, uint32_t mode) {
    if (is_invalid(fd)) {
        return MS_ERROR_INVALID_HANDLE;
    }
    return set_readonly(handle_of(fd), mode);
}

MsSysError ms_sys_fs_chown_fd(MsSysFd fd, int64_t uid, int64_t gid) {
    (void)fd;
    (void)uid;
    (void)gid;
    return MS_ERROR_NOT_SUPPORTED;
}

MsSysError ms_sys_fs_set_times_fd(MsSysFd fd, MsSysTime accessed, MsSysTime modified) {
    if (is_invalid(fd)) {
        return MS_ERROR_INVALID_HANDLE;
    }
    FILETIME access_time;
    FILETIME write_time;
    if (!filetime_of(accessed, &access_time) || !filetime_of(modified, &write_time)) {
        return MS_ERROR_INVALID_PARAMETER;
    }
    return SetFileTime(handle_of(fd), NULL, &access_time, &write_time) ? 0 : last_error();
}

MsSysError ms_sys_fs_clone_file(MsSysFd output, MsSysFd input) {
    (void)output;
    (void)input;
    return MS_ERROR_NOT_SUPPORTED;
}

/* ---- changing files by path (the rest is src/runtime/sys/fs_path.c) ---- */

MsSysError ms_sys_fs_chmod_link(const char *path, uint32_t mode) {
    (void)path;
    (void)mode;
    return MS_ERROR_NOT_SUPPORTED;
}

MsSysError ms_sys_fs_set_times(const char *path, MsSysTime accessed, MsSysTime modified, bool follow) {
    if (!follow) {
        return MS_ERROR_NOT_SUPPORTED;
    }
    WidePath wide = {0};
    MsSysError error = open_path(path, &wide);
    if (error != 0) {
        return error;
    }
    const DWORD share = FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE;
    const HANDLE handle =
        CreateFileW(wide.text, FILE_WRITE_ATTRIBUTES, share, NULL, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, NULL);
    error = handle == INVALID_HANDLE_VALUE ? last_error() : 0;
    close_path(&wide);
    if (error != 0) {
        return error;
    }
    error = ms_sys_fs_set_times_fd((MsSysFd)handle, accessed, modified);
    (void)CloseHandle(handle);
    return error;
}

/* ---- the process's view ---- */

MsSysFdKind ms_sys_fs_fd_kind(MsSysFd fd) {
    if (is_invalid(fd)) {
        return MS_SYS_FD_OTHER;
    }
    const HANDLE handle = handle_of(fd);
    switch (GetFileType(handle)) {
    case FILE_TYPE_DISK:
        return MS_SYS_FD_FILE;
    case FILE_TYPE_PIPE:
        return MS_SYS_FD_PIPE;
    case FILE_TYPE_CHAR:
        return is_console(handle) ? MS_SYS_FD_CONSOLE : MS_SYS_FD_OTHER;
    default:
        return MS_SYS_FD_OTHER;
    }
}

bool ms_sys_fs_is_terminal(MsSysFd fd) { return !is_invalid(fd) && is_console(handle_of(fd)); }

bool ms_sys_error_is_broken_pipe(MsSysError error) { return error == ERROR_BROKEN_PIPE_CODE || error == ERROR_NO_DATA_CODE; }

bool ms_sys_fs_is_output(MsSysFd fd) {
    return !is_invalid(fd) && (handle_of(fd) == GetStdHandle(STD_OUTPUT_HANDLE) || handle_of(fd) == GetStdHandle(STD_ERROR_HANDLE));
}

MsSysFd ms_sys_fs_standard(int32_t which) {
    const DWORD slot = which == 0 ? STD_INPUT_HANDLE : which == 1 ? STD_OUTPUT_HANDLE : STD_ERROR_HANDLE;
    return (MsSysFd)GetStdHandle(slot);
}

MsSysError ms_sys_fs_redirect_null(int32_t which) {
    const DWORD slot = which == 0 ? STD_INPUT_HANDLE : which == 1 ? STD_OUTPUT_HANDLE : STD_ERROR_HANDLE;
    const HANDLE null = CreateFileW(L"NUL", GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING,
                                    FILE_ATTRIBUTE_NORMAL, NULL);
    if (null == INVALID_HANDLE_VALUE) {
        return last_error();
    }
    /* The handle stays open for the life of the process, as the standard handle it now is. */
    if (!SetStdHandle(slot, null)) {
        const MsSysError error = last_error();
        (void)CloseHandle(null);
        return error;
    }
    return 0;
}

MsSysError ms_sys_fs_event_new(MsSysFd *event) {
    const HANDLE handle = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (handle == NULL) {
        return last_error();
    }
    *event = (MsSysFd)handle;
    return 0;
}

void ms_sys_fs_event_signal(MsSysFd event) { (void)SetEvent(handle_of(event)); }

void ms_sys_fs_event_free(MsSysFd event) { (void)CloseHandle(handle_of(event)); }

bool ms_sys_fs_wait_console(MsSysFd fd, MsSysFd event) {
    const HANDLE handles[2] = {handle_of(fd), handle_of(event)};
    return WaitForMultipleObjects(2, handles, FALSE, INFINITE) == WAIT_OBJECT_0;
}

void ms_sys_fs_cancel_io(MsSysFd fd) { (void)CancelIoEx(handle_of(fd), NULL); }
