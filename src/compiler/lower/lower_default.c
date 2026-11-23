/* compiler/lower/lower_default.c: argument defaults of a call, and record field defaults. A field written `port: Int = 8080` has a function
 * `fn(out, record) Void` that builds the default in place at `out`; the shape table of the type names it, so a
 * parse that finds no member builds the default as a call of the type does. */
#include "compiler/lower/lower_fn.h"
#include "compiler/lower/lower.h"
#include "compiler/mir/mir_analysis.h"
#include "compiler/natives/native_sigs.h"
#include "compiler/own/taken.h"
#include "compiler/syntax/walk.h"

uint32_t lower_field_default(Lower *cx, uint32_t module, const MsExpr *expr, MirTy ty, MirTy record, const LowerSubst *subst) {
  MirParam *params = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirParam, 3);
  params[0] = (MirParam){MIR_PTR, (uint8_t)MM_BORROW};
  params[1] = (MirParam){MIR_PTR, (uint8_t)MM_BORROW};
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_printf(&text, "default.%zu", (size_t)cx->module->funcs.len);
  const MsName name = mir_name(cx->module, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  MirFunc func;
  mir_func_init(cx->module, &func, name, params, 2, MIR_VOID);
  func.linkage = ML_INTERNAL;
  const uint32_t id = mir_add_func(cx->module, &func);
  LowerSubst copy = subst != NULL ? *subst : (LowerSubst){0};
  if (copy.count != 0) {
    MsTy *vars = MS_ARENA_NEW_ARRAY(&cx->program->arena, MsTy, copy.count * 2 + 1);
    for (size_t index = 0; index < copy.count; index++) {
      vars[index] = copy.vars[index];
      vars[copy.count + index] = copy.args[index];
    }
    copy.vars = vars;
    copy.args = vars + copy.count;
  }
  lower_default_list_push(&cx->defaults, (LowerDefault){expr, module, id, ty, record, copy, false});
  return id;
}

static bool lower_default(Lower *cx, uint32_t index) {
  const LowerDefault item = cx->defaults.ptr[index];
  const MirFunc reserved = cx->module->funcs.ptr[item.func];
  LowerFn fn = {.cx = cx,
                .facts = &cx->program->modules.ptr[item.module].facts,
                .module_index = item.module,
                .file = lower_file(cx, item.module),
                .subst = item.subst,
                .ret = MIR_VOID,
                .hint = item.ty,
                .default_record_ty = item.record};
  mir_b_init(&fn.b, cx->module, reserved.name, reserved.params, reserved.nparams, MIR_VOID);
  fn.b.func.loc = (MirLoc){fn.file, 0, 0, 0};
  (void)fn_scope_begin(&fn);
  MirValue params[2];
  mir_b_params(&fn.b, params, 2);
  fn.default_base = params[1];
  fn.nvars = 16;
  fn.vars = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirVar, (size_t)fn.nvars + 1);
  mir_b_set_loc(&fn.b, fn_loc(&fn, item.expr->pos));
  MirValue value = fn_expr(&fn, item.expr, LW_MOVE);
  bool ok = value != MIR_NONE && !fn.failed;
  if (ok) {
    const MirTy ty = mir_b_ty(&fn.b, value);
    const bool owns = mir_needs_drop(cx->module, ty);
    if (owns) {
      (void)mir_b_emit(&fn.b, MOP_ScopeDisown, &value, 1, (MirImm){0}, MIR_NONE);
    }
    const MirValue stored[2] = {params[0], value};
    (void)mir_b_emit(&fn.b, owns ? MOP_Put : MOP_Store, stored, 2, (MirImm){0}, MIR_NONE);
    fn_scope_unwind(&fn, 0);
    mir_b_ret(&fn.b, MIR_NONE);
  }
  MirFunc built;
  if (!mir_b_into_func(&fn.b, &built) || !ok) {
    return !fn.failed ? lower_fail(cx, "a field default could not be built") : false;
  }
  built.linkage = ML_INTERNAL;
  mir_func_release(&cx->module->funcs.ptr[item.func]);
  cx->module->funcs.ptr[item.func] = built;
  cx->defaults.ptr[index].lowered = true;
  return true;
}

bool lower_default_bodies(Lower *cx, bool *progressed) {
  for (size_t index = 0; index < cx->defaults.len; index++) {
    if (!cx->defaults.ptr[index].lowered) {
      *progressed = true;
      if (!lower_default(cx, (uint32_t)index)) {
        return lower_fail(cx, "  while lowering a field default at %u:%u", cx->defaults.ptr[index].expr->pos.line,
                          cx->defaults.ptr[index].expr->pos.column);
      }
    }
  }
  return true;
}

/* The parameter or field of declaration `decl` whose default expression is node `node`. */
static const MsParam *declared_default(const MsDecl *decl, const MsParams *method, uint32_t case_index, MsNode node) {
  const MsParams *list = method;
  if (method != NULL) {
    /* a method's parameters are its own */
  } else if (decl != NULL && decl->kind == MS_D_FN) {
    list = &decl->u.fn.params;
  } else if (decl != NULL && decl->kind == MS_D_TYPE) {
    list = &decl->u.type.fields;
  } else if (decl != NULL && decl->kind == MS_D_ENUM && case_index < decl->u.enumeration.cases.len) {
    list = &decl->u.enumeration.cases.ptr[case_index]->fields;
  }
  for (uint32_t index = 0; list != NULL && index < list->len; index++) {
    if (list->ptr[index]->def != NULL && list->ptr[index]->def->id == node) {
      return list->ptr[index];
    }
  }
  return NULL;
}

/* The parameter of a module-level function, written in `module`, whose default expression is node `node`: a call through a
 * function value names no callee, so the default is found from the node the checker recorded. */
static const MsParam *function_default(const Lower *cx, uint32_t module, MsNode node) {
  for (MsSymbolId id = 1; id < cx->program->symbols.len; id++) {
    const MsSymbol *symbol = &cx->program->symbols.ptr[id];
    if (symbol->module != module || symbol->decl == NULL || symbol->decl->kind != MS_D_FN) {
      continue;
    }
    const MsParam *found = declared_default(symbol->decl, NULL, 0, node);
    if (found != NULL) {
      return found;
    }
  }
  return NULL;
}

/* The parameter of an interface operation, written in `module`, whose default expression is node `node`. */
static const MsParam *interface_default(const Lower *cx, uint32_t module, MsNode node) {
  for (MsSymbolId id = 1; id < cx->program->symbols.len; id++) {
    const MsSymbol *symbol = &cx->program->symbols.ptr[id];
    if (symbol->module != module || symbol->decl == NULL || symbol->decl->kind != MS_D_INTERFACE) {
      continue;
    }
    for (uint32_t at = 0; at < symbol->decl->u.iface.methods.len; at++) {
      const MsParam *found = declared_default(NULL, &symbol->decl->u.iface.methods.ptr[at]->func.params, 0, node);
      if (found != NULL) {
        return found;
      }
    }
  }
  return NULL;
}

/* Whether the default `expr`, written in module `module`, is the call `caller_site()` of `@std/test/test.ms`. */
static bool is_caller_site(const LowerFn *fn, uint32_t module, const MsExpr *expr) {
  const Lower *cx = fn->cx;
  if (expr->kind != MS_E_CALL) {
    return false;
  }
  const MsCall *call = fn_find_call(&cx->program->modules.ptr[module].facts, expr->id);
  if (call == NULL || call->arg_count != 0) {
    return false;
  }
  const MsSymbol *symbol = &cx->program->symbols.ptr[fn_symbol_at(cx, call->callee.decl)];
  const MsSpan file = ms_names_span(cx->program->names, cx->program->modules.ptr[symbol->module].file);
  return ms_span_is_text(ms_names_span(cx->program->names, symbol->name), "caller_site") &&
         ms_span_ends_with(file, ms_span_of_text("test/test.ms"));
}

/* `caller_site()` as a default: the position (`file:line:col`) of the call that omitted the argument. */
static MirValue caller_position(LowerFn *fn) {
  const MsSpan file = ms_names_span(fn->cx->program->names, fn->cx->program->modules.ptr[fn->module_index].file);
  const MirLoc here = fn->stmt_loc.line != 0 ? fn->stmt_loc : fn->b.loc;
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_printf(&text, "%.*s:%u:%u", (int)file.len, (const char *)file.ptr, here.line, here.col);
  const MirImm imm = {.tag = MI_STR, .a = mir_add_string(fn->cx->module, ms_strbuild_span(&text))};
  ms_strbuild_free(&text);
  return fn_emit(fn, MOP_StrLit, NULL, 0, imm, MIR_STR);
}

static MirValue default_argument(LowerFn *fn, const MsCall *call, const MsCallArg *arg, MirTy expected);

LowerOuterEnv fn_env_capture(const LowerFn *fn) {
  return (LowerOuterEnv){fn->facts, fn->module_index, fn->file, fn->subst, fn_locals_save(fn), fn->default_call, fn->default_args,
                         fn->default_params, fn->default_has_self};
}

void fn_env_install(LowerFn *fn, const LowerOuterEnv *env) {
  fn->facts = env->facts;
  fn->module_index = env->module_index;
  fn->file = env->file;
  fn->subst = env->subst;
  fn_locals_restore(fn, &env->locals);
  fn->default_call = env->default_call;
  fn->default_args = env->default_args;
  fn->default_params = env->default_params;
  fn->default_has_self = env->default_has_self;
}

/* A default argument is written in the callee's module: its names and types come from that module's facts. */
MirValue fn_default_argument(LowerFn *fn, const MsCall *call, const MsCallArg *arg, MirTy expected, const LowerOuterEnv *outer) {
  if (fn->nouter == LOWER_MAX_DEFAULT_DEPTH) {
    (void)fn_fail(fn, "default arguments nest too deeply");
    return MIR_NONE;
  }
  fn->outer[fn->nouter++] = *outer; /* what the caller's writebacks put their values back in */
  const MirValue value = default_argument(fn, call, arg, expected);
  fn->nouter--;
  return value;
}

static MirValue default_argument(LowerFn *fn, const MsCall *call, const MsCallArg *arg, MirTy expected) {
  const MsFacts *saved_facts = fn->facts;
  const uint32_t saved_file = fn->file;
  const uint32_t saved_module = fn->module_index;
  fn->facts = &fn->cx->program->modules.ptr[arg->node.module].facts;
  fn->file = lower_file(fn->cx, arg->node.module);
  fn->module_index = arg->node.module;
  const MsMethodEntry *method = call->callee.kind == MS_REF_METHOD || call->callee.kind == MS_REF_NATIVE
                                    ? fn_method_entry(fn->cx, call->callee.decl.module, call->callee.decl.node)
                                    : NULL;
  const MsSymbolId callee_id = method != NULL ? 0 : fn_symbol_at(fn->cx, call->callee.decl);
  const MsDecl *callee_decl = callee_id != 0 ? fn->cx->program->symbols.ptr[callee_id].decl : NULL;
  const MsParam *param = declared_default(callee_decl, fn->default_params != NULL ? fn->default_params : method != NULL ? &method->source->func.params : NULL,
                                          call->callee.index, arg->node.node);
  if (param == NULL) {
    param = interface_default(fn->cx, arg->node.module, arg->node.node); /* the interface's own default */
  }
  if (param == NULL) {
    param = function_default(fn->cx, arg->node.module, arg->node.node); /* a function value's default */
  }
  if (param != NULL && is_caller_site(fn, arg->node.module, param->def)) {
    fn->facts = saved_facts;
    fn->file = saved_file;
    fn->module_index = saved_module;
    return caller_position(fn);
  }
  const MirTy saved_hint = fn->hint;
  fn->hint = expected;
  /* A default is written over the callee's type variables (`items: List[T?] = []`): this call's type arguments stand
   * for them while it is lowered. */
  const LowerSubst saved_subst = fn->subst;
  MsTy *own_args = NULL;
  const MsSymbol *owner = callee_id != 0 ? &fn->cx->program->symbols.ptr[callee_id] : NULL;
  const MsTy *own_vars = owner != NULL ? fn->cx->program->symbol_vars.ptr + owner->var_at : NULL;
  uint32_t own_count = owner != NULL ? owner->var_count : 0;
  if (method != NULL && method->variables.len >= method->shared) { /* a method's own variables follow its receiver's */
    own_vars = method->variables.ptr + method->shared;
    own_count = (uint32_t)(method->variables.len - method->shared);
  }
  if (fn->default_params != NULL && fn->default_vars.count != 0) {
    fn->subst = fn->default_vars; /* a method value: the variables it was bound with */
  } else if (own_count != 0 && own_count == call->type_arg_count) {
    own_args = MS_ARENA_NEW_ARRAY(&fn->cx->program->arena, MsTy, own_count);
    for (uint32_t at = 0; at < own_count; at++) {
      own_args[at] = ms_ty_subst(&fn->cx->program->types, call->type_args[at], saved_subst.vars, saved_subst.args, saved_subst.count);
    }
    fn->subst = (LowerSubst){own_vars, own_args, own_count};
  }
  if (method != NULL && method->shared != 0 && call->arg_count > ms_ty_param_count(&fn->cx->program->types, call->callee_ty) &&
      call->args[0].source == MS_ARG_WRITTEN && fn->default_params == NULL) {
    /* A default over the receiver's type variables (`value: T = self.value.clone()`): the receiver's own type
     * arguments stand for them. */
    MsTyTable *types = &fn->cx->program->types;
    const MsTy receiver = ms_ty_subst(types, ms_facts_type(saved_facts, call->args[0].node.node), saved_subst.vars,
                                      saved_subst.args, saved_subst.count);
    const size_t have = ms_ty_arg_count(types, receiver);
    if (have >= method->shared) {
      const size_t total = method->shared + fn->subst.count;
      MsTy *vars = MS_ARENA_NEW_ARRAY(&fn->cx->program->arena, MsTy, total * 2 + 1);
      for (size_t at = 0; at < method->shared; at++) {
        vars[at] = method->variables.ptr[at];
        vars[total + at] = ms_ty_args(types, receiver)[at];
      }
      for (size_t at = 0; at < fn->subst.count; at++) {
        vars[method->shared + at] = fn->subst.vars[at];
        vars[total + method->shared + at] = fn->subst.args[at];
      }
      fn->subst = (LowerSubst){vars, vars + total, total};
    }
  }
  /* The default's locals are numbered in the callee's function, so they get tables of their own: sharing the caller's
   * would let the default's `var _resource` stand for a caller local with the same number. */
  const LowerFnLocals saved_locals = fn_locals_save(fn);
  const uint32_t counted = fn->facts->local_counts != NULL && call->callee.kind != MS_REF_LOCAL ? fn->facts->local_counts[call->callee.decl.node] : 0;
  fn_locals_fresh(fn, counted > 16 ? counted : 16);
  const MsParams *outer_params = fn->default_params; /* a call inside the default is an ordinary call */
  fn->default_params = NULL;
  /* The default runs as the callee's, so a fault in it shows the callee's frame, called from this line. */
  const MsName callee_name = method != NULL ? lower_trace_name(fn->cx, method->receiver, method->name)
                             : owner != NULL ? lower_trace_name(fn->cx, MS_TY_NONE, owner->name) : MS_NAME_EMPTY;
  const uint32_t outer_scope = fn->b.loc.scope;
  if (callee_name != MS_NAME_EMPTY) {
    (void)mir_b_open_scope(&fn->b, callee_name, fn->file, fn->b.loc.line);
  }
  const MirValue value = param != NULL ? fn_expr(fn, param->def, LW_MOVE) : MIR_NONE;
  mir_b_close_scope(&fn->b, outer_scope);
  fn->default_params = outer_params;
  fn_locals_restore(fn, &saved_locals);
  fn->subst = saved_subst;
  fn->hint = saved_hint;
  fn->facts = saved_facts;
  fn->file = saved_file;
  fn->module_index = saved_module;
  return value;
}

/* The argument position of a parameter (not `var`) a default argument names as a place it passes on as `var`, or false:
 * the default changes the value the call passes for it, so the later reads and the call itself see the change. */
bool fn_default_param_place(const LowerFn *fn, const MsExpr *place, uint32_t *at) {
  const MsRef *ref = fn->default_call != NULL && place->kind == MS_E_NAME ? ms_facts_ref(fn->facts, place->id) : NULL;
  if (ref == NULL || ref->kind != MS_REF_PARAM || (fn->default_has_self && ref->local == 0)) {
    return false;
  }
  *at = fn->default_has_self ? ref->local - 1 : ref->local;
  return *at < fn->default_call->arg_count && (fn->default_call->args[*at].flags & MS_PARAM_VAR) == 0 &&
         fn->default_args[*at] != MIR_NONE;
}
