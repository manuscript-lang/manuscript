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
/* Runs `argv` (NULL-terminated; argv[0] a path, or a name looked up on PATH) to completion. On failure `output` gets `what`
 * and the tool's output (or why it could not run). */
bool ms_build_run(const char *what, const char *const *argv, MsBuf *output);
/* Like ms_build_run, in the directory `cwd` (NULL: the current one). */
bool ms_build_run_in(const char *what, const char *const *argv, const char *cwd, MsBuf *output);
/* Whether `name` is a program on PATH: it starts when asked its `--version`. */
bool ms_build_have(const char *name);
/* Makes a fresh private directory from `pattern` (ending in XXXXXX, replaced in place); returns 0 or the host's code. */
int ms_build_make_dir(char *pattern);
/* Makes the directory `path` and the missing ones above it. */
bool ms_build_make_path(const char *path);
/* Makes a private directory `<prefix>-XXXXXX` in the system's temporary directory; `path` gets its name, NUL-terminated (the
 * NUL is not counted). Returns 0 or the host's code. */
int ms_build_make_scratch(const char *prefix, MsBuf *path);
/* Like ms_build_read and ms_build_write; 0 or the host's error code. */
int ms_build_read_file(const char *path, MsBuf *out);
int ms_build_write_file(const char *path, const void *bytes, size_t len);
/* Whether `path` (links followed) is a regular file. */
bool ms_build_is_file(const char *path);
/* Appends the host message of the error code `err_no` to `out`. */
void ms_build_errno_text(int err_no, MsBuf *out);
/* Removes a file, an empty directory, or a directory and all it holds. Missing paths are fine. */
void ms_build_unlink(const char *path);
void ms_build_remove_tree(const char *path);

#endif
