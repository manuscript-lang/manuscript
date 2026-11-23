/* compiler/lower/lower_conv.c: conversions the checker recorded on an expression: a value seen as an interface it
 * implements (a vtable of the type's methods, made on first use), and the other conversions. */
#include "compiler/lower/lower_fn.h"
#include "compiler/mir/mir_analysis.h"
#include "compiler/mir/mir_layout.h"

static const MsConversion *find_conversion(const MsFacts *facts, MsNode node) {
  size_t lo = 0;
  size_t hi = facts->conversions.len;
  while (lo < hi) {
    const size_t mid = lo + (hi - lo) / 2;
    if (facts->conversions.ptr[mid].node < node) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo < facts->conversions.len && facts->conversions.ptr[lo].node == node ? &facts->conversions.ptr[lo]
                                                                                 : NULL;
}

/* The method table entry of the method an interface operation resolves to for `receiver`. */
static const MsMethodEntry *resolve_operation(Lower *cx, MsTy receiver, MsName name) {
  MsMethodMatchList matches = {0};
  ms_check_find_method(cx->program, receiver, name, &matches);
  const MsMethodEntry *found = NULL;
  for (size_t index = 0; index < matches.len && found == NULL; index++) {
    found = matches.ptr[index].entry;
  }
  ms_method_match_list_free(&matches);
  return found;
}

/* Instantiates `entry` for `receiver`: its variables are bound by matching the receiver form. */
static uint32_t method_function(Lower *cx, const MsMethodEntry *entry, MsTy receiver, const MsTy *args, uint32_t nargs, MsTy instantiated) {
  MsTy bound[16] = {0};
  const size_t count = entry->variables.len;
  if (count > 16 || !ms_check_unify(&cx->program->types, entry->receiver, receiver, entry->variables.ptr, count, bound)) {
    (void)lower_fail(cx, "an interface method does not fit its receiver type");
    return MIR_NONE;
  }
  /* The method's own variables (`pick[K]`) are read off the arguments of the call. */
  const size_t nparams = ms_ty_param_count(&cx->program->types, entry->ty);
  const MsTyParam *params = ms_ty_params(&cx->program->types, entry->ty);
  for (uint32_t at = 0; at < nargs && at < nparams; at++) {
    (void)ms_check_unify(&cx->program->types, params[at].ty, args[at], entry->variables.ptr, count, bound);
  }
  if (instantiated != MS_TY_NONE) { /* what the call's own type fixes (`read[B]() List[B]` called as `List[Int]`) */
    (void)ms_check_unify(&cx->program->types, entry->ty, instantiated, entry->variables.ptr, count, bound);
  }
  const LowerTarget target = {entry->module, entry->source->id, &entry->source->func, entry->name, entry->ty,
                              {NULL, 0}, entry->variables.ptr, (uint32_t)count, MS_TY_NONE, 0, false};
  LowerTarget with_receiver = target;
  with_receiver.receiver = entry->receiver;
  with_receiver.receiver_flags =
      (uint8_t)((entry->source->mutating ? MS_PARAM_VAR : 0) | (entry->source->consuming ? MS_PARAM_MOVE : 0));
  return lower_instance(cx, &with_receiver, bound, (uint32_t)count, NULL);
}

uint32_t lower_operation_method(Lower *cx, MsTy receiver, MsName name, const MsTy *args, uint32_t nargs, MsTy instantiated) {
  const MsMethodEntry *entry = resolve_operation(cx, receiver, name);
  return entry != NULL && !entry->source->func.external && entry->source->func.body.len > 0
             ? method_function(cx, entry, receiver, args, nargs, instantiated)
             : MIR_NONE;
}

uint32_t lower_named_method(Lower *cx, MsTy receiver, const char *operation) {
  MsName name = MS_NAME_EMPTY;
  if (!ms_names_find(cx->program->names, ms_span_of_text(operation), &name)) {
    return MIR_NONE;
  }
  return lower_operation_method(cx, receiver, name, NULL, 0, MS_TY_NONE);
}

uint32_t lower_own_method(Lower *cx, MsTy receiver, MsProperty property) {
  const bool equal = property == MS_PROPERTY_EQUAL;
  if (!ms_check_decided_by_method(cx->program, receiver, property)) {
    return MIR_NONE;
  }
  const uint32_t method = lower_named_method(cx, receiver, equal ? "equals" : "hash");
  if (method == MIR_NONE) {
    return MIR_NONE;
  }
  const MirFunc *func = &cx->module->funcs.ptr[method];
  const bool fits = equal ? func->nparams == 2 && func->ret == MIR_BOOL && func->params[0].mode != MM_MOVE &&
                                func->params[1].mode != MM_MOVE
                          : func->nparams == 1 && func->ret == MIR_INT && func->params[0].mode != MM_MOVE;
  return fits ? method : MIR_NONE;
}

static void vtable_name(Lower *cx, const LowerSubst *subst, MsTy receiver, MsTy iface, MsStrBuild *out) {
  ms_strbuild_append_text(out, "vtable ");
  lower_type_text(cx, subst, receiver, out);
  ms_strbuild_append_text(out, " as ");
  lower_type_text(cx, subst, iface, out);
}

enum { LOWER_THUNK_PARAMS = 33 };

/* The interface-callable form of a method: it takes the address of the stored data first, reads the receiver
 * from it, and calls `method` with it (a `var` receiver is passed on as that address). A parameter the interface
 * declares as an interface value (`other: Self`) arrives as one: it is unwrapped when it holds `own` (this
 * vtable's type), and otherwise the call has no answer (`false`, or a fault for any other result). */
static uint32_t method_thunk(Lower *cx, uint32_t method, MirTy data_ty, MsName name, bool changes_receiver,
                             const MirMethodSig *sig, uint32_t own) {
  const MirFunc target = cx->module->funcs.ptr[method];
  MirParam *params = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirParam, (size_t)target.nparams + 1);
  for (uint32_t index = 0; index < target.nparams; index++) {
    params[index] = target.params[index];
  }
  params[0] = (MirParam){MIR_PTR, (uint8_t)MM_BORROW};
  for (uint32_t index = 1; index < target.nparams && index <= sig->nparams; index++) {
    const MirTy declared = sig->params[index - 1];
    if (declared != params[index].ty && mir_ty_data(cx->module, declared)->kind == MK_IFACE) {
      params[index].ty = declared;
    }
  }
  MirBuilder b;
  mir_b_init(&b, cx->module, name, params, target.nparams, target.ret);
  b.func.kind = MFK_METHOD;
  b.func.linkage = ML_INTERNAL;
  MirValue args[LOWER_THUNK_PARAMS] = {MIR_NONE};
  mir_b_params(&b, args, target.nparams);
  const MirImm ty = {.tag = MI_TY, .a = data_ty};
  if (!changes_receiver) { /* a `var` receiver is the slot itself: the method reads and writes it */
    const MirOp read = target.params[0].mode == MM_MOVE ? MOP_Take : MOP_Load;
    args[0] = mir_b_emit(&b, read, args, 1, ty, data_ty);
  }
  for (uint32_t index = 1; index < target.nparams && index <= sig->nparams; index++) {
    if (params[index].ty == target.params[index].ty) {
      continue;
    }
    const MirImm vtable = {.tag = MI_VTABLE, .a = own};
    const MirValue same = mir_b_emit(&b, MOP_IfaceIs, &args[index], 1, vtable, MIR_BOOL);
    const MirBlock yes = mir_b_new_block(&b);
    const MirBlock no = mir_b_new_block(&b);
    mir_b_br_if(&b, same, yes, NULL, 0, no, NULL, 0);
    mir_b_seal_block(&b, no);
    mir_b_switch_to(&b, no);
    if (target.ret == MIR_BOOL) {
      mir_b_ret(&b, mir_b_bconst(&b, false));
    } else {
      mir_b_unreachable(&b);
    }
    mir_b_seal_block(&b, yes);
    mir_b_switch_to(&b, yes);
    const MirValue data = mir_b_emit(&b, MOP_IfaceData, &args[index], 1, (MirImm){0}, MIR_PTR);
    args[index] = mir_b_emit(&b, MOP_Load, &data, 1, (MirImm){.tag = MI_TY, .a = target.params[index].ty},
                             target.params[index].ty);
  }
  mir_b_ret(&b, mir_b_call(&b, method, args, target.nparams));
  uint32_t id = MIR_NONE;
  return mir_b_finish(&b, &id) ? id : MIR_NONE;
}

/* The interface-callable form of an operation a standard type implements natively (`compare` of an Int): it reads the
 * receiver from the address it is given and does the operation the way a call on that type would. */
static uint32_t native_thunk(Lower *cx, MsTy receiver, MsName operation, const MirMethodSig *sig, MirTy data_ty,
                             MsName name) {
  const uint32_t nparams = sig->nparams + 1;
  MirParam *params = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirParam, (size_t)nparams + 1);
  params[0] = (MirParam){MIR_PTR, (uint8_t)MM_BORROW};
  for (uint32_t index = 0; index < sig->nparams; index++) {
    params[index + 1] = (MirParam){sig->params[index], (uint8_t)(mir_owns(sig->owned, index) ? MM_MOVE : MM_BORROW)};
  }
  LowerFn fn = {.cx = cx, .facts = &cx->program->modules.ptr[0].facts, .module_index = 0, .file = lower_file(cx, 0),
                .ret = sig->ret};
  mir_b_init(&fn.b, cx->module, name, params, nparams, sig->ret);
  fn.b.func.kind = MFK_METHOD;
  fn.b.func.linkage = ML_INTERNAL;
  fn.b.func.loc = (MirLoc){fn.file, 0, 0, 0};
  (void)fn_scope_begin(&fn);
  fn.nvars = 16;
  fn.vars = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirVar, (size_t)fn.nvars + 1);
  MirValue args[LOWER_THUNK_PARAMS] = {MIR_NONE};
  mir_b_params(&fn.b, args, nparams);
  const MirImm ty = {.tag = MI_TY, .a = data_ty};
  args[0] = mir_b_emit(&fn.b, MOP_Load, args, 1, ty, data_ty);
  MirValue result = MIR_NONE;
  const bool done = fn_native_on(&fn, NULL, receiver, ms_names_span(cx->program->names, operation), nparams, args,
                                 sig->ret, &result);
  if (!done || fn.failed) {
    const MsSpan op = ms_names_span(cx->program->names, operation);
    (void)lower_fail(cx, "the interface operation `%.*s` has no native form for its receiver type", (int)op.len,
                     (const char *)op.ptr);
    return MIR_NONE;
  }
  if (sig->ret != MIR_VOID && result != MIR_NONE && fn_fresh_owner(&fn, result)) { /* the caller takes the result */
    (void)mir_b_emit(&fn.b, MOP_ScopeDisown, &result, 1, (MirImm){0}, MIR_NONE);
  }
  fn_scope_unwind(&fn, 0);
  mir_b_ret(&fn.b, result);
  uint32_t id = MIR_NONE;
  return mir_b_finish(&fn.b, &id) ? id : MIR_NONE;
}

static uint32_t build_vtable(Lower *cx, const LowerSubst *subst, MsTy receiver, MsTy iface, MsName name) {
  if (subst != NULL && subst->count > 0) { /* the methods are those of the instance's receiver, not of its variables */
    receiver = ms_ty_subst(&cx->program->types, receiver, subst->vars, subst->args, subst->count);
  }
  const MsDef *def = ms_defs_get(&cx->program->defs, ms_ty_row(&cx->program->types, iface)->def);
  uint32_t *methods = MS_ARENA_NEW_ARRAY(&cx->module->arena, uint32_t, def->operations.len + 2);
  MsName text_name = MS_NAME_EMPTY;
  if (!ms_names_find(cx->program->names, ms_span_of_text("to_string"), &text_name)) {
    (void)lower_fail(cx, "the text of an interface value needs `to_string`");
    return MIR_NONE;
  }
  const MirTy iface_ty = lower_type(cx, subst, iface);
  /* Added before its methods are built: a method taking `Self` checks its argument against this vtable. */
  const MirVtable vtable = {name, mir_ty_data(cx->module, iface_ty)->id, methods, (uint32_t)def->operations.len + 1,
                            lower_type(cx, subst, receiver), 0};
  const uint32_t own = mir_add_vtable(cx->module, &vtable);
  for (size_t index = 0; index <= def->operations.len; index++) { /* the last slot is the payload's text */
    const MsName operation = index < def->operations.len ? def->operations.ptr[index].name : text_name;
    const MsMethodEntry *entry = resolve_operation(cx, receiver, operation);
    if (entry == NULL || entry->source->func.external) { /* the runtime implements it: no body to call */
      MsStrBuild text = ms_strbuild_new();
      ms_strbuild_append(&text, ms_names_span(&cx->module->names, name));
      ms_strbuild_printf(&text, ".native.%zu", index);
      const MsName thunk = mir_name(cx->module, ms_strbuild_span(&text));
      ms_strbuild_free(&text);
      const MirIfaceDef *shape = &cx->module->ifaces.ptr[mir_ty_data(cx->module, iface_ty)->id];
      methods[index] = native_thunk(cx, receiver, operation, &shape->methods[index],
                                    lower_type(cx, subst, receiver), thunk);
      if (methods[index] == MIR_NONE) {
        return MIR_NONE;
      }
      continue;
    }
    methods[index] = entry != NULL ? method_function(cx, entry, receiver, NULL, 0, MS_TY_NONE) : MIR_NONE;
    if (methods[index] != MIR_NONE) {
      MsStrBuild text = ms_strbuild_new();
      ms_strbuild_append(&text, ms_names_span(&cx->module->names, cx->module->funcs.ptr[methods[index]].name));
      ms_strbuild_append_text(&text, ".vt");
      const MsName thunk = mir_name(cx->module, ms_strbuild_span(&text));
      ms_strbuild_free(&text);
      methods[index] = method_thunk(cx, methods[index], lower_type(cx, subst, receiver), thunk, entry->source->mutating,
                                  &cx->module->ifaces.ptr[mir_ty_data(cx->module, iface_ty)->id].methods[index], own);
    }
    if (methods[index] == MIR_NONE) {
      return MIR_NONE;
    }
  }
  /* An owned interface value whose payload is a resource closes it where it drops: the vtable's drop slot closes. */
  const uint32_t closer = lower_vtable_close_drop(cx, receiver,
                                                  lower_type(cx, subst, receiver));
  if (closer != MIR_NONE) {
    cx->module->vtables.ptr[own].close_drop = closer + 1;
  }
  return own;
}

uint32_t lower_vtable(Lower *cx, const LowerSubst *subst, MsTy receiver, MsTy iface) {
  MsStrBuild key = ms_strbuild_new();
  vtable_name(cx, subst, receiver, iface, &key);
  const MsName name = mir_name(cx->module, ms_strbuild_span(&key));
  const MsName id = ms_names_intern(&cx->vtable_keys, ms_strbuild_span(&key));
  ms_strbuild_free(&key);
  if (id < cx->vtables.len) {
    return cx->vtables.ptr[id];
  }
  /* Recorded before the methods are lowered, so a method that builds the same view finds it. */
  mir_idlist_push(&cx->vtables, MIR_NONE);
  const uint32_t vtable = build_vtable(cx, subst, receiver, iface, name);
  cx->vtables.ptr[id] = vtable;
  return vtable;
}

static MirValue view_as_interface(LowerFn *fn, const MsExpr *expr, const MsConversion *conversion, MirValue value) {
  const uint32_t vtable = lower_vtable(fn->cx, &fn->subst, conversion->from, conversion->to);
  if (vtable == MIR_NONE) {
    (void)fn_fail(fn, "a value cannot be viewed as this interface: a method of the interface has no body for its type");
    return MIR_NONE;
  }
  const MirImm imm = {.tag = MI_VTABLE, .a = vtable};
  const MirTy to = fn_type(fn, conversion->to);
  /* A view of a binding that keeps its value does not own it; a fresh value or a moved one is the interface's. */
  const bool place = expr->kind == MS_E_NAME || expr->kind == MS_E_MEMBER;
  if (!place && fn->temps && fn_temp_closes(fn, conversion->from) && fn_owns_result(fn, value) &&
      fn_type(fn, conversion->from) == mir_b_ty(&fn->b, value)) {
    /* A resource temporary seen as an interface closes as itself where its statement ends; the interface only views it. */
    const bool held = mir_needs_drop(fn->cx->module, mir_b_ty(&fn->b, value));
    const MirValue owned = fn_own_temporary(fn, conversion->from, value);
    const MirImm view = {.tag = MI_VTABLE, .a = vtable, .b = held ? 1u : 0u};
    const MirValue iface = mir_b_emit(&fn->b, MOP_IfaceNew, &owned, 1, view, to);
    if (held) {
      (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &iface, 1, (MirImm){0}, MIR_NONE);
    }
    return iface;
  }
  const bool droppable = mir_needs_drop(fn->cx->module, mir_b_ty(&fn->b, value));
  const bool shared = place ? ms_facts_use(fn->facts, expr->id) != MS_USE_MOVE : !fn_fresh_owner(fn, value);
  const bool views = shared && droppable; /* a literal or other borrowed value is viewed, never moved in */
  if (!views) {
    if (fn_fresh_owner(fn, value)) { /* the interface takes over what the scope owned */
      (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &value, 1, (MirImm){0}, MIR_NONE);
    }
    return fn_emit(fn, MOP_IfaceNew, &value, 1, imm, to);
  }
  const MirImm kept = {.tag = MI_VTABLE, .a = vtable, .b = 1}; /* the operand stays with its binding */
  const MirValue view = mir_b_emit(&fn->b, MOP_IfaceNew, &value, 1, kept, to);
  (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &view, 1, (MirImm){0}, MIR_NONE);
  return view;
}

MirValue fn_convert(LowerFn *fn, const MsExpr *expr, MirValue value) {
  const MsConversion *conversion = find_conversion(fn->facts, expr->id);
  if (conversion == NULL || value == MIR_NONE) {
    return value;
  }
  if (conversion->kind == MS_CONV_INTERFACE_VIEW) {
    return view_as_interface(fn, expr, conversion, value);
  }
  if (conversion->kind == MS_CONV_OPTIONAL_WRAP) {
    /* Wrapping a place in an Optional shows it as one: the Optional owns nothing, so dropping it must not close the place. */
    const MirImm none = {0};
    const MirTy to = fn_type(fn, conversion->to);
    const MsTy payload = ms_ty_args(&fn->cx->program->types, conversion->to)[0];
    if (payload != conversion->from) { /* an implementor of the interface the optional holds: seen as it first */
      const MsConversion inner = {conversion->node, MS_CONV_INTERFACE_VIEW, conversion->from, payload};
      value = view_as_interface(fn, expr, &inner, value);
      if (value == MIR_NONE) {
        return MIR_NONE;
      }
      return fn_emit(fn, MOP_OptSome, &value, 1, none, to);
    }
    /* An optional wrapped around a value some binding still owns views it; a fresh value moves into the optional. */
    const MsRef *ref = expr->kind == MS_E_NAME || expr->kind == MS_E_MEMBER ? ms_facts_ref(fn->facts, expr->id) : NULL;
    const bool place = ref != NULL && ref->kind != MS_REF_CASE && ref->kind != MS_REF_TYPE; /* a case name builds a value */
    const bool kept = place && ms_facts_use(fn->facts, expr->id) != MS_USE_MOVE; /* a read of a binding is not a fresh value */
    if (!mir_needs_drop(fn->cx->module, mir_b_ty(&fn->b, value)) || (!kept && fn_fresh_owner(fn, value))) {
      return fn_emit(fn, MOP_OptSome, &value, 1, none, to);
    }
    /* A view of a value something else owns: `opt.view` is borrowed, so dropping it closes nothing. A boxed Optional
     * holds its payload in a heap block of its own, which a view cannot own: it holds a copy. */
    if (mir_ty_opt_boxed(fn->cx->module, mir_b_ty(&fn->b, value))) {
      value = fn_implicit_clone(fn, value, true);
      return value == MIR_NONE ? MIR_NONE : fn_emit(fn, MOP_OptSome, &value, 1, none, to);
    }
    return mir_b_emit(&fn->b, MOP_OptView, &value, 1, none, to);
  }
  if (conversion->kind == MS_CONV_FUNCTION_VALUE) {
    return fn_adapt_function(fn, value, fn_type(fn, conversion->to), conversion->to);
  }
  (void)fn_fail(fn, "this conversion (kind %d) is not lowered yet", (int)conversion->kind);
  return MIR_NONE;
}
