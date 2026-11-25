/* compiler/lower/lower_call.c: calls to module functions (with their type arguments and default arguments)
 * and to runtime functions declared `extern fn`. */
#include "compiler/lower/lower_fn.h"
#include "compiler/natives/native_sigs.h"
#include "compiler/own/look_fields.h"
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
  const MsExpr *callee = fn_call_callee(call);
  return callee->kind == MS_E_MEMBER && callee->u.member.left->id == node ? callee->u.member.left : NULL;
}

bool fn_is_text_literal(const MsExpr *expr) {
  return expr->kind == MS_E_TEXT && (expr->u.text.len == 0 || (expr->u.text.len == 1 && expr->u.text.ptr[0].expr == NULL));
}

/* Whether the method called is declared `move fn`: it takes its receiver. */
static bool consuming_receiver(LowerFn *fn, const MsCall *call) {
  const MsMethodEntry *entry = fn_method_entry(fn->cx, call->callee.decl.module, call->callee.decl.node);
  return entry != NULL && entry->source->consuming;
}

/* Whether `written`, the receiver of the call, is a place a standard native changes: the native takes it out of its
 * place itself, once, so reading it for the call must leave it there. */
static bool native_takes_place(LowerFn *fn, const MsExpr *expr, const MsCall *call, const MsExpr *written) {
  if ((call->callee.kind != MS_REF_NATIVE && call->callee.kind != MS_REF_METHOD) || written == NULL ||
      fn_call_callee(expr)->kind != MS_E_MEMBER || written != fn_call_callee(expr)->u.member.left) {
    return false;
  }
  const MsTyTable *table = &fn->cx->program->types;
  const MsTy receiver = fn_read_type(fn, written);
  const bool standard = ms_ty_kind(table, receiver) == MS_TY_NATIVE || ms_builtin_name(ms_ty_builtin(table, receiver))[0] != 0;
  return standard && fn_place_changeable(fn, written) &&
         fn_native_changes_receiver(fn, receiver, ms_names_span(fn->cx->program->names, fn_call_callee(expr)->u.member.name),
                                    fn_type(fn, ms_facts_type(fn->facts, expr->id)));
}

/* Whether the call hands argument `index` (written as `written`) to its callee, rather than borrowing it. */
bool fn_arg_moves(LowerFn *fn, const MsExpr *expr, const MsCall *call, uint32_t index, const MsExpr *written) {
  const bool owning = (call->callee.kind == MS_REF_TYPE && !ms_own_look_field(fn->cx->program, call, index)) ||
                      call->callee.kind == MS_REF_CASE;
  const bool takes_receiver = index == 0 && call->callee.kind == MS_REF_METHOD &&
                              written == fn_call_callee(expr)->u.member.left && consuming_receiver(fn, call);
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

/* A runtime operation hands a fresh resource argument on only once it succeeds (a list's bad index faults first), so the
 * argument stays in its closing slot across the call; `held` gets that slot. */
static bool held_across(const MsCall *call, bool native) {
  return native && (call->callee.kind == MS_REF_NATIVE || call->callee.kind == MS_REF_METHOD || call->callee.kind == MS_REF_FUNCTION);
}

static bool lower_args(LowerFn *fn, const MsExpr *expr, const MsCall *call, MirValue *out, VarSlot *slots,
                       uint32_t *nslots, bool receiver_var, bool native, MirValue *held) {
  uint32_t order_small[LOWER_MAX_ARGS];
  MirValue pending_small[LOWER_MAX_ARGS];
  const bool big = call->arg_count > LOWER_MAX_ARGS;
  uint32_t *order = big ? MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, uint32_t, call->arg_count) : order_small;
  MirValue *pending = big ? MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, MirValue, call->arg_count) : pending_small;
  MirValue receiver_slot = MIR_NONE; /* a fresh list literal receiver that closes its resources: registered before the arguments */
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
                         (((arg->flags & MS_PARAM_VAR) != 0 && (index > 0 || call->callee.kind == MS_REF_FUNCTION)) || (index == 0 && receiver_var)) && *nslots < call->arg_count;
    /* Phases: the written values, then the `var` slots, then the defaults, which may read a `var` parameter. */
    const uint32_t phase = by_slot ? 1 : (arg->source == MS_ARG_DEFAULT ? 2 : 0);
    const bool receiver_place = index == 0 && (call->callee.kind == MS_REF_METHOD || call->callee.kind == MS_REF_NATIVE) && arg->source == MS_ARG_WRITTEN;
    if ((by_slot || receiver_place) && step < call->arg_count) { /* the keys of its place run where it is written, once */
      const MsExpr *written = fn_written_arg(expr, arg->node.node);
      if (written != NULL) {
        fn_presolve_keys(fn, written);
      }
    }
    if (phase != step / call->arg_count) {
      continue;
    }
    if (by_slot) {
      const MsExpr *place = fn_written_arg(expr, arg->node.node);
      out[index] = place != NULL ? fn_var_slot(fn, place, &slots[*nslots], slots, *nslots) : MIR_NONE;
      (*nslots) += place != NULL ? 1 : 0;
      /* The variable's value is in the slot until the call returns: a later argument that leaves the function puts it back. */
      if (out[index] != MIR_NONE && place != NULL && slots[*nslots - 1].record == MIR_NONE && !slots[*nslots - 1].in_place &&
          !fn_lend_writeback(fn, &slots[*nslots - 1])) {
        return false;
      }
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
      fn->placing_member = index == 0 && native_takes_place(fn, expr, call, written) ? written : NULL;
      out[index] = written != NULL ? fn_expr(fn, written, want) : MIR_NONE;
      fn->placing_member = NULL;
      fn->hint = saved_hint;
      if (fn->terminated && written != NULL && index + declared >= call->arg_count) {
        /* The argument never returns (`f(panic("..."))`): the call is dead code, built over a value of the parameter's
         * type that nothing reads. */
        const MirTy param = fn_type(fn, ms_ty_params(types, call->callee_ty)[index + declared - call->arg_count].ty);
        if (param != MIR_VOID) {
          out[index] = mir_b_emit(&fn->b, MOP_Undef, NULL, 0, (MirImm){0}, param);
        }
      }
      if (wanted != saved_hint && out[index] != MIR_NONE && mir_ty_data(fn->cx->module, wanted)->kind == MK_OPT &&
          mir_b_ty(&fn->b, out[index]) == mir_ty_data(fn->cx->module, wanted)->elem) {
        out[index] = fn_emit(fn, MOP_OptSome, &out[index], 1, (MirImm){0}, wanted);
      }
      if (want == LW_BORROW && out[index] != MIR_NONE && written != NULL) {
        out[index] = fn_closing_temporary(fn, expr, index, written, out[index]);
      }
      if (index == 0 && native && call->callee.kind == MS_REF_NATIVE && call->arg_count > 1 && want == LW_BORROW && written != NULL &&
          written->kind == MS_E_LIST && out[index] != MIR_NONE && fn_fresh_owner(fn, out[index])) {
        /* The receiver closes after the arguments that follow it, so its slot is registered first: a fault in the call
         * closes the incoming operands before it. */
        const MsTy checked = ms_ty_subst(&fn->cx->program->types, fn_read_type(fn, written), fn->subst.vars,
                                         fn->subst.args, fn->subst.count);
        receiver_slot = fn_pending_own(fn, checked, out[index]);
        if (receiver_slot != MIR_NONE) {
          const MirTy held_ty = mir_b_ty(&fn->b, out[index]);
          out[index] = fn_emit(fn, MOP_Load, &receiver_slot, 1, (MirImm){.tag = MI_TY, .a = held_ty}, held_ty);
        }
      }
      if (want == LW_MOVE && out[index] != MIR_NONE && written != NULL &&
          (written->kind == MS_E_CALL || (written->kind == MS_E_NAME && ms_facts_use(fn->facts, written->id) == MS_USE_MOVE)) &&
          (step + 1 < call->arg_count || held_across(call, native))) {
        MsTy checked = ms_ty_subst(&fn->cx->program->types, fn_read_type(fn, written), fn->subst.vars,
                                   fn->subst.args, fn->subst.count);
        const size_t params = ms_ty_param_count(&fn->cx->program->types, call->callee_ty);
        if (params != 0 && index + params >= call->arg_count && fn_type(fn, checked) != mir_b_ty(&fn->b, out[index])) {
          /* A value converted to the Optional the parameter takes closes as that Optional. */
          checked = ms_ty_subst(&fn->cx->program->types,
                                ms_ty_params(&fn->cx->program->types, call->callee_ty)[index + params - call->arg_count].ty,
                                fn->subst.vars, fn->subst.args, fn->subst.count);
        }
        pending[index] = fn_pending_own(fn, checked, out[index]);
      }
    } else if (arg->source == MS_ARG_DEFAULT) {
      const MsTyTable *types = &fn->cx->program->types;
      const size_t declared = ms_ty_param_count(types, call->callee_ty);
      const size_t at = index >= call->arg_count - declared ? index - (call->arg_count - declared) : 0;
      const bool outer_has_self = fn->default_has_self; /* an ordinary call inside a method value's default */
      const LowerOuterEnv caller = fn_env_capture(fn);
      fn->default_has_self = false;
      fn->default_call = call;
      fn->default_args = out;
      const DefaultExit *saved_exit = fn->default_exit;
      fn->default_exit = fn->call_exit != NULL ? fn->call_exit : saved_exit;
      out[index] = fn_default_argument(fn, call, arg, fn_type(fn, ms_ty_params(types, call->callee_ty)[at].ty), &caller);
      fn->default_exit = saved_exit;
      fn->default_call = NULL;
      fn->default_args = NULL;
      fn->default_has_self = outer_has_self;
      if (owning_constructor(call) && out[index] != MIR_NONE) {
        /* A default resource waits in a closing slot too: a later default that faults closes it. */
        const MsTy param = ms_ty_subst(&fn->cx->program->types, ms_ty_params(types, call->callee_ty)[at].ty, fn->subst.vars, fn->subst.args,
                                       fn->subst.count);
        pending[index] = fn_pending_own(fn, param, out[index]);
      }
    } else if (arg->source == MS_ARG_MISSING_VALUE) {
      const MsTyTable *types = &fn->cx->program->types;
      const size_t declared = ms_ty_param_count(types, call->callee_ty);
      const size_t at = index >= call->arg_count - declared ? index - (call->arg_count - declared) : 0;
      out[index] = fn_missing_value(fn, expr->pos);
      if (out[index] != MIR_NONE && (ms_ty_params(types, call->callee_ty)[at].flags & MS_PARAM_LIFTED) != 0) {
        const MirTy opt = mir_ty_opt(fn->cx->module, mir_b_ty(&fn->b, out[index])); /* an omittable parameter is passed as an optional */
        out[index] = fn_emit(fn, MOP_OptSome, &out[index], 1, (MirImm){0}, opt);
      }
    } else {
      const MsTyTable *types = &fn->cx->program->types;
      const size_t declared = ms_ty_param_count(types, call->callee_ty);
      const size_t at = index >= call->arg_count - declared ? index - (call->arg_count - declared) : 0;
      const MsTyParam *param = &ms_ty_params(types, call->callee_ty)[at];
      MirTy ty = fn_type(fn, param->ty);
      if ((param->flags & MS_PARAM_LIFTED) != 0 && ty != MIR_VOID && mir_ty_data(fn->cx->module, ty)->kind != MK_OPT) {
        ty = mir_ty_opt(fn->cx->module, ty); /* an omittable parameter is passed as an optional */
      }
      out[index] = ty == MIR_VOID ? mir_b_unit(&fn->b) : fn_emit(fn, MOP_OptNone, NULL, 0, (MirImm){0}, ty);
    }
    if (out[index] == MIR_NONE) {
      return fn_fail(fn, "argument %u of the call at %u:%u has no value (callee kind %d)", index + 1, expr->pos.line, expr->pos.column, (int)call->callee.kind);
    }
  }
  fn->receiver_slot = receiver_slot;
  for (uint32_t at = 0; at < call->arg_count; at++) {
    if (pending[at] != MIR_NONE && held_across(call, native)) {
      held[at] = pending[at];
      const MirTy held_ty = mir_b_ty(&fn->b, out[at]);
      const MsExpr *written = call->args[at].source == MS_ARG_WRITTEN ? fn_written_arg(expr, call->args[at].node.node) : NULL;
      /* A moving parameter gets an owned value; the slot keeps the same bytes until the call returns, so a fault
       * before the callee takes them still closes the resource. */
      const bool moves = written != NULL && fn_arg_moves(fn, expr, call, at, written) && mir_needs_drop(fn->cx->module, held_ty);
      out[at] = fn_emit(fn, moves ? MOP_Take : MOP_Load, &pending[at], 1, (MirImm){.tag = MI_TY, .a = held_ty}, held_ty);
    } else if (pending[at] != MIR_NONE) {
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
  const MsName name = mir_name(fn->cx->module, ms_names_span(fn->cx->program->names, symbol->name));
  const MsNativeSig *sig = ms_native_sig_find(ms_names_span(&fn->cx->module->names, name));
  const MirExtern def = {.name = name,
                         .params = mir_params,
                         .nparams = count,
                         .ret = ret,
                         .role = (uint8_t)(sig != NULL && sig->keeps ? MR_KEEPS_SLOT : MR_NONE)};
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
  const MsExpr *callee = fn_call_callee(expr);
  if (callee->kind != MS_E_MEMBER || call->arg_count == 0) {
    (void)fn_fail(fn, "an interface operation needs an interface receiver");
    return MIR_NONE;
  }
  const MsTy receiver = ms_ty_subst(&fn->cx->program->types, fn_read_type(fn, callee->u.member.left),
                                    fn->subst.vars, fn->subst.args, fn->subst.count);
  MsTy written[16] = {0};
  const uint32_t nwritten = expr->u.call.args.len < 16 ? (uint32_t)expr->u.call.args.len : 16;
  for (uint32_t at = 0; at < nwritten; at++) {
    written[at] = ms_ty_subst(&fn->cx->program->types, fn_read_type(fn, expr->u.call.args.ptr[at].value),
                              fn->subst.vars, fn->subst.args, fn->subst.count);
  }
  const uint32_t method = lower_operation_method(fn->cx, receiver, callee->u.member.name, written, nwritten,
                                              ms_ty_subst(&fn->cx->program->types, call->callee_ty, fn->subst.vars, fn->subst.args, fn->subst.count));
  if (method != MIR_NONE && fn->cx->module->funcs.ptr[method].nparams == call->arg_count) { /* the operation's own arity */
    const MirValue result = mir_b_call(&fn->b, method, args, call->arg_count);
    fn_own_result(fn, result);
    if (fn->cx->module->funcs.ptr[method].ret_borrowed && mir_needs_drop(fn->cx->module, ret)) {
      /* An operation answers an owner, as through the vtable: the implementation's view is copied here. */
      return fn_emit(fn, MOP_Clone, &result, 1, (MirImm){0}, ret);
    }
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
    const MsTy receiver = ms_ty_subst(&fn->cx->program->types, fn_read_type(fn, callee->u.member.left),
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
  const uint32_t index = fn_operation_index(fn, fn_call_callee(expr), call->callee.index);
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
    const MirValue fresh = mir_b_list_new(&fn->b, data->elem, capacity);
    fn_own_result(fn, fresh);
    return fresh;
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
    return fn_empty_map(fn, ty);
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
  const MsExpr *callee = fn_call_callee(expr);
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
  /* A program's own `fn f() Void: ...` is an ordinary empty declaration: it has a body that does nothing. */
  return symbol != NULL && symbol->decl != NULL && symbol->decl->kind == MS_D_FN && symbol->decl->u.fn.bodiless &&
         call->callee.decl.module >= fn->cx->program->user_modules;
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
      fn_value_extern_call(fn, name, args, call->arg_count, ret,
                           call->type_arg_count > 0 ? fn_type(fn, call->type_args[0]) : MIR_NONE, &checked) ||
      fn_signature_extern_call(fn, name, args, call->arg_count, ret, &checked)) {
    return checked;
  }
  const uint32_t external = runtime_function(fn, &fn->cx->program->symbols.ptr[id], ret);
  const MsNativeSig *sig = ms_native_sig_find(ms_names_span(&fn->cx->module->names, name));
  const char *op = ms_native_op_find(ms_names_span(&fn->cx->module->names, name));
  if (op != NULL && fn_inline_scalar_op(fn, op, args, call->arg_count, ret, &checked)) {
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

/* `Self(fields...)` in a method of a type set: `Self` is a variable the call binds to the receiving member, so the checker
 * could not record the constructor. Build the bound member's record from the arguments, matched to its fields by label or
 * position and evaluated as written. */
static MirValue construct_self(LowerFn *fn, const MsExpr *expr) {
  const MsTyTable *types = &fn->cx->program->types;
  MsTy member = MS_TY_NONE;
  for (size_t at = 0; at < fn->subst.count; at++) {
    if (ms_span_is_text(ms_names_span(fn->cx->program->names, ms_ty_row(types, fn->subst.vars[at])->name), "Self")) {
      member = fn->subst.args[at];
    }
  }
  const MirTy ty = member == MS_TY_NONE ? MIR_NONE : fn_type(fn, member);
  const MirTyData *data = ty == MIR_NONE ? NULL : mir_ty_data(fn->cx->module, ty);
  const MirTypeDef *def = data == NULL || data->kind != MK_TYPE ? NULL : &fn->cx->module->type_defs.ptr[data->id];
  const size_t written = expr->u.call.args.len;
  if (def == NULL || def->nfields == 0 || written != def->nfields) {
    (void)fn_fail(fn, "`Self(...)` needs a record type that every argument fills");
    return MIR_NONE;
  }
  MirValue *values = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, MirValue, def->nfields);
  bool *filled = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, bool, def->nfields);
  for (size_t at = 0; at < def->nfields; at++) {
    filled[at] = false;
  }
  for (size_t at = 0; at < written; at++) {
    const MsArg *arg = &expr->u.call.args.ptr[at];
    size_t field = at;
    for (size_t index = 0; arg->has_name && index < def->nfields; index++) {
      const MsSpan label = ms_names_span(fn->cx->program->names, arg->name);
      field = ms_span_equal(label, ms_names_span(&fn->cx->module->names, def->fields[index].name)) ? index : field;
    }
    if (filled[field]) {
      (void)fn_fail(fn, "`Self(...)` fills a field twice");
      return MIR_NONE;
    }
    filled[field] = true;
    values[field] = fn_expr(fn, arg->value, LW_MOVE);
    if (values[field] == MIR_NONE) {
      return MIR_NONE;
    }
  }
  mir_b_set_loc(&fn->b, fn_loc(fn, expr->pos));
  const MirImm imm = {.tag = MI_TYPE, .a = data->id};
  return fn_emit(fn, MOP_TypeNew, values, def->nfields, imm, ty);
}

/* Where one call keeps its arguments, their `var` slots and the operands it holds: the stack for most calls, the module's
 * arena for a call of more than LOWER_MAX_ARGS arguments (a record constructor takes one per field). */
typedef struct CallBufs {
  MirValue *args, *held;
  VarSlot *slots;
} CallBufs;

static MirValue call_body(LowerFn *fn, const MsExpr *expr, CallBufs *bufs) {
  MirValue *held = bufs->held;
  const MsCall *call = fn_find_call(fn->facts, expr->id);
  if (call == NULL && expr->u.call.callee->kind == MS_E_NAME &&
      ms_span_is_text(ms_names_span(fn->cx->program->names, expr->u.call.callee->u.sym), "Self")) {
    return construct_self(fn, expr);
  }
  /* A callee that is a parameter, a local or a function-valued field, or any expression with no declaration behind it (`fs[i]()`), is a value. */
  const bool named = expr->u.call.callee->kind == MS_E_NAME;
  const bool value_callee = call == NULL || call->callee.kind == MS_REF_NONE || call->callee.kind == MS_REF_FIELD ||
                            (named && (call->callee.kind == MS_REF_PARAM || call->callee.kind == MS_REF_LOCAL));
  if (value_callee && (named || call != NULL)) {
    return fn_call_value(fn, expr, call != NULL && named && call->callee.kind != MS_REF_NONE ? &call->callee : NULL);
  }
  if (call == NULL) {
    (void)fn_fail(fn, "the checker recorded no usable call at %u:%u (node %u, %u calls)", expr->pos.line, expr->pos.column, expr->id, (unsigned)fn->facts->calls.len);
    return MIR_NONE;
  }
  MirValue *args = bufs->args;
  VarSlot *slots = bufs->slots;
  uint32_t nslots = 0;
  LowerTarget target;
  const bool source = (call->callee.kind == MS_REF_FUNCTION || call->callee.kind == MS_REF_METHOD) &&
                      fn_callee_target(fn, call, &target);
  const bool receiver_var = source && call->callee.kind == MS_REF_METHOD && (target.receiver_flags & MS_PARAM_VAR) != 0;
  /* An interface operation takes its `var` arguments in slots too: the vtable's method changes them there. */
  const bool dispatched = call->callee.kind == MS_REF_OPERATION && fn_call_callee(expr)->kind == MS_E_MEMBER &&
                          mir_ty_data(fn->cx->module, fn_type(fn, fn_read_type(fn, fn_call_callee(expr)->u.member.left)))->kind == MK_IFACE;
  if (!lower_args(fn, expr, call, args, source || dispatched ? slots : NULL, &nslots, receiver_var, !source, held)) {
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
    const MsExpr *callee = fn_call_callee(expr);
    if (call->callee.kind == MS_REF_METHOD && target.receiver != MS_TY_NONE && callee->kind == MS_E_MEMBER) {
      const MsTy actual = ms_ty_subst(&fn->cx->program->types, fn_read_type(fn, callee->u.member.left),
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
  if (!fn_adapt_function_args(fn, func, call, args)) {
    return MIR_NONE;
  }
  MirValue result = mir_b_call(&fn->b, func, args, call->arg_count);
  fn_own_result(fn, result);
  result = fn_view_as_plain(fn, result, ret);
  return fn_var_slots_back(fn, slots, nslots) ? result : MIR_NONE;
}

static MirValue call_expr(LowerFn *fn, const MsExpr *expr) {
  const MsCall *found = fn_find_call(fn->facts, expr->id);
  const uint32_t count = found != NULL && found->arg_count > LOWER_MAX_ARGS ? found->arg_count : LOWER_MAX_ARGS;
  MirValue args_small[LOWER_MAX_ARGS], held_small[LOWER_MAX_ARGS];
  VarSlot slots_small[LOWER_MAX_ARGS];
  const bool big = count > LOWER_MAX_ARGS;
  CallBufs bufs = {.args = big ? MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, MirValue, count) : args_small,
                   .held = big ? MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, MirValue, count) : held_small,
                   .slots = big ? MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, VarSlot, count) : slots_small};
  for (uint32_t at = 0; at < count; at++) {
    bufs.held[at] = MIR_NONE;
  }
  const uint32_t lent = fn->nwritebacks; /* the `var` arguments' slots, lent for this call only */
  /* A `?` in a default the call omits leaves the call, not the caller: the call is a scope of its own, and its failed
   * Result and its result meet at a join. */
  const bool exits = found != NULL && fn_call_default_tries(fn, found);
  DefaultExit exit = {.keep = fn->nopen};
  const DefaultExit *saved_call = fn->call_exit;
  const DefaultExit *saved_default = fn->default_exit;
  fn->call_exit = NULL;
  MirValue joined = MIR_NONE;
  if (exits) {
    exit.ret = fn_type(fn, ms_facts_type(fn->facts, expr->id));
    exit.join = mir_b_new_block(&fn->b);
    joined = mir_b_add_block_param(&fn->b, exit.join, exit.ret, MM_MOVE);
    (void)fn_scope_begin(fn);
    fn->call_exit = &exit;
  }
  fn->receiver_slot = MIR_NONE;
  MirValue result = call_body(fn, expr, &bufs);
  fn->receiver_slot = MIR_NONE;
  fn->call_exit = saved_call;
  fn->default_exit = saved_default;
  fn->nwritebacks = lent;
  /* A fault the operation posted leaves while the held slots still own their values: the exit closes them. */
  bool holding = false;
  for (uint32_t at = 0; at < count; at++) {
    holding |= bufs.held[at] != MIR_NONE;
  }
  if (holding) {
    fn_unwind_site(fn, result);
  }
  for (uint32_t at = 0; at < count && !fn->terminated; at++) {
    if (bufs.held[at] != MIR_NONE) { /* the operation took it: nothing is left to close */
      (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &bufs.held[at], 1, (MirImm){0}, MIR_NONE);
    }
  }
  if (!exits) {
    return result;
  }
  if (result == MIR_NONE || fn->terminated || fn->failed) {
    return MIR_NONE;
  }
  if (mir_b_ty(&fn->b, result) != exit.ret) {
    (void)fn_fail(fn, "a call whose default uses `?` must return a Result");
    return MIR_NONE;
  }
  if (mir_needs_drop(fn->cx->module, exit.ret)) {
    (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &result, 1, (MirImm){0}, MIR_NONE);
  }
  fn_scope_unwind(fn, exit.keep);
  mir_b_br(&fn->b, exit.join, &result, 1);
  mir_b_seal_block(&fn->b, exit.join);
  mir_b_switch_to(&fn->b, exit.join);
  fn_scope_pop(fn);
  if (mir_needs_drop(fn->cx->module, exit.ret)) {
    fn_own(fn, fn_scope(fn), joined);
  }
  return joined;
}

/* Whether `expr` is a call typed `Never`: it does not return. The call's own result type counts, not the checked type of the
 * expression, which may be the one the context expects. */
bool fn_call_never(const LowerFn *fn, const MsExpr *expr) {
  if (expr->kind != MS_E_CALL) {
    return false;
  }
  const MsCall *call = fn_find_call(fn->facts, expr->id);
  const MsTyTable *types = &fn->cx->program->types;
  MsTy ty = ms_facts_type(fn->facts, expr->id);
  if (call != NULL && call->callee_ty != MS_TY_NONE && ms_ty_kind(types, call->callee_ty) == MS_TY_FUNCTION) {
    ty = ms_ty_result(types, call->callee_ty);
  }
  return ty != MS_TY_NONE && ms_ty_is(types, ty, MS_BUILTIN_Never);
}

/* A call typed `Never` does not return: the block ends there, so a match arm that panics adds no edge to the join. */
MirValue fn_call(LowerFn *fn, const MsExpr *expr, LowerWant want) {
  (void)want;
  const MirValue result = call_expr(fn, expr);
  if (!fn->failed && !fn->terminated && fn_call_never(fn, expr)) {
    fn_unwind_exit(fn); /* a call that does not return leaves by a posted fault */
    const MirBlock dead = mir_b_new_block(&fn->b); /* what the rest of the expression emits goes nowhere */
    mir_b_seal_block(&fn->b, dead);
    mir_b_switch_to(&fn->b, dead);
    fn->terminated = true;
  }
  return result;
}
