/* compiler/lower/lower_call.c: calls to module functions (with their type arguments and default arguments)
 * and to runtime functions declared `extern fn`. */
#include "compiler/lower/lower_fn.h"
#include "compiler/natives/native_sigs.h"
#include "compiler/own/taken.h"
#include "compiler/syntax/walk.h"
#include "compiler/mir/mir_analysis.h"

const MsCall *fn_find_call(const MsFacts *facts, MsNode node) {
  size_t lo = 0;
  size_t hi = facts->calls.len;
  while (lo < hi) {
    const size_t mid = lo + (hi - lo) / 2;
    if (facts->calls.ptr[mid].node < node) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo < facts->calls.len && facts->calls.ptr[lo].node == node ? &facts->calls.ptr[lo] : NULL;
}

/* The symbol a function reference names: the symbol declared by that node of that module. */
MsSymbolId fn_symbol_at(const Lower *cx, MsNodeRef decl) {
  const MsSymbolList *symbols = &cx->program->symbols;
  for (MsSymbolId id = 1; id < symbols->len; id++) {
    const MsSymbol *symbol = &symbols->ptr[id];
    if (symbol->module == decl.module && symbol->decl != NULL && symbol->decl->id == decl.node) {
      return id;
    }
  }
  return 0;
}

/* The expression a written argument names. */
const MsExpr *fn_written_arg(const MsExpr *call, MsNode node) {
  for (uint32_t index = 0; index < call->u.call.args.len; index++) {
    if (call->u.call.args.ptr[index].value->id == node) {
      return call->u.call.args.ptr[index].value;
    }
  }
  /* The receiver of a method call is written before the dot. */
  const MsExpr *callee = call->u.call.callee;
  return callee->kind == MS_E_MEMBER && callee->u.member.left->id == node ? callee->u.member.left : NULL;
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

/* A default argument is written in the callee's module: its names and types come from that module's facts. */
static MirValue default_arg(LowerFn *fn, const MsCall *call, const MsCallArg *arg, MirTy expected) {
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
  const MsParam *param = declared_default(callee_decl, method != NULL ? &method->source->func.params : NULL,
                                          call->callee.index, arg->node.node);
  if (param != NULL && is_caller_site(fn, arg->node.module, param->def)) {
    fn->facts = saved_facts;
    fn->file = saved_file;
    fn->module_index = saved_module;
    return caller_position(fn);
  }
  const MirTy saved_hint = fn->hint;
  fn->hint = expected;
  /* The default's locals are numbered in the callee's function, so they get tables of their own: sharing the caller's
   * would let the default's `var _resource` stand for a caller local with the same number. */
  const LowerFnLocals saved_locals = fn_locals_save(fn);
  const uint32_t counted = fn->facts->local_counts != NULL ? fn->facts->local_counts[call->callee.decl.node] : 0;
  fn_locals_fresh(fn, counted > 16 ? counted : 16);
  const MirValue value = param != NULL ? fn_expr(fn, param->def, LW_MOVE) : MIR_NONE;
  fn_locals_restore(fn, &saved_locals);
  fn->hint = saved_hint;
  fn->facts = saved_facts;
  fn->file = saved_file;
  fn->module_index = saved_module;
  return value;
}

bool fn_is_text_literal(const MsExpr *expr) {
  return expr->kind == MS_E_TEXT && (expr->u.text.len == 0 || (expr->u.text.len == 1 && expr->u.text.ptr[0].expr == NULL));
}

/* A `var` argument of a source function: the place it names, and the slot the callee changes it in. */
/* Moves the value of `place` into a new slot and returns the slot's address. */
MirValue fn_var_slot(LowerFn *fn, const MsExpr *place, VarSlot *out, const VarSlot *earlier, uint32_t nearlier) {
  MirValue owned;
  if (place->kind == MS_E_UNARY && place->op == MS_U_TRY && fn_place_changeable(fn, place->u.bin.left)) {
    return fn_try_var_slot(fn, place, out);
  }
  MirValue element;
  if (fn_default_var_slot(fn, place, &element)) { /* a default passing on a `var` parameter of its own call */
    *out = (VarSlot){NULL, element, MIR_VOID, MIR_NONE, true, MIR_NONE, MIR_NONE};
    return element;
  }
  if (fn_list_element_addr(fn, place, &element)) {
    *out = (VarSlot){place, element, MIR_NONE, MIR_NONE, true, MIR_NONE, MIR_NONE};
    return element;
  }
  MsExpr *indexed = NULL;
  MsExpr *index_key = NULL;
  /* `xs[i]` with a name for `i` parses as a type application, so ask for the index form, not the node kind. */
  const bool is_place = place->kind == MS_E_NAME || place->kind == MS_E_MEMBER || ms_expr_index(place, &indexed, &index_key);
  MirValue record = MIR_NONE;
  if (is_place) {
    /* A field of an owning record is taken out of it, not copied; `fn_put_field` stores it back. */
    /* Another field of a variable an earlier argument already took: it is read from that record, which goes back once. */
    bool shared = false;
    for (uint32_t at = 0; at < nearlier && !shared; at++) {
      if (earlier[at].record != MIR_NONE && earlier[at].place != NULL && fn_same_field_root(fn, earlier[at].place, place) &&
          fn_read_field(fn, place, earlier[at].record, &owned)) {
        record = earlier[at].record;
        shared = true;
      }
    }
    if (!shared && !fn_take_field(fn, place, &record, &owned) && !fn_take_place(fn, place, &owned)) {
      return MIR_NONE;
    }
  } else {
    /* A temporary: the callee changes it and what is left is dropped after the call. */
    owned = fn_expr(fn, place, LW_MOVE);
    /* A resource: it waits in a closing slot the callee changes in place, and the slot closes what is left. */
    const MsTy checked = ms_ty_subst(&fn->cx->program->types, ms_facts_type(fn->facts, place->id), fn->subst.vars,
                                     fn->subst.args, fn->subst.count);
    if (owned != MIR_NONE && fn->temps && checked != MS_TY_NONE) {
      const MirValue kept = fn_pending_own(fn, checked, owned);
      if (kept != MIR_NONE) {
        *out = (VarSlot){NULL, kept, mir_b_ty(&fn->b, owned), MIR_NONE, true, MIR_NONE, MIR_NONE};
        return kept;
      }
    }
    if (owned != MIR_NONE && mir_needs_drop(fn->cx->module, mir_b_ty(&fn->b, owned))) {
      (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &owned, 1, (MirImm){0}, MIR_NONE);
    }
  }
  if (owned == MIR_NONE) {
    return MIR_NONE;
  }
  const MirTy ty = mir_b_ty(&fn->b, owned);
  const MirImm of_type = {.tag = MI_TY, .a = ty};
  const MirValue slot = mir_b_emit(&fn->b, MOP_Slot, NULL, 0, of_type, MIR_PTR);
  const MirValue stored[2] = {slot, owned};
  (void)mir_b_emit(&fn->b, mir_needs_drop(fn->cx->module, ty) ? MOP_Put : MOP_Store, stored, 2, (MirImm){0}, MIR_NONE);
  *out = (VarSlot){is_place ? place : NULL, slot, ty, record, false, MIR_NONE, MIR_NONE};
  return slot;
}

/* Stores slot `at`'s value into its place. A field's record carries the change on to the later fields of the same root. */
static bool put_back(LowerFn *fn, VarSlot *slots, uint32_t count, uint32_t at, MirValue value) {
  if (slots[at].record == MIR_NONE) {
    return fn_put_place(fn, slots[at].place, value);
  }
  const MirValue old = slots[at].record;
  MirValue record = old;
  if (!fn_put_field_chain(fn, slots[at].place, old, value, &record)) {
    return false;
  }
  for (uint32_t later = at + 1; later < count; later++) {
    if (slots[later].record == old) {
      slots[later].record = record;
    }
  }
  return true;
}

/* After the call: each slot's value goes back into the place it came from. */
bool fn_var_slots_back(LowerFn *fn, VarSlot *slots, uint32_t count) {
  for (uint32_t at = 0; at < count; at++) {
    if (slots[at].in_place) {
      continue;
    }
    const MirImm of_type = {.tag = MI_TY, .a = slots[at].ty};
    const MirValue updated = mir_b_emit(&fn->b, mir_needs_drop(fn->cx->module, slots[at].ty) ? MOP_Take : MOP_Load,
                                        &slots[at].slot, 1, of_type, slots[at].ty);
    if (slots[at].optional != MIR_NONE) {
      const MirValue wrapped = fn_emit(fn, MOP_OptSome, &updated, 1, (MirImm){0}, slots[at].optional);
      if (slots[at].home != MIR_NONE) {
        const MirValue stored[2] = {slots[at].home, wrapped};
        (void)mir_b_emit(&fn->b, mir_needs_drop(fn->cx->module, slots[at].optional) ? MOP_Put : MOP_Store, stored, 2, (MirImm){0}, MIR_NONE);
        continue;
      }
      if (!put_back(fn, slots, count, at, wrapped)) {
        return false;
      }
    } else if (slots[at].place == NULL) {
      if (mir_needs_drop(fn->cx->module, slots[at].ty)) {
        (void)mir_b_emit(&fn->b, MOP_Drop, &updated, 1, (MirImm){0}, MIR_NONE);
      }
    } else if (!put_back(fn, slots, count, at, updated)) {
      return false;
    }
  }
  return true;
}

/* Whether the method called is declared `move fn`: it takes its receiver. */
static bool consuming_receiver(LowerFn *fn, const MsCall *call) {
  const MsMethodEntry *entry = fn_method_entry(fn->cx, call->callee.decl.module, call->callee.decl.node);
  return entry != NULL && entry->source->consuming;
}

/* Whether the call hands argument `index` (written as `written`) to its callee, rather than borrowing it. */
bool fn_arg_moves(LowerFn *fn, const MsExpr *expr, const MsCall *call, uint32_t index, const MsExpr *written) {
  const bool owning = call->callee.kind == MS_REF_TYPE || call->callee.kind == MS_REF_CASE;
  const bool takes_receiver = index == 0 && call->callee.kind == MS_REF_METHOD &&
                              written == expr->u.call.callee->u.member.left && consuming_receiver(fn, call);
  return owning || takes_receiver || (call->args[index].flags & MS_PARAM_MOVE) != 0 ||
         ms_own_call_takes(fn->cx->program, call, index);
}

/* Whether argument `a` is written before argument `b`: arguments are evaluated as written, which named
 * arguments may put out of declaration order. Arguments nobody wrote (defaults) come last. */
static bool written_before(const MsExpr *call, const MsCall *fact, uint32_t a, uint32_t b) {
  const MsExpr *left = fact->args[a].source == MS_ARG_WRITTEN ? fn_written_arg(call, fact->args[a].node.node) : NULL;
  const MsExpr *right = fact->args[b].source == MS_ARG_WRITTEN ? fn_written_arg(call, fact->args[b].node.node) : NULL;
  if (left == NULL || right == NULL) {
    return left != NULL && right == NULL;
  }
  const MsPos from = ms_expr_start(left), to = ms_expr_start(right);
  return from.line != to.line ? from.line < to.line : from.column < to.column;
}

/* Whether the call builds a record or an alternative from its arguments. */
static bool owning_constructor(const MsCall *call) {
  return call->callee.kind == MS_REF_TYPE || call->callee.kind == MS_REF_CASE;
}

static bool lower_args(LowerFn *fn, const MsExpr *expr, const MsCall *call, MirValue *out, VarSlot *slots,
                       uint32_t *nslots, bool receiver_var) {
  uint32_t order[LOWER_MAX_ARGS];
  MirValue pending[LOWER_MAX_ARGS];
  for (uint32_t at = 0; at < call->arg_count; at++) {
    out[at] = MIR_NONE;
    pending[at] = MIR_NONE;
  }
  for (uint32_t at = 0; at < call->arg_count; at++) {
    uint32_t place = at;
    while (place > 0 && written_before(expr, call, at, order[place - 1])) {
      order[place] = order[place - 1];
      place--;
    }
    order[place] = at;
  }
  /* A `var` argument is the variable itself, taken into its slot once every other argument has run: a call
   * among them that changes the variable is seen by the callee. */
  for (uint32_t step = 0; step < 3 * call->arg_count; step++) {
    const uint32_t index = order[step % call->arg_count];
    const MsCallArg *arg = &call->args[index];
    const bool by_slot = arg->source == MS_ARG_WRITTEN && slots != NULL &&
                         (((arg->flags & MS_PARAM_VAR) != 0 && (index > 0 || call->callee.kind != MS_REF_OPERATION)) || (index == 0 && receiver_var)) && *nslots < LOWER_MAX_ARGS;
    /* Phases: the written values, then the `var` slots, then the defaults, which may read a `var` parameter. */
    const uint32_t phase = by_slot ? 1 : (arg->source == MS_ARG_DEFAULT ? 2 : 0);
    if (phase != step / call->arg_count) {
      continue;
    }
    if (by_slot) {
      const MsExpr *place = fn_written_arg(expr, arg->node.node);
      out[index] = place != NULL ? fn_var_slot(fn, place, &slots[*nslots], slots, *nslots) : MIR_NONE;
      (*nslots) += place != NULL ? 1 : 0;
    } else if (arg->source == MS_ARG_WRITTEN) {
      const MsExpr *written = fn_written_arg(expr, arg->node.node);
      /* A constructor's fields own what they are given. */
      const LowerWant want = fn_arg_moves(fn, expr, call, index, written) ? LW_MOVE : LW_BORROW;
      /* A literal the checker left open takes its type from the parameter. */
      const MirTy saved_hint = fn->hint;
      const MsTyTable *types = &fn->cx->program->types;
      const size_t declared = call->callee_ty != MS_TY_NONE && ms_ty_kind(types, call->callee_ty) == MS_TY_FUNCTION
                                  ? ms_ty_param_count(types, call->callee_ty)
                                  : 0;
      if (written != NULL && (written->kind == MS_E_LIST || written->kind == MS_E_MAP) && index + declared >= call->arg_count &&
          index + declared - call->arg_count < declared) {
        fn->hint = fn_type(fn, ms_ty_params(types, call->callee_ty)[index + declared - call->arg_count].ty);
      }
      const MirTy wanted = fn->hint;
      if (wanted != saved_hint && mir_ty_data(fn->cx->module, wanted)->kind == MK_OPT) {
        fn->hint = mir_ty_data(fn->cx->module, wanted)->elem; /* a literal for an optional parameter is its payload */
      }
      out[index] = written != NULL ? fn_expr(fn, written, want) : MIR_NONE;
      fn->hint = saved_hint;
      if (wanted != saved_hint && out[index] != MIR_NONE && mir_ty_data(fn->cx->module, wanted)->kind == MK_OPT &&
          mir_b_ty(&fn->b, out[index]) == mir_ty_data(fn->cx->module, wanted)->elem) {
        out[index] = fn_emit(fn, MOP_OptSome, &out[index], 1, (MirImm){0}, wanted);
      }
      if (want == LW_BORROW && out[index] != MIR_NONE && written != NULL) {
        out[index] = fn_closing_temporary(fn, expr, index, written, out[index]);
      }
      if (want == LW_MOVE && owning_constructor(call) && out[index] != MIR_NONE && written != NULL &&
          written->kind == MS_E_CALL && step + 1 < call->arg_count) {
        const MsTy checked = ms_ty_subst(&fn->cx->program->types, ms_facts_type(fn->facts, written->id), fn->subst.vars,
                                         fn->subst.args, fn->subst.count);
        pending[index] = fn_pending_own(fn, checked, out[index]);
      }
    } else if (arg->source == MS_ARG_DEFAULT) {
      const MsTyTable *types = &fn->cx->program->types;
      const size_t declared = ms_ty_param_count(types, call->callee_ty);
      const size_t at = index >= call->arg_count - declared ? index - (call->arg_count - declared) : 0;
      fn->default_call = call;
      fn->default_args = out;
      out[index] = default_arg(fn, call, arg, fn_type(fn, ms_ty_params(types, call->callee_ty)[at].ty));
      fn->default_call = NULL;
      fn->default_args = NULL;
    } else {
      const MsTyTable *types = &fn->cx->program->types;
      const size_t declared = ms_ty_param_count(types, call->callee_ty);
      const size_t at = index >= call->arg_count - declared ? index - (call->arg_count - declared) : 0;
      const MirTy ty = fn_type(fn, ms_ty_params(types, call->callee_ty)[at].ty);
      out[index] = ty == MIR_VOID ? mir_b_unit(&fn->b) : fn_emit(fn, MOP_OptNoneOwned, NULL, 0, (MirImm){0}, ty);
    }
    if (out[index] == MIR_NONE) {
      return fn_fail(fn, "argument %u of the call at %u:%u has no value (callee kind %d)", index + 1, expr->pos.line, expr->pos.column, (int)call->callee.kind);
    }
  }
  for (uint32_t at = 0; at < call->arg_count; at++) {
    if (pending[at] != MIR_NONE) {
      out[at] = fn_pending_take(fn, pending[at], mir_b_ty(&fn->b, out[at]));
    }
  }
  return true;
}

/* The runtime function an `extern fn` declares, from the callee's type. */
static uint32_t runtime_function(LowerFn *fn, const MsSymbol *symbol, MirTy ret) {
  const MsTyTable *types = &fn->cx->program->types;
  const uint32_t count = (uint32_t)ms_ty_param_count(types, symbol->ty);
  const MsTyParam *params = ms_ty_params(types, symbol->ty);
  MirParam *mir_params = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, MirParam, (size_t)count + 1);
  for (uint32_t index = 0; index < count; index++) {
    mir_params[index] = (MirParam){fn_type(fn, params[index].ty), (uint8_t)((params[index].flags & MS_PARAM_MOVE) != 0 ? MM_MOVE : MM_BORROW)};
  }
  const MsSpan name = ms_names_span(fn->cx->program->names, symbol->name);
  const MsNativeSig *sig = ms_native_sig_find(name);
  const MirExtern def = {.name = mir_name(fn->cx->module, name),
                         .params = mir_params,
                         .nparams = count,
                         .ret = ret,
                         .role = (uint8_t)(sig != NULL && sig->spawns ? MR_SPAWNS_TASK : MR_NONE)};
  return mir_extern_intern(fn->cx->module, &def);
}

/* The method-table entry of the method declared by `node` in `module`. */
const MsMethodEntry *fn_method_entry(const Lower *cx, uint32_t module, MsNode node) {
  for (size_t index = 0; index < cx->program->methods.len; index++) {
    const MsMethodEntry *entry = &cx->program->methods.ptr[index];
    if (entry->module == module && entry->source->id == node) {
      return entry;
    }
  }
  return NULL;
}

/* What a call names, as something to lower: a module function or a method with a body. False for any other
 * callee (a runtime function, an operation, a builtin). */
bool fn_callee_target(LowerFn *fn, const MsCall *call, LowerTarget *out) {
  Lower *cx = fn->cx;
  if (call->callee.kind == MS_REF_FUNCTION) {
    const MsSymbolId id = fn_symbol_at(cx, call->callee.decl);
    if (id == 0 || cx->program->symbols.ptr[id].native != MS_NATIVE_SOURCE) {
      return false;
    }
    *out = lower_symbol_target(cx, id);
    return true;
  }
  if (call->callee.kind != MS_REF_METHOD) {
    return false;
  }
  const MsMethodEntry *entry = fn_method_entry(cx, call->callee.decl.module, call->callee.decl.node);
  if (entry != NULL && ms_ty_param_count(&cx->program->types, call->callee_ty) > 0) {
    /* A method declared once on a type set has an entry per member: the one whose receiver is the call's. */
    const MsTy receiver = ms_ty_subst(&cx->program->types, ms_ty_params(&cx->program->types, call->callee_ty)[0].ty,
                                      fn->subst.vars, fn->subst.args, fn->subst.count);
    for (size_t index = 0; index < cx->program->methods.len; index++) {
      const MsMethodEntry *other = &cx->program->methods.ptr[index];
      if (other->module == entry->module && other->source->id == entry->source->id && other->receiver == receiver) {
        entry = other;
        break;
      }
    }
  }
  if (entry == NULL || entry->source->func.external) {
    return false;
  }
  *out = (LowerTarget){entry->module, entry->source->id, &entry->source->func, entry->source->func.name, entry->ty,
                       {NULL, 0}, entry->variables.ptr, (uint32_t)entry->variables.len, MS_TY_NONE, 0, false};
  out->receiver = entry->receiver;
  out->receiver_flags = (uint8_t)((entry->source->mutating ? MS_PARAM_VAR : 0) | (entry->source->consuming ? MS_PARAM_MOVE : 0));
  return true;
}

/* A call of an interface operation on a value of a bound variable (`item.clone()` with `T: Clonable`): the
 * instance knows the concrete receiver type, so the call is the method that type implements, or the structural
 * copy when it has none. */
static MirValue call_bound_operation(LowerFn *fn, const MsExpr *expr, const MsCall *call, const MirValue *args, MirTy ret) {
  const MsExpr *callee = expr->u.call.callee;
  if (callee->kind != MS_E_MEMBER || call->arg_count == 0) {
    (void)fn_fail(fn, "an interface operation needs an interface receiver");
    return MIR_NONE;
  }
  const MsTy receiver = ms_ty_subst(&fn->cx->program->types, ms_facts_type(fn->facts, callee->u.member.left->id),
                                    fn->subst.vars, fn->subst.args, fn->subst.count);
  MsTy written[16] = {0};
  const uint32_t nwritten = expr->u.call.args.len < 16 ? (uint32_t)expr->u.call.args.len : 16;
  for (uint32_t at = 0; at < nwritten; at++) {
    written[at] = ms_ty_subst(&fn->cx->program->types, ms_facts_type(fn->facts, expr->u.call.args.ptr[at].value->id),
                              fn->subst.vars, fn->subst.args, fn->subst.count);
  }
  const uint32_t method = lower_operation_method(fn->cx, receiver, callee->u.member.name, written, nwritten);
  if (method != MIR_NONE) {
    const MirValue result = mir_b_call(&fn->b, method, args, call->arg_count);
    fn_own_result(fn, result);
    return result;
  }
  const MsSpan operation = ms_names_span(fn->cx->program->names, callee->u.member.name);
  const MsTyTable *table = &fn->cx->program->types;
  MirValue native;
  if ((ms_ty_kind(table, receiver) == MS_TY_NATIVE || ms_builtin_name(ms_ty_builtin(table, receiver))[0] != 0) &&
      fn_native_on(fn, callee->u.member.left, receiver, operation, call->arg_count, args, ret, &native)) {
    return native; /* the instance's receiver is a standard type: its own native */
  }
  const MirValue structural = fn_value_operation(fn, operation, args, call->arg_count, ret);
  if (structural != MIR_NONE) {
    return structural;
  }
  const bool standard = ms_ty_kind(table, receiver) == MS_TY_NATIVE || ms_builtin_name(ms_ty_builtin(table, receiver))[0] != 0;
  if (standard && (call->arg_count != 1 || ret != mir_b_ty(&fn->b, args[0]))) {
    return fn_native_call(fn, expr, call, args, ret); /* the runtime's `msrt_<type>_<operation>` of that receiver */
  }
  if (call->arg_count != 1 || ret != mir_b_ty(&fn->b, args[0])) {
    (void)fn_fail(fn, "the operation `%.*s` on a bound value is not lowered yet (receiver kind %d, builtin %d)", (int)operation.len, (const char *)operation.ptr, (int)ms_ty_kind(table, receiver), (int)ms_ty_builtin(table, receiver));
    return MIR_NONE;
  }
  return mir_needs_drop(fn->cx->module, ret) ? fn_emit(fn, MOP_Clone, args, 1, (MirImm){0}, ret) : args[0];
}

/* The operation is named by the member written; the checker's index does not say which one it is. */
uint32_t fn_operation_index(LowerFn *fn, const MsExpr *callee, uint32_t index) {
  if (callee->kind == MS_E_MEMBER) {
    const MsTy receiver = ms_ty_subst(&fn->cx->program->types, ms_facts_type(fn->facts, callee->u.member.left->id),
                                      fn->subst.vars, fn->subst.args, fn->subst.count);
    const MsTyRow *row = ms_ty_row(&fn->cx->program->types, receiver);
    const MsDef *def = row->def != 0 ? ms_defs_get(&fn->cx->program->defs, row->def) : NULL;
    for (uint32_t at = 0; def != NULL && at < def->operations.len; at++) {
      if (def->operations.ptr[at].name == callee->u.member.name) {
        index = at;
      }
    }
  }
  return index;
}

/* A call of an interface operation: dispatched through the receiver's vtable. */
static MirValue call_operation(LowerFn *fn, const MsExpr *expr, const MsCall *call, const MirValue *args, MirTy ret) {
  const MirTyData *data = mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, args[0]));
  if (data->kind != MK_IFACE) {
    return call_bound_operation(fn, expr, call, args, ret);
  }
  const uint32_t index = fn_operation_index(fn, expr->u.call.callee, call->callee.index);
  const MirImm imm = {.tag = MI_METHOD, .a = data->id, .b = index};
  return fn_emit(fn, MOP_CallMethod, args, call->arg_count, imm, ret);
}

/* `Case(payload...)`: an alternative's case built from its payload. */
static MirValue construct_case(LowerFn *fn, const MsCall *call, const MirValue *args, MirTy ty) {
  const MirTyData *data = mir_ty_data(fn->cx->module, ty);
  if (data->kind != MK_ALT) {
    (void)fn_fail(fn, "a case is built into an alternative");
    return MIR_NONE;
  }
  const MirImm imm = {.tag = MI_CASE, .a = data->id, .b = call->callee.index};
  return fn_emit(fn, MOP_AltNew, args, call->arg_count, imm, ty);
}

/* `Type(fields...)`: the record built from its arguments in field order. */
static MirValue construct(LowerFn *fn, const MsExpr *expr, const MsCall *call, const MirValue *args, MirTy ty) {
  const MirTyData *data = mir_ty_data(fn->cx->module, ty);
  if (data->kind == MK_LIST) {
    /* `List[T](reserve: n)`: the optional reserve is the starting capacity, none reserves nothing. */
    MirValue capacity = mir_b_iconst(&fn->b, 0);
    if (call->arg_count == 1 && mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, args[0]))->kind == MK_OPT) {
      const MirValue present = fn_emit(fn, MOP_OptIsSome, &args[0], 1, (MirImm){0}, MIR_BOOL);
      const MirValue wanted = fn_emit(fn, MOP_OptGet, &args[0], 1, (MirImm){0}, MIR_INT);
      capacity = mir_b_select(&fn->b, present, wanted, capacity);
      /* a negative reserve reserves nothing */
      capacity = mir_b_select(&fn->b, mir_b_icmp(&fn->b, MCC_LT, capacity, mir_b_iconst(&fn->b, 0)),
                              mir_b_iconst(&fn->b, 0), capacity);
      /* a reserve is a hint: past 2^27 items it is capped, and the list grows on demand */
      const MirValue limit = mir_b_iconst(&fn->b, (int64_t)1 << 27);
      capacity = mir_b_select(&fn->b, mir_b_icmp(&fn->b, MCC_GT, capacity, limit), limit, capacity);
    }
    return mir_b_list_new(&fn->b, data->elem, capacity);
  }
  const MsExpr *written = expr->u.call.args.len == 1 ? expr->u.call.args.ptr[0].value : NULL;
  const bool empty_list = written != NULL && written->kind == MS_E_LIST && written->u.list.len == 0;
  if (data->kind == MK_BYTES && written != NULL && !empty_list) {
    /* `Bytes(values)`: the runtime narrows each element of the list to a byte, into a slot it writes. */
    const MirImm of_type = {.tag = MI_TY, .a = ty};
    const MirValue values = fn_expr(fn, written, LW_BORROW);
    if (values == MIR_NONE) {
      return MIR_NONE;
    }
    const MirValue slot = fn_emit(fn, MOP_Slot, NULL, 0, of_type, MIR_PTR);
    MirValue wanted[2] = {values, slot};
    const MirTyData *list = mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, values));
    const char *native = list->kind == MK_LIST && list->elem == MIR_UINT8 ? "msrt_bytes_from_values" : "msrt_bytes_from_ints";
    (void)fn_runtime_call(fn, mir_name(fn->cx->module, ms_span_of_text(native)), wanted, 2, MIR_VOID);
    return fn_emit(fn, MOP_Take, &slot, 1, of_type, ty);
  }
  if (data->kind == MK_BYTES) {
    /* A builder starts as an empty buffer of its own. */
    ms_span_list_push(&fn->cx->module->blobs, ms_span_of_text(""));
    const MirImm blob = {.tag = MI_INT, .i = (int64_t)fn->cx->module->blobs.len - 1};
    const MirValue empty = mir_b_emit(&fn->b, MOP_BytesLit, NULL, 0, blob, MIR_BYTES);
    return fn_emit(fn, MOP_Clone, &empty, 1, (MirImm){0}, MIR_BYTES);
  }
  if (data->kind == MK_OBJ && data->obj_class == MIR_OBJ_COLLECTION && data->nargs == 1 && written != NULL && !empty_list) {
    const MirValue values = fn_expr(fn, written, LW_BORROW);
    return values == MIR_NONE ? MIR_NONE : fn_set_from_list(fn, values, ty);
  }
  if (data->kind == MK_OBJ && data->obj_class == MIR_OBJ_COLLECTION) {
    return fn_runtime_call(fn, mir_name(fn->cx->module, ms_span_of_text("msrt_map_new")), NULL, 0, ty);
  }
  if (data->kind != MK_TYPE) {
    (void)fn_fail(fn, "a value of this type cannot be built by its name yet (MIR kind %d, %u arguments, first source %d)", (int)data->kind, call->arg_count, call->arg_count > 0 ? (int)call->args[0].source : -1);
    return MIR_NONE;
  }
  const MirImm imm = {.tag = MI_TYPE, .a = data->id};
  return fn_emit(fn, MOP_TypeNew, args, call->arg_count, imm, ty);
}

/* Whether a native callee is an operation of a receiver (not an `extern fn`, which call_runtime handles). */
static bool callee_is_operation(LowerFn *fn, const MsExpr *expr, const MsCall *call) {
  /* `value.to_string()` names an operation of its receiver, whatever declaration its recorded place matches. */
  const MsExpr *callee = expr->u.call.callee;
  if (callee->kind == MS_E_MEMBER) {
    const MsRef *left = ms_facts_ref(fn->facts, callee->u.member.left->id);
    if (left == NULL || left->kind != MS_REF_MODULE) {
      return true;
    }
  }
  const MsSymbolId id = fn_symbol_at(fn->cx, call->callee.decl);
  return id == 0 || fn->cx->program->symbols.ptr[id].native != MS_NATIVE_EXTERN;
}

/* Whether the callee is a function of the standard library declared without a body (`fn panic(message) Never: ...`):
 * the runtime provides it, as `msrt_<name>`. */
static bool is_bodiless_function(LowerFn *fn, const MsCall *call) {
  const MsSymbolId id = fn_symbol_at(fn->cx, call->callee.decl);
  const MsSymbol *symbol = id == 0 ? NULL : &fn->cx->program->symbols.ptr[id];
  return symbol != NULL && symbol->decl != NULL && symbol->decl->kind == MS_D_FN && symbol->decl->u.fn.bodiless;
}

static int base64_digit(uint8_t c) {
  if (c >= 'A' && c <= 'Z') return c - 'A';
  if (c >= 'a' && c <= 'z') return c - 'a' + 26;
  if (c >= '0' && c <= '9') return c - '0' + 52;
  return c == '+' ? 62 : c == '/' ? 63 : -1;
}

/* `msstd_embed_bytes("<base64>")`: the file's bytes held in the program's read-only data, decoded here once, so a
 * read decodes nothing. MIR_NONE when the call is another one. */
static MirValue embedded_bytes(LowerFn *fn, const MsExpr *expr, MsSpan name) {
  if (!ms_span_is_text(name, "msstd_embed_bytes") || expr->u.call.args.len != 1 ||
      expr->u.call.args.ptr[0].value->kind != MS_E_TEXT || expr->u.call.args.ptr[0].value->u.text.len > 1) {
    return MIR_NONE;
  }
  const MsExpr *text = expr->u.call.args.ptr[0].value;
  const MsSpan encoded = text->u.text.len == 0 ? ms_span_of_text("") : text->u.text.ptr[0].lit;
  MsStrBuild decoded = ms_strbuild_new();
  uint32_t bits = 0;
  int held = 0;
  for (size_t at = 0; at < encoded.len && encoded.ptr[at] != '='; at++) {
    const int digit = base64_digit(encoded.ptr[at]);
    if (digit < 0) {
      ms_strbuild_free(&decoded);
      (void)fn_fail(fn, "an embedded file is not base64 text");
      return MIR_NONE;
    }
    bits = bits << 6 | (uint32_t)digit;
    held += 6;
    if (held >= 8) {
      held -= 8;
      ms_strbuild_append_byte(&decoded, (uint8_t)(bits >> held & 0xffu));
    }
  }
  const MsSpan bytes = ms_strbuild_span(&decoded);
  uint8_t *stored = ms_arena_alloc_array(&fn->cx->module->arena, 1, 1, bytes.len + 1);
  __builtin_memcpy(stored, bytes.ptr, bytes.len);
  ms_span_list_push(&fn->cx->module->blobs, ms_span_of(stored, bytes.len));
  ms_strbuild_free(&decoded);
  const MirImm blob = {.tag = MI_INT, .i = (int64_t)fn->cx->module->blobs.len - 1};
  const MirValue data = mir_b_emit(&fn->b, MOP_BytesLit, NULL, 0, blob, MIR_BYTES);
  return fn_emit(fn, MOP_Clone, &data, 1, (MirImm){0}, MIR_BYTES);
}

static MirValue call_runtime(LowerFn *fn, const MsExpr *expr, const MsCall *call, const MirValue *args, MirTy ret) {
  const MsSymbolId id = fn_symbol_at(fn->cx, call->callee.decl);
  if (id == 0 || fn->cx->program->symbols.ptr[id].native != MS_NATIVE_EXTERN) {
    (void)fn_fail(fn, "this callee is not lowered yet (reference kind %d)", (int)call->callee.kind);
    return MIR_NONE;
  }
  const MsName extern_name = mir_name(fn->cx->module, ms_names_span(fn->cx->program->names, fn->cx->program->symbols.ptr[id].name));
  const MirValue embedded = embedded_bytes(fn, expr, ms_names_span(&fn->cx->module->names, extern_name));
  if (embedded != MIR_NONE) {
    return embedded;
  }
  MirValue checked = MIR_NONE;
  fn->native_arg_moves = 0; /* the operands the declaration takes (`move handler: fn`) */
  for (uint32_t index = 0; index < call->arg_count && index < 32; index++) {
    fn->native_arg_moves |= (call->args[index].flags & MS_PARAM_MOVE) != 0 ? 1u << index : 0;
  }
  const bool status = fn_status_call(fn, mir_name(fn->cx->module, ms_names_span(fn->cx->program->names, fn->cx->program->symbols.ptr[id].name)),
                                     fn->cx->program->symbols.ptr[id].module, args, call->arg_count, ret, &checked);
  fn->native_arg_moves = 0;
  if (status) {
    return checked;
  }
  const MsName name = mir_name(fn->cx->module, ms_names_span(fn->cx->program->names, fn->cx->program->symbols.ptr[id].name));
  if (fn_shape_extern_call(fn, name, args, call->arg_count, ret, &checked) ||
      fn_value_extern_call(fn, name, args, call->arg_count, ret, &checked) ||
      fn_signature_extern_call(fn, name, args, call->arg_count, ret, &checked)) {
    return checked;
  }
  const uint32_t external = runtime_function(fn, &fn->cx->program->symbols.ptr[id], ret);
  const MsNativeSig *sig = ms_native_sig_find(ms_names_span(&fn->cx->module->names, name));
  if (sig != NULL && sig->inline_op != NULL && fn_inline_scalar_op(fn, sig->inline_op, args, call->arg_count, &checked)) {
    return checked;
  }
  /* A plain enum handed to a number parameter of the signature is its case index. */
  MirValue scalars[NS_MAX_PARAMS];
  const bool by_sig = sig != NULL && sig->count == call->arg_count && call->arg_count <= NS_MAX_PARAMS;
  for (uint32_t at = 0; by_sig && at < call->arg_count; at++) {
    scalars[at] = sig->kinds[at] == NS_VALUE ? fn_native_scalar(fn, args[at]) : args[at];
  }
  bool retyped = false;
  for (uint32_t at = 0; by_sig && at < call->arg_count; at++) {
    retyped = retyped || scalars[at] != args[at];
  }
  /* The extern's parameter was the enum; the number it now receives needs the matching declaration. */
  const uint32_t callee = retyped ? fn_runtime_extern(fn, name, scalars, call->arg_count, ret) : external;
  const MirValue result = mir_b_call_rt(&fn->b, callee, by_sig ? scalars : args, call->arg_count);
  fn_own_result(fn, result);
  return result;
}

static MirValue call_expr(LowerFn *fn, const MsExpr *expr) {
  const MsCall *call = fn_find_call(fn->facts, expr->id);
  /* A callee that is a parameter, a local or a function-valued field, or any expression with no declaration behind it (`fs[i]()`), is a value. */
  const bool named = expr->u.call.callee->kind == MS_E_NAME;
  const bool value_callee = call == NULL || call->callee.kind == MS_REF_NONE || call->callee.kind == MS_REF_FIELD ||
                            (named && (call->callee.kind == MS_REF_PARAM || call->callee.kind == MS_REF_LOCAL));
  if (value_callee && (named || call != NULL)) {
    return fn_call_value(fn, expr, call != NULL && named && call->callee.kind != MS_REF_NONE ? &call->callee : NULL);
  }
  if (call == NULL || call->arg_count > LOWER_MAX_ARGS) {
    (void)fn_fail(fn, "the checker recorded no usable call at %u:%u (node %u, %u calls)", expr->pos.line, expr->pos.column, expr->id, (unsigned)fn->facts->calls.len);
    return MIR_NONE;
  }
  MirValue args[LOWER_MAX_ARGS];
  VarSlot slots[LOWER_MAX_ARGS];
  uint32_t nslots = 0;
  LowerTarget target;
  const bool source = (call->callee.kind == MS_REF_FUNCTION || call->callee.kind == MS_REF_METHOD) &&
                      fn_callee_target(fn, call, &target);
  const bool receiver_var = source && call->callee.kind == MS_REF_METHOD && (target.receiver_flags & MS_PARAM_VAR) != 0;
  /* An interface operation takes its `var` arguments in slots too: the vtable's method changes them there. */
  const bool dispatched = call->callee.kind == MS_REF_OPERATION && expr->u.call.callee->kind == MS_E_MEMBER &&
                          mir_ty_data(fn->cx->module, fn_type(fn, ms_facts_type(fn->facts, expr->u.call.callee->u.member.left->id)))->kind == MK_IFACE;
  if (!lower_args(fn, expr, call, args, source || dispatched ? slots : NULL, &nslots, receiver_var)) {
    return MIR_NONE;
  }
  const MirTy ret = fn_type(fn, ms_facts_type(fn->facts, expr->id));
  mir_b_set_loc(&fn->b, fn_loc(fn, expr->pos));
  if (call->callee.kind == MS_REF_TYPE) {
    return construct(fn, expr, call, args, ret);
  }
  if (call->callee.kind == MS_REF_OPERATION) {
    const MirValue answer = call_operation(fn, expr, call, args, ret);
    return fn_var_slots_back(fn, slots, nslots) ? answer : MIR_NONE;
  }
  if (call->callee.kind == MS_REF_CASE) {
    return construct_case(fn, call, args, ret);
  }
  if (call->callee.kind == MS_REF_NATIVE && callee_is_operation(fn, expr, call)) {
    return fn_native_call(fn, expr, call, args, ret);
  }
  if (call->callee.kind == MS_REF_FUNCTION && is_bodiless_function(fn, call)) {
    return fn_builtin_call(fn, call, args, ret);
  }
  if (!source) {
    return call_runtime(fn, expr, call, args, ret);
  }
  MsTy bound[16] = {0};
  const MsTy *type_args = call->type_args;
  uint32_t ntype_args = call->type_arg_count;
  if (target.variables != NULL) {
    /* A method's variables are the receiver form's and its own: bind them against the instantiated signature. */
    /* The call's type is written in the caller's variables; the receiver below is already in its instance's types. */
    const MsTy callee_ty = ms_ty_subst(&fn->cx->program->types, call->callee_ty, fn->subst.vars, fn->subst.args, fn->subst.count);
    if (target.nvariables > 16 || !ms_check_unify(&fn->cx->program->types, target.ty, callee_ty, target.variables,
                                                  target.nvariables, bound)) {
      (void)fn_fail(fn, "a method's type arguments could not be found from its call");
      return MIR_NONE;
    }
    /* The receiver form binds the variables the signature does not mention (`List[T].join(separator)`). */
    const MsExpr *callee = expr->u.call.callee;
    if (call->callee.kind == MS_REF_METHOD && target.receiver != MS_TY_NONE && callee->kind == MS_E_MEMBER) {
      const MsTy actual = ms_ty_subst(&fn->cx->program->types, ms_facts_type(fn->facts, callee->u.member.left->id),
                                      fn->subst.vars, fn->subst.args, fn->subst.count);
      (void)ms_check_unify(&fn->cx->program->types, target.receiver, actual, target.variables, target.nvariables, bound);
    }
    type_args = bound;
    ntype_args = target.nvariables;
  }
  const uint32_t func = lower_instance(fn->cx, &target, type_args, ntype_args, &fn->subst);
  if (func == MIR_NONE) {
    return MIR_NONE;
  }
  const MirValue result = mir_b_call(&fn->b, func, args, call->arg_count);
  fn_own_result(fn, result);
  return fn_var_slots_back(fn, slots, nslots) ? result : MIR_NONE;
}

/* A call typed `Never` does not return: the block ends there, so a match arm that panics adds no edge to the join. */
MirValue fn_call(LowerFn *fn, const MsExpr *expr, LowerWant want) {
  (void)want;
  const MirValue result = call_expr(fn, expr);
  /* The call's own result type: the checked type of the expression may be the one the context expects. */
  const MsCall *call = fn_find_call(fn->facts, expr->id);
  const MsTyTable *types = &fn->cx->program->types;
  MsTy ty = ms_facts_type(fn->facts, expr->id);
  if (call != NULL && call->callee_ty != MS_TY_NONE && ms_ty_kind(types, call->callee_ty) == MS_TY_FUNCTION) {
    ty = ms_ty_result(types, call->callee_ty);
  }
  if (!fn->failed && !fn->terminated && ty != MS_TY_NONE && ms_ty_is(types, ty, MS_BUILTIN_Never)) {
    mir_b_unreachable(&fn->b);
    fn->terminated = true;
  }
  return result;
}
