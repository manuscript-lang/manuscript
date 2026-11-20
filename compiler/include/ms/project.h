/* Projects: file names to the module graph the checker reads. Port of crates/ms-driver (`project` and `load`).
 *
 * Paths are `/`-separated text, cleaned as Go's path/filepath does. Every function allocates its results in the
 * caller's arena. A failure fills an MsProjectError, whose text (ms_project_error_text) is what the Rust driver
 * printed, byte for byte. POSIX only for now: the file-system calls are in project/path.c. */
#ifndef MS_PROJECT_H
#define MS_PROJECT_H

#include "ms/base.h"

typedef enum MsProjectErrorKind {
    MS_PERR_NONE,
    MS_PERR_PATH,    /* a failed system call on a path: `op path: message` */
    MS_PERR_ERRNO,   /* a bare errno, as Go returns from symlink walks */
    MS_PERR_MESSAGE, /* any other text */
    MS_PERR_MANIFEST /* `file:line:column: cause` */
} MsProjectErrorKind;

typedef struct MsProjectError MsProjectError;
struct MsProjectError {
    MsProjectErrorKind kind;
    const char *op, *path;       /* MS_PERR_PATH */
    int err_no;                  /* MS_PERR_PATH, MS_PERR_ERRNO */
    const char *message;         /* MS_PERR_MESSAGE */
    const char *file;            /* MS_PERR_MANIFEST: where it was found, and the cause */
    uint32_t line, column, offset;
    const MsProjectError *cause;
};

/* The text of the error, as `Display` printed it. */
const char *ms_project_error_text(MsArena *a, const MsProjectError *err);
/* True for ENOENT only (Go's os.IsNotExist), looking through a manifest location. */
bool ms_project_error_not_exist(const MsProjectError *err);
void ms_project_error_message(MsProjectError *err, const char *message);
void ms_project_error_path(MsProjectError *err, MsArena *a, const char *op, const char *path, int err_no);

/* ---- paths (project/path.c): filepath.Clean, Join, Dir, Base, Ext, Abs, Rel, EvalSymlinks ---- */

const char *ms_path_clean(MsArena *a, const char *path);
/* Joins the non-empty elements and cleans the result; all empty gives "". */
const char *ms_path_join(MsArena *a, const char *const *elements, size_t count);
#define MS_PATH_JOIN(a, ...) \
    ms_path_join((a), (const char *const[]){__VA_ARGS__}, sizeof((const char *const[]){__VA_ARGS__}) / sizeof(char *))
const char *ms_path_dir(MsArena *a, const char *path);
const char *ms_path_base(MsArena *a, const char *path);
/* The suffix beginning at the final dot of the last element ("" for none); points into `path`. */
const char *ms_path_ext(const char *path);
bool ms_path_is_abs(const char *path);
MS_NODISCARD bool ms_path_abs(MsArena *a, const char *path, const char **out, MsProjectError *err);
MS_NODISCARD bool ms_path_rel(MsArena *a, const char *base, const char *target, const char **out, MsProjectError *err);
/* True when `rel` (from ms_path_rel) leaves its base directory. */
bool ms_path_escapes(const char *rel);
MS_NODISCARD bool ms_path_eval_symlinks(MsArena *a, const char *path, const char **out, MsProjectError *err);

#endif
