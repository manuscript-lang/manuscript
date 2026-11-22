/* compiler/lower/lower_tests.c: the test entry (ms_lower_tests). Instead of `main` the program starts at a function
 * that hands `run_test_files` (stdlib/internal/test_runner.ms) one runner closure per test file. A runner takes the
 * selected test indices and the results path, and calls `run_plain_file` with the file's tests as closures that
 * return `Void!`, and their global indices. A file with a fixture is not lowered yet. */
#include "compiler/lower/lower_fn.h"
#include "compiler/lower/lower.h"
#include "compiler/mir/mir_analysis.h"

#include <string.h>

typedef struct TestRun {
  Lower *cx;
  uint32_t plain;     /* the MIR function of run_plain_file */
  uint32_t run_files; /* the MIR function of run_test_files */
  MirTy test_fn;      /* fn() Void! */
  MirTy runner_fn;    /* fn(List[Int], String) Void */
  uint32_t next_index;
} TestRun;

static bool has_suffix(MsSpan text, const char *suffix) {
  const size_t length = strlen(suffix);
  return text.len >= length && memcmp(text.ptr + text.len - length, suffix, length) == 0;
}

/* The symbol `name` of the bundled test runner module, or 0. */
static MsSymbolId runner_symbol(const MsCheckProgram *program, const char *name) {
  MsName id = MS_NAME_EMPTY;
  if (!ms_names_find(program->names, ms_span_of_text(name), &id)) {
    return 0;
  }
  for (uint32_t index = program->user_modules; index < program->modules.len; index++) {
    const MsModuleInfo *info = &program->modules.ptr[index];
    if (!has_suffix(ms_names_span(program->names, info->file), "internal/test_runner.ms")) {
      continue;
    }
    const MsSymbolId *found = ms_scope_get(&info->scope, id);
    return found != NULL ? *found : 0;
  }
  return 0;
}

static uint32_t runner_function(Lower *cx, const char *name) {
  const MsSymbolId symbol = runner_symbol(cx->program, name);
  if (symbol == 0) {
    (void)lower_fail(cx, "the test runner `%s` is not loaded", name);
    return MIR_NONE;
  }
  const LowerTarget target = lower_symbol_target(cx, symbol);
  return lower_instance(cx, &target, NULL, 0, NULL);
}

static LowerFn begin_fn(Lower *cx, uint32_t module_index, const MirFunc *reserved) {
  LowerFn fn = {.cx = cx,
                .facts = &cx->program->modules.ptr[module_index].facts,
                .module_index = module_index,
                .file = lower_file(cx, module_index),
                .ret = reserved->ret};
  mir_b_init(&fn.b, cx->module, reserved->name, reserved->params, reserved->nparams, reserved->ret);
  fn.b.func.kind = MFK_CLOSURE;
  fn.b.func.loc = (MirLoc){fn.file, 0, 0, 0};
  (void)fn_scope_begin(&fn);
  return fn;
}

/* Replaces the reserved closure function `slot` by the one `fn` built. */
static bool end_fn(LowerFn *fn, uint32_t slot, bool ok) {
  MirFunc built;
  if (!mir_b_into_func(&fn->b, &built) || !ok || fn->failed) {
    return !fn->failed ? lower_fail(fn->cx, "a test function could not be built") : false;
  }
  built.linkage = ML_INTERNAL;
  built.kind = MFK_CLOSURE;
  mir_func_release(&fn->cx->module->funcs.ptr[slot]);
  fn->cx->module->funcs.ptr[slot] = built;
  return true;
}

/* The closure of one `test` block: its body, returning `ok` at the end. */
static uint32_t lower_test(TestRun *run, uint32_t module_index, const MsDecl *decl) {
  Lower *cx = run->cx;
  const uint32_t slot = lower_closure_func(cx, run->test_fn, NULL, 0);
  const MirFunc reserved = cx->module->funcs.ptr[slot];
  LowerFn fn = begin_fn(cx, module_index, &reserved);
  MirValue env;
  mir_b_params(&fn.b, &env, 1);
  fn.nvars = fn.facts->local_counts != NULL ? fn.facts->local_counts[decl->id] : 0;
  fn.vars = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirVar, (size_t)fn.nvars + 1);
  const bool ok = fn_stmts(&fn, decl->u.test.body);
  if (!fn.terminated) {
    const MirValue done = fn_result_wrap(&fn, MIR_NONE);
    fn_scope_unwind(&fn, 0);
    mir_b_ret(&fn.b, done);
  }
  return end_fn(&fn, slot, ok) ? slot : MIR_NONE;
}

static MirValue closure_value(LowerFn *fn, uint32_t func, MirTy ty) {
  const MirImm imm = {.tag = MI_FUNC, .a = func};
  return fn_emit(fn, MOP_ClosureNew, NULL, 0, imm, ty);
}

static MirValue list_of(LowerFn *fn, MirValue *items, uint32_t count, MirTy list_ty) {
  const MirTyData *data = mir_ty_data(fn->cx->module, list_ty);
  if (count == 0) {
    return mir_b_list_new(&fn->b, data->elem, mir_b_iconst(&fn->b, 0));
  }
  if (mir_needs_drop(fn->cx->module, data->elem)) {
    for (uint32_t index = 0; index < count; index++) {
      (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &items[index], 1, (MirImm){0}, MIR_NONE); /* the list owns it */
    }
  }
  return fn_emit(fn, MOP_ListLit, items, count, (MirImm){0}, list_ty);
}

/* The runner closure of one file: `run_plain_file(file, tests, indices, selected, results)`. */
static uint32_t lower_runner(TestRun *run, uint32_t module_index, uint32_t file, const uint32_t *tests,
                             uint32_t count, uint32_t first_index) {
  Lower *cx = run->cx;
  const uint32_t slot = lower_closure_func(cx, run->runner_fn, NULL, 0);
  const MirFunc reserved = cx->module->funcs.ptr[slot];
  const MirParam *plain = cx->module->funcs.ptr[run->plain].params;
  LowerFn fn = begin_fn(cx, module_index, &reserved);
  MirValue params[3];
  mir_b_params(&fn.b, params, 3);
  MirValue *closures = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirValue, (size_t)count + 1);
  MirValue *indices = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirValue, (size_t)count + 1);
  for (uint32_t index = 0; index < count; index++) {
    closures[index] = closure_value(&fn, tests[index], run->test_fn);
    indices[index] = mir_b_iconst(&fn.b, (int64_t)first_index + index);
  }
  const MirValue args[5] = {mir_b_iconst(&fn.b, file), list_of(&fn, closures, count, plain[1].ty),
                            list_of(&fn, indices, count, plain[2].ty), params[1], params[2]};
  const MirValue result = mir_b_call(&fn.b, run->plain, args, 5);
  fn_own_result(&fn, result);
  fn_scope_unwind(&fn, 0);
  mir_b_ret(&fn.b, MIR_NONE);
  return end_fn(&fn, slot, true) ? slot : MIR_NONE;
}

/* Lowers the tests of one module as a runner, when it has any. */
static bool lower_file_tests(TestRun *run, uint32_t module_index, uint32_t *runners, uint32_t *nrunners) {
  const MsModule *tree = run->cx->program->modules.ptr[module_index].tree;
  uint32_t *tests = MS_ARENA_NEW_ARRAY(&run->cx->module->arena, uint32_t, (size_t)tree->ndecls + 1);
  uint32_t count = 0;
  const uint32_t first = run->next_index;
  for (uint32_t index = 0; index < tree->ndecls; index++) {
    const MsDecl *decl = tree->decls[index];
    if (decl->kind != MS_D_TEST || decl->u.test.bench) {
      continue;
    }
    tests[count] = lower_test(run, module_index, decl);
    if (tests[count] == MIR_NONE) {
      return false;
    }
    count++;
    run->next_index++;
  }
  if (count == 0) {
    return true;
  }
  const uint32_t runner = lower_runner(run, module_index, *nrunners, tests, count, first);
  runners[(*nrunners)++] = runner;
  return runner != MIR_NONE;
}

/* The entry: `run_test_files([runners])`, whose status it returns. */
static uint32_t lower_entry(TestRun *run, const uint32_t *runners, uint32_t count) {
  Lower *cx = run->cx;
  const MirFunc files_fn = cx->module->funcs.ptr[run->run_files];
  MirParam none = {0};
  MirFunc entry;
  mir_func_init(cx->module, &entry, mir_name(cx->module, ms_span_of_text("main.tests")), &none, 0, files_fn.ret);
  const uint32_t slot = mir_add_func(cx->module, &entry);
  const MirFunc reserved = cx->module->funcs.ptr[slot];
  LowerFn fn = begin_fn(cx, 0, &reserved);
  fn.b.func.kind = MFK_NORMAL;
  MirValue *closures = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirValue, (size_t)count + 1);
  for (uint32_t index = 0; index < count; index++) {
    closures[index] = closure_value(&fn, runners[index], run->runner_fn);
  }
  const MirValue list = list_of(&fn, closures, count, files_fn.params[0].ty);
  const MirValue result = mir_b_call(&fn.b, run->run_files, &list, 1);
  fn_own_result(&fn, result);
  (void)mir_b_emit(&fn.b, MOP_ScopeDisown, &result, 1, (MirImm){0}, MIR_NONE);
  fn_scope_unwind(&fn, 0);
  mir_b_ret(&fn.b, result);
  MirFunc built;
  if (!mir_b_into_func(&fn.b, &built) || fn.failed) {
    return lower_fail(cx, "the test entry could not be built") ? 0 : MIR_NONE;
  }
  built.linkage = ML_EXPORT;
  mir_func_release(&cx->module->funcs.ptr[slot]);
  cx->module->funcs.ptr[slot] = built;
  return slot;
}

bool ms_lower_tests(MsCheckProgram *program, MirModule *module, MsStrBuild *error) {
  Lower cx;
  lower_init(&cx, program, module, error);
  TestRun run = {.cx = &cx};
  bool ok = true;
  run.plain = runner_function(&cx, "run_plain_file");
  run.run_files = run.plain == MIR_NONE ? MIR_NONE : runner_function(&cx, "run_test_files");
  ok = run.run_files != MIR_NONE;
  if (ok) {
    const MirTyData *list = mir_ty_data(module, module->funcs.ptr[run.run_files].params[0].ty);
    run.runner_fn = list->elem;
    run.test_fn = mir_ty_data(module, module->funcs.ptr[run.plain].params[1].ty)->elem;
    uint32_t *runners = MS_ARENA_NEW_ARRAY(&module->arena, uint32_t, (size_t)program->user_modules + 1);
    uint32_t nrunners = 0;
    for (uint32_t index = 0; ok && index < program->user_modules; index++) {
      ok = lower_file_tests(&run, index, runners, &nrunners);
    }
    const uint32_t entry = ok ? lower_entry(&run, runners, nrunners) : MIR_NONE;
    ok = ok && entry != MIR_NONE && lower_pending(&cx);
    module->entry = entry;
  }
  lower_release(&cx);
  return ok;
}
