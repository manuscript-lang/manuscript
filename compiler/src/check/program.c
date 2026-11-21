/* The program's method table and the checking of one module against it (ms/program.h). */
#include <stdlib.h>
#include <string.h>

#include "ms/check.h"
#include "ms/desugar.h"
#include "ms/extern_sig.h"
#include "ms/methods.h"
#include "ms/program.h"
#include "ms/public_sig.h"
#include "ms/stdlib.h"

/* The modules whose methods every module sees: the prelude's types (`List`, `Optional`, `Result`,
 * `String`) are declared there. */
static const char *const program_prelude[] = {"@std/core.ms", "@std/string.ms", "@std/collections/collections.ms"};

/* Desugars the inherent methods of module `m`; a `+source` half names the types its native half
 * declares. Must run before anything declares the module. */
static void program_desugar(MsCheck *c, MsModId m) {
    const MsStr path = ms_name(c->names, c->mods[m].path);
    MsDecl **foreign = NULL;
    uint32_t nforeign = 0;
    if (path.len > 7 && memcmp(path.ptr + path.len - 7, "+source", 7) == 0) {
        const MsModId native = ms_module_find(c, ms_intern(c->names, path.ptr, path.len - 7));
        const MsModule *types = native == MS_NONE ? NULL : c->mods[native].syntax;
        foreign = MS_NEW_N(&c->arena, MsDecl *, (types == NULL ? 0 : types->ndecls) + 1);
        for (uint32_t d = 0; types != NULL && d < types->ndecls; d++) {
            if (types->decls[d]->kind == MS_D_TYPE || types->decls[d]->kind == MS_D_ENUM) {
                foreign[nforeign++] = types->decls[d];
            }
        }
    }
    MsInherentError *errors = NULL;
    uint32_t nerrors = 0;
    ms_module_desugar(c, m, c->mods[m].text, foreign, nforeign, &errors, &nerrors);
}

static void program_desugar_bundled(MsCheck *c) {
    for (MsModId m = 0; !c->std_desugared && m < c->nmods; m++) {
        program_desugar(c, m);
    }
    c->std_desugared = true;
}

void ms_program_begin(MsCheck *c) {
    if (c->methods == NULL) {
        c->methods = calloc(1, sizeof *c->methods);
    } else {
        ms_methods_free(c->methods);
    }
    ms_methods_init(c->methods);
    for (MsModId m = 0; m < c->nmods; m++) {
        c->mods[m].impls_added = false;
    }
}

/* Adds the operations and impls of module `m` once, whatever imports it. */
static void program_add_impls(MsCheck *c, MsModId m) {
    if (m == MS_NONE || c->mods[m].impls_added || c->mods[m].syntax == NULL) {
        return;
    }
    c->mods[m].impls_added = true;
    ms_module_resolve_types(c, m);
    ms_module_ensure_operations(c, m, c->methods);
    ms_module_add_implementations(c, m, c->methods);
}

static void program_add_bundled(MsCheck *c, MsStr path);

/* The bundled modules `m` imports, and theirs: a value of a type one of them declares (a `Promise`
 * returned by a function of `@std/process.ms`) has the methods the type's own module gives it,
 * whether or not the program imports that module. */
static void program_add_imported_bundled(MsCheck *c, MsModId m) {
    const MsModule *syntax = c->mods[m].syntax;
    for (uint32_t i = 0; syntax != NULL && i < syntax->nimports; i++) {
        const MsModId target = c->mods[m].import_targets == NULL ? MS_NONE : c->mods[m].import_targets[i];
        if (target == MS_NONE) {
            program_add_bundled(c, syntax->imports[i].path);
        }
    }
}

/* A bundled module by path, with its `+source` half and the bundled modules they import. */
static void program_add_bundled(MsCheck *c, MsStr path) {
    const MsModId native = ms_module_find(c, ms_intern(c->names, path.ptr, path.len));
    const bool fresh = native != MS_NONE && !c->mods[native].impls_added;
    program_add_impls(c, native);
    const MsStr source = ms_arena_fmt(&c->arena, "%.*s+source", (int)path.len, path.ptr);
    const MsModId half = ms_module_find(c, ms_intern(c->names, source.ptr, source.len));
    const bool half_fresh = half != MS_NONE && !c->mods[half].impls_added;
    program_add_impls(c, half);
    if (fresh) {
        program_add_imported_bundled(c, native);
    }
    if (half_fresh) {
        program_add_imported_bundled(c, half);
    }
}

bool ms_program_check_module(MsCheck *c, MsModId module, MsStr text) {
    program_desugar_bundled(c);
    if (c->methods == NULL) {
        ms_program_begin(c);
    }
    MsInherentError *errors = NULL;
    uint32_t nerrors = 0;
    ms_module_desugar(c, module, text, NULL, 0, &errors, &nerrors);
    if (nerrors > 0) {
        return false;
    }
    if (c->mods[module].text.len == 0) {
        c->mods[module].text = text; // the exact-source fixes of name resolution read it
    }
    ms_module_resolve_types(c, module);
    for (size_t i = 0; i < sizeof program_prelude / sizeof *program_prelude; i++) {
        program_add_bundled(c, (MsStr){program_prelude[i], (uint32_t)strlen(program_prelude[i])});
    }
    const MsModule *syntax = c->mods[module].syntax;
    for (uint32_t i = 0; i < syntax->nimports; i++) {
        const MsModId target = c->mods[module].import_targets == NULL ? MS_NONE : c->mods[module].import_targets[i];
        if (target != MS_NONE) {
            program_add_impls(c, target);
        } else {
            program_add_bundled(c, syntax->imports[i].path);
        }
    }
    c->mods[module].impls_added = true;
    ms_module_ensure_operations(c, module, c->methods);
    ms_module_add_implementations(c, module, c->methods);
    ms_module_check_public(c, module, c->methods);
    ms_module_check_externs(c, module);
    ms_module_check_bodies_with(c, module, c->methods);
    return true;
}
