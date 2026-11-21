/* The test build of the lowering (`ms_lower_tests_why`): every `test` block of the project modules becomes a function of no
 * parameters returning `Result[Void, Error]`, and the entry `main` hands one closure per test file to `run_test_files` of
 * `@std/internal/test_runner.ms`, which runs the files' tests (`run_plain_file`) and writes the records `ms test` reads.
 * A file with a fixture, and a bench, are not covered yet: the build is handed over with the reason. */
#include <stdio.h>
#include <string.h>

#include "ms/lower_internal.h"
#include "ms/lower.h"
#include "ms/mir_analysis.h"
#include "ms/mir_builder.h"

#define LT_RUNNER "@std/internal/test_runner.ms"

static bool lt_is_project(const Lb *lb, uint32_t view) {
    const MsStr path = ms_name(lb->c->names, lb->c->mods[lb->views[view].module].path);
    return !(path.len >= 5 && memcmp(path.ptr, "@std/", 5) == 0);
}

/* `fn() Result[Void, Error]`, the signature of a test block; MS_TY_NONE when the library lacks either type. */
static MsTy lt_signature(Lb *lb) {
    const MsSymId result = ms_map_get(&lb->c->std_types, ms_intern_cstr(lb->c->names, "Result"));
    const MsSymId error = ms_map_get(&lb->c->std_types, ms_intern_cstr(lb->c->names, "Error"));
    if (result == MS_NONE || error == MS_NONE || lb->c->syms.ty[result] == MS_TY_NONE || lb->c->syms.ty[error] == MS_TY_NONE) {
        return MS_TY_NONE;
    }
    const MsTy args[2] = {lb->void_ty, lb->c->syms.ty[error]};
    const MsSym fn = ms_intern_cstr(lb->c->names, "fn");
    const MsTyDesc desc = {.name = fn, .id = fn, .kind = MS_K_FUNCTION, .result = ms_ty_apply(lb->mut, lb->c->syms.ty[result], args, 2)};
    return ms_ty_intern(&lb->mut->tys, &desc);
}

/* Whether the module declares a fixture factory: its tests take the fixture, which this build does not hand over yet. */
static bool lt_has_fixture(const Lb *lb, const MsModule *syntax) {
    for (uint32_t i = 0; i < syntax->ndecls; i++) {
        if (syntax->decls[i]->kind == MS_D_FN && !syntax->decls[i]->synthetic && ms_name_is(lb->c->names, syntax->decls[i]->u.fn.name, "make_fixture")) {
            return true;
        }
    }
    return false;
}

static void lt_refuse(Lb *lb, const MsDecl *d, const char *reason) {
    if (lb->why == NULL) {
        return;
    }
    const MsStr path = ms_name(lb->c->names, lb->c->mods[lb->module].path);
    ms_buf_printf(lb->why, "%.*s\t%.*s:%u:%u\t%s\n", (int)d->u.test.name.len, d->u.test.name.ptr, (int)path.len, path.ptr, d->pos.line,
                  d->pos.column, reason);
}

/* Lowers each test block of the project modules in this pass, in module and source order, and lists them in
 * `lb->tests`. A block that does not lower is listed with no function, so the entry is not built. */
void lt_lower(Lb *lb) {
    lb->tests = NULL; // the arena it lived in is freed between passes
    lb->ntests = lb->ctests = 0;
    const MsTy sig = lt_signature(lb);
    for (uint32_t v = 0; v < lb->nviews; v++) {
        if (!lt_is_project(lb, v)) {
            continue;
        }
        (void)lb_view_enter(lb, v);
        const MsModuleRow *row = &lb->c->mods[lb->module];
        const bool fixture = lt_has_fixture(lb, row->syntax);
        for (uint32_t i = 0; i < row->syntax->ndecls; i++) {
            const MsDecl *d = row->syntax->decls[i];
            if (d->kind != MS_D_TEST || d->u.test.bench != lb->bench) {
                continue;
            }
            LbTest test = {.view = v, .decl = i, .func = MIR_NONE};
            if (fixture) {
                lt_refuse(lb, d, "a file with a fixture");
            } else if (sig == MS_TY_NONE || !lb->facts->body_checked[d->id] || lb_lines_have_diagnostic(row, d->pos.line, d->pos.line + 1)) {
                lt_refuse(lb, d, "body not checked");
            } else {
                MsFunc *fn = MS_NEW(&lb->m->arena, MsFunc);
                *fn = (MsFunc){.name = ms_intern(lb->c->names, d->u.test.name.ptr, d->u.test.name.len), .body = d->u.test.body};
                const LbCallable callable = {.fn = fn,
                                             .node = d->id,
                                             .pos = d->pos,
                                             .name = mir_name(lb->m, d->u.test.name.ptr, d->u.test.name.len),
                                             .sig = sig,
                                             .self_ty = MS_TY_NONE};
                const uint32_t slot = lb_add_stub(lb, &callable);
                test.func = slot != MIR_NONE && lb_function(lb, &callable, slot) ? slot : MIR_NONE;
            }
            MIR_PUSH(lb->m, lb->tests, lb->ntests, lb->ctests, LbTest, test);
        }
    }
}

/* The module function of the exported standard-library function `name` of `path`, or MIR_NONE. */
static uint32_t lt_std_func(const Lb *lb, const char *path, const char *name) {
    const MsModId module = ms_map_get(&lb->c->module_by_path, ms_intern_cstr(lb->c->names, path));
    if (module == MS_NONE) {
        return MIR_NONE;
    }
    const MsSymId sym = ms_map_get(&lb->c->mods[module].names, ms_intern_cstr(lb->c->names, name));
    return sym == MS_NONE || lb->c->syms.nvars[sym] != 0 ? MIR_NONE : lb->func_of[sym];
}

static MirValue lt_closure(MirBuilder *b, uint32_t func, MirTy ty) {
    return mir_b_emit(b, MOP_ClosureNew, NULL, 0, (MirImm){.tag = MI_FUNC, .a = func}, ty);
}

static MirValue lt_list_const(Lb *lb, MirBuilder *b, const uint32_t *values, uint32_t count, MirTy ty) {
    int64_t *items = MS_NEW_N(&lb->m->arena, int64_t, (size_t)count + 1);
    for (uint32_t i = 0; i < count; i++) {
        items[i] = values[i];
    }
    const MirConsts table = {items, count};
    MIR_PUSH(lb->m, lb->m->list_consts, lb->m->nlist_consts, lb->m->clist_consts, MirConsts, table);
    return mir_b_emit(b, MOP_ListConst, NULL, 0, (MirImm){.tag = MI_INT, .i = (int64_t)lb->m->nlist_consts - 1}, ty);
}

static void lt_drop(MirBuilder *b, MirValue v) { (void)mir_b_emit(b, MOP_Drop, &v, 1, (MirImm){0}, MIR_NONE); }

/* The closure function of file `position`: its parameters are the selection and the results path, and it runs the
 * file's tests (`tests[first..first + count]`) under `plain`. MIR_NONE when it cannot be built. */
static uint32_t lt_file_runner(Lb *lb, uint32_t plain, uint32_t position, const uint32_t *thunks, const uint32_t *indices,
                               uint32_t count, const MirTyData *runner) {
    const MirFunc *harness = &lb->m->funcs[plain];
    MirParam *params = MS_NEW_N(&lb->m->arena, MirParam, (size_t)runner->nargs + 1);
    params[0] = (MirParam){MIR_PTR, MM_BORROW};
    for (uint32_t i = 0; i < runner->nargs; i++) {
        params[i + 1] = (MirParam){runner->args[i], MM_BORROW};
    }
    MirBuilder b;
    mir_b_init(&b, lb->m, lb_unique_name(lb, (MsStr){"test file", 9}), params, runner->nargs + 1, runner->elem);
    b.f.kind = MFK_CLOSURE;
    MirValue *values = MS_NEW_N(&b.scratch, MirValue, (size_t)runner->nargs + 1);
    mir_b_params(&b, values, runner->nargs + 1);
    const MirTy test_ty = mir_ty_data(lb->m, harness->params[1].ty)->elem;
    MirValue *items = MS_NEW_N(&b.scratch, MirValue, (size_t)count + 1);
    for (uint32_t i = 0; i < count; i++) {
        items[i] = lt_closure(&b, thunks[i], test_ty);
    }
    MirValue args[5];
    args[0] = mir_b_iconst(&b, position);
    args[1] = mir_b_emit(&b, MOP_ListLit, items, count, (MirImm){0}, harness->params[1].ty);
    args[2] = lt_list_const(lb, &b, indices, count, harness->params[2].ty);
    args[3] = values[1];
    args[4] = values[2];
    (void)mir_b_call(&b, plain, args, 5);
    for (uint32_t i = 1; i <= 2; i++) { // the lists made here, which the harness only borrowed
        if (harness->params[i].mode == MM_BORROW) {
            lt_drop(&b, args[i]);
        }
    }
    mir_b_ret(&b, mir_b_unit(&b));
    MirFunc f = {0};
    return mir_b_into_func(&b, &f) ? mir_add_func(lb->m, &f) : MIR_NONE;
}

/* Builds `main` over the lowered tests and writes each test's `module::name` identity, one per line, to `names`; false
 * when a test or the runner did not lower. */
bool lt_entry(Lb *lb, MsBuf *names) {
    const uint32_t run_files = lt_std_func(lb, LT_RUNNER, "run_test_files");
    const uint32_t plain = lt_std_func(lb, LT_RUNNER, "run_plain_file");
    if (run_files == MIR_NONE || plain == MIR_NONE) {
        if (lb->why != NULL) {
            ms_buf_puts(lb->why, "run_test_files\t" LT_RUNNER "\tthe test runner did not lower\n");
        }
        return false;
    }
    if (lb->ntests == 0 || lb->bench) { // benches run under a driver, which this entry does not build yet
        if (lb->why != NULL && lb->bench) {
            ms_buf_puts(lb->why, "bench\t-\tbenches are not built in C yet\n");
        }
        return false;
    }
    for (uint32_t i = 0; i < lb->ntests; i++) {
        if (lb->tests[i].func == MIR_NONE) {
            return false;
        }
    }
    const MirFunc *runner_list = &lb->m->funcs[run_files];
    const MirTy runner_ty = mir_ty_data(lb->m, runner_list->params[0].ty)->elem;
    uint32_t *thunks = MS_NEW_N(&lb->m->arena, uint32_t, lb->ntests);
    uint32_t *indices = MS_NEW_N(&lb->m->arena, uint32_t, lb->ntests);
    uint32_t *runners = MS_NEW_N(&lb->m->arena, uint32_t, lb->ntests);
    uint32_t nrunners = 0;
    // The tests of a file are adjacent (module order, then source order), so a run of one view is one file.
    for (uint32_t first = 0; first < lb->ntests;) {
        uint32_t end = first;
        while (end < lb->ntests && lb->tests[end].view == lb->tests[first].view) {
            end++;
        }
        for (uint32_t i = first; i < end; i++) {
            thunks[i - first] = lb_thunk(lb, lb->tests[i].func);
            indices[i - first] = i;
            if (thunks[i - first] == MIR_NONE) {
                return false;
            }
        }
        const uint32_t runner = lt_file_runner(lb, plain, nrunners, thunks, indices, end - first, mir_ty_data(lb->m, runner_ty));
        if (runner == MIR_NONE) {
            return false;
        }
        runners[nrunners++] = runner;
        first = end;
    }
    mir_b_init(&lb->b, lb->m, mir_name(lb->m, "main", 4), NULL, 0, MIR_INT);
    MirValue *items = MS_NEW_N(&lb->b.scratch, MirValue, (size_t)nrunners + 1);
    for (uint32_t i = 0; i < nrunners; i++) {
        items[i] = lt_closure(&lb->b, runners[i], runner_ty);
    }
    const MirValue list = mir_b_emit(&lb->b, MOP_ListLit, items, nrunners, (MirImm){0}, runner_list->params[0].ty);
    const MirValue status = mir_b_call(&lb->b, run_files, &list, 1);
    if (runner_list->params[0].mode == MM_BORROW) {
        lt_drop(&lb->b, list);
    }
    mir_b_ret(&lb->b, status);
    mir_func_compact_blocks(&lb->b.f);
    lb->b.f.linkage = ML_EXPORT;
    MirFunc entry = {0};
    if (!mir_b_into_func(&lb->b, &entry)) {
        return false;
    }
    lb->m->entry = mir_add_func(lb->m, &entry);
    for (uint32_t i = 0; i < lb->ntests; i++) {
        const MsModuleRow *row = &lb->c->mods[lb->views[lb->tests[i].view].module];
        const MsStr path = ms_name(lb->c->names, row->path);
        const MsStr name = row->syntax->decls[lb->tests[i].decl]->u.test.name;
        ms_buf_printf(names, "%.*s::%.*s\n", (int)path.len, path.ptr, (int)name.len, name.ptr);
    }
    return true;
}
