/* compiler/lower/lower_func.c: the lowering driver. Functions are lowered on demand from `main`: a use of a
 * function with a set of type arguments reserves one MIR function (an instance), and its body is lowered from
 * a work list until nothing is left. */
#include "compiler/lower/lower_fn.h"
#include "compiler/mir/mir_analysis.h"

uint32_t lower_file(Lower *cx, uint32_t module) {
  while (cx->files.len <= module) {
    mir_idlist_push(&cx->files, MIR_NONE);
  }
  if (cx->files.ptr[module] == MIR_NONE) {
    const MsName file = cx->program->modules.ptr[module].file;
    cx->files.ptr[module] = mir_add_file(cx->module, ms_names_span(cx->program->names, file));
  }
  return cx->files.ptr[module];
}

LowerTarget lower_symbol_target(const Lower *cx, MsSymbolId symbol) {
  const MsSymbol *entry = &cx->program->symbols.ptr[symbol];
  return (LowerTarget){entry->module, entry->decl->id, &entry->decl->u.fn, entry->name, entry->ty, {NULL, 0}};
}

/* The type variables of a target, in declaration order (the impl's, then the function's own), as the checker
 * typed them. */
static bool decl_variables(Lower *cx, const LowerTarget *target, MsTy *out, uint32_t count) {
  const MsFacts *facts = &cx->program->modules.ptr[target->module].facts;
  const uint32_t outer = target->outer.len;
  if (target->func == NULL || outer + target->func->type_params.len != count) {
    return lower_fail(cx, "a generic function was used with the wrong number of type arguments");
  }
  for (uint32_t index = 0; index < count; index++) {
    const MsTypeParam *param =
        index < outer ? target->outer.ptr[index] : target->func->type_params.ptr[index - outer];
    out[index] = ms_facts_type(facts, param->id);
    if (out[index] == MS_TY_NONE) {
      return lower_fail(cx, "the checker left a type parameter untyped");
    }
  }
  return true;
}

/* `args` with the caller's variables replaced, copied into the program arena. */
static MsTy *concrete_args(Lower *cx, const MsTy *args, uint32_t nargs, const LowerSubst *caller) {
  MsTy *out = MS_ARENA_NEW_ARRAY(&cx->program->arena, MsTy, (size_t)nargs + 1);
  for (uint32_t index = 0; index < nargs; index++) {
    out[index] = args[index];
    if (caller != NULL && caller->count > 0 && ms_ty_has_variable(&cx->program->types, args[index])) {
      out[index] = ms_ty_subst(&cx->program->types, args[index], caller->vars, caller->args, caller->count);
    }
  }
  return out;
}

/* The instance key: the symbol and the type of each argument, as text. */
static void instance_key(Lower *cx, const LowerTarget *target, const MsTy *args, uint32_t nargs, MsStrBuild *out) {
  ms_strbuild_append_u64(out, target->module);
  ms_strbuild_append_byte(out, '.');
  ms_strbuild_append_u64(out, target->node);
  for (uint32_t index = 0; index < nargs; index++) {
    ms_strbuild_append_byte(out, index == 0 ? ':' : ',');
    ms_strbuild_append_u64(out, args[index]);
  }
  (void)cx;
}

/* The name of an instance: the function's name, then its type arguments (`print[String]`). */
static MsName instance_name(Lower *cx, const LowerTarget *target, const MsTy *args, uint32_t nargs) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append(&text, ms_names_span(cx->program->names, target->name));
  for (uint32_t index = 0; index < nargs; index++) {
    ms_strbuild_append_byte(&text, index == 0 ? '[' : ',');
    lower_type_text(cx, NULL, args[index], &text);
  }
  ms_strbuild_append_text(&text, nargs > 0 ? "]" : "");
  const MsName name = mir_name(cx->module, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  return name;
}

static MirMode param_mode(uint8_t flags) {
  return (flags & MS_PARAM_MOVE) != 0 ? MM_MOVE : ((flags & MS_PARAM_VAR) != 0 ? MM_VAR : MM_BORROW);
}

/* Reserves the MIR function of an instance: its signature, and a body that is `unreachable` until lowered. */
static uint32_t reserve(Lower *cx, const LowerTarget *target, const MsTy *args, uint32_t nargs) {
  MsTy vars[16];
  if (nargs > 16 || (nargs > 0 && !decl_variables(cx, target, vars, nargs))) {
    (void)lower_fail(cx, "a function has too many type parameters");
    return MIR_NONE;
  }
  const LowerSubst subst = {vars, args, nargs};
  const MsTyTable *types = &cx->program->types;
  const uint32_t count = (uint32_t)ms_ty_param_count(types, target->ty);
  const MsTyParam *params = ms_ty_params(types, target->ty);
  MirParam *mir_params = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirParam, (size_t)count + 1);
  for (uint32_t index = 0; index < count; index++) {
    mir_params[index] = (MirParam){lower_type(cx, &subst, params[index].ty), (uint8_t)param_mode(params[index].flags)};
  }
  const MirTy ret = lower_type(cx, &subst, ms_ty_result(types, target->ty));
  MirFunc func;
  mir_func_init(cx->module, &func, instance_name(cx, target, args, nargs), mir_params, count, ret);
  return mir_add_func(cx->module, &func);
}

uint32_t lower_instance(Lower *cx, const LowerTarget *target, const MsTy *args, uint32_t nargs, const LowerSubst *caller) {
  MsTy *concrete = concrete_args(cx, args, nargs, caller);
  MsStrBuild key = ms_strbuild_new();
  instance_key(cx, target, concrete, nargs, &key);
  const MsName id = ms_names_intern(&cx->instance_keys, ms_strbuild_span(&key));
  ms_strbuild_free(&key);
  if (id < cx->instances.len) {
    return cx->instances.ptr[id].func;
  }
  const uint32_t func = reserve(cx, target, concrete, nargs);
  /* Names are dense, so a new key's id is the next index. */
  lower_instance_list_push(&cx->instances, (LowerInstance){*target, concrete, nargs, func, false});
  return func;
}

/* ---- bodies ---- */

/* Declares the parameters as variables and gives the function scope the owned ones. */
static void bind_params(LowerFn *fn, const LowerTarget *target) {
  const MsTyTable *types = &fn->cx->program->types;
  const uint32_t count = (uint32_t)ms_ty_param_count(types, target->ty);
  const MsTyParam *params = ms_ty_params(types, target->ty);
  MirValue *values = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, MirValue, (size_t)count + 1);
  mir_b_params(&fn->b, values, count);
  fn->param_vars = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, MirVar, (size_t)count + 1);
  for (uint32_t index = 0; index < count; index++) {
    const MirTy ty = mir_b_ty(&fn->b, values[index]);
    fn->param_vars[index] = mir_b_declare_var(&fn->b, ty, (MirMode)param_mode(params[index].flags));
    mir_b_def_var(&fn->b, fn->param_vars[index], values[index]);
    if ((params[index].flags & MS_PARAM_MOVE) != 0 && mir_needs_drop(fn->cx->module, ty)) {
      fn_own(fn, fn_scope(fn), values[index]);
    }
  }
}

/* The end of a body that did not return: the function scope closes, then the function returns nothing. */
static void finish_body(LowerFn *fn) {
  if (fn->terminated) {
    return;
  }
  fn_scope_unwind(fn, 0);
  mir_b_ret(&fn->b, MIR_NONE);
}

static bool lower_body(Lower *cx, uint32_t index) {
  LowerInstance *instance = &cx->instances.ptr[index];
  const LowerTarget *target = &instance->target;
  if (target->func == NULL) {
    return lower_fail(cx, "a call reached a declaration with no body");
  }
  MsTy vars[16];
  if (instance->nargs > 0 && !decl_variables(cx, target, vars, instance->nargs)) {
    return false;
  }
  MirFunc *reserved = &cx->module->funcs.ptr[instance->func];
  LowerFn fn = {.cx = cx,
                .facts = &cx->program->modules.ptr[target->module].facts,
                .func = target->func,
                .module_index = target->module,
                .file = lower_file(cx, target->module),
                .subst = {vars, instance->args, instance->nargs},
                .ret = reserved->ret};
  mir_b_init(&fn.b, cx->module, reserved->name, reserved->params, reserved->nparams, reserved->ret);
  fn.b.func.loc = (MirLoc){fn.file, 0, 0, 0};
  (void)fn_scope_begin(&fn);
  bind_params(&fn, target);
  fn.nvars = fn.facts->local_counts != NULL ? fn.facts->local_counts[target->node] : 0;
  fn.vars = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirVar, (size_t)fn.nvars + 1);
  const bool ok = fn_stmts(&fn, target->func->body) && !fn.failed;
  finish_body(&fn);
  MirFunc built;
  if (!mir_b_into_func(&fn.b, &built) || !ok) {
    return !fn.failed ? lower_fail(cx, "a function could not be built") : false;
  }
  built.linkage = reserved->linkage;
  mir_func_release(reserved);
  *reserved = built;
  instance->lowered = true;
  return true;
}

static bool lower_pending(Lower *cx) {
  for (size_t index = 0; index < cx->instances.len; index++) {
    if (!cx->instances.ptr[index].lowered && !lower_body(cx, (uint32_t)index)) {
      return false;
    }
  }
  return true;
}

static void lower_init(Lower *cx, MsCheckProgram *program, MirModule *module, MsStrBuild *error) {
  *cx = (Lower){.program = program, .module = module, .error = error};
  ms_names_init(&cx->instance_keys);
  (void)ms_names_intern(&cx->instance_keys, ms_span_of_text("")); /* id 0 is the empty text; no key is empty */
  lower_instance_list_push(&cx->instances, (LowerInstance){{0}, NULL, 0, MIR_NONE, true});
}

static void lower_release(Lower *cx) {
  lower_ty_map_free(&cx->types);
  ms_names_free(&cx->instance_keys);
  lower_instance_list_free(&cx->instances);
  mir_idlist_free(&cx->files);
}

bool ms_lower_program(MsCheckProgram *program, uint32_t entry_module, MirModule *module, MsStrBuild *error) {
  Lower cx;
  lower_init(&cx, program, module, error);
  MsName main_name = MS_NAME_EMPTY;
  const MsSymbolId *found = NULL;
  if (ms_names_find(program->names, ms_span_of_text("main"), &main_name)) {
    found = ms_scope_get(&program->modules.ptr[entry_module].scope, main_name);
  }
  bool ok = found != NULL || lower_fail(&cx, "the program has no `main` function");
  if (ok) {
    const LowerTarget target = lower_symbol_target(&cx, *found);
    const uint32_t entry = lower_instance(&cx, &target, NULL, 0, NULL);
    ok = entry != MIR_NONE && lower_pending(&cx);
    module->entry = entry;
    module->funcs.ptr[entry].linkage = ML_EXPORT;
  }
  lower_release(&cx);
  return ok;
}
