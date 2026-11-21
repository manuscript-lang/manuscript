/* Files and directories by path, on every platform, over libuv's synchronous uv_fs_* calls (ms_rt/sys_fs.h). What a
 * descriptor or a handle needs, and what libuv cannot express (nanosecond times, the link's own mode), stays in
 * sys/posix/fs.c and sys/windows/fs.c.
 *
 * An error is the host code the other functions of the layer return: the errno on Unix and the Win32 code on Windows,
 * so ms_sys_fs_error_kind reads every function alike. libuv's own negative codes are turned back into those. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c11 */
#ifdef __APPLE__
#define _DARWIN_C_SOURCE
#endif

#include <stdlib.h>
#include <string.h>
#include <uv.h>
#ifdef _WIN32
#include <windows.h>
#endif

#include "ms_rt/sys_fs.h"

/* libuv hands a path to the kernel as it is, and Windows reads a path past about 260 characters, or one with `/`
 * past that length, only in its verbatim form (\\?\C:\x, \\?\UNC\host\share\x). A long path is rewritten that way,
 * as the layer always did; `*owned` holds the copy to free (NULL when the path is used as it is). */
static const char *long_path(const char *path, char **owned) {
    *owned = NULL;
#ifdef _WIN32
    enum { LIMIT = 240 };
    if (strlen(path) < LIMIT || strncmp(path, "\\\\?\\", 4) == 0) {
        return path;
    }
    const int units = MultiByteToWideChar(CP_UTF8, 0, path, -1, NULL, 0);
    if (units <= 0) {
        return path;
    }
    WCHAR *wide = malloc((size_t)units * sizeof *wide);
    if (wide == NULL) {
        return path;
    }
    (void)MultiByteToWideChar(CP_UTF8, 0, path, -1, wide, units);
    const DWORD needed = GetFullPathNameW(wide, 0, NULL, NULL);
    WCHAR *full = needed == 0 ? NULL : malloc(((size_t)needed + 8) * sizeof *full);
    const DWORD written = full == NULL ? 0 : GetFullPathNameW(wide, needed, full, NULL);
    free(wide);
    if (written == 0 || written >= needed) {
        free(full);
        return path;
    }
    const bool unc = wcsncmp(full, L"\\\\", 2) == 0;
    const WCHAR *prefix = unc ? L"\\\\?\\UNC\\" : L"\\\\?\\";
    const WCHAR *rest = unc ? full + 2 : full;
    const size_t total = wcslen(prefix) + wcslen(rest) + 1;
    WCHAR *verbatim = malloc(total * sizeof *verbatim);
    if (verbatim == NULL) {
        free(full);
        return path;
    }
    wcscpy(verbatim, prefix);
    wcscat(verbatim, rest);
    free(full);
    const int bytes = WideCharToMultiByte(CP_UTF8, 0, verbatim, -1, NULL, 0, NULL, NULL);
    char *text = bytes <= 0 ? NULL : malloc((size_t)bytes);
    if (text != NULL) {
        (void)WideCharToMultiByte(CP_UTF8, 0, verbatim, -1, text, bytes, NULL, NULL);
        *owned = text;
    }
    free(verbatim);
    return text != NULL ? text : path;
#else
    return path;
#endif
}

/* The host code of a failed request. */
static MsSysError host_code(const uv_fs_t *req) {
    const int result = (int)req->result;
#ifdef _WIN32
    if (req->sys_errno_ != 0) {
        return (MsSysError)req->sys_errno_;
    }
    switch (result) {
    case UV_ENOENT: return ms_sys_fs_error_of(MS_SYS_ERR_NOT_FOUND);
    case UV_EACCES:
    case UV_EPERM: return ms_sys_fs_error_of(MS_SYS_ERR_PERMISSION);
    case UV_EEXIST: return ms_sys_fs_error_of(MS_SYS_ERR_EXISTS);
    case UV_EINVAL: return ms_sys_fs_error_of(MS_SYS_ERR_INVALID);
    case UV_ENOSYS:
    case UV_ENOTSUP: return ms_sys_fs_error_of(MS_SYS_ERR_UNSUPPORTED);
    default: return ms_sys_fs_error_of(MS_SYS_ERR_IO);
    }
#else
    return (MsSysError)-result; /* libuv reports -errno on Unix */
#endif
}

/* Finishes a request: 0, or the host code. `req` is cleaned up. */
static MsSysError finish(uv_fs_t *req) {
    const MsSysError code = req->result < 0 ? host_code(req) : 0;
    uv_fs_req_cleanup(req);
    return code;
}

#define WITH_REQUEST(call)  \
    uv_fs_t req;            \
    (void)(call);           \
    return finish(&req)

static MsSysError do_mkdir(const char *path, uint32_t mode) { WITH_REQUEST(uv_fs_mkdir(NULL, &req, path, (int)mode, NULL)); }

static MsSysError do_unlink(const char *path) { WITH_REQUEST(uv_fs_unlink(NULL, &req, path, NULL)); }

static MsSysError do_rmdir(const char *path) { WITH_REQUEST(uv_fs_rmdir(NULL, &req, path, NULL)); }

static MsSysError do_rename(const char *from, const char *to) { WITH_REQUEST(uv_fs_rename(NULL, &req, from, to, NULL)); }

static MsSysError do_link(const char *from, const char *to) { WITH_REQUEST(uv_fs_link(NULL, &req, from, to, NULL)); }

static MsSysError do_chmod(const char *path, uint32_t mode) { WITH_REQUEST(uv_fs_chmod(NULL, &req, path, (int)mode, NULL)); }

static MsSysError do_access(const char *path, int32_t mode) { WITH_REQUEST(uv_fs_access(NULL, &req, path, mode, NULL)); }

static MsSysError do_symlink(const char *target, const char *path) {
    int flags = 0;
#ifdef _WIN32
    /* Windows makes a directory link and a file link differently: ask what the target is, relative to the link. */
    MsSysStat info;
    const char *separator = strrchr(path, '/');
    const char *backslash = strrchr(path, '\\');
    separator = backslash != NULL && (separator == NULL || backslash > separator) ? backslash : separator;
    const bool absolute = target[0] == '/' || target[0] == '\\' || (target[0] != 0 && target[1] == ':');
    char *joined = NULL;
    if (!absolute && separator != NULL) {
        const size_t directory = (size_t)(separator - path) + 1;
        joined = malloc(directory + strlen(target) + 1);
        if (joined != NULL) {
            memcpy(joined, path, directory);
            strcpy(joined + directory, target);
        }
    }
    if (ms_sys_fs_stat(joined != NULL ? joined : target, true, &info) == 0 && (info.mode & MS_SYS_S_IFMT) == MS_SYS_S_IFDIR) {
        flags = UV_FS_SYMLINK_DIR;
    }
    free(joined);
#endif
    uv_fs_t req;
    (void)uv_fs_symlink(NULL, &req, target, path, flags, NULL);
    return finish(&req);
}

/* The string a request returned, as malloc'd text for the caller. */
static MsSysError take_text(uv_fs_t *req, char **text, size_t *length) {
    if (req->result < 0) {
        return finish(req);
    }
    const char *source = req->ptr;
    const size_t size = strlen(source);
    char *copy = malloc(size + 1);
    if (copy == NULL) {
        uv_fs_req_cleanup(req);
        return ms_sys_fs_error_of(MS_SYS_ERR_IO);
    }
    memcpy(copy, source, size + 1);
    uv_fs_req_cleanup(req);
    *text = copy;
    *length = size;
    return 0;
}

static MsSysError do_readlink(const char *path, char **target, size_t *length) {
    uv_fs_t req;
    (void)uv_fs_readlink(NULL, &req, path, NULL);
    return take_text(&req, target, length);
}

static MsSysError do_canonicalize(const char *path, char **resolved, size_t *length) {
    uv_fs_t req;
    (void)uv_fs_realpath(NULL, &req, path, NULL);
    return take_text(&req, resolved, length);
}

static MsSysError do_chown(const char *path, int64_t uid, int64_t gid, bool follow) {
#ifdef _WIN32
    (void)path;
    (void)uid;
    (void)gid;
    (void)follow;
    return ms_sys_fs_error_of(MS_SYS_ERR_UNSUPPORTED); /* libuv's chown is a silent no-op there */
#else
    uv_fs_t req;
    (void)(follow ? uv_fs_chown(NULL, &req, path, (uv_uid_t)uid, (uv_gid_t)gid, NULL)
                  : uv_fs_lchown(NULL, &req, path, (uv_uid_t)uid, (uv_gid_t)gid, NULL));
    return finish(&req);
#endif
}

static MsSysError do_truncate(const char *path, int64_t size) {
    uv_fs_t open;
    const int fd = (int)uv_fs_open(NULL, &open, path, UV_FS_O_WRONLY, 0, NULL);
    if (fd < 0) {
        return finish(&open);
    }
    uv_fs_req_cleanup(&open);
    uv_fs_t truncate;
    (void)uv_fs_ftruncate(NULL, &truncate, fd, size, NULL);
    const MsSysError error = finish(&truncate);
    uv_fs_t close;
    (void)uv_fs_close(NULL, &close, fd, NULL);
    (void)finish(&close);
    return error;
}

static MsSysTime time_of(uv_timespec_t stamp) { return (MsSysTime){.seconds = stamp.tv_sec, .nanos = stamp.tv_nsec}; }

static MsSysError do_stat(const char *path, bool follow, MsSysStat *out) {
    uv_fs_t req;
    (void)(follow ? uv_fs_stat(NULL, &req, path, NULL) : uv_fs_lstat(NULL, &req, path, NULL));
    if (req.result < 0) {
        return finish(&req);
    }
    const uv_stat_t *source = &req.statbuf;
    *out = (MsSysStat){.mode = (uint32_t)source->st_mode,
                       .size = (int64_t)source->st_size,
                       .modified = time_of(source->st_mtim),
                       .accessed = time_of(source->st_atim),
                       .changed = time_of(source->st_ctim),
                       .created = time_of(source->st_birthtim),
                       .has_created = source->st_birthtim.tv_sec != 0 || source->st_birthtim.tv_nsec != 0,
                       .block_size = source->st_blksize,
                       .blocks = source->st_blocks,
                       .rdev = source->st_rdev,
                       .device = source->st_dev,
                       .inode = source->st_ino,
                       .links = source->st_nlink,
                       .uid = source->st_uid,
                       .gid = source->st_gid};
    uv_fs_req_cleanup(&req);
    return 0;
}

static MsSysError do_stat_filesystem(const char *path, MsSysFsStat *out) {
    uv_fs_t req;
    (void)uv_fs_statfs(NULL, &req, path, NULL);
    if (req.result < 0) {
        return finish(&req);
    }
    const uv_statfs_t *source = req.ptr;
    *out = (MsSysFsStat){.kind = (int64_t)source->f_type,
                         .block_size = (int64_t)source->f_bsize,
                         .blocks = (int64_t)source->f_blocks,
                         .blocks_free = (int64_t)source->f_bfree,
                         .blocks_available = (int64_t)source->f_bavail,
                         .files = (int64_t)source->f_files,
                         .files_free = (int64_t)source->f_ffree};
    uv_fs_req_cleanup(&req);
    return 0;
}

/* ---- directories ---- */

struct MsSysDir {
    uv_fs_t request; /* the whole listing, read by uv_fs_scandir_next */
};

static MsSysError do_dir_open(const char *path, MsSysDir **dir) {
    MsSysDir *created = malloc(sizeof *created);
    if (created == NULL) {
        return ms_sys_fs_error_of(MS_SYS_ERR_IO);
    }
    (void)uv_fs_scandir(NULL, &created->request, path, 0, NULL);
    if (created->request.result < 0) {
        const MsSysError error = finish(&created->request);
        free(created);
        return error;
    }
    *dir = created;
    return 0;
}

MsSysError ms_sys_fs_dir_read(MsSysDir *dir, MsSysDirEntry *entry, bool *found) {
    uv_dirent_t item;
    const int result = uv_fs_scandir_next(&dir->request, &item);
    if (result == UV_EOF) {
        *found = false;
        return 0;
    }
    if (result < 0) {
        return ms_sys_fs_error_of(MS_SYS_ERR_IO);
    }
    const size_t length = strlen(item.name);
    if (length >= sizeof entry->name) {
        return ms_sys_fs_error_of(MS_SYS_ERR_INVALID);
    }
    memcpy(entry->name, item.name, length + 1);
    entry->name_length = length;
    switch (item.type) {
    case UV_DIRENT_DIR: entry->kind = MS_SYS_DT_DIR; break;
    case UV_DIRENT_FILE: entry->kind = MS_SYS_DT_REG; break;
    case UV_DIRENT_LINK: entry->kind = MS_SYS_DT_LNK; break;
    default: entry->kind = MS_SYS_DT_UNKNOWN; break;
    }
    *found = true;
    return 0;
}

void ms_sys_fs_dir_close(MsSysDir *dir) {
    uv_fs_req_cleanup(&dir->request);
    free(dir);
}

/* ---- the exported operations: the same, on a path that is long enough for the host ---- */

MsSysError ms_sys_fs_mkdir(const char *path, uint32_t mode) {
    char *own_path;
    const char *host_path = long_path(path, &own_path);
    const MsSysError error = do_mkdir(host_path, mode);
    free(own_path);
    return error;
}

MsSysError ms_sys_fs_unlink(const char *path) {
    char *own_path;
    const char *host_path = long_path(path, &own_path);
    const MsSysError error = do_unlink(host_path);
    free(own_path);
    return error;
}

MsSysError ms_sys_fs_rmdir(const char *path) {
    char *own_path;
    const char *host_path = long_path(path, &own_path);
    const MsSysError error = do_rmdir(host_path);
    free(own_path);
    return error;
}

MsSysError ms_sys_fs_rename(const char *from, const char *to) {
    char *own_from;
    const char *host_from = long_path(from, &own_from);
    char *own_to;
    const char *host_to = long_path(to, &own_to);
    const MsSysError error = do_rename(host_from, host_to);
    free(own_from);
    free(own_to);
    return error;
}

MsSysError ms_sys_fs_link(const char *from, const char *to) {
    char *own_from;
    const char *host_from = long_path(from, &own_from);
    char *own_to;
    const char *host_to = long_path(to, &own_to);
    const MsSysError error = do_link(host_from, host_to);
    free(own_from);
    free(own_to);
    return error;
}

MsSysError ms_sys_fs_chmod(const char *path, uint32_t mode) {
    char *own_path;
    const char *host_path = long_path(path, &own_path);
    const MsSysError error = do_chmod(host_path, mode);
    free(own_path);
    return error;
}

MsSysError ms_sys_fs_access(const char *path, int32_t mode) {
    char *own_path;
    const char *host_path = long_path(path, &own_path);
    const MsSysError error = do_access(host_path, mode);
    free(own_path);
    return error;
}

MsSysError ms_sys_fs_symlink(const char *target, const char *path) {
    char *own_path;
    const char *host_path = long_path(path, &own_path);
    const MsSysError error = do_symlink(target, host_path);
    free(own_path);
    return error;
}

MsSysError ms_sys_fs_readlink(const char *path, char **target, size_t *length) {
    char *own_path;
    const char *host_path = long_path(path, &own_path);
    const MsSysError error = do_readlink(host_path, target, length);
    free(own_path);
    return error;
}

MsSysError ms_sys_fs_canonicalize(const char *path, char **resolved, size_t *length) {
    char *own_path;
    const char *host_path = long_path(path, &own_path);
    const MsSysError error = do_canonicalize(host_path, resolved, length);
    free(own_path);
    return error;
}

MsSysError ms_sys_fs_chown(const char *path, int64_t uid, int64_t gid, bool follow) {
    char *own_path;
    const char *host_path = long_path(path, &own_path);
    const MsSysError error = do_chown(host_path, uid, gid, follow);
    free(own_path);
    return error;
}

MsSysError ms_sys_fs_truncate(const char *path, int64_t size) {
    char *own_path;
    const char *host_path = long_path(path, &own_path);
    const MsSysError error = do_truncate(host_path, size);
    free(own_path);
    return error;
}

MsSysError ms_sys_fs_stat(const char *path, bool follow, MsSysStat *out) {
    char *own_path;
    const char *host_path = long_path(path, &own_path);
    const MsSysError error = do_stat(host_path, follow, out);
    free(own_path);
    return error;
}

MsSysError ms_sys_fs_stat_filesystem(const char *path, MsSysFsStat *out) {
    char *own_path;
    const char *host_path = long_path(path, &own_path);
    const MsSysError error = do_stat_filesystem(host_path, out);
    free(own_path);
    return error;
}

MsSysError ms_sys_fs_dir_open(const char *path, MsSysDir **dir) {
    char *own_path;
    const char *host_path = long_path(path, &own_path);
    const MsSysError error = do_dir_open(host_path, dir);
    free(own_path);
    return error;
}

/* ---- the process's view ---- */

/* The host code for a libuv error that is not a request's. */
static MsSysError host_error(int code) {
#ifdef _WIN32
    switch (code) {
    case UV_ENOENT: return ms_sys_fs_error_of(MS_SYS_ERR_NOT_FOUND);
    case UV_EACCES:
    case UV_EPERM: return ms_sys_fs_error_of(MS_SYS_ERR_PERMISSION);
    case UV_EINVAL: return ms_sys_fs_error_of(MS_SYS_ERR_INVALID);
    default: return ms_sys_fs_error_of(MS_SYS_ERR_IO);
    }
#else
    return (MsSysError)-code;
#endif
}

typedef int (*TextCall)(char *buffer, size_t *size);

/* Calls a libuv text query (uv_cwd, uv_os_tmpdir) with a buffer that grows until the text fits. */
static MsSysError query_text(TextCall call, char **text, size_t *length) {
    size_t capacity = 256;
    for (;;) {
        char *buffer = malloc(capacity);
        if (buffer == NULL) {
            return ms_sys_fs_error_of(MS_SYS_ERR_IO);
        }
        size_t size = capacity;
        const int result = call(buffer, &size);
        if (result == 0) {
            *text = buffer;
            *length = size;
            return 0;
        }
        free(buffer);
        if (result != UV_ENOBUFS) {
            return host_error(result);
        }
        capacity = size > capacity ? size : capacity * 2; /* size is the length needed, the terminator included */
    }
}

MsSysError ms_sys_fs_current_directory(char **path, size_t *length) { return query_text(uv_cwd, path, length); }

MsSysError ms_sys_fs_temp_directory(char **path, size_t *length) { return query_text(uv_os_tmpdir, path, length); }

uint32_t ms_sys_fs_random(void) {
    uint32_t value = 0;
    if (uv_random(NULL, &(uv_random_t){0}, &value, sizeof value, 0, NULL) != 0) {
        value = (uint32_t)uv_hrtime(); /* the entropy source failed: the clock still differs from call to call */
    }
    return value;
}
