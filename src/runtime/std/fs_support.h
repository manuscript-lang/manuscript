/* What the @std/fs and @std/io natives share: failures with their text, validated paths, the blocking-pool wrapper,
 * a growable byte buffer, path names, and building runtime values. Everything here runs on the runtime thread or on
 * a pool thread, so nothing that a job may call touches the runtime's allocator (the natives copy results out). */
#ifndef MS_STD_FS_SUPPORT_H
#define MS_STD_FS_SUPPORT_H

#include "abi.h"
#include "ms_rt/fs.h"
#include "ms_rt/safe.h"
#include "ms_rt/sys_fs.h"
#include "ms_sched.h"

/* ---- failures ---- */

/* The status of a failed operation and, for STATUS_FAILED, its diagnostic text. */
typedef struct MsFsFail {
    uint8_t status; /* STATUS_OK while nothing failed */
    char *message;  /* owned (malloc), NUL-terminated; only for STATUS_FAILED */
    size_t message_length;
} MsFsFail;

/* The status an OS error maps to (classifyOS): not found, exists, not empty, invalid, permission, unsupported, or
 * STATUS_FAILED for the rest. */
uint8_t ms_fs_classify(MsSysError error);
bool ms_fs_failed(const MsFsFail *fail);
void ms_fs_fail_free(MsFsFail *fail);
void ms_fs_fail_status(MsFsFail *fail, uint8_t status);
/* STATUS_FAILED with `text`. */
void ms_fs_fail_text(MsFsFail *fail, const char *text);
/* A bare system-call failure: the status of `error`, and for STATUS_FAILED the host's text. */
void ms_fs_fail_raw(MsFsFail *fail, MsSysError error);
/* An OS failure of `operation` on `count` paths: `open /x: permission denied`. A status other than STATUS_FAILED
 * carries no text. */
void ms_fs_fail_errno(MsFsFail *fail, MsSysError error, const char *operation, const MsBytes *paths, size_t count);
/* An OS failure that is always STATUS_FAILED with its text, `read name: reason`, whatever the code means (streams
 * report every failure so). */
void ms_fs_fail_os(MsFsFail *fail, MsSysError error, const char *operation, MsBytes name);
/* The same for one path. */
void ms_fs_fail_errno_at(MsFsFail *fail, MsSysError error, const char *operation, MsBytes path);

/* A libuv failure (a negative UV_* code) of `operation` on `name` (empty for none): not found, permission denied and
 * unsupported keep their status, the rest are STATUS_FAILED with `operation name: reason`. */
void ms_fs_fail_uv(MsFsFail *fail, int code, const char *operation, MsBytes name);

/* Ends a native: returns the failure's status and always fills `err` for a failure (the caller reads the slot whatever the
 * status; empty when there is no text). STATUS_FAILED stores the failure's text; any other
 * status stores `detail` (the path or paths, "a -> b" for a pair) when there is one. A pending stop request is
 * delivered by return: the text is dropped first, the status is then irrelevant. A success is returned as it is. */
uint8_t ms_fs_finish(MsFsFail *fail, MsStr *err);
uint8_t ms_fs_finish_at(MsFsFail *fail, MsBytes path, MsStr *err);
uint8_t ms_fs_finish_pair(MsFsFail *fail, MsBytes source, MsBytes destination, MsStr *err);

/* ---- stop requests and the blocking pool ---- */

/* Whether a stop request is pending for the running task; never true on a pool thread, where a job runs to its end. */
bool ms_fs_cancel_requested(void);
/* A pending stop request as a failure: true, with `fail` set to "cancelled", when one is pending. */
bool ms_fs_poll_cancel(MsFsFail *fail);
/* Runs `run(job)` on the blocking pool when other tasks could use the time, otherwise inline. The wait is shielded,
 * so `job` may live on the caller's stack; a stop request takes effect once the job is done and is reported as a
 * failure in `fail`. */
typedef void (*MsFsRunFn)(void *job);
void ms_fs_run(MsFsRunFn run, void *job, MsFsFail *fail);

/* ---- validated paths ---- */

/* A path made ready for the OS layer: non-empty, no NUL, NUL-terminated. Small paths stay inside the struct, so
 * it is initialised in place and never copied. */
typedef struct MsFsPath {
    const char *text;
    size_t length;
    char *heap; /* owned; null while the text fits inline */
    char inline_text[256];
} MsFsPath;

MS_NODISCARD bool ms_fs_path_init(MsFsPath *path, MsBytes bytes);
void ms_fs_path_free(MsFsPath *path);

/* ---- a growable byte buffer ---- */

typedef struct MsFsBuffer {
    uint8_t *data; /* owned (malloc); null while empty */
    size_t length;
    size_t capacity;
} MsFsBuffer;

MS_NODISCARD bool ms_fs_buffer_append(MsFsBuffer *buffer, const uint8_t *bytes, size_t length);
MS_NODISCARD bool ms_fs_buffer_push(MsFsBuffer *buffer, uint8_t byte);
/* Appends `bytes` with every invalid UTF-8 sequence replaced by U+FFFD, so one odd name does not make its directory
 * unlistable. */
MS_NODISCARD bool ms_fs_buffer_append_lossy(MsFsBuffer *buffer, const uint8_t *bytes, size_t length);
void ms_fs_buffer_free(MsFsBuffer *buffer);
static inline MsBytes ms_fs_buffer_view(const MsFsBuffer *buffer) { return ms_bytes_of(buffer->data, buffer->length); }

bool ms_fs_valid_utf8(MsBytes bytes);

/* ---- path names ---- */

/* Path names follow the host's rules (the separator, volumes and absolute paths of std::path). The rules are a
 * parameter of the `_with` forms so one host tests the other's rules; the plain forms use the host's. */
typedef enum { MS_FS_RULES_UNIX, MS_FS_RULES_WINDOWS } MsFsRules;

bool ms_fs_is_separator_with(MsFsRules rules, uint8_t byte);
bool ms_fs_is_absolute_with(MsFsRules rules, MsBytes path);
/* The shortest equivalent path by lexical processing ("." for an empty result): repeated separators and "." go,
 * ".." undoes the element before it and vanishes above a root. */
MS_NODISCARD bool ms_fs_path_clean_with(MsFsRules rules, MsBytes path, MsFsBuffer *out);
/* Two elements joined and cleaned; an absolute second element replaces the first. */
MS_NODISCARD bool ms_fs_path_join_with(MsFsRules rules, MsBytes first, MsBytes second, MsFsBuffer *out);
/* The last element: "." for an empty path, the root or volume for a bare one. A view into `path`, or a constant. */
MsBytes ms_fs_path_base_with(MsFsRules rules, MsBytes path);
/* Everything but the last element, cleaned; a path without one (a root, a volume, empty) is cleaned itself. */
MS_NODISCARD bool ms_fs_path_dir_with(MsFsRules rules, MsBytes path, MsFsBuffer *out);

/* The separator `join` and `clean` write. */
uint8_t ms_fs_separator(void);
bool ms_fs_is_separator(uint8_t byte);
bool ms_fs_is_absolute(MsBytes path);
MS_NODISCARD bool ms_fs_path_clean(MsBytes path, MsFsBuffer *out);
MS_NODISCARD bool ms_fs_path_join(MsBytes first, MsBytes second, MsFsBuffer *out);
MsBytes ms_fs_path_base(MsBytes path);
MS_NODISCARD bool ms_fs_path_dir(MsBytes path, MsFsBuffer *out);

/* ---- operations the other fs files share ---- */

/* Fills a FileInfo (everything but the name) from a stat. */
void ms_fs_info_fill(MsFsInfo *out, const MsSysStat *stat);
/* A new directory in the temporary directory named from `pattern` (a `*` marks the random digits); its path is left
 * in `out`. */
bool ms_fs_make_temporary_directory(MsBytes pattern, MsFsBuffer *out, MsFsFail *fail);

/* Whether a listing entry is a directory or a symbolic link: its own kind, or an lstat when the filesystem gives none. */
void ms_fs_entry_kind(MsBytes directory, const MsSysDirEntry *entry, bool *is_dir, bool *is_symlink);
/* Removes the tree at `path` without following links; a missing path is already removed. */
void ms_fs_remove_tree(MsBytes path, MsFsFail *fail);

/* Reads to the end of `fd` into `out`, failing with STATUS_LIMIT_EXCEEDED past `max` bytes. A cancellable read checks for
 * a stop request between reads (a pool thread must not) and waits for a pipe or device to be readable. `stat` is the
 * descriptor's fstat, or null when it has none. */
void ms_fs_read_limited(MsSysFd fd, int64_t max, bool cancellable, const MsSysStat *stat, MsFsBuffer *out, MsFsFail *fail);
/* The absolute, canonical form of an existing path (every link resolved), or the host error. */
MsSysError ms_fs_eval_symlinks(MsBytes path, MsFsBuffer *out);
/* os.Remove: the path as a file, then as an empty directory. */
MsSysError ms_fs_remove_one(const char *path);
/* Whether two stats describe the same file. */
bool ms_fs_same_file(const MsSysStat *a, const MsSysStat *b);

/* ---- runtime values ---- */


void ms_fs_write_string(MsStr *out, const uint8_t *bytes, size_t length);
void ms_fs_write_buffer_string(MsStr *out, const MsFsBuffer *buffer);


/* An optional size limit: unset is unlimited, a negative one invalid. */
MS_NODISCARD bool ms_fs_limit(uint8_t present, int64_t value, int64_t *out);

#define MS_FS_UNLIMITED INT64_MAX

#endif
