#define _POSIX_C_SOURCE 200809L
/* ms_lower_dump STDLIB_DIR [--run] FILE...: checks each single-file program with the C checker, lowers
 * the functions the C lowering handles, and prints each as the Rust lowering's text, so the two
 * can be compared function by function (compiler/tests/lower-diff.sh). Files that fail to parse
 * or import project modules print nothing. Output: `=== path`, then one `fn` block per function.
 * With `--run` it prints what mir_run.h computes for each lowered function instead.
 * ms_lower_dump --run-mir FILE: the same for every module in a Rust oracle dump (`=== path`
 * sections of MIR text), so the two can be compared where the text differs by design. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/check.h"
#include "ms/lower.h"
#include "ms/desugar.h"
#include "ms/methods.h"
#include "ms/program.h"
#include "ms/ownership.h"
#include "ms/mir_pass.h"
#include "ms/mir_verify.h"
#include "ms/parse.h"
#include "ms/walk.h"
#include "ms/stdlib.h"
#include "mir_run.h"
#include "read_file.h"
#include "std_files.h"

/* A construct C lowers differently from Rust by design: Rust threads parameters through a loop
 * header and tests a `match` arm by arm, C branches once (`switch`, or `br_if` on a Bool); Rust
 * inlines the hash probe of `m[k]` where C calls `msrt_map_get_ptr`. */
typedef struct Divergence {
    const MsCheck *check;
    const MsFacts *facts;
    bool found;
} Divergence;

static void note_divergent_stmt(void *ctx, const MsStmt *s) {
    if (s->kind == MS_S_WHILE || s->kind == MS_S_FOR) {
        ((Divergence *)ctx)->found = true;
    }
}

static void note_divergent_expr(void *ctx, const MsExpr *e) {
    Divergence *d = ctx;
    const MsExpr *left = NULL;
    const MsExpr *at = NULL;
    const bool indexed = (e->kind == MS_E_INDEX || e->kind == MS_E_APPLY) && ms_expr_index(e, &left, &at);
    const MsTy receiver = indexed ? d->facts->expr_ty[left->id] : MS_TY_NONE;
    if (e->kind == MS_E_MATCH || (receiver != MS_TY_NONE && ms_ty_is(&d->check->tys, receiver, MS_BI_MAP))) {
        d->found = true;
    }
}

/* Whether the function called `name` in `module` holds one. */
static bool function_diverges(const MsCheck *check, MsModId id, const MsModule *module, MsStr name) {
    const MsNames *names = check->names;
    for (uint32_t i = 0; i < module->ndecls; i++) {
        const MsDecl *d = module->decls[i];
        const MsStr own = d->kind == MS_D_FN ? ms_name(names, d->u.fn.name) : (MsStr){0};
        if (own.len == name.len && own.len != 0 && memcmp(own.ptr, name.ptr, name.len) == 0) {
            Divergence divergence = {.check = check, .facts = check->mods[id].facts};
            const MsVisitor visitor = {.ctx = &divergence, .stmt = note_divergent_stmt, .expr = note_divergent_expr};
            ms_walk_decl(&visitor, d);
            return divergence.found;
        }
    }
    return false;
}

/* Every function C lowered must pass the MIR verifier, whatever Rust did. */
static bool verify_module(const MirModule *mir, const char *path) {
    MirVerifyErrors errors = {0};
    const bool ok = mir_verify_module(mir, false, &errors);
    for (uint32_t i = 0; i < errors.count; i++) {
        MsBuf text = {0};
        mir_verify_error_text(&errors.errors[i], &text);
        fprintf(stderr, "%s: verify: %.*s\n", path, (int)text.len, (const char *)text.data);
        ms_buf_free(&text);
    }
    mir_verify_errors_free(&errors);
    return ok;
}

/* Checks the bodies of module `id` against a fresh program: a record is admitted only once its
 * methods are known (one with a `close` needs a cleanup). A module with an inherent error is left
 * unchecked. */
static void check_bodies(MsCheck *check, MsModId id, const char *text, size_t length) {
    ms_program_begin(check);
    (void)ms_program_check_module(check, id, (MsStr){text, (uint32_t)length});
}

static bool lower_file(MsCheck *check, MsArena *syntax, MsNames *names, const char *path, bool run) {
    size_t length = 0;
    char *text = read_whole_file(path, &length);
    if (text == NULL) {
        return true;
    }
    bool verified = true;
    MsModule *module = MS_NEW(syntax, MsModule);
    MsDiag diag;
    if (ms_parse(syntax, names, text, length, module, &diag) && ms_module_only_std_imports(module)) {
        if (!run) {
            printf("=== %s\n", path);
        }
        const MsModId id = ms_module_add(check, ms_intern_cstr(names, "main.ms"), module);
        check_bodies(check, id, text, length);
        if (check->mods[id].facts != NULL) { // an inherent error leaves the module unchecked
            // The ownership walk fills `ret_borrowed` and narrows `body_checked` to the functions it handles.
            ms_module_check_ownership(check, id);
        }
        MirModule mir;
        mir_module_init(&mir);
        (void)ms_lower_module(check, id, &mir);
        verified = verify_module(&mir, path);
        MsBuf elaborate_error = {0};
        if (!mir_elaborate(&mir, &elaborate_error)) { // Rust's output has its drops placed
            fprintf(stderr, "%s: elaborate: %.*s\n", path, (int)elaborate_error.len,
                    (const char *)elaborate_error.data);
            verified = false;
        }
        ms_buf_free(&elaborate_error);
        if (run) {
            run_module(&mir, path);
        }
        for (uint32_t i = 0; i < mir.nfuncs && !run; i++) {
            MsBuf out = {0};
            mir_print_func(&mir, &mir.funcs[i], &out);
            if (function_diverges(check, id, module, ms_name(&mir.names, mir.funcs[i].name))) {
                printf("; divergent\n");
            }
            printf("%.*s\n", (int)out.len, (const char *)out.data);
            ms_buf_free(&out);
        }
        mir_module_free(&mir);
    }
    free(text);
    return verified;
}

/* Runs the module in each `=== path` section of an oracle dump; sections that are not a module
 * (`error ...`) are skipped. */
static int run_oracle_dump(const char *path) {
    size_t length = 0;
    char *text = read_whole_file(path, &length);
    if (text == NULL) {
        fprintf(stderr, "cannot read %s\n", path);
        return 1;
    }
    char *section = strstr(text, "=== ");
    while (section != NULL) {
        char *end = strstr(section + 1, "\n=== ");
        char *next = end == NULL ? NULL : end + 1;
        const char *newline = strchr(section, '\n');
        char *source = newline == NULL ? NULL : (char *)(uintptr_t)newline + 1;
        if (source != NULL && strncmp(source, "module ", 7) == 0) {
            char *file = strndup(section + 4, (size_t)(newline - section - 4));
            MirModule mir;
            mir_module_init(&mir);
            uint32_t line = 0;
            MsStr message = {0};
            const size_t size = next == NULL ? strlen(source) : (size_t)(next - source);
            if (mir_parse(&mir, source, size, &line, &message)) {
                if (mir_expand_owned_needed(&mir)) {
                    (void)mir_expand_owned(&mir); // the interpreter has no owned shorthands (`opt.unbox`)
                }
                run_module(&mir, file);
            }
            mir_module_free(&mir);
            free(file);
        }
        section = next;
    }
    free(text);
    return 0;
}

int main(int argc, char **argv) {
    if (argc == 3 && strcmp(argv[1], "--run-mir") == 0) {
        return run_oracle_dump(argv[2]);
    }
    if (argc < 2) {
        fputs("usage: ms_lower_dump STDLIB_DIR [--run] FILE...\n", stderr);
        return 2;
    }
    const bool run = argc > 2 && strcmp(argv[2], "--run") == 0;
    StdFiles files = {0};
    if (!read_std_files(&files, argv[1])) {
        return 1;
    }
    MsNames names;
    ms_names_init(&names);
    MsArena syntax = {0};
    MsCheck check;
    ms_check_init(&check, &names);
    MsStr err = {0};
    if (!ms_std_load(&check, &syntax, files.items, files.count, &err)) {
        fprintf(stderr, "standard declarations: %.*s\n", (int)err.len, err.ptr);
        return 1;
    }
    bool verified = true;
    for (int i = run ? 3 : 2; i < argc; i++) {
        verified = lower_file(&check, &syntax, &names, argv[i], run) && verified;
    }
    ms_check_free(&check);
    ms_arena_free(&syntax);
    ms_names_free(&names);
    free_std_files(&files);
    return verified ? 0 : 1;
}
