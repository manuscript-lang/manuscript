/* ms_rt/sys_fs.h: files, directories and paths, the only door to the operating system's file calls for runtime/std.
 * Implemented per platform: sys/posix/fs.c (Linux and macOS) and sys/windows/fs.c.
 *
 * Rules:
 *  - paths are UTF-8, NUL-terminated and non-empty; the Windows layer converts them to UTF-16 and refuses text that
 *    is not UTF-8 (MS_SYS_ERROR_INVALID), so callers validate nothing platform-specific;
 *  - a function returns 0 on success, otherwise the host's error code (errno, or the Win32 code). The code is only
 *    interpreted through ms_sys_fs_error_kind and ms_sys_fs_error_text, never compared with host constants;
 *  - a result that has no fixed size is allocated with malloc and the caller frees it: these functions run on
 *    blocking-pool threads, where the runtime's allocator must not be touched;
 *  - a descriptor is an MsSysFd, the integer the host uses (a file descriptor, or a HANDLE).
 *
 * Internal to the runtime: programs never call these, so they have no recorded signature.
 */
#ifndef MS_RT_SYS_FS_H
#define MS_RT_SYS_FS_H

#include "ms_rt/base.h"
#include "ms_rt/safe.h"

typedef intptr_t MsSysFd;
typedef int32_t MsSysError;

#define MS_SYS_FD_INVALID ((MsSysFd)-1)

/* ---- errors ---- */

typedef enum {
    MS_SYS_ERR_OTHER = 0,
    MS_SYS_ERR_NOT_FOUND,
    MS_SYS_ERR_EXISTS,
    MS_SYS_ERR_NOT_EMPTY,
    MS_SYS_ERR_NOT_DIRECTORY,
    MS_SYS_ERR_IS_DIRECTORY,
    MS_SYS_ERR_INVALID,
    MS_SYS_ERR_PERMISSION,
    MS_SYS_ERR_WOULD_BLOCK,
    MS_SYS_ERR_UNSUPPORTED,
    MS_SYS_ERR_LINK_LOOP,
    MS_SYS_ERR_INTERRUPTED,
    MS_SYS_ERR_IO,
    MS_SYS_ERR_BAD_DESCRIPTOR,
    MS_SYS_ERR_NO_ENTRY_DEVICE /* ENXIO: a FIFO opened without a reader (posix only) */
} MsSysErrorKind;

/* What a host error code means. */
MsSysErrorKind ms_sys_fs_error_kind(MsSysError error);
/* The host code for a kind this layer reports itself (invalid, exists, io, bad descriptor, unsupported). */
MsSysError ms_sys_fs_error_of(MsSysErrorKind kind);
/* The host's detail text for a code: fixed wording on Unix, the system message on Windows. Written to `buffer` and
 * NUL-terminated, truncated to fit; returns the length written. */
size_t ms_sys_fs_error_text(MsSysError error, char *buffer, size_t capacity);

/* ---- opening and descriptors ---- */

/* Open flags. The access mode is the low two bits; the rest are bits. They are the same on every host. */
enum {
    MS_SYS_O_READ = 0x0,
    MS_SYS_O_WRITE = 0x1,
    MS_SYS_O_READ_WRITE = 0x2,
    MS_SYS_O_ACCESS_MASK = 0x3,
    MS_SYS_O_CREATE = 0x40,
    MS_SYS_O_EXCLUSIVE = 0x80,
    MS_SYS_O_TRUNCATE = 0x200,
    MS_SYS_O_APPEND = 0x400,
    MS_SYS_O_NONBLOCK = 0x800, /* posix only; Windows ignores it */
    MS_SYS_O_SYNC = 0x1000
};

/* Opens `path`; `mode` carries the permission bits of a created file. The descriptor is close-on-exec. */
MS_NODISCARD MsSysError ms_sys_fs_open(const char *path, int32_t flags, uint32_t mode, MsSysFd *fd);
/* Closes once and never retries, even when interrupted: the descriptor is gone either way. */
MS_NODISCARD MsSysError ms_sys_fs_close(MsSysFd fd);

/* Closes after the real result is known: a failure here cannot change it. */
static inline void ms_sys_fs_close_quietly(MsSysFd fd) {
    const MsSysError ignored = ms_sys_fs_close(fd);
    (void)ignored;
}
/* A second descriptor over the same open file; the two share the file position. */
MS_NODISCARD MsSysError ms_sys_fs_dup(MsSysFd fd, MsSysFd *out);
/* Switches a descriptor opened with MS_SYS_O_NONBLOCK back to blocking mode (a no-op on Windows). */
void ms_sys_fs_set_blocking(MsSysFd fd);

/* Reads up to `capacity` bytes; *count is 0 at end of file. */
MS_NODISCARD MsSysError ms_sys_fs_read(MsSysFd fd, uint8_t *buffer, size_t capacity, size_t *count);
MS_NODISCARD MsSysError ms_sys_fs_write(MsSysFd fd, const uint8_t *data, size_t length, size_t *count);
/* Positioned transfers leave the file position where it was. */
MS_NODISCARD MsSysError ms_sys_fs_pread(MsSysFd fd, uint8_t *buffer, size_t capacity, int64_t offset, size_t *count);
MS_NODISCARD MsSysError ms_sys_fs_pwrite(MsSysFd fd, const uint8_t *data, size_t length, int64_t offset, size_t *count);
/* origin 0 start, 1 current, 2 end; *position is the new offset. */
MS_NODISCARD MsSysError ms_sys_fs_seek(MsSysFd fd, int64_t offset, int32_t origin, int64_t *position);
MS_NODISCARD MsSysError ms_sys_fs_truncate_fd(MsSysFd fd, int64_t size);
MS_NODISCARD MsSysError ms_sys_fs_sync(MsSysFd fd);
MS_NODISCARD MsSysError ms_sys_fs_data_sync(MsSysFd fd);
/* An advisory whole-file lock without waiting: *taken is false when another handle holds a conflicting lock. */
MS_NODISCARD MsSysError ms_sys_fs_try_lock(MsSysFd fd, bool exclusive, bool *taken);
MS_NODISCARD MsSysError ms_sys_fs_unlock(MsSysFd fd);

/* ---- what a descriptor is ---- */

/* How reads of a descriptor block. A file never blocks a read for long, so it is read on the blocking pool; the
 * others are waited on (a pipe or console on Windows cannot be, and has its own kind). */
typedef enum {
    MS_SYS_FD_FILE = 0, /* a regular file */
    MS_SYS_FD_PIPE,
    MS_SYS_FD_CONSOLE,
    MS_SYS_FD_OTHER /* a terminal, socket, device, or anything the kind of is unknown */
} MsSysFdKind;

MsSysFdKind ms_sys_fs_fd_kind(MsSysFd fd);
/* Whether `fd` is a terminal (a console on Windows). */
bool ms_sys_fs_is_terminal(MsSysFd fd);
/* Whether `error` says the reader of a pipe went away (EPIPE; ERROR_BROKEN_PIPE or ERROR_NO_DATA on Windows). */
bool ms_sys_error_is_broken_pipe(MsSysError error);
/* Whether `fd` is standard output or error, which the runtime's buffered `print` shares. */
bool ms_sys_fs_is_output(MsSysFd fd);
/* The descriptor of standard stream `which` (0 input, 1 output, 2 error): the number itself on Unix, the standard
 * handle on Windows. */
MsSysFd ms_sys_fs_standard(int32_t which);
/* Points standard stream `which` (0 input, 1 output, 2 error) at the null device, for this process and children. */
MS_NODISCARD MsSysError ms_sys_fs_redirect_null(int32_t which);

#ifdef _WIN32
/* A manual-reset event that ends a console wait from another thread. */
MS_NODISCARD MsSysError ms_sys_fs_event_new(MsSysFd *event);
void ms_sys_fs_event_signal(MsSysFd event);
void ms_sys_fs_event_free(MsSysFd event);
/* Blocks until the console input `fd` has input or `event` is signalled; true when there is input (or it failed,
 * which the next read reports), false when stopped. */
bool ms_sys_fs_wait_console(MsSysFd fd, MsSysFd event);
/* Fails the blocking read another thread has pending on `fd`, so that thread returns. */
void ms_sys_fs_cancel_io(MsSysFd fd);
#endif

/* ---- file information ---- */

typedef struct MsSysTime {
    int64_t seconds;
    int64_t nanos;
} MsSysTime;

/* What stat reports, in Unix terms: `mode` carries the S_IF* file type and the permission bits; fields a host
 * cannot report are zero. */
typedef struct MsSysStat {
    uint32_t mode;
    int64_t size;
    MsSysTime modified;
    MsSysTime accessed;
    MsSysTime changed;
    MsSysTime created;
    bool has_created;
    uint64_t block_size;
    uint64_t blocks;
    uint64_t rdev;
    uint64_t device;
    uint64_t inode;
    uint64_t links;
    uint64_t uid;
    uint64_t gid;
} MsSysStat;

enum {
    MS_SYS_S_IFMT = 0170000,
    MS_SYS_S_IFSOCK = 0140000,
    MS_SYS_S_IFLNK = 0120000,
    MS_SYS_S_IFREG = 0100000,
    MS_SYS_S_IFBLK = 0060000,
    MS_SYS_S_IFDIR = 0040000,
    MS_SYS_S_IFCHR = 0020000,
    MS_SYS_S_IFIFO = 0010000
};

MS_NODISCARD MsSysError ms_sys_fs_stat(const char *path, bool follow, MsSysStat *out);
MS_NODISCARD MsSysError ms_sys_fs_fstat(MsSysFd fd, MsSysStat *out);

typedef struct MsSysFsStat {
    int64_t kind;
    int64_t block_size;
    int64_t blocks;
    int64_t blocks_free;
    int64_t blocks_available;
    int64_t files;
    int64_t files_free;
} MsSysFsStat;

MS_NODISCARD MsSysError ms_sys_fs_stat_filesystem(const char *path, MsSysFsStat *out);

/* ---- changing files by descriptor ---- */

MS_NODISCARD MsSysError ms_sys_fs_chmod_fd(MsSysFd fd, uint32_t mode);
/* A negative uid or gid leaves that id unchanged. Unsupported on Windows. */
MS_NODISCARD MsSysError ms_sys_fs_chown_fd(MsSysFd fd, int64_t uid, int64_t gid);
MS_NODISCARD MsSysError ms_sys_fs_set_times_fd(MsSysFd fd, MsSysTime accessed, MsSysTime modified);
/* Makes `output` share the extents of `input` (Linux FICLONE); unsupported elsewhere. */
MS_NODISCARD MsSysError ms_sys_fs_clone_file(MsSysFd output, MsSysFd input);

/* ---- changing files by path ---- */

MS_NODISCARD MsSysError ms_sys_fs_mkdir(const char *path, uint32_t mode);
MS_NODISCARD MsSysError ms_sys_fs_unlink(const char *path);
MS_NODISCARD MsSysError ms_sys_fs_rmdir(const char *path);
MS_NODISCARD MsSysError ms_sys_fs_rename(const char *from, const char *to);
MS_NODISCARD MsSysError ms_sys_fs_link(const char *from, const char *to);
/* A symbolic link at `path` pointing at `target`. */
MS_NODISCARD MsSysError ms_sys_fs_symlink(const char *target, const char *path);
/* The link's target, malloc'd and NUL-terminated; *length excludes the NUL. */
MS_NODISCARD MsSysError ms_sys_fs_readlink(const char *path, char **target, size_t *length);
/* The absolute path with every link resolved, malloc'd. */
MS_NODISCARD MsSysError ms_sys_fs_canonicalize(const char *path, char **resolved, size_t *length);
MS_NODISCARD MsSysError ms_sys_fs_chmod(const char *path, uint32_t mode);
/* The mode of a symbolic link itself (macOS); unsupported elsewhere. */
MS_NODISCARD MsSysError ms_sys_fs_chmod_link(const char *path, uint32_t mode);
MS_NODISCARD MsSysError ms_sys_fs_chown(const char *path, int64_t uid, int64_t gid, bool follow);
MS_NODISCARD MsSysError ms_sys_fs_truncate(const char *path, int64_t size);
MS_NODISCARD MsSysError ms_sys_fs_access(const char *path, int32_t mode);
/* Setting the times of a link itself is unsupported on Windows. */
MS_NODISCARD MsSysError ms_sys_fs_set_times(const char *path, MsSysTime accessed, MsSysTime modified, bool follow);

/* ---- directories ---- */

typedef struct MsSysDir MsSysDir;

/* The kinds a directory listing reports; the Unix d_type values. */
enum {
    MS_SYS_DT_UNKNOWN = 0,
    MS_SYS_DT_DIR = 4,
    MS_SYS_DT_REG = 8,
    MS_SYS_DT_LNK = 10
};

enum { MS_SYS_NAME_MAX = 1024 };

typedef struct MsSysDirEntry {
    char name[MS_SYS_NAME_MAX]; /* NUL-terminated UTF-8 */
    size_t name_length;
    uint8_t kind; /* MS_SYS_DT_* */
} MsSysDirEntry;

/* Opens a directory for listing; free it with ms_sys_fs_dir_close. */
MS_NODISCARD MsSysError ms_sys_fs_dir_open(const char *path, MsSysDir **dir);
/* The next entry, never "." or ".."; *found is false at the end. */
MS_NODISCARD MsSysError ms_sys_fs_dir_read(MsSysDir *dir, MsSysDirEntry *entry, bool *found);
void ms_sys_fs_dir_close(MsSysDir *dir);

/* ---- the process's view ---- */

/* The working directory, malloc'd. */
MS_NODISCARD MsSysError ms_sys_fs_current_directory(char **path, size_t *length);
/* The directory for temporary files, malloc'd ($TMPDIR or /tmp; the user's temporary directory on Windows). */
MS_NODISCARD MsSysError ms_sys_fs_temp_directory(char **path, size_t *length);
/* A number that differs from call to call, for naming temporary files. Not for security. */
uint32_t ms_sys_fs_random(void);

#endif
