/* Checks the bodies of a module the way the Rust checker's program does: the implementations of
 * the modules it imports, the inherent methods desugared to impls and the interface operations
 * join one method table first. For the dump tools of compiler/tools; include it from one file,
 * after std_files.h. */
#ifndef MS_TOOLS_CHECK_PROGRAM_H
#define MS_TOOLS_CHECK_PROGRAM_H

#include "ms/check.h"
#include "ms/desugar.h"
#include "ms/methods.h"
#include "ms/stdlib.h"

/* The text of the bundled file `path` (`@std/io/io.ms`, or `@std/io/io.ms+source`). */
static MsStr std_text(const MsCheck *check, const MsStdFile *files, uint32_t nfiles, MsSym path) {
    MsStr full = ms_name(check->names, path);
    const char *plus = memchr(full.ptr, '+', full.len);
    const size_t len = plus == NULL ? full.len : (size_t)(plus - full.ptr);
    if (len < 5) {
        return (MsStr){0};
    }
    for (uint32_t i = 0; i < nfiles; i++) {
        if (strlen(files[i].name) == len - 5 && memcmp(files[i].name, full.ptr + 5, len - 5) == 0) {
            return (MsStr){files[i].text, (uint32_t)files[i].len};
        }
    }
    return (MsStr){0};
}

/* The implementations of the modules `id` imports join the method table first, as the Rust
 * checker's program-wide table has them. */
static void add_import_methods(MsCheck *check, const MsStdFile *files, uint32_t nfiles, MsModId id, MsMethodTable *table) {
    const MsModule *syntax = check->mods[id].syntax;
    for (uint32_t i = 0; i < syntax->nimports; i++) {
        const MsStr path = syntax->imports[i].path;
        for (int half = 0; half < 2; half++) {
            char buf[512];
            snprintf(buf, sizeof buf, "%.*s%s", (int)path.len, path.ptr, half == 0 ? "" : "+source");
            const MsModId m = ms_module_find(check, ms_intern_cstr(check->names, buf));
            if (m == MS_NONE || m == id || check->mods[m].syntax == NULL) {
                continue;
            }
            MsInherentError *errors = NULL;
            uint32_t nerrors = 0;
            const MsStr text = std_text(check, files, nfiles, check->mods[m].path);
            ms_module_desugar(check, m, text, NULL, 0, &errors, &nerrors);
            ms_module_resolve_types(check, m);
            ms_module_ensure_operations(check, m, table);
            ms_module_add_implementations(check, m, table);
        }
    }
}

/* Checks the bodies of module `id` with the program's method table: the inherent methods desugared
 * to impls, the interface operations and the implementations resolved first, as the Rust checker
 * does. A module with an inherent error is left unchecked. */
static void check_bodies_with_methods(MsCheck *check, const MsStdFile *files, uint32_t nfiles, MsModId id,
                                      const char *text, size_t length) {
    MsInherentError *errors = NULL;
    uint32_t nerrors = 0;
    ms_module_desugar(check, id, (MsStr){text, (uint32_t)length}, NULL, 0, &errors, &nerrors);
    if (nerrors > 0) {
        return;
    }
    ms_module_resolve_types(check, id);
    MsMethodTable table;
    ms_methods_init(&table);
    add_import_methods(check, files, nfiles, id, &table);
    ms_module_ensure_operations(check, id, &table);
    ms_module_add_implementations(check, id, &table);
    ms_module_check_bodies_with(check, id, &table);
    ms_methods_free(&table);
}

#endif
