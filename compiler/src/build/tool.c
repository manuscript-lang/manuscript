/* Files of the build steps (ms/build_tool.h). The child processes and directories are in tool_posix.c and
 * tool_windows.c. */
#include <stdio.h>

#include "ms/build_tool.h"

bool ms_build_read(const char *path, MsBuf *out) {
    FILE *file = fopen(path, "rb");
    if (file == NULL) {
        return false;
    }
    char chunk[16384];
    size_t n;
    while ((n = fread(chunk, 1, sizeof chunk, file)) > 0) {
        ms_buf_put(out, chunk, n);
    }
    const bool ok = ferror(file) == 0;
    (void)fclose(file);
    return ok;
}

bool ms_build_write(const char *path, const void *bytes, size_t len) {
    FILE *file = fopen(path, "wb");
    if (file == NULL) {
        return false;
    }
    const bool ok = len == 0 || fwrite(bytes, 1, len, file) == len;
    return fclose(file) == 0 && ok;
}
