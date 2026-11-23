/* compiler/lower/lower_func.c: the lowering driver. Functions are lowered on demand from `main`: a use of a
 * function with a set of type arguments reserves one MIR function (an instance), and its body is lowered from
 * a work list until nothing is left. */
#include "compiler/lower/lower_fn.h"
#include "compiler/mir/mir_layout.h"
#include "compiler/own/moves.h"
#include "compiler/own/result_borrows.h"
#include "compiler/own/taken.h"
#include "compiler/syntax/walk.h"
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

/* Appends the type variables `ty` mentions, each once, in order of appearance. */
static void collect_variables(const MsTyTable *types, MsTy ty, MsTy *out, uint32_t *count, uint32_t capacity) {
  if (ty == MS_TY_NONE || !ms_ty_has_variable(types, ty)) {
    return;
  }
  if (ms_ty_kind(types, ty) == MS_TY_VARIABLE) {
    for (uint32_t index = 0; index < *count; index++) {
      if (out[index] == ty) {
        return;
      }
    }
    if (*count < capacity) {
      out[(*count)++] = ty;
    }
    return;
  }
  for (size_t index = 0; index < ms_ty_arg_count(types, ty); index++) {
    collect_variables(types, ms_ty_args(types, ty)[index], out, count, capacity);
  }
  for (size_t index = 0; index < ms_ty_param_count(types, ty); index++) {
    collect_variables(types, ms_ty_params(types, ty)[index].ty, out, count, capacity);
  }
  collect_variables(types, ms_ty_result(types, ty), out, count, capacity);
}

LowerTarget lower_symbol_target(const Lower *cx, MsSymbolId symbol) {
  const MsSymbol *entry = &cx->program->symbols.ptr[symbol];
  LowerTarget target = {entry->module, entry->decl->id, &entry->decl->u.fn, entry->name, entry->ty, {NULL, 0}, NULL, 0, MS_TY_NONE, 0, false};
  MsTy found[16];
  uint32_t count = 0;
  collect_variables(&cx->program->types, entry->ty, found, &count, 16);
  if (count > 0) {
    MsTy *variables = MS_ARENA_NEW_ARRAY(&cx->program->arena, MsTy, count);
    __builtin_memcpy(variables, found, count * sizeof(MsTy));
    target.variables = variables;
    target.nvariables = count;
  }
  return target;
}

/* The type variables of a target, in declaration order (the impl's, then the function's own), as the checker
 * typed them. */
static bool decl_variables(Lower *cx, const LowerTarget *target, MsTy *out, uint32_t count) {
  const MsFacts *facts = &cx->program->modules.ptr[target->module].facts;
  if (target->variables != NULL && target->nvariables == count) {
    for (uint32_t index = 0; index < count; index++) {
      out[index] = target->variables[index];
    }
    return true;
  }
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
  if (target->receiver != MS_TY_NONE) {
    /* A method declared once on a union (`fn Ordered.min`) has an entry per member: each is an instance of its own. */
    ms_strbuild_append_byte(out, '@');
    ms_strbuild_append_u64(out, target->receiver);
  }
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

/* What a fault trace calls an instance: the declared name without type arguments, a method's behind its receiver
 * type's name (`Cell.bump`). */
MsName lower_trace_name(Lower *cx, MsTy receiver, MsName declared_name) {
  const MsSpan declared = ms_names_span(cx->program->names, declared_name);
  if (receiver == MS_TY_NONE) {
    return mir_name(cx->module, declared);
  }
  MsStrBuild text = ms_strbuild_new();
  lower_type_text(cx, NULL, receiver, &text);
  MsSpan head = ms_strbuild_span(&text);
  for (size_t index = 0; index < head.len; index++) {
    if (head.ptr[index] == '[') {
      head.len = index;
      break;
    }
  }
  if (head.len > 0 && head.ptr[head.len - 1] == '?') { /* `T?` is the Optional type */
    head = ms_span_of_text("Optional");
  }
  MsStrBuild full = ms_strbuild_new();
  ms_strbuild_append(&full, head);
  ms_strbuild_append_byte(&full, '.');
  ms_strbuild_append(&full, declared);
  const MsName name = mir_name(cx->module, ms_strbuild_span(&full));
  ms_strbuild_free(&full);
  ms_strbuild_free(&text);
  return name;
}

static MirMode param_mode(uint8_t flags) {
  return (flags & MS_PARAM_MOVE) != 0 ? MM_MOVE : MM_BORROW;
}

enum { LOWER_MAX_PARAMS = 32 };

/* The parameters of a target as MIR sees them: a method's receiver, then the signature's parameters. */
static uint32_t target_params(const Lower *cx, const LowerTarget *target, MsTyParam *out) {
  const MsTyTable *types = &cx->program->types;
  uint32_t count = 0;
  if (target->receiver != MS_TY_NONE) {
    out[count++] = (MsTyParam){0, target->receiver, target->receiver_flags};
  }
  const uint32_t declared = (uint32_t)ms_ty_param_count(types, target->ty);
  const uint32_t taken = ms_own_taken_mask(cx->program, target->module, target->node);
  for (uint32_t index = 0; index < declared && count < LOWER_MAX_PARAMS; index++) {
    out[count] = ms_ty_params(types, target->ty)[index];
    out[count++].flags |= index < 32 && (taken >> index & 1u) != 0 ? MS_PARAM_MOVE : 0; /* the body owns it */
  }
  return count;
}

/* A result that is a place of a parameter, or a call whose own result is such a place: the callee can hand back
 * the reference itself. */
typedef struct PlaceReturns {
  const Lower *cx;
  const MsFacts *facts;
  const MsFunc *func; /* the function whose returns are counted */
  MsTy result; /* the declared result type, or MS_TY_NONE when unknown */
  uint32_t depth;
  uint32_t returns;
  uint32_t places;
} PlaceReturns;

static bool returns_places(const Lower *cx, uint32_t module, const MsFunc *func, MsTy result, uint32_t depth);

/* A native whose result is a type argument of one of its arguments (`List[T].get` answers a `T` of a `List[T]`): it can
 * only hand back a part of what it was given, so its result is a view. A native with any other result (a status, a
 * count) builds a new value. */
/* Whether an argument of `call` that the result may be a part of is a value built in the call (`get_or(i, Tok(..))`):
 * it dies with the statement, so the result is not something to lend on. */
static bool built_source(const PlaceReturns *counts, const MsCall *call, const MsExpr *value) {
  const MsTyTable *types = &counts->cx->program->types;
  const MsTy result = ms_facts_type(counts->facts, value->id);
  for (uint32_t index = 0; index < call->arg_count; index++) {
    if (call->args[index].node.node == 0 ||
        &counts->cx->program->modules.ptr[call->args[index].node.module].facts != counts->facts) {
      continue;
    }
    const MsTy arg = ms_facts_type(counts->facts, call->args[index].node.node);
    bool holds = arg == result && index > 0; /* a fallback of the result's own type may be what is handed back */
    for (size_t at = 0; arg != MS_TY_NONE && at < ms_ty_arg_count(types, arg); at++) {
      holds = holds || ms_ty_args(types, arg)[at] == result;
    }
    const MsExpr *written = holds ? fn_written_arg(value, call->args[index].node.node) : NULL;
    if (written != NULL && written->kind != MS_E_NAME && written->kind != MS_E_MEMBER && written->kind != MS_E_INDEX &&
        written->kind != MS_E_APPLY) {
      return true;
    }
  }
  return false;
}

static bool native_returns_element(const PlaceReturns *counts, const MsCall *call, const MsExpr *value) {
  const MsTyTable *types = &counts->cx->program->types;
  const MsTy result = ms_facts_type(counts->facts, value->id);
  if (built_source(counts, call, value)) {
    return false;
  }
  for (uint32_t index = 0; index < call->arg_count; index++) {
    if (call->args[index].node.node == 0) {
      continue;
    }
    const MsFacts *facts = &counts->cx->program->modules.ptr[call->args[index].node.module].facts;
    const MsTy arg = ms_facts_type(facts, call->args[index].node.node);
    for (size_t at = 0; arg != MS_TY_NONE && at < ms_ty_arg_count(types, arg); at++) {
      if (ms_ty_args(types, arg)[at] == result) {
        return true;
      }
    }
  }
  return false;
}

/* A call to a function whose result borrows, whose parameters it does not take, and whose own returns are places. */
static bool call_borrows(const PlaceReturns *counts, const MsExpr *value) {
  const MsCall *call = ms_facts_call(counts->facts, value->id);
  if (call != NULL && call->callee.kind == MS_REF_NATIVE) {
    return native_returns_element(counts, call, value);
  }
  if (call == NULL || counts->depth >= 4 || (call->callee.kind != MS_REF_FUNCTION && call->callee.kind != MS_REF_METHOD)) {
    return false;
  }
  const MsFunc *callee = ms_own_find_func(counts->cx->program, &call->callee);
  if (callee == counts->func) {
    return true; /* a recursive call answers what the function's other returns answer */
  }
  if (callee != NULL && (callee->bodiless || callee->external)) {
    return native_returns_element(counts, call, value);
  }
  if (callee == NULL || !ms_own_result_is_borrowed(counts->cx->program, call->callee.decl.module, call->callee.decl.node) ||
      (call->callee.kind == MS_REF_METHOD && ms_method_of_func(callee)->consuming)) {
    return false;
  }
  for (uint32_t index = 0; index < callee->params.len; index++) {
    if (callee->params.ptr[index]->moving) {
      return false;
    }
  }
  const MsTyTable *types = &counts->cx->program->types;
  const MsTy signature = ms_facts_type(&counts->cx->program->modules.ptr[call->callee.decl.module].facts, call->callee.decl.node);
  const MsTy result = signature != MS_TY_NONE && ms_ty_kind(types, signature) == MS_TY_FUNCTION ? ms_ty_result(types, signature) : MS_TY_NONE;
  return !built_source(counts, call, value) && returns_places(counts->cx, call->callee.decl.module, callee, result, counts->depth + 1);
}

static void count_place_returns(void *ctx, const MsStmt *stmt) {
  PlaceReturns *counts = ctx;
  if (stmt->kind != MS_S_RETURN || stmt->u.expr == NULL) {
    return;
  }
  const MsExpr *value = stmt->u.expr;
  if (value->kind == MS_E_NAME && ms_span_is_text(ms_names_span(counts->cx->program->names, value->u.sym), "none")) {
    const MsRef *ref = ms_facts_ref(counts->facts, value->id);
    if (ref == NULL || (ref->kind != MS_REF_PARAM && ref->kind != MS_REF_LOCAL)) {
      return; /* `none` holds nothing to borrow or own */
    }
  }
  counts->returns++;
  if (counts->result != MS_TY_NONE && ms_facts_type(counts->facts, value->id) != counts->result) {
    const MsConversion *conversion = ms_facts_conversion(counts->facts, value->id);
    if (conversion == NULL || conversion->kind != MS_CONV_OPTIONAL_WRAP) {
      return; /* any other conversion builds a new owner; a wrapped place stays a view of it */
    }
  }
  if (value->kind == MS_E_NAME) { /* `none` and a case name are values, not places */
    const MsRef *ref = ms_facts_ref(counts->facts, value->id);
    counts->places += ref != NULL && (ref->kind == MS_REF_PARAM || ref->kind == MS_REF_LOCAL) ? 1u : 0u;
  } else if (value->kind == MS_E_CALL) {
    counts->places += call_borrows(counts, value) ? 1u : 0u;
  } else {
    counts->places += value->kind == MS_E_MEMBER || value->kind == MS_E_INDEX || value->kind == MS_E_APPLY ? 1u : 0u;
  }
}

static bool returns_places(const Lower *cx, uint32_t module, const MsFunc *func, MsTy result, uint32_t depth) {
  PlaceReturns counts = {cx, &cx->program->modules.ptr[module].facts, func, result, depth, 0, 0};
  const MsVisitor visitor = {.ctx = &counts, .stmt = count_place_returns};
  ms_walk_block(&visitor, func->body);
  return counts.returns != 0 && counts.returns == counts.places;
}

/* Whether the callee's result borrows from a parameter: the checker's fact says every path returns a part of a
 * parameter, and each return is that place itself (a wrapper such as `ok(part)` builds a value and stays an owner). */
typedef struct BodyCloses {
  const MsFacts *facts;
  bool found;
} BodyCloses;

static void note_body_closes(void *ctx, const MsStmt *stmt) {
  BodyCloses *closes = ctx;
  if (stmt->kind == MS_S_BIND && ms_facts_closer(closes->facts, stmt->u.bind.pattern->id) != NULL) {
    closes->found = true;
  }
}

/* A body that closes resources can replace its result with the close error, a new value: it never hands back a part
 * of a parameter. */
static bool body_closes(const Lower *cx, const LowerTarget *target) {
  BodyCloses closes = {&cx->program->modules.ptr[target->module].facts, false};
  const MsVisitor visitor = {.ctx = &closes, .stmt = note_body_closes};
  ms_walk_block(&visitor, target->func->body);
  return closes.found;
}

static bool borrows_result(const Lower *cx, const LowerTarget *target, MirTy ret, const MirParam *params, uint32_t count) {
  const MirTyData *ret_data = mir_ty_data(cx->module, ret);
  if (ret_data->kind == MK_OPT && mir_ty_opt_boxed(cx->module, ret_data->elem)) {
    return false; /* a boxed Optional owns the heap block that holds its payload: a view of a part cannot be one */
  }
  if (target->entry || body_closes(cx, target) || !ms_own_result_is_borrowed(cx->program, target->module, target->node) ||
      !mir_needs_drop(cx->module, ret)) {
    return false;
  }
  for (uint32_t index = 0; index < count; index++) {
    if (params[index].mode == MM_MOVE) {
      return false; /* the body owns (and releases) a moved parameter: its part cannot outlive the call */
    }
  }
  return returns_places(cx, target->module, target->func, ms_ty_result(&cx->program->types, target->ty), 0);
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
  MsTyParam params[LOWER_MAX_PARAMS];
  const uint32_t count = target_params(cx, target, params);
  MirParam *mir_params = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirParam, (size_t)count + 1);
  for (uint32_t index = 0; index < count; index++) {
    /* A `var` parameter travels as the address of a slot that holds its value. */
    const MirTy ty = (params[index].flags & MS_PARAM_VAR) != 0 ? MIR_PTR : lower_type(cx, &subst, params[index].ty);
    mir_params[index] = (MirParam){ty, (uint8_t)param_mode(params[index].flags)};
  }
  const MirTy declared = lower_type(cx, &subst, ms_ty_result(types, target->ty));
  const MirTy ret = target->entry && declared == MIR_VOID ? MIR_INT : declared;
  MirFunc func;
  mir_func_init(cx->module, &func, instance_name(cx, target, args, nargs), mir_params, count, ret);
  func.display = lower_trace_name(cx, target->receiver, target->name);
  func.ret_borrowed = borrows_result(cx, target, ret, mir_params, count);
  /* A function that takes a closure and keeps it (a promise's entry) holds what a closure into its maker's frame
   * borrows until the result is dropped. */
  const uint32_t taken = ms_own_taken_mask(cx->program, target->module, target->node);
  const uint32_t offset = target->receiver != MS_TY_NONE ? 1 : 0;
  for (uint32_t index = 0; index < count && taken != 0; index++) {
    func.keeps_scoped |= index >= offset && index - offset < 32 && (taken >> (index - offset) & 1u) != 0 &&
                         mir_ty_data(cx->module, mir_params[index].ty)->kind == MK_FN;
  }
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

/* Whether the body assigns into the parameter `index` (`param.field = value`): such a parameter is an owned
 * variable, like a `var` local, so the assignment can replace what it holds. */
typedef struct ParamWrites {
  const MsFacts *facts;
  uint32_t index;
  bool found;
} ParamWrites;

static void note_param_write(void *ctx, const MsStmt *stmt) {
  ParamWrites *writes = ctx;
  if (stmt->kind != MS_S_ASSIGN || !stmt->u.assign.member_target) {
    return;
  }
  const MsExpr *root = stmt->u.assign.target;
  while (root != NULL && root->kind == MS_E_MEMBER) {
    root = root->u.member.left;
  }
  const MsRef *ref = root != NULL && root->kind == MS_E_NAME ? ms_facts_ref(writes->facts, root->id) : NULL;
  if (ref != NULL && ref->kind == MS_REF_PARAM && ref->local == writes->index) {
    writes->found = true;
  }
}

/* A field handed on (`param.field` where the body moves it) leaves the parameter partly moved, which only an owned
 * variable tracks. */
static void note_param_move(void *ctx, const MsExpr *expr) {
  ParamWrites *writes = ctx;
  const MsCall *call = expr->kind == MS_E_CALL ? ms_facts_call(writes->facts, expr->id) : NULL;
  for (uint32_t at = 0; call != NULL && at < call->arg_count; at++) {
    /* A field handed on as a `var` argument (`param.items.append(x)`) is changed in the parameter's own record. */
    const MsExpr *written = (call->args[at].flags & MS_PARAM_VAR) != 0 && call->args[at].source == MS_ARG_WRITTEN
                                ? fn_written_arg(expr, call->args[at].node.node)
                                : NULL;
    const MsExpr *root = written;
    while (root != NULL && root->kind == MS_E_MEMBER) {
      root = root->u.member.left;
    }
    const MsRef *ref = root != NULL && root != written && root->kind == MS_E_NAME ? ms_facts_ref(writes->facts, root->id) : NULL;
    if (ref != NULL && ref->kind == MS_REF_PARAM && ref->local == writes->index) {
      writes->found = true;
    }
  }
  if (expr->kind != MS_E_MEMBER || expr->u.member.left->kind != MS_E_NAME ||
      ms_facts_use(writes->facts, expr->id) != MS_USE_MOVE) {
    return;
  }
  const MsRef *ref = ms_facts_ref(writes->facts, expr->u.member.left->id);
  if (ref != NULL && ref->kind == MS_REF_PARAM && ref->local == writes->index) {
    writes->found = true;
  }
}

static bool assigns_into_param(const LowerFn *fn, const LowerTarget *target, uint32_t index) {
  ParamWrites writes = {fn->facts, index, false};
  const MsVisitor visitor = {.ctx = &writes, .stmt = note_param_write, .expr = note_param_move};
  ms_walk_block(&visitor, target->func->body);
  return writes.found;
}

/* Declares the parameters as variables and gives the function scope the owned ones. */
static void bind_params(LowerFn *fn, const LowerTarget *target) {
  MsTyParam params[LOWER_MAX_PARAMS];
  const uint32_t count = target_params(fn->cx, target, params);
  MirValue *values = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, MirValue, (size_t)count + 1);
  mir_b_params(&fn->b, values, count);
  fn->param_vars = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, MirVar, (size_t)count + 1);
  for (uint32_t index = 0; index < count; index++) {
    if ((params[index].flags & MS_PARAM_VAR) != 0 && index < 32 && (fn->shared_params >> index & 1u) != 0 &&
        index < LOWER_MAX_CLOSING_PARAMS) {
      /* A lambda changes it: the value stays in the caller's slot, which the closure borrows. */
      const MirTy ty = fn_type(fn, params[index].ty);
      fn->param_vars[index] = mir_b_declare_var(&fn->b, ty, MM_BORROW);
      fn->closing[fn->nvars + index] = values[index];
      fn->closing_var[fn->nvars + index] = true;
      fn->closing_types[fn->nvars + index] = ty;
      continue;
    }
    if ((params[index].flags & MS_PARAM_VAR) != 0 && fn->nvar_params < LOWER_MAX_VAR_PARAMS) {
      const MirTy ty = fn_type(fn, params[index].ty);
      const bool owns = mir_needs_drop(fn->cx->module, ty);
      const MirImm of_type = {.tag = MI_TY, .a = ty};
      const MirValue held = mir_b_emit(&fn->b, owns ? MOP_Take : MOP_Load, &values[index], 1, of_type, ty);
      fn->param_vars[index] = mir_b_declare_var(&fn->b, ty, owns ? MM_MOVE : MM_BORROW);
      mir_b_def_var(&fn->b, fn->param_vars[index], held);
      fn->var_params[fn->nvar_params++] = (LowerVarParam){fn->param_vars[index], values[index], ty};
      continue;
    }
    const MirTy ty = mir_b_ty(&fn->b, values[index]);
    const uint32_t offset = target->receiver != MS_TY_NONE ? 1 : 0;
    const MsParam *declared = (params[index].flags & MS_PARAM_MOVE) != 0 && index >= offset && index - offset < target->func->params.len
                                  ? target->func->params.ptr[index - offset]
                                  : NULL;
    const bool receiver = offset == 1 && index == 0 && (params[index].flags & MS_PARAM_MOVE) != 0;
    const MsNode site = receiver ? target->node : (declared == NULL ? 0 : declared->id);
    const MsCloser *closer = site == 0 ? NULL : ms_facts_closer(fn->facts, site);
    const MsTy checked = receiver ? target->receiver : (declared == NULL ? MS_TY_NONE : ms_facts_type(fn->facts, declared->id));
    if (fn_param_closer_for(fn, closer, checked)) {
      /* A resource parameter is the body's to close: it lives in a slot its scope owns. */
      fn->param_vars[index] = mir_b_declare_var(&fn->b, ty, MM_BORROW);
      (void)fn_own_param(fn, index, checked, values[index], fn->param_vars[index], closer != NULL && (closer->flags & MS_CLOSER_FIELDS) != 0);
      continue;
    }
    fn->param_vars[index] = mir_b_declare_var(&fn->b, ty, (MirMode)param_mode(params[index].flags));
    mir_b_def_var(&fn->b, fn->param_vars[index], values[index]);
    if ((params[index].flags & MS_PARAM_MOVE) != 0 && mir_needs_drop(fn->cx->module, ty)) {
      if (assigns_into_param(fn, target, index)) {
        (void)fn_scope_own_var(fn, fn->param_vars[index]); /* the variable owns what it holds */
      } else {
        fn_own(fn, fn_scope(fn), values[index]);
      }
    }
  }
}

/* The end of a body that did not return: the function scope closes, then the function returns nothing. */
static void finish_body(LowerFn *fn) {
  if (fn->terminated) {
    return;
  }
  if (!fn_end_is_reachable(fn)) {
    mir_b_unreachable(&fn->b);
    return;
  }
  MirValue done = fn_result_wrap(fn, MIR_NONE);
  if (done == MIR_NONE) {
    done = fn_default_result(fn);
  }
  fn_scope_unwind(fn, 0);
  mir_b_ret(&fn->b, done);
}

static bool lower_body(Lower *cx, uint32_t index) {
  /* Lowering a body adds instances and functions, which moves both lists: keep copies, not pointers. */
  const LowerInstance instance = cx->instances.ptr[index];
  const LowerTarget *target = &instance.target;
  if (target->func == NULL) {
    return lower_fail(cx, "a call reached a declaration with no body");
  }
  MsTy vars[16];
  if (instance.nargs > 0 && !decl_variables(cx, target, vars, instance.nargs)) {
    return false;
  }
  MsPos moved_at = {0};
  MsName moved_name = 0;
  if (instance.nargs > 0 && ms_own_moves_instance(cx->program, target->module, target->func, vars, instance.args,
                                                 instance.nargs, &moved_at, &moved_name)) {
    const MsSpan name = ms_names_span(cx->program->names, moved_name);
    const MsSpan file = cx->module->files.ptr[lower_file(cx, target->module)];
    return lower_user_fail(cx,
                           "%.*s:%u:%u: `%.*s` is moved here, but its parameter only borrows it, and a resource cannot be moved out of a borrow; declare the parameter `move`",
                           (int)file.len, (const char *)file.ptr, moved_at.line, moved_at.column, (int)name.len,
                           (const char *)name.ptr);
  }
  const MirFunc stub = cx->module->funcs.ptr[instance.func];
  const MirFunc *reserved = &stub;
  LowerFn fn = {.cx = cx,
                .facts = &cx->program->modules.ptr[target->module].facts,
                .func = target->func,
                .keeps_scoped = stub.keeps_scoped,
                .module_index = target->module,
                .file = lower_file(cx, target->module),
                .subst = {vars, instance.args, instance.nargs},
                .decl_void = target->entry && ms_ty_is(&cx->program->types, ms_ty_result(&cx->program->types, target->ty), MS_BUILTIN_Void),
                .ret = reserved->ret};
  mir_b_init(&fn.b, cx->module, reserved->name, reserved->params, reserved->nparams, reserved->ret);
  fn.b.func.loc = (MirLoc){fn.file, 0, 0, 0};
  (void)fn_scope_begin(&fn);
  fn.nvars = fn.facts->local_counts != NULL ? fn.facts->local_counts[target->node] : 0;
  fn.vars = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirVar, (size_t)fn.nvars + 1);
  fn.local_owns = MS_ARENA_NEW_ARRAY(&cx->module->arena, uint8_t, (size_t)fn.nvars + 1);
  fn_init_closing(&fn);
  fn_find_shared(&fn, target->func->body);
  bind_params(&fn, target);
  fn.returns_borrow = cx->module->funcs.ptr[instance.func].ret_borrowed;
  const bool ok = fn_stmts(&fn, target->func->body) && !fn.failed;
  finish_body(&fn);
  MirFunc built;
  if (!mir_b_into_func(&fn.b, &built) || !ok) {
    return !fn.failed ? lower_fail(cx, "a function could not be built") : false;
  }
  MirFunc *slot = &cx->module->funcs.ptr[instance.func];
  built.linkage = slot->linkage;
  built.keeps_scoped = slot->keeps_scoped;
  built.ret_borrowed = slot->ret_borrowed;
  built.display = slot->display;
  mir_func_release(slot);
  *slot = built;
  cx->instances.ptr[index].lowered = true;
  return true;
}

bool lower_pending(Lower *cx) {
  bool progressed = true;
  while (progressed) {
    progressed = false;
    for (size_t index = 0; index < cx->instances.len; index++) {
      if (!cx->instances.ptr[index].lowered) {
        progressed = true;
        if (!lower_body(cx, (uint32_t)index) || cx->failed) {
          const MsSpan name = ms_names_span(cx->program->names, cx->instances.ptr[index].target.name);
          return lower_fail(cx, "  while lowering `%.*s`", (int)name.len, (const char *)name.ptr);
        }
      }
    }
    if (!lower_lambda_bodies(cx, &progressed) || !lower_default_bodies(cx, &progressed) ||
        !lower_glue_bodies(cx, &progressed)) {
      return false;
    }
  }
  return true;
}

void lower_init(Lower *cx, MsCheckProgram *program, MirModule *module, MsStrBuild *error) {
  *cx = (Lower){.program = program, .module = module, .error = error};
  ms_names_init(&cx->instance_keys);
  ms_names_init(&cx->vtable_keys);
  (void)ms_names_intern(&cx->vtable_keys, ms_span_of_text(""));
  mir_idlist_push(&cx->vtables, MIR_NONE);
  (void)ms_names_intern(&cx->instance_keys, ms_span_of_text("")); /* id 0 is the empty text; no key is empty */
  lower_instance_list_push(&cx->instances, (LowerInstance){{0}, NULL, 0, MIR_NONE, true});
}

void lower_release(Lower *cx) {
  lower_ty_map_free(&cx->types);
  ms_names_free(&cx->instance_keys);
  ms_names_free(&cx->vtable_keys);
  mir_idlist_free(&cx->vtables);
  mir_idlist_free(&cx->hooked);
  lower_instance_list_free(&cx->instances);
  lower_lambda_list_free(&cx->lambdas);
  lower_default_list_free(&cx->defaults);
  lower_glue_list_free(&cx->glues);
  lower_source_list_free(&cx->sources);
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
  bool ok = found != NULL || lower_user_fail(&cx, "the entry file has no `main` function; declare `fn main()`");
  if (ok) {
    /* The module is named for the entry file's stem (`src/main.ms` is `main`). */
    MsSpan stem = ms_names_span(program->names, program->modules.ptr[entry_module].file);
    for (size_t at = stem.len; at > 0; at--) {
      if (stem.ptr[at - 1] == '/' || stem.ptr[at - 1] == '\\') {
        stem = (MsSpan){stem.ptr + at, stem.len - at};
        break;
      }
    }
    if (stem.len > 3 && ms_span_is_text((MsSpan){stem.ptr + stem.len - 3, 3}, ".ms")) {
      stem.len -= 3;
    }
    module->name = mir_name(module, stem);
    LowerTarget target = lower_symbol_target(&cx, *found);
    const uint32_t entry = lower_instance(&cx, &target, NULL, 0, NULL);
    ok = entry != MIR_NONE && lower_pending(&cx);
    const uint32_t start = ok ? lower_entry_status(&cx, entry) : entry;
    ok = ok && start != MIR_NONE;
    module->entry = start;
    if (start != MIR_NONE) {
      module->funcs.ptr[start].linkage = ML_EXPORT;
    }
  }
  lower_release(&cx);
  return ok && !cx.failed;
}
