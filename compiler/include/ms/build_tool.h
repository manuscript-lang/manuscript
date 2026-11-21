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
/* Runs `argv` (NULL-terminated, argv[0] a path) with its output in the file `log`. On failure `output` gets `what` and the
 * tool's output (or why it could not run). */
bool ms_build_run(const char *what, char *const *argv, const char *log, MsBuf *output);

#endif
