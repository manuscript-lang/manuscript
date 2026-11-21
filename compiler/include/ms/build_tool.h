/* Files and child processes of the build steps (build/object.c, build/link.c). */
#ifndef MS_BUILD_TOOL_H
#define MS_BUILD_TOOL_H

#include <stdbool.h>
#include <stddef.h>

#include "ms/base.h"

/* Appends the bytes of `path` to `out`; false when it cannot be read. */
bool ms_build_read(const char *path, MsBuf *out);
/* Writes `len` bytes to `path`. */
bool ms_build_write(const char *path, const void *bytes, size_t len);
/* Runs `argv` (NULL-terminated; argv[0] a path, or a name looked up on PATH) with its output in the file `log`. On failure
 * `output` gets `what` and the tool's output (or why it could not run). */
bool ms_build_run(const char *what, const char *const *argv, const char *log, MsBuf *output);
/* Like ms_build_run, in the directory `cwd` (NULL: the current one). */
bool ms_build_run_in(const char *what, const char *const *argv, const char *cwd, const char *log, MsBuf *output);
/* Whether `name` is an executable on PATH. */
bool ms_build_have(const char *name);
/* Makes a fresh private directory from `pattern` (ending in XXXXXX, replaced in place). */
bool ms_build_make_dir(char *pattern);
/* Makes the directory `path` and the missing ones above it. */
bool ms_build_make_path(const char *path);
/* Appends the system message of `err_no` to `out`. */
void ms_build_errno_text(int err_no, MsBuf *out);
/* Removes a file, an empty directory, or a directory and all it holds. Missing paths are fine. */
void ms_build_unlink(const char *path);
void ms_build_remove_tree(const char *path);

#endif
