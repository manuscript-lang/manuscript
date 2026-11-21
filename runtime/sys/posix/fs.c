/* Files, directories and paths on Linux and macOS: the one place runtime/std reaches the kernel's file calls.
 * Every function returns 0 or the errno of the failure (ms_rt/sys_fs.h). */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include "ms_rt/sys_fs.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

#ifdef __linux__
#include <sys/ioctl.h>
#include <sys/statfs.h>
#include <sys/sysmacros.h>
#else
#include <sys/mount.h>
#endif

#include "ms_rt/sys.h"

/* The Linux ioctl that makes one file share the extents of another (FICLONE). */
#define MS_FICLONE 0x40049409UL

/* ---- errors ---- */

MsSysErrorKind ms_sys_fs_error_kind(MsSysError error) {
    switch (error) {
    case ENOENT:
        return MS_SYS_ERR_NOT_FOUND;
    case EEXIST:
        return MS_SYS_ERR_EXISTS;
    case ENOTEMPTY:
        return MS_SYS_ERR_NOT_EMPTY;
    case ENOTDIR:
        return MS_SYS_ERR_NOT_DIRECTORY;
    case EISDIR:
        return MS_SYS_ERR_IS_DIRECTORY;
    case EINVAL:
        return MS_SYS_ERR_INVALID;
    case EPERM:
    case EACCES:
        return MS_SYS_ERR_PERMISSION;
    case EAGAIN:
#if EWOULDBLOCK != EAGAIN
    case EWOULDBLOCK:
#endif
        return MS_SYS_ERR_WOULD_BLOCK;
    case ENOTSUP:
#if EOPNOTSUPP != ENOTSUP
    case EOPNOTSUPP:
#endif
    case ENOSYS:
        return MS_SYS_ERR_UNSUPPORTED;
    case ELOOP:
        return MS_SYS_ERR_LINK_LOOP;
    case EINTR:
        return MS_SYS_ERR_INTERRUPTED;
    case EIO:
        return MS_SYS_ERR_IO;
    case EBADF:
        return MS_SYS_ERR_BAD_DESCRIPTOR;
    case ENXIO:
        return MS_SYS_ERR_NO_ENTRY_DEVICE;
    default:
        return MS_SYS_ERR_OTHER;
    }
}

MsSysError ms_sys_fs_error_of(MsSysErrorKind kind) {
    switch (kind) {
    case MS_SYS_ERR_INVALID:
        return EINVAL;
    case MS_SYS_ERR_EXISTS:
        return EEXIST;
    case MS_SYS_ERR_IO:
        return EIO;
    case MS_SYS_ERR_BAD_DESCRIPTOR:
        return EBADF;
    case MS_SYS_ERR_UNSUPPORTED:
        return ENOTSUP;
    case MS_SYS_ERR_NOT_FOUND:
        return ENOENT;
    case MS_SYS_ERR_PERMISSION:
        return EACCES;
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
    return EIO;
}

typedef struct MsErrnoText {
    int code;
    const char *text;
} MsErrnoText;

/* Fixed wording, the same on every Unix. */
static const MsErrnoText errno_texts[] = {
    {EPERM, "operation not permitted"},
    {ENOENT, "no such file or directory"},
    {ESRCH, "no such process"},
    {EINTR, "interrupted system call"},
    {EIO, "input/output error"},
    {ENXIO, "no such device or address"},
    {E2BIG, "argument list too long"},
    {ENOEXEC, "exec format error"},
    {EBADF, "bad file descriptor"},
    {ECHILD, "no child processes"},
    {EAGAIN, "resource temporarily unavailable"},
    {ENOMEM, "cannot allocate memory"},
    {EACCES, "permission denied"},
    {EFAULT, "bad address"},
    {EBUSY, "device or resource busy"},
    {EEXIST, "file exists"},
    {EXDEV, "invalid cross-device link"},
    {ENODEV, "no such device"},
    {ENOTDIR, "not a directory"},
    {EISDIR, "is a directory"},
    {EINVAL, "invalid argument"},
    {ENFILE, "too many open files in system"},
    {EMFILE, "too many open files"},
    {ENOTTY, "inappropriate ioctl for device"},
    {ETXTBSY, "text file busy"},
    {EFBIG, "file too large"},
    {ENOSPC, "no space left on device"},
    {ESPIPE, "illegal seek"},
    {EROFS, "read-only file system"},
    {EMLINK, "too many links"},
    {EPIPE, "broken pipe"},
    {ERANGE, "numerical result out of range"},
    {ENAMETOOLONG, "file name too long"},
    {ENOSYS, "function not implemented"},
    {ENOTEMPTY, "directory not empty"},
    {ELOOP, "too many levels of symbolic links"},
    {EDQUOT, "disk quota exceeded"},
    {ENOTSUP, "operation not supported"},
    {ECONNRESET, "connection reset by peer"},
    {ETIMEDOUT, "connection timed out"},
};

size_t ms_sys_fs_error_text(MsSysError error, char *buffer, size_t capacity) {
    if (capacity == 0) {
        return 0;
    }
    const char *text = NULL;
    for (size_t i = 0; i < MS_COUNT_OF(errno_texts); i++) {
        if (errno_texts[i].code == error) {
            text = errno_texts[i].text;
            break;
        }
    }
    char fallback[48];
    if (text == NULL) {
        (void)snprintf(fallback, sizeof fallback, "errno %d", error);
        text = fallback;
    }
    const size_t length = strnlen(text, capacity - 1);
    memcpy(buffer, text, length);
    buffer[length] = '\0';
    return length;
}

/* ---- helpers ---- */

/* The errno of the call that just failed. */
static MsSysError last_error(void) { return errno; }

/* Runs a call that returns a negative value on failure, retrying when a signal interrupts it. */
#define MS_RETRY_INTERRUPTED(result, call) \
    do {                                   \
        (result) = (call);                 \
    } while ((result) < 0 && errno == EINTR)

static MsSysError status_of(long result) { return result < 0 ? last_error() : 0; }

static int host_open_flags(int32_t flags) {
    int host = O_CLOEXEC;
    switch (flags & MS_SYS_O_ACCESS_MASK) {
    case MS_SYS_O_WRITE:
        host |= O_WRONLY;
        break;
    case MS_SYS_O_READ_WRITE:
        host |= O_RDWR;
        break;
    default:
        host |= O_RDONLY;
        break;
    }
    host |= (flags & MS_SYS_O_CREATE) != 0 ? O_CREAT : 0;
    host |= (flags & MS_SYS_O_EXCLUSIVE) != 0 ? O_EXCL : 0;
    host |= (flags & MS_SYS_O_TRUNCATE) != 0 ? O_TRUNC : 0;
    host |= (flags & MS_SYS_O_APPEND) != 0 ? O_APPEND : 0;
    host |= (flags & MS_SYS_O_NONBLOCK) != 0 ? O_NONBLOCK : 0;
    host |= (flags & MS_SYS_O_SYNC) != 0 ? O_SYNC : 0;
    return host;
}

/* ---- opening and descriptors ---- */

MsSysError ms_sys_fs_open(const char *path, int32_t flags, uint32_t mode, MsSysFd *fd) {
    int opened = -1;
    MS_RETRY_INTERRUPTED(opened, open(path, host_open_flags(flags), (mode_t)mode));
    if (opened < 0) {
        return last_error();
    }
    *fd = opened;
    return 0;
}

MsSysError ms_sys_fs_close(MsSysFd fd) {
    if (fd < 0) {
        return EBADF;
    }
    /* Never retried: even an interrupted close can have released the descriptor. */
    return status_of(close((int)fd));
}

MsSysError ms_sys_fs_dup(MsSysFd fd, MsSysFd *out) {
    if (fd < 0) {
        return EBADF;
    }
    const int copy = fcntl((int)fd, F_DUPFD_CLOEXEC, 0);
    if (copy < 0) {
        return last_error();
    }
    *out = copy;
    return 0;
}

void ms_sys_fs_set_blocking(MsSysFd fd) {
    const int current = fcntl((int)fd, F_GETFL);
    if (current >= 0) {
        (void)fcntl((int)fd, F_SETFL, current & ~O_NONBLOCK);
    }
}

MsSysError ms_sys_fs_read(MsSysFd fd, uint8_t *buffer, size_t capacity, size_t *count) {
    if (fd < 0) {
        return EBADF;
    }
    ssize_t transferred = -1;
    MS_RETRY_INTERRUPTED(transferred, read((int)fd, buffer, capacity));
    if (transferred < 0) {
        return last_error();
    }
    *count = (size_t)transferred;
    return 0;
}

MsSysError ms_sys_fs_write(MsSysFd fd, const uint8_t *data, size_t length, size_t *count) {
    if (fd < 0) {
        return EBADF;
    }
    ssize_t transferred = -1;
    MS_RETRY_INTERRUPTED(transferred, write((int)fd, data, length));
    if (transferred < 0) {
        return last_error();
    }
    *count = (size_t)transferred;
    return 0;
}

MsSysError ms_sys_fs_pread(MsSysFd fd, uint8_t *buffer, size_t capacity, int64_t offset, size_t *count) {
    if (fd < 0) {
        return EBADF;
    }
    ssize_t transferred = -1;
    MS_RETRY_INTERRUPTED(transferred, pread((int)fd, buffer, capacity, (off_t)offset));
    if (transferred < 0) {
        return last_error();
    }
    *count = (size_t)transferred;
    return 0;
}

MsSysError ms_sys_fs_pwrite(MsSysFd fd, const uint8_t *data, size_t length, int64_t offset, size_t *count) {
    if (fd < 0) {
        return EBADF;
    }
    ssize_t transferred = -1;
    MS_RETRY_INTERRUPTED(transferred, pwrite((int)fd, data, length, (off_t)offset));
    if (transferred < 0) {
        return last_error();
    }
    *count = (size_t)transferred;
    return 0;
}

MsSysError ms_sys_fs_seek(MsSysFd fd, int64_t offset, int32_t origin, int64_t *position) {
    if (fd < 0) {
        return EBADF;
    }
    int whence = SEEK_SET;
    if (origin == 1) {
        whence = SEEK_CUR;
    } else if (origin == 2) {
        whence = SEEK_END;
    } else if (origin != 0 || offset < 0) {
        return EINVAL;
    }
    const off_t at = lseek((int)fd, (off_t)offset, whence);
    if (at < 0) {
        return last_error();
    }
    *position = at;
    return 0;
}

MsSysError ms_sys_fs_truncate_fd(MsSysFd fd, int64_t size) {
    if (fd < 0) {
        return EBADF;
    }
    int result = -1;
    MS_RETRY_INTERRUPTED(result, ftruncate((int)fd, (off_t)size));
    return status_of(result);
}

/* Flushes to stable storage; macOS needs F_FULLFSYNC for the data to reach the disk. */
static MsSysError flush_to_disk(MsSysFd fd, bool data_only) {
    if (fd < 0) {
        return EBADF;
    }
    int result = -1;
#ifdef __APPLE__
    (void)data_only;
    MS_RETRY_INTERRUPTED(result, fcntl((int)fd, F_FULLFSYNC));
#else
    MS_RETRY_INTERRUPTED(result, data_only ? fdatasync((int)fd) : fsync((int)fd));
#endif
    return status_of(result);
}

MsSysError ms_sys_fs_sync(MsSysFd fd) { return flush_to_disk(fd, false); }

MsSysError ms_sys_fs_data_sync(MsSysFd fd) { return flush_to_disk(fd, true); }

MsSysError ms_sys_fs_try_lock(MsSysFd fd, bool exclusive, bool *taken) {
    if (fd < 0) {
        return EBADF;
    }
    int result = -1;
    MS_RETRY_INTERRUPTED(result, flock((int)fd, (exclusive ? LOCK_EX : LOCK_SH) | LOCK_NB));
    if (result == 0) {
        *taken = true;
        return 0;
    }
    if (errno == EWOULDBLOCK) {
        *taken = false;
        return 0;
    }
    return last_error();
}

MsSysError ms_sys_fs_unlock(MsSysFd fd) {
    if (fd < 0) {
        return EBADF;
    }
    int result = -1;
    MS_RETRY_INTERRUPTED(result, flock((int)fd, LOCK_UN));
    return status_of(result);
}

/* ---- file information ---- */

#ifdef __linux__

/* The kernel's statx structure, declared here because musl's headers have none. The layout is the kernel ABI. */
struct MsStatxTimestamp {
    int64_t tv_sec;
    uint32_t tv_nsec;
    int32_t reserved;
};

struct MsStatx {
    uint32_t stx_mask;
    uint32_t stx_blksize;
    uint64_t stx_attributes;
    uint32_t stx_nlink;
    uint32_t stx_uid;
    uint32_t stx_gid;
    uint16_t stx_mode;
    uint16_t reserved0;
    uint64_t stx_ino;
    uint64_t stx_size;
    uint64_t stx_blocks;
    uint64_t stx_attributes_mask;
    struct MsStatxTimestamp stx_atime;
    struct MsStatxTimestamp stx_btime;
    struct MsStatxTimestamp stx_ctime;
    struct MsStatxTimestamp stx_mtime;
    uint32_t stx_rdev_major;
    uint32_t stx_rdev_minor;
    uint32_t stx_dev_major;
    uint32_t stx_dev_minor;
    uint64_t reserved1[16];
};

enum { MS_STATX_BASIC_STATS = 0x7ff, MS_STATX_BTIME = 0x800 };

static int ms_statx(int directory, const char *path, int flags, struct MsStatx *out) {
    return (int)syscall(SYS_statx, directory, path, flags, (unsigned)(MS_STATX_BASIC_STATS | MS_STATX_BTIME), out);
}

static MsSysTime time_of_statx(const struct MsStatxTimestamp *stamp) {
    return (MsSysTime){.seconds = stamp->tv_sec, .nanos = stamp->tv_nsec};
}

static void fill_from_statx(const struct MsStatx *source, MsSysStat *out) {
    *out = (MsSysStat){
        .mode = source->stx_mode,
        .size = (int64_t)source->stx_size,
        .modified = time_of_statx(&source->stx_mtime),
        .accessed = time_of_statx(&source->stx_atime),
        .changed = time_of_statx(&source->stx_ctime),
        .block_size = source->stx_blksize,
        .blocks = source->stx_blocks,
        .rdev = makedev(source->stx_rdev_major, source->stx_rdev_minor),
        .device = makedev(source->stx_dev_major, source->stx_dev_minor),
        .inode = source->stx_ino,
        .links = source->stx_nlink,
        .uid = source->stx_uid,
        .gid = source->stx_gid,
    };
    if ((source->stx_mask & MS_STATX_BTIME) != 0) {
        out->created = time_of_statx(&source->stx_btime);
        out->has_created = true;
    }
}

#endif

static MsSysTime time_of_timespec(const struct timespec *stamp) {
    return (MsSysTime){.seconds = stamp->tv_sec, .nanos = stamp->tv_nsec};
}

/* The portable struct stat route: macOS always, Linux when statx is refused. */
static void fill_from_stat(const struct stat *source, MsSysStat *out) {
    *out = (MsSysStat){
        .mode = source->st_mode,
        .size = (int64_t)source->st_size,
        .block_size = (uint64_t)source->st_blksize,
        .blocks = (uint64_t)source->st_blocks,
        .rdev = (uint64_t)source->st_rdev,
        .device = (uint64_t)source->st_dev,
        .inode = (uint64_t)source->st_ino,
        .links = (uint64_t)source->st_nlink,
        .uid = source->st_uid,
        .gid = source->st_gid,
    };
#ifdef __APPLE__
    out->modified = time_of_timespec(&source->st_mtimespec);
    out->accessed = time_of_timespec(&source->st_atimespec);
    out->changed = time_of_timespec(&source->st_ctimespec);
    out->created = time_of_timespec(&source->st_birthtimespec);
    out->has_created = true;
#else
    out->modified = time_of_timespec(&source->st_mtim);
    out->accessed = time_of_timespec(&source->st_atim);
    out->changed = time_of_timespec(&source->st_ctim);
#endif
}

MsSysError ms_sys_fs_fstat(MsSysFd fd, MsSysStat *out) {
    if (fd < 0) {
        return EBADF;
    }
#ifdef __linux__
    struct MsStatx extended;
    int result = -1;
    MS_RETRY_INTERRUPTED(result, ms_statx((int)fd, "", AT_EMPTY_PATH, &extended));
    if (result == 0) {
        fill_from_statx(&extended, out);
        return 0;
    }
    if (errno != ENOSYS) {
        return last_error();
    }
#endif
    struct stat plain;
    int plain_result = -1;
    MS_RETRY_INTERRUPTED(plain_result, fstat((int)fd, &plain));
    if (plain_result < 0) {
        return last_error();
    }
    fill_from_stat(&plain, out);
    return 0;
}

/* ---- changing files by descriptor ---- */

MsSysError ms_sys_fs_chmod_fd(MsSysFd fd, uint32_t mode) {
    if (fd < 0) {
        return EBADF;
    }
    int result = -1;
    MS_RETRY_INTERRUPTED(result, fchmod((int)fd, (mode_t)mode));
    return status_of(result);
}

static uid_t id_of(int64_t value) { return value >= 0 ? (uid_t)value : (uid_t)-1; }

MsSysError ms_sys_fs_chown_fd(MsSysFd fd, int64_t uid, int64_t gid) {
    if (fd < 0) {
        return EBADF;
    }
    int result = -1;
    MS_RETRY_INTERRUPTED(result, fchown((int)fd, id_of(uid), (gid_t)id_of(gid)));
    return status_of(result);
}

static struct timespec timespec_of(MsSysTime time) {
    int64_t nanos = time.nanos;
    if (nanos < 0) {
        nanos = 0;
    } else if (nanos > 999999999) {
        nanos = 999999999;
    }
    return (struct timespec){.tv_sec = (time_t)time.seconds, .tv_nsec = (long)nanos};
}

MsSysError ms_sys_fs_set_times_fd(MsSysFd fd, MsSysTime accessed, MsSysTime modified) {
    if (fd < 0) {
        return EBADF;
    }
    const struct timespec times[2] = {timespec_of(accessed), timespec_of(modified)};
    int result = -1;
    MS_RETRY_INTERRUPTED(result, futimens((int)fd, times));
    return status_of(result);
}

MsSysError ms_sys_fs_clone_file(MsSysFd output, MsSysFd input) {
#ifdef __linux__
    if (output < 0 || input < 0) {
        return EBADF;
    }
    return status_of(ioctl((int)output, MS_FICLONE, (int)input));
#else
    (void)output;
    (void)input;
    return ENOTSUP;
#endif
}

/* ---- changing files by path ---- */

MsSysError ms_sys_fs_chmod_link(const char *path, uint32_t mode) {
#ifdef __APPLE__
    int result = -1;
    MS_RETRY_INTERRUPTED(result, fchmodat(AT_FDCWD, path, (mode_t)mode, AT_SYMLINK_NOFOLLOW));
    return status_of(result);
#else
    (void)path;
    (void)mode;
    return ENOTSUP;
#endif
}

/* Opens a file to set its times: reading is enough, writing is the fallback for a file only writable. */
static MsSysError open_for_times(const char *path, MsSysFd *fd) {
    const MsSysError error = ms_sys_fs_open(path, MS_SYS_O_READ, 0, fd);
    if (error == 0) {
        return 0;
    }
    return ms_sys_fs_open(path, MS_SYS_O_WRITE, 0, fd);
}

MsSysError ms_sys_fs_set_times(const char *path, MsSysTime accessed, MsSysTime modified, bool follow) {
    if (!follow) {
        const struct timespec times[2] = {timespec_of(accessed), timespec_of(modified)};
        int result = -1;
        MS_RETRY_INTERRUPTED(result, utimensat(AT_FDCWD, path, times, AT_SYMLINK_NOFOLLOW));
        return status_of(result);
    }
    MsSysFd fd = MS_SYS_FD_INVALID;
    MsSysError error = open_for_times(path, &fd);
    if (error != 0) {
        return error;
    }
    error = ms_sys_fs_set_times_fd(fd, accessed, modified);
    ms_sys_fs_close_quietly(fd);
    return error;
}

/* ---- the process's view ---- */

MsSysError ms_sys_fs_current_directory(char **path, size_t *length) {
    size_t capacity = 256;
    for (;;) {
        char *buffer = malloc(capacity);
        if (buffer == NULL) {
            return ENOMEM;
        }
        if (getcwd(buffer, capacity) != NULL) {
            *path = buffer;
            *length = strlen(buffer);
            return 0;
        }
        const MsSysError error = last_error();
        free(buffer);
        if (error != ERANGE || !ms_size_mul(capacity, 2, &capacity)) {
            return error;
        }
    }
}

MsSysError ms_sys_fs_temp_directory(char **path, size_t *length) {
    // NOLINTNEXTLINE(concurrency-mt-unsafe): the runtime never changes the environment after start-up.
    const char *configured = getenv("TMPDIR");
    const char *chosen = configured != NULL ? configured : "/tmp";
    const size_t size = strlen(chosen);
    char *copy = malloc(size + 1);
    if (copy == NULL) {
        return ENOMEM;
    }
    memcpy(copy, chosen, size + 1);
    *path = copy;
    *length = size;
    return 0;
}

uint32_t ms_sys_fs_random(void) {
    int local = 0;
    uint64_t state = (uint64_t)ms_sys_monotonic_ns() ^ ((uint64_t)getpid() << 32) ^ (uint64_t)(uintptr_t)&local;
    state += UINT64_C(0x9E3779B97F4A7C15);
    state = (state ^ (state >> 30)) * UINT64_C(0xBF58476D1CE4E5B9);
    state = (state ^ (state >> 27)) * UINT64_C(0x94D049BB133111EB);
    return (uint32_t)((state ^ (state >> 31)) >> 16);
}

MsSysFdKind ms_sys_fs_fd_kind(MsSysFd fd) {
    struct stat info;
    if (fstat((int)fd, &info) != 0) {
        return MS_SYS_FD_OTHER;
    }
    return S_ISREG(info.st_mode) ? MS_SYS_FD_FILE : MS_SYS_FD_OTHER;
}

bool ms_sys_fs_is_terminal(MsSysFd fd) { return isatty((int)fd) != 0; }

bool ms_sys_error_is_broken_pipe(MsSysError error) { return error == EPIPE; }

bool ms_sys_fs_is_output(MsSysFd fd) { return fd == 1 || fd == 2; }

MsSysFd ms_sys_fs_standard(int32_t which) { return which; }

MsSysError ms_sys_fs_redirect_null(int32_t which) {
    const int null = open("/dev/null", O_RDWR | O_CLOEXEC);
    if (null < 0) {
        return last_error();
    }
    const int moved = dup2(null, (int)which);
    const MsSysError error = moved < 0 ? last_error() : 0;
    ms_sys_fs_close_quietly(null);
    return error;
}
