/* The path a debugger or profiler is given for a source file of a module. Port of debug_files.rs.
 *
 * A standard-library module is known to the compiler by its logical name (`@std/data/csv.ms`),
 * which names no file. Debug info names the real file when the standard-library sources are on disk
 * (the directory the caller read from `MS_STDLIB_DIR`, or `MS_STDLIB_SOURCE_DIR` set at build time,
 * as an absolute path), so that
 * `callgrind_annotate` and debuggers show the lines without any setup; otherwise the logical name is
 * kept. */
#include <stdio.h>
#include "ms/mir_debug.h"
#include <stdlib.h>
#include <string.h>

#ifndef MS_STDLIB_SOURCE_DIR
#define MS_STDLIB_SOURCE_DIR ""
#endif

/* The "e" (close on exec) mode letter is a glibc/BSD extension; the Windows C library rejects it. */
#ifdef _WIN32
#define MS_FOPEN_CLOEXEC_READ "rb"
#else
#define MS_FOPEN_CLOEXEC_READ "rbe"
#endif

static bool df_exists(const char *path) {
    FILE *f = fopen(path, MS_FOPEN_CLOEXEC_READ);
    if (f == NULL) {
        return false;
    }
    (void)fclose(f);
    return true;
}

/* `dir/rest` when that file exists, as the standard-library sources have it. */
static bool df_join(MsArena *arena, const char *dir, MsStr rest, MsStr *out) {
    const MsStr joined = ms_arena_fmt(arena, "%s/%.*s", dir, (int)rest.len, rest.ptr);
    *out = joined;
    return df_exists(joined.ptr);
}

/* `path` spelled the way DWARF consumers split and rejoin it: forward slashes and no Windows
 * verbatim prefix (`\\?\C:\dir` becomes `C:/dir`). */
MsStr mir_portable_path(MsArena *arena, MsStr path) {
    if (path.len >= 4 && memcmp(path.ptr, "\\\\?\\", 4) == 0) {
        path.ptr += 4;
        path.len -= 4;
    }
    char *copy = ms_arena_strndup(arena, path.ptr, path.len);
    for (uint32_t i = 0; i < path.len; i++) {
        if (copy[i] == '\\') {
            copy[i] = '/';
        }
    }
    return (MsStr){copy, path.len};
}

MsStr mir_debug_file_name(MsArena *arena, MsStr path, const char *stdlib_dir) {
    if (path.len < 5 || memcmp(path.ptr, "@std/", 5) != 0) {
        return path;
    }
    const MsStr rest = {path.ptr + 5, path.len - 5};
    const char *dirs[2] = {stdlib_dir, MS_STDLIB_SOURCE_DIR};
    for (int i = 0; i < 2; i++) {
        MsStr probe, file;
        if (dirs[i] == NULL || dirs[i][0] == '\0' ||
            !df_join(arena, dirs[i], (MsStr){"bytes.ms", 8}, &probe)) {
            continue;
        }
        if (df_join(arena, dirs[i], rest, &file)) {
            return mir_portable_path(arena, file);
        }
        return path;
    }
    return path;
}
