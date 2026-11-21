#define _POSIX_C_SOURCE 200809L
/* ms_lower_dump STDLIB_DIR --program --why FILE...: per program, the functions the lowering refused and where
 * (`ms_lower_program_why`), or why the program was not lowered at all.
 * ms_lower_dump STDLIB_DIR --program [--run] FILE...: the same for a whole project, the entry file plus every
 * project module it imports, lowered into one module (compiler/tests/lower-program-diff.sh).
 * ms_lower_dump STDLIB_DIR [--run] FILE...: checks each single-file program with the C checker, lowers
 * the functions the C lowering handles, and prints each as the Rust lowering's text, so the two
 * can be compared function by function (compiler/tests/lower-diff.sh). Files that fail to parse
 * or import project modules print nothing. Output: `=== path`, then one `fn` block per function.
 * With `--run` it prints what mir_run.h computes for each lowered function instead.
 * With MS_LOWER_RUN_OUT=PATH the text mode also writes what `--run` would print to PATH, from the same lowering.
 * ms_lower_dump --run-mir FILE: the same for every module in a Rust oracle dump (`=== path`
 * sections of MIR text), so the two can be compared where the text differs by design. */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "dump_io.h"
#include "ms/check.h"
#include "ms/lower.h"
#include "ms/desugar.h"
#include "ms/methods.h"
#include "ms/program.h"
#include "ms/rt_ops.h"
#include "ms/ownership.h"
#include "ms/mir_analysis.h"
#include "ms/mir_pass.h"
#include "ms/mir_verify.h"
#include "ms/parse.h"
#include "ms/project.h"
#include "ms/walk.h"
#include "ms/stdlib.h"
#include "mir_run.h"
#include "read_file.h"
#include "std_files.h"

/* A construct C lowers differently from Rust by design: Rust threads parameters through a loop
 * header and tests a `match` arm by arm, C branches once (`switch`, or `br_if` on a Bool). */
/* The module's constant lists, which `list.const.view N` names by number. */
static void print_list_consts(const MirModule *mir) {
    for (uint32_t i = 0; i < mir->nlist_consts; i++) {
        printf("consts %u [", i);
        for (uint32_t k = 0; k < mir->list_consts[i].n; k++) {
            printf("%s%lld", k != 0 ? ", " : "", (long long)mir->list_consts[i].v[k]);
        }
        printf("]\n");
    }
}

/* What a function holds that C lowers its own way: a loop or `match`, or a `var` that a `return name` hands out (Rust
 * wraps such a `var` in an Optional to move it out, C moves the value the `var` holds). */
typedef struct Divergence {
    bool found;
    bool has_var;
    bool returns_name;
} Divergence;

static void note_divergent_stmt(void *ctx, const MsStmt *s) {
    Divergence *d = ctx;
    if (s->kind == MS_S_WHILE || s->kind == MS_S_FOR) {
        d->found = true;
    }
    d->has_var = d->has_var || (s->kind == MS_S_BIND && s->u.bind.is_mutable);
    d->returns_name = d->returns_name || (s->kind == MS_S_RETURN && s->u.expr != NULL && s->u.expr->kind == MS_E_NAME);
}

static void note_divergent_expr(void *ctx, const MsExpr *e) {
    if (e->kind == MS_E_MATCH) {
        ((Divergence *)ctx)->found = true;
    }
}

/* Whether a block branches back to itself or to an earlier one: a loop, of any origin (a `while`
 * is one, and so is the loop of a generated text function, which has no source to inspect). */
static bool has_back_edge(const MirFunc *f) {
    for (uint32_t i = 0; i < f->nblocks; i++) {
        const MirTerm *term = &f->blocks[i].term;
        for (uint32_t t = 0; t < mir_term_ntargets(term); t++) {
            if (mir_term_target_const(term, t)->block <= i) {
                return true;
            }
        }
    }
    return false;
}

/* Whether `f` calls a runtime function that returns a view of its receiver (`String.view`): Rust lowers that call
 * through a generated fast-path function, which C leaves to its optimizer passes, so the text differs by design. */
static bool calls_borrowing_native(const MirModule *m, const MirFunc *f) {
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            const MirInst *inst = &f->blocks[b].insts[i];
            if (inst->op != MOP_CallRt || inst->imm.tag != MI_EXT) {
                continue;
            }
            const MsStr name = ms_name(&m->names, m->externs[inst->imm.a].name);
            const MsRtFn *fn = ms_rt_fn_find((const char *)name.ptr, name.len);
            if (fn != NULL && fn->borrows) {
                return true;
            }
        }
    }
    return false;
}

/* Whether the function called `name` in `module` holds one. */
static bool function_diverges(const MsNames *names, const MsModule *module, MsStr name) {
    for (uint32_t i = 0; i < module->ndecls; i++) {
        const MsDecl *d = module->decls[i];
        const MsStr own = d->kind == MS_D_FN ? ms_name(names, d->u.fn.name) : (MsStr){0};
        if (own.len == name.len && own.len != 0 && memcmp(own.ptr, name.ptr, name.len) == 0) {
            Divergence found = {0};
            const MsVisitor visitor = {.ctx = &found, .stmt = note_divergent_stmt, .expr = note_divergent_expr};
            ms_walk_decl(&visitor, d);
            return found.found || (found.has_var && found.returns_name);
        }
    }
    return false;
}

/* Whether any module of `modules` holds a loop or a `match` in the function called `name`. */
static bool program_function_diverges(const MsNames *names, const MsModule *const *modules, uint32_t count, MsStr name) {
    for (uint32_t i = 0; i < count; i++) {
        if (function_diverges(names, modules[i], name)) {
            return true;
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

static int run_out_fd = -1; /* MS_LOWER_RUN_OUT: where the text mode also writes the `--run` output */

/* Runs the module's functions with the interpreter's output going to `run_out_fd`. */
static void run_module_to_file(MirModule *mir, const char *path) {
    if (mir_expand_owned_needed(mir)) {
        (void)mir_expand_owned(mir); // the interpreter has no owned shorthands (`alt.take`)
    }
    (void)fflush(stdout);
    const int saved = dup(STDOUT_FILENO);
    if (saved < 0 || dup2(run_out_fd, STDOUT_FILENO) < 0) {
        return;
    }
    run_module(mir, path);
    (void)fflush(stdout);
    (void)dup2(saved, STDOUT_FILENO);
    (void)close(saved);
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
        ms_program_begin(check);
        // The core library declares `Error`, whose field defaults a construction in the module takes.
        const MsModId core = ms_map_get(&check->module_by_path, ms_intern_cstr(check->names, "@std/core.ms"));
        if (core != MS_NONE) {
            ms_module_check_bodies_with(check, core, check->methods);
        }
        (void)ms_program_check_module(check, id, (MsStr){text, (uint32_t)length});
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
            if (mir_expand_owned_needed(&mir)) {
                (void)mir_expand_owned(&mir); // the interpreter has no owned shorthands (`alt.take`)
            }
            run_module(&mir, path);
        }
        if (!run) {
            print_list_consts(&mir);
        }
        for (uint32_t i = 0; i < mir.nfuncs && !run; i++) {
            MsBuf out = {0};
            mir_print_func(&mir, &mir.funcs[i], &out);
            if (function_diverges(names, module, ms_name(&mir.names, mir.funcs[i].name)) || has_back_edge(&mir.funcs[i]) || calls_borrowing_native(&mir, &mir.funcs[i])) {
                printf("; divergent\n");
            }
            printf("%.*s\n", (int)out.len, (const char *)out.data);
            ms_buf_free(&out);
        }
        if (!run && run_out_fd >= 0) {
            run_module_to_file(&mir, path); // after the text: running expands the owned shorthands
        }
        mir_module_free(&mir);
    }
    free(text);
    return verified;
}


/* Loads the project `path` (entry file plus the modules it imports), checks every module, lowers the program and
 * prints each function. A program with diagnostics prints nothing. */
static bool lower_program_file(const StdFiles *files, MsNames *names, const char *path, bool run, bool why) {
    MsArena arena = {0};
    MsGraph graph;
    MsProjectError error = {0};
    bool verified = true;
    if (ms_project_load(&arena, names, path, &graph, &error) && graph.ndiagnostics == 0 && graph.count != 0) {
        MsCheck check;
        ms_check_init(&check, names);
        MsArena std_syntax = {0};
        MsStr err = {0};
        if (!ms_std_load(&check, &std_syntax, files->items, files->count, &err)) {
            fprintf(stderr, "standard declarations: %.*s\n", (int)err.len, err.ptr);
            return false;
        }
        MsModId *ids = MS_NEW_N(&arena, MsModId, graph.count);
        ms_graph_add_modules(&check, names, &arena, &graph, ids);
        if (ms_graph_check(&check, &graph, ids, NULL) == 0) {
            const MsModule **modules = MS_NEW_N(&arena, const MsModule *, graph.count);
            for (uint32_t i = 0; i < graph.count; i++) {
                ms_module_check_ownership(&check, ids[i]);
                modules[i] = &graph.modules[i].syntax;
            }
            (void)ms_program_check_bundled(&check); // the standard modules the program reaches
            MirModule mir;
            mir_module_init(&mir);
            MsBuf refused = {0};
            (void)ms_lower_program_why(&check, ids[graph.count - 1], &mir, why ? &refused : NULL);
            if (why) { // `--why`: the functions the lowering refused, and nothing else
                printf("=== %s\n%.*s", path, (int)refused.len, refused.data != NULL ? (const char *)refused.data : "");
                ms_buf_free(&refused);
                mir_module_free(&mir);
                ms_check_free(&check);
                ms_arena_free(&std_syntax);
                ms_arena_free(&arena);
                return true;
            }
            verified = verify_module(&mir, path);
            MsBuf elaborate_error = {0};
            if (!mir_elaborate(&mir, &elaborate_error)) {
                fprintf(stderr, "%s: elaborate: %.*s\n", path, (int)elaborate_error.len, (const char *)elaborate_error.data);
                verified = false;
            }
            ms_buf_free(&elaborate_error);
            if (run) {
                run_module(&mir, path);
            } else {
                printf("=== %s\n", path);
                for (uint32_t i = 0; i < mir.nfiles; i++) { // locations name a file by number: Rust and C number them differently
                    printf("file %u \"%.*s\"\n", i, (int)mir.files[i].len, mir.files[i].ptr);
                }
                if (mir.entry != MIR_NONE) {
                    const MsStr entry = ms_name(&mir.names, mir.funcs[mir.entry].name);
                    printf("entry @%.*s\n", (int)entry.len, entry.ptr);
                }
            }
            if (!run) {
                print_list_consts(&mir);
            }
            for (uint32_t i = 0; i < mir.nfuncs && !run; i++) {
                MsBuf out = {0};
                mir_print_func(&mir, &mir.funcs[i], &out);
                if (program_function_diverges(names, modules, graph.count, ms_name(&mir.names, mir.funcs[i].name)) || has_back_edge(&mir.funcs[i]) || calls_borrowing_native(&mir, &mir.funcs[i])) {
                    printf("; divergent\n");
                }
                printf("%.*s\n", (int)out.len, (const char *)out.data);
                ms_buf_free(&out);
            }
            mir_module_free(&mir);
        } else if (why) {
            printf("=== %s\n\t\tchecker diagnostics\n", path);
        }
        ms_check_free(&check);
        ms_arena_free(&std_syntax);
    } else if (why) {
        printf("=== %s\n\t\tproject does not load\n", path);
    }
    ms_arena_free(&arena);
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

/* `MS_WHY=1`: each place the body checker gave a function up, as `WHY file:line` on stderr, in the order met. */

int main(int argc, char **argv) {
    if (getenv("MS_WHY") != NULL) {
        ms_body_decline_hook = print_decline;
    }
    if (argc == 3 && strcmp(argv[1], "--run-mir") == 0) {
        return run_oracle_dump(argv[2]);
    }
    if (argc < 2) {
        fputs("usage: ms_lower_dump STDLIB_DIR [--run] FILE...\n", stderr);
        return 2;
    }
    const bool program = argc > 2 && strcmp(argv[2], "--program") == 0;
    const bool run = argc > 2 && (strcmp(argv[2], "--run") == 0 || (program && argc > 3 && strcmp(argv[3], "--run") == 0));
    const bool why = program && argc > 3 && strcmp(argv[3], "--why") == 0;
    StdFiles files = {0};
    if (!read_std_files(&files, argv[1])) {
        return 1;
    }
    MsNames names;
    ms_names_init(&names);
    if (program) {
        bool all_verified = true;
        for (int i = run || why ? 4 : 3; i < argc; i++) {
            all_verified = lower_program_file(&files, &names, argv[i], run, why) && all_verified;
        }
        ms_names_free(&names);
        free_std_files(&files);
        return all_verified ? 0 : 1;
    }
    MsArena syntax = {0};
    MsCheck check;
    ms_check_init(&check, &names);
    MsStr err = {0};
    if (!ms_std_load(&check, &syntax, files.items, files.count, &err)) {
        fprintf(stderr, "standard declarations: %.*s\n", (int)err.len, err.ptr);
        return 1;
    }
    bool verified = true;
    const char *run_out = getenv("MS_LOWER_RUN_OUT");
    if (run_out != NULL && !run) {
        run_out_fd = open(run_out, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    }
    for (int i = run ? 3 : 2; i < argc; i++) {
        verified = lower_file(&check, &syntax, &names, argv[i], run) && verified;
    }
    if (run_out_fd >= 0) {
        (void)close(run_out_fd);
    }
    ms_check_free(&check);
    ms_arena_free(&syntax);
    ms_names_free(&names);
    free_std_files(&files);
    return verified ? 0 : 1;
}
