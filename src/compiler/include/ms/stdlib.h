/* Loads the bundled standard library into the checker tables. */
#ifndef MS_STDLIB_H
#define MS_STDLIB_H

#include "ms/tables.h"

typedef struct MsStdFile {
    const char *name; /* `bytes.ms`, `net/http.ms`; the prelude files of `src/stdlib/core/` are flat */
    const char *text;
    size_t len;
} MsStdFile;

/* qsort order for MsStdFile rows: by name. */
static inline int ms_std_file_by_name(const void *a, const void *b) {
    return strcmp(((const MsStdFile *)a)->name, ((const MsStdFile *)b)->name);
}

/* Parses every file (syntax and texts live in `syntax`), splits files that mix native operations
 * with bodies into a native half and a `+source` half, registers the native declarations and the
 * exported types of source modules, and declares every native type's variables. Modules appear in
 * `c->mods` in the order of the Rust loader: files sorted by name, a native half before its
 * `+source` half. Returns false with a message in *err (allocated in `syntax`) on the first error,
 * as the Rust loader's `Err` strings read. */
bool ms_std_load(MsCheck *c, MsArena *syntax, const MsStdFile *files, uint32_t nfiles, MsStr *err);

/* `@std/net/http.ms` -> `http`; the module name native identities use. */
MsStr ms_module_stem(MsStr file);

#endif
