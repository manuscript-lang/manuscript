/* compiler/lower/lower_tests.c: the test entry (ms_lower_tests). Instead of `main` the program starts at a function
 * that hands `run_test_files` (src/stdlib/internal/test_runner.ms) one runner closure per test file. A runner takes the
 * selected test indices and the results path, and calls `run_plain_file` with the file's tests as closures that
 * return `Void!`, and their global indices. A file with a `make_fixture` factory calls `run_fixture_file` instead: its
 * tests take the fixture as a `var` parameter, and the fixture type's hook methods become closures. */
#include "base/message.h"
#include "compiler/lower/lower_fn.h"
#include "compiler/lower/lower.h"
#include "compiler/mir/mir_analysis.h"

typedef struct TestRun {
  Lower *cx;
  uint32_t plain;     /* the MIR function of run_plain_file */
  uint32_t run_files; /* the MIR function of run_test_files */
  MirTy test_fn;      /* fn() Void! */
  MirTy runner_fn;    /* fn(List[Int], String) Void */
  uint32_t next_index;
  bool bench;         /* lower the `bench` blocks instead of the `test` blocks */
  uint32_t driver;    /* the MIR function of run_bench_block, when lowering benches */
  MsSymbolId fixture_driver; /* run_bench_fixture, the generic driver of a file with a fixture */
} TestRun;

/* The symbol `name` of the bundled test runner module, or 0. */
static MsSymbolId module_symbol(const MsCheckProgram *program, const char *module, const char *name) {
  MsName id = MS_NAME_EMPTY;
  if (!ms_names_find(program->names, ms_span_of_text(name), &id)) {
    return 0;
  }
  for (uint32_t index = program->user_modules; index < program->modules.len; index++) {
    const MsModuleInfo *info = &program->modules.ptr[index];
    if (!ms_span_ends_with_text(ms_names_span(program->names, info->file), module)) {
      continue;
    }
    const MsSymbolId *found = ms_scope_get(&info->scope, id);
    return found != NULL ? *found : 0;
  }
  return 0;
}

static MsSymbolId runner_symbol(const MsCheckProgram *program, const char *name) {
  return module_symbol(program, "internal/test_runner.ms", name);
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
static uint32_t lower_test(TestRun *run, uint32_t module_index, const MsDecl *decl, MirTy test_fn, MsTy fixture) {
  Lower *cx = run->cx;
  const uint32_t slot = lower_closure_func(cx, test_fn, NULL, 0);
  const MirFunc reserved = cx->module->funcs.ptr[slot];
  LowerFn fn = begin_fn(cx, module_index, &reserved);
  MirValue values[2];
  mir_b_params(&fn.b, values, fixture == MS_TY_NONE ? 1 : 2);
  fn.param_vars = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirVar, 2);
  if (fixture != MS_TY_NONE) {
    /* The fixture is the test's `var` parameter: copied in here, put back at every exit. */
    const MirTy held_ty = fn_type(&fn, fixture);
    const bool owns = mir_needs_drop(cx->module, held_ty);
    const MirImm of_type = {.tag = MI_TY, .a = held_ty};
    const MirValue held = mir_b_emit(&fn.b, owns ? MOP_Take : MOP_Load, &values[1], 1, of_type, held_ty);
    fn.param_vars[0] = mir_b_declare_var(&fn.b, held_ty, owns ? MM_MOVE : MM_BORROW);
    mir_b_def_var(&fn.b, fn.param_vars[0], held);
    fn.var_params = fn_grow(&fn, fn.var_params, &fn.var_params_cap, fn.nvar_params, sizeof(LowerVarParam));
    fn.var_params[fn.nvar_params++] = (LowerVarParam){fn.param_vars[0], values[1], held_ty};
  }
  fn.nvars = fn.facts->local_counts != NULL ? fn.facts->local_counts[decl->id] : 0;
  fn.vars = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirVar, (size_t)fn.nvars + 1);
  fn.local_owns = MS_ARENA_NEW_ARRAY(&cx->module->arena, uint8_t, (size_t)fn.nvars + 1);
  fn_init_closing(&fn);
  fn_find_shared(&fn, decl->u.test.body);
  if (decl->u.test.bench && decl->u.test.body.len > 0) {
    fn.sink_stmt = decl->u.test.body.ptr[decl->u.test.body.len - 1];
  }
  const bool ok = fn_stmts(&fn, decl->u.test.body);
  if (!fn.terminated) {
    const MirValue done = fn_result_wrap(&fn, MIR_NONE);
    fn_scope_unwind(&fn, 0);
    mir_b_ret(&fn.b, done);
  }
  if (!end_fn(&fn, slot, ok)) {
    return MIR_NONE;
  }
  /* A fault trace names the block as it is written: `test adds two numbers`, `bench sort`. */
  cx->module->funcs.ptr[slot].runs_once = !decl->u.test.bench;
  cx->module->funcs.ptr[slot].display = mir_name(
      cx->module, ms_message_format(&cx->module->arena, decl->u.test.bench ? "bench %S" : "test %S", decl->u.test.name, (MsSpan){0}));
  return slot;
}

static MirValue closure_value(LowerFn *fn, uint32_t func, MirTy ty) {
  const MirImm imm = {.tag = MI_FUNC, .a = func};
  return fn_emit(fn, MOP_ClosureNew, NULL, 0, imm, ty);
}

static MirValue list_of(LowerFn *fn, MirValue *items, uint32_t count, MirTy list_ty) {
  const MirTyData *data = mir_ty_data(fn->cx->module, list_ty);
  if (count == 0) {
    const MirValue fresh = mir_b_list_new(&fn->b, data->elem, mir_b_iconst(&fn->b, 0));
    fn_own_result(fn, fresh);
    return fresh;
  }
  if (mir_needs_drop(fn->cx->module, data->elem)) {
    for (uint32_t index = 0; index < count; index++) {
      (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &items[index], 1, (MirImm){0}, MIR_NONE); /* the list owns it */
    }
  }
  return fn_emit(fn, MOP_ListLit, items, count, (MirImm){0}, list_ty);
}

/* The closure of one `bench` block: `run_bench_block(body, operations)`, the standard driver that repeats and times
 * the body, which it takes as a `fn() Void!` and whose `Void!` the closure returns, as a test's does. */
static uint32_t bench_closure(TestRun *run, uint32_t module_index, uint32_t body, int64_t per) {
  Lower *cx = run->cx;
  const uint32_t slot = lower_closure_func(cx, run->test_fn, NULL, 0);
  const MirFunc reserved = cx->module->funcs.ptr[slot];
  LowerFn fn = begin_fn(cx, module_index, &reserved);
  MirValue env;
  mir_b_params(&fn.b, &env, 1);
  const MirValue closure = closure_value(&fn, body, run->test_fn);
  if (cx->module->funcs.ptr[run->driver].params[0].mode == MM_MOVE) {
    (void)mir_b_emit(&fn.b, MOP_ScopeDisown, &closure, 1, (MirImm){0}, MIR_NONE); /* the driver owns it */
  }
  const MirValue args[2] = {closure, mir_b_iconst(&fn.b, per)};
  const MirValue result = mir_b_call(&fn.b, run->driver, args, 2);
  fn_own_result(&fn, result);
  (void)mir_b_emit(&fn.b, MOP_ScopeDisown, &result, 1, (MirImm){0}, MIR_NONE);
  fn_scope_unwind(&fn, 0);
  mir_b_ret(&fn.b, result);
  return end_fn(&fn, slot, true) ? slot : MIR_NONE;
}

/* The closure of one `bench` block of a file with a fixture, of the type a test of such a file has (`fn(var F) Void!`):
 * `run_bench_fixture[F](body, operations, fixture)`, the driver that times `body(fixture)`. The fixture was made, and
 * `before_all` and `before_each` ran, before this is called, so the setup is outside the timing. */
static uint32_t bench_fixture_closure(TestRun *run, uint32_t module_index, uint32_t body, MirTy test_fn, MsTy fixture,
                                      int64_t per) {
  Lower *cx = run->cx;
  const LowerTarget target = lower_symbol_target(cx, run->fixture_driver);
  const uint32_t driver = lower_instance(cx, &target, &fixture, 1, NULL);
  if (driver == MIR_NONE) {
    return MIR_NONE;
  }
  const uint32_t slot = lower_closure_func(cx, test_fn, NULL, 0);
  const MirFunc reserved = cx->module->funcs.ptr[slot];
  LowerFn fn = begin_fn(cx, module_index, &reserved);
  MirValue values[2];
  mir_b_params(&fn.b, values, 2);
  const MirValue closure = closure_value(&fn, body, test_fn);
  if (cx->module->funcs.ptr[driver].params[0].mode == MM_MOVE) {
    (void)mir_b_emit(&fn.b, MOP_ScopeDisown, &closure, 1, (MirImm){0}, MIR_NONE); /* the driver owns it */
  }
  const MirValue args[3] = {closure, mir_b_iconst(&fn.b, per), values[1]};
  const MirValue result = mir_b_call(&fn.b, driver, args, 3);
  fn_own_result(&fn, result);
  (void)mir_b_emit(&fn.b, MOP_ScopeDisown, &result, 1, (MirImm){0}, MIR_NONE);
  fn_scope_unwind(&fn, 0);
  mir_b_ret(&fn.b, result);
  return end_fn(&fn, slot, true) ? slot : MIR_NONE;
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

/* The module's `make_fixture` factory, or 0 when the file has no fixture. */
static MsSymbolId fixture_factory(const MsCheckProgram *program, uint32_t module_index) {
  MsName name = MS_NAME_EMPTY;
  if (!ms_names_find(program->names, ms_span_of_text("make_fixture"), &name)) {
    return 0;
  }
  const MsSymbolId *found = ms_scope_get(&program->modules.ptr[module_index].scope, name);
  const bool usable = found != NULL && program->symbols.ptr[*found].kind == MS_SYMBOL_FN &&
                      program->symbols.ptr[*found].ty != MS_TY_NONE;
  return usable ? *found : 0;
}

/* A hook closure that does nothing and succeeds: the file's fixture type has no such method. */
static uint32_t noop_hook(TestRun *run, uint32_t module_index, MirTy hook_ty) {
  Lower *cx = run->cx;
  const uint32_t slot = lower_closure_func(cx, hook_ty, NULL, 0);
  const MirFunc reserved = cx->module->funcs.ptr[slot];
  LowerFn fn = begin_fn(cx, module_index, &reserved);
  MirValue values[2];
  mir_b_params(&fn.b, values, 2);
  const MirValue done = fn_result_wrap(&fn, MIR_NONE);
  fn_scope_unwind(&fn, 0);
  mir_b_ret(&fn.b, done);
  return end_fn(&fn, slot, true) ? slot : MIR_NONE;
}

/* The runner closure of a file with a fixture: `run_fixture_file[F](file, make, hooks..., tests, indices, ...)`. The
 * hooks are the fixture type's methods of those names, and succeed trivially when it has none. */
static uint32_t lower_fixture_runner(TestRun *run, uint32_t module_index, uint32_t file, MsSymbolId factory,
                                     const MsDecl **decls, uint32_t count, uint32_t first_index) {
  static const char *const HOOKS[4] = {"before_all", "before_each", "after_each", "after_all"};
  Lower *cx = run->cx;
  const MsTy fixture = ms_ty_result(&cx->program->types, cx->program->symbols.ptr[factory].ty);
  const LowerTarget target = lower_symbol_target(cx, runner_symbol(cx->program, "run_fixture_file"));
  const uint32_t fixture_run = lower_instance(cx, &target, &fixture, 1, NULL);
  if (fixture_run == MIR_NONE) {
    return MIR_NONE;
  }
  const MirParam *run_params = cx->module->funcs.ptr[fixture_run].params;
  const MirTy test_fn = mir_ty_data(cx->module, run_params[6].ty)->elem;
  uint32_t *tests = MS_ARENA_NEW_ARRAY(&cx->module->arena, uint32_t, (size_t)count + 1);
  for (uint32_t index = 0; index < count; index++) {
    tests[index] = lower_test(run, module_index, decls[index], test_fn, fixture);
    if (tests[index] != MIR_NONE && run->bench) {
      tests[index] = bench_fixture_closure(run, module_index, tests[index], test_fn, fixture, decls[index]->u.test.per);
    }
    if (tests[index] == MIR_NONE) {
      return MIR_NONE;
    }
  }
  uint32_t hooks[4];
  for (uint32_t index = 0; index < 4; index++) {
    const uint32_t method = lower_named_method(cx, fixture, HOOKS[index]);
    hooks[index] = method == MIR_NONE ? noop_hook(run, module_index, run_params[2 + index].ty)
                                      : lower_forwarding_closure(cx, run_params[2 + index].ty, method);
    if (hooks[index] == MIR_NONE) {
      return MIR_NONE;
    }
  }
  const LowerTarget maker = lower_symbol_target(cx, factory);
  const uint32_t make_func = lower_instance(cx, &maker, NULL, 0, NULL);
  const uint32_t make = make_func == MIR_NONE ? MIR_NONE : lower_forwarding_closure(cx, run_params[1].ty, make_func);
  if (make == MIR_NONE) {
    return MIR_NONE;
  }
  const uint32_t slot = lower_closure_func(cx, run->runner_fn, NULL, 0);
  const MirFunc reserved = cx->module->funcs.ptr[slot];
  LowerFn fn = begin_fn(cx, module_index, &reserved);
  MirValue params[3];
  mir_b_params(&fn.b, params, 3);
  MirValue *closures = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirValue, (size_t)count + 1);
  MirValue *indices = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirValue, (size_t)count + 1);
  for (uint32_t index = 0; index < count; index++) {
    closures[index] = closure_value(&fn, tests[index], test_fn);
    indices[index] = mir_b_iconst(&fn.b, (int64_t)first_index + index);
  }
  MirValue args[10] = {mir_b_iconst(&fn.b, file), closure_value(&fn, make, run_params[1].ty)};
  for (uint32_t index = 0; index < 4; index++) {
    args[2 + index] = closure_value(&fn, hooks[index], run_params[2 + index].ty);
  }
  args[6] = list_of(&fn, closures, count, run_params[6].ty);
  args[7] = list_of(&fn, indices, count, run_params[7].ty);
  args[8] = params[1];
  args[9] = params[2];
  const MirValue result = mir_b_call(&fn.b, fixture_run, args, 10);
  fn_own_result(&fn, result);
  fn_scope_unwind(&fn, 0);
  mir_b_ret(&fn.b, MIR_NONE);
  return end_fn(&fn, slot, true) ? slot : MIR_NONE;
}

/* Lowers the tests of one module as a runner, when it has any. */
static bool lower_file_tests(TestRun *run, uint32_t module_index, uint32_t *runners, uint32_t *nrunners) {
  const MsModule *tree = run->cx->program->modules.ptr[module_index].tree;
  const MsDecl **decls = MS_ARENA_NEW_ARRAY(&run->cx->module->arena, const MsDecl *, (size_t)tree->ndecls + 1);
  uint32_t count = 0;
  for (uint32_t index = 0; index < tree->ndecls; index++) {
    if (tree->decls[index]->kind == MS_D_TEST && tree->decls[index]->u.test.bench == run->bench) {
      decls[count++] = tree->decls[index];
    }
  }
  if (count == 0) {
    return true;
  }
  const uint32_t first = run->next_index;
  run->next_index += count;
  const MsSymbolId factory = fixture_factory(run->cx->program, module_index);
  uint32_t runner = MIR_NONE;
  if (factory != 0) {
    runner = lower_fixture_runner(run, module_index, *nrunners, factory, decls, count, first);
  } else {
    uint32_t *tests = MS_ARENA_NEW_ARRAY(&run->cx->module->arena, uint32_t, (size_t)count + 1);
    for (uint32_t index = 0; index < count; index++) {
      tests[index] = lower_test(run, module_index, decls[index], run->test_fn, MS_TY_NONE);
      if (tests[index] != MIR_NONE && run->bench) {
        tests[index] = bench_closure(run, module_index, tests[index], decls[index]->u.test.per);
      }
      if (tests[index] == MIR_NONE) {
        return false;
      }
    }
    runner = lower_runner(run, module_index, *nrunners, tests, count, first);
  }
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

static bool lower_blocks(MsCheckProgram *program, MirModule *module, MsStrBuild *error, bool bench) {
  Lower cx;
  lower_init(&cx, program, module, error);
  TestRun run = {.cx = &cx, .bench = bench};
  bool ok = true;
  run.plain = runner_function(&cx, "run_plain_file");
  run.run_files = run.plain == MIR_NONE ? MIR_NONE : runner_function(&cx, "run_test_files");
  ok = run.run_files != MIR_NONE;
  if (ok && bench) {
    const MsSymbolId driver = module_symbol(program, "test/bench.ms", "run_bench_block");
    if (driver == 0) {
      ok = lower_fail(&cx, "the bench driver @std/test/bench.ms is not loaded");
    } else {
      const LowerTarget target = lower_symbol_target(&cx, driver);
      run.driver = lower_instance(&cx, &target, NULL, 0, NULL);
      ok = run.driver != MIR_NONE;
      run.fixture_driver = module_symbol(program, "test/bench.ms", "run_bench_fixture");
      ok = ok && run.fixture_driver != 0;
    }
  }
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
  return ok && !cx.failed;
}

bool ms_lower_tests(MsCheckProgram *program, MirModule *module, MsStrBuild *error) {
  return lower_blocks(program, module, error, false);
}

bool ms_lower_benches(MsCheckProgram *program, MirModule *module, MsStrBuild *error) {
  return lower_blocks(program, module, error, true);
}
