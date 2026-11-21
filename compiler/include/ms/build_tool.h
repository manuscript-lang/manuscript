/* Files and child processes of the build steps (build/object.c, build/link.c). */
#ifndef MS_BUILD_TOOL_H
#define MS_BUILD_TOOL_H

#include <stdbool.h>
#include <stddef.h>

#include "ms/base.h"

/* The process environment, which POSIX leaves out of its headers; one declaration for the whole unit. */
extern char **environ;

/* Appends the bytes of `path` to `out`; false when it cannot be read. */
bool ms_build_read(const char *path, MsBuf *out);
/* Writes `len` bytes to `path`. */
bool ms_build_write(const char *path, const void *bytes, size_t len);
/* Appends the message of the errno value `err_no` to `out`. */
void ms_build_put_errno(MsBuf *out, int err_no);
/* Runs `argv` (NULL-terminated, argv[0] a path) with its output in the file `log`. On failure `output` gets `what` and the
 * tool's output (or why it could not run). */
bool ms_build_run(const char *what, const char *const *argv, const char *log, MsBuf *output);

#endif
