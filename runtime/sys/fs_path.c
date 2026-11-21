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

#include "ms_rt/sys_fs.h"

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

MsSysError ms_sys_fs_mkdir(const char *path, uint32_t mode) { WITH_REQUEST(uv_fs_mkdir(NULL, &req, path, (int)mode, NULL)); }

MsSysError ms_sys_fs_unlink(const char *path) { WITH_REQUEST(uv_fs_unlink(NULL, &req, path, NULL)); }

MsSysError ms_sys_fs_rmdir(const char *path) { WITH_REQUEST(uv_fs_rmdir(NULL, &req, path, NULL)); }

MsSysError ms_sys_fs_rename(const char *from, const char *to) { WITH_REQUEST(uv_fs_rename(NULL, &req, from, to, NULL)); }

MsSysError ms_sys_fs_link(const char *from, const char *to) { WITH_REQUEST(uv_fs_link(NULL, &req, from, to, NULL)); }

MsSysError ms_sys_fs_chmod(const char *path, uint32_t mode) { WITH_REQUEST(uv_fs_chmod(NULL, &req, path, (int)mode, NULL)); }

MsSysError ms_sys_fs_access(const char *path, int32_t mode) { WITH_REQUEST(uv_fs_access(NULL, &req, path, mode, NULL)); }

MsSysError ms_sys_fs_symlink(const char *target, const char *path) {
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

MsSysError ms_sys_fs_readlink(const char *path, char **target, size_t *length) {
    uv_fs_t req;
    (void)uv_fs_readlink(NULL, &req, path, NULL);
    return take_text(&req, target, length);
}

MsSysError ms_sys_fs_canonicalize(const char *path, char **resolved, size_t *length) {
    uv_fs_t req;
    (void)uv_fs_realpath(NULL, &req, path, NULL);
    return take_text(&req, resolved, length);
}

MsSysError ms_sys_fs_chown(const char *path, int64_t uid, int64_t gid, bool follow) {
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

MsSysError ms_sys_fs_truncate(const char *path, int64_t size) {
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

MsSysError ms_sys_fs_stat(const char *path, bool follow, MsSysStat *out) {
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

MsSysError ms_sys_fs_stat_filesystem(const char *path, MsSysFsStat *out) {
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

MsSysError ms_sys_fs_dir_open(const char *path, MsSysDir **dir) {
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
