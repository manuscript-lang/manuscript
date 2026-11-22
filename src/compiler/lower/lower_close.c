/* compiler/lower/lower_close.c: resources closed where their scope ends. A local whose type implements Closeable
 * (the `closers` fact) lives in a memory slot owned by its scope (`scope.own S K slot`, K = the close thunk + 2);
 * drop elaboration closes it on every path that still holds it. The thunks take the slot's address, so the same
 * close serves the scope end and an unwinding fault. A fallible close hands its Result to the function's close
 * exit, which returns the error, or faults when the function has no error to return. */
#include "compiler/lower/lower_fn.h"
#include "compiler/mir/mir_analysis.h"
#include "compiler/own/closers.h"

enum { OK_CASE = 0, ERR_CASE = 1 };
static const char *const NO_ERROR_MESSAGE = "a resource could not be closed: its close returned an error";

static MirImm imm_ty(MirTy ty) {
  return (MirImm){.tag = MI_TY, .a = ty};
}

static MsName named(Lower *cx, const char *base, uint32_t first, uint32_t second) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_printf(&text, "%s.%u.%u", base, first, second);
  const MsName name = mir_name(cx->module, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  return name;
}

/* ---- close thunks: `fn(slot: ptr)` ---- */

/* The value in the slot at `slot`, taken out when it owns something. */
static MirValue take_from(MirBuilder *b, MirValue slot, MirTy ty, bool owns) {
  return mir_b_emit(b, owns ? MOP_Take : MOP_Load, &slot, 1, imm_ty(ty), ty);
}

/* `fn(slot)`: closes the value the slot holds. `result` returns the close's own result, else it is dropped. */
static uint32_t add_thunk(Lower *cx, MsName name, uint32_t method, MirTy ty, bool result) {
  MirModule *module = cx->module;
  const MirTy method_ret = module->funcs.ptr[method].ret;
  MirBuilder b;
  const MirParam param = {MIR_PTR, (uint8_t)MM_BORROW};
  mir_b_init(&b, module, name, &param, 1, result ? method_ret : MIR_VOID);
  b.func.linkage = ML_INTERNAL;
  MirValue slot = MIR_NONE;
  mir_b_params(&b, &slot, 1);
  const MirValue value = take_from(&b, slot, ty, mir_needs_drop(module, ty));
  const MirValue closed = mir_b_call(&b, method, &value, 1);
  if (result) {
    mir_b_ret(&b, closed);
  } else {
    if (closed != MIR_NONE && mir_needs_drop(module, method_ret)) {
      (void)mir_b_emit(&b, MOP_Drop, &closed, 1, (MirImm){0}, MIR_NONE);
    }
    mir_b_ret(&b, mir_b_unit(&b));
  }
  uint32_t id = MIR_NONE;
  return mir_b_finish(&b, &id) ? id : MIR_NONE;
}

static bool result_def(const MirModule *module, MirTy ty, const MirAltDef **def) {
  const MirTyData *data = mir_ty_data(module, ty);
  if (data->kind != MK_ALT || module->alts.ptr[data->id].std != MSTD_RESULT) {
    return false;
  }
  *def = &module->alts.ptr[data->id];
  return true;
}

/* The silent thunk of `method` on `ty` and, for a fallible close, the thunk that returns its Result. */
static bool close_thunks(Lower *cx, uint32_t method, MirTy ty, uint32_t *silent) {
  const MsName name = named(cx, "close.slot", method, 0);
  *silent = mir_func_by_name(cx->module, name);
  if (*silent != MIR_NONE) {
    return true;
  }
  const MirAltDef *def = NULL;
  const bool fallible = result_def(cx->module, cx->module->funcs.ptr[method].ret, &def);
  uint32_t result = MIR_NONE;
  if (fallible) {
    result = add_thunk(cx, named(cx, "close.result", method, 0), method, ty, true);
    if (result == MIR_NONE) {
      return false;
    }
  }
  *silent = add_thunk(cx, name, method, ty, false);
  if (*silent == MIR_NONE) {
    return false;
  }
  if (fallible) {
    cx->module->funcs.ptr[*silent].has_slot_result = true;
    cx->module->funcs.ptr[*silent].slot_result = result;
  }
  return true;
}

/* ---- close exits: the error edge of a failing close ---- */

/* The error a failed close `Result` carries, as a `Result` of the function's type. The outcome's other parts are
 * released: nothing else holds them. */
static MirValue convert(MirBuilder *b, MirModule *module, MirValue outcome, uint32_t from, MirTy ret, uint32_t to) {
  const MirTy error = module->alts.ptr[from].cases[ERR_CASE].fields[0].ty;
  const bool owns = mir_needs_drop(module, error);
  const MirImm field = {.tag = MI_ALTFIELD, .a = from, .b = ERR_CASE, .c = 0};
  const MirValue payload = mir_b_emit(b, owns ? MOP_AltTake : MOP_AltGet, &outcome, 1, field, error);
  if (owns) {
    const MirImm taken = {.tag = MI_ALTMASK, .a = from, .b = ERR_CASE, .c = 1};
    (void)mir_b_emit(b, MOP_AltRelease, &outcome, 1, taken, MIR_NONE);
  }
  const MirImm failed = {.tag = MI_CASE, .a = to, .b = ERR_CASE};
  return mir_b_emit(b, MOP_AltNew, &payload, 1, failed, ret);
}

/* `fn(move outcome [, move pending]) -> ret`: the function's result for a failed close, `outcome` being the
 * close's `Result`. A function returning a Result with the same error type returns that error (the pending result
 * wins when it already failed); any other function faults, since the close has nowhere to return its error. */
static uint32_t add_exit(Lower *cx, MirTy ret, MirTy outcome_ty, bool pending) {
  MirModule *module = cx->module;
  const MsName name = named(cx, pending ? "close.exit.pending" : "close.exit", ret, outcome_ty);
  const uint32_t found = mir_func_by_name(module, name);
  if (found != MIR_NONE) {
    return found;
  }
  const MirAltDef *from = NULL, *to = NULL;
  const bool known = result_def(module, outcome_ty, &from) && from->cases[ERR_CASE].nfields > 0;
  const bool returns = known && result_def(module, ret, &to) && to->cases[ERR_CASE].nfields > 0 &&
                       to->cases[ERR_CASE].fields[0].ty == from->cases[ERR_CASE].fields[0].ty;
  const MirParam params[2] = {{outcome_ty, (uint8_t)MM_MOVE}, {ret, (uint8_t)MM_MOVE}};
  MirBuilder b;
  mir_b_init(&b, module, name, params, pending ? 2 : 1, ret);
  b.func.linkage = ML_INTERNAL;
  MirValue values[2] = {MIR_NONE, MIR_NONE};
  mir_b_params(&b, values, pending ? 2 : 1);
  const MirImm none = {0};
  if (returns) {
    if (pending) {
      const MirValue tag = mir_b_emit(&b, MOP_AltTag, &values[1], 1, none, MIR_INT);
      const MirValue is_error = mir_b_icmp(&b, MCC_EQ, tag, mir_b_iconst(&b, ERR_CASE));
      const MirBlock keep = mir_b_new_block(&b);
      const MirBlock replace = mir_b_new_block(&b);
      mir_b_br_if(&b, is_error, keep, NULL, 0, replace, NULL, 0);
      mir_b_seal_block(&b, keep);
      mir_b_seal_block(&b, replace);
      mir_b_switch_to(&b, keep);
      (void)mir_b_emit(&b, MOP_Drop, &values[0], 1, none, MIR_NONE);
      mir_b_ret(&b, values[1]);
      mir_b_switch_to(&b, replace);
      (void)mir_b_emit(&b, MOP_Drop, &values[1], 1, none, MIR_NONE);
    }
    mir_b_ret(&b, convert(&b, module, values[0], (uint32_t)(from - module->alts.ptr), ret, (uint32_t)(to - module->alts.ptr)));
  } else {
    for (uint32_t at = 0; at < (pending ? 2u : 1u); at++) {
      (void)mir_b_emit(&b, MOP_Drop, &values[at], 1, none, MIR_NONE);
    }
    const MirBlock block = b.cur;
    mir_b_fault(&b, MF_MESSAGE);
    b.func.blocks.ptr[block].term.fault_str = (uint32_t)ms_names_intern(&module->strings, ms_span_of_text(NO_ERROR_MESSAGE));
  }
  uint32_t id = MIR_NONE;
  return mir_b_finish(&b, &id) ? id : MIR_NONE;
}

/* The function's close exits, made on its first fallible resource; `outcome_ty` is the close's `Result`. */
static bool ensure_exits(LowerFn *fn, MirTy outcome_ty) {
  if (fn->b.func.has_close_exit) {
    return true;
  }
  const uint32_t plain = add_exit(fn->cx, fn->ret, outcome_ty, false);
  const uint32_t pending = add_exit(fn->cx, fn->ret, outcome_ty, true);
  if (plain == MIR_NONE || pending == MIR_NONE) {
    return fn_fail(fn, "the close exit functions were not built");
  }
  fn->b.func.has_close_exit = true;
  fn->b.func.close_exit[0] = plain;
  fn->b.func.close_exit[1] = pending;
  return true;
}

/* ---- the binding ---- */

static bool lowerable(uint8_t flags) {
  return (flags & MS_CLOSER_CONSUMES) != 0 &&
         (flags & (MS_CLOSER_WRITES_BACK | MS_CLOSER_PARTIAL)) == 0;
}

bool fn_closer_for(LowerFn *fn, const MsCloser *closer, MsTy checked) {
  if (closer == NULL || fn->closing == NULL) {
    return false;
  }
  if ((closer->flags & MS_CLOSER_GENERIC) == 0) {
    return lowerable(closer->flags);
  }
  /* A type variable closes only in the instances whose type does. */
  MsCloser instance;
  const MsTy ty = ms_ty_subst(&fn->cx->program->types, checked, fn->subst.vars, fn->subst.args, fn->subst.count);
  return ms_own_closer_of(fn->cx->program, ty, &instance) &&
         lowerable((uint8_t)((closer->flags & ~MS_CLOSER_GENERIC) | instance.flags));
}

/* Puts `value` in a fresh slot owned by the innermost scope and returns the slot; `owns` says it needs a drop. */
static MirValue own_slot(LowerFn *fn, MirTy ty, MirValue value, uint32_t silent) {
  const MirImm none = {0};
  const bool owns = mir_needs_drop(fn->cx->module, ty);
  const MirValue slot = mir_b_emit(&fn->b, MOP_Slot, NULL, 0, imm_ty(ty), MIR_PTR);
  const MirValue stored[2] = {slot, value};
  (void)mir_b_emit(&fn->b, owns ? MOP_Put : MOP_Store, stored, 2, none, MIR_NONE);
  const MirImm own = {.tag = MI_SCOPE, .a = fn_scope(fn), .b = silent + 2};
  (void)mir_b_emit(&fn->b, MOP_ScopeOwn, &slot, 1, own, MIR_NONE);
  return slot;
}

/* The silent close thunk for the type `checked` (in the function's terms), with its exits made. */
static bool prepare(LowerFn *fn, MsTy checked, MirTy ty, uint32_t *silent) {
  Lower *cx = fn->cx;
  const uint32_t method = lower_named_method(cx, ms_ty_subst(&cx->program->types, checked, fn->subst.vars, fn->subst.args, fn->subst.count), "close");
  if (method == MIR_NONE || !close_thunks(cx, method, ty, silent)) {
    return fn_fail(fn, "the close of a resource binding could not be lowered");
  }
  const MirAltDef *def = NULL;
  if (result_def(cx->module, cx->module->funcs.ptr[method].ret, &def) && !ensure_exits(fn, cx->module->funcs.ptr[method].ret)) {
    return false;
  }
  return true;
}

bool fn_own_param(LowerFn *fn, uint32_t index, MsTy checked, MirValue value, MirVar var) {
  const MirTy ty = mir_b_ty(&fn->b, value);
  uint32_t silent = MIR_NONE;
  if (!prepare(fn, checked, ty, &silent)) {
    return false;
  }
  const MirValue slot = own_slot(fn, ty, value, silent);
  const MirValue view = mir_b_emit(&fn->b, MOP_Load, &slot, 1, imm_ty(ty), ty);
  mir_b_def_var(&fn->b, var, view);
  fn->closing[fn->nvars + index] = slot;
  return !fn->failed;
}

bool fn_bind_closing(LowerFn *fn, uint32_t local, MsTy checked, MirValue value, bool is_var) {
  const MirTy ty = mir_b_ty(&fn->b, value);
  uint32_t silent = MIR_NONE;
  if (!prepare(fn, checked, ty, &silent)) {
    return false;
  }
  if (mir_needs_drop(fn->cx->module, ty)) {
    (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &value, 1, (MirImm){0}, MIR_NONE);
  }
  const MirValue slot = own_slot(fn, ty, value, silent);
  fn->closing[local] = slot;
  fn->closing_var[local] = is_var;
  fn->closing_types[local] = ty;
  if (!is_var) {
    const MirValue view = mir_b_emit(&fn->b, MOP_Load, &slot, 1, imm_ty(ty), ty);
    mir_b_def_var(&fn->b, fn_local(fn, local, ty), view);
  }
  return !fn->failed;
}

/* The slot of the `var` resource a local reference names, or MIR_NONE. */
static MirValue var_slot_of(const LowerFn *fn, const MsRef *ref) {
  if (fn->closing == NULL || ref == NULL || ref->kind != MS_REF_LOCAL || ref->local >= fn->nvars ||
      !fn->closing_var[ref->local]) {
    return MIR_NONE;
  }
  return fn->closing[ref->local];
}

bool fn_closing_read(LowerFn *fn, const MsRef *ref, MirValue *view) {
  const MirValue slot = var_slot_of(fn, ref);
  if (slot == MIR_NONE) {
    return false;
  }
  const MirTy ty = fn->closing_types[ref->local];
  *view = mir_b_emit(&fn->b, MOP_Load, &slot, 1, imm_ty(ty), ty);
  return true;
}

bool fn_closing_assign(LowerFn *fn, const MsRef *ref, MirValue value, bool *done) {
  const MirValue slot = var_slot_of(fn, ref);
  *done = slot != MIR_NONE;
  if (slot == MIR_NONE) {
    return true;
  }
  const MirTy ty = mir_b_ty(&fn->b, value);
  const bool owns = mir_needs_drop(fn->cx->module, ty);
  if (owns) {
    (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &value, 1, (MirImm){0}, MIR_NONE);
  }
  /* The slot closes what it holds, and holds the new value from here. */
  const MirImm refill = {.tag = MI_INT, .i = 2};
  (void)mir_b_emit(&fn->b, MOP_ScopeMark, &slot, 1, refill, MIR_NONE);
  const MirValue stored[2] = {slot, value};
  (void)mir_b_emit(&fn->b, owns ? MOP_Put : MOP_Store, stored, 2, (MirImm){0}, MIR_NONE);
  return !fn->failed;
}

bool fn_closing_move(LowerFn *fn, const MsExpr *name, MirValue view, MirValue *taken) {
  const MsRef *ref = ms_facts_ref(fn->facts, name->id);
  if (fn->closing == NULL || ref == NULL || (ref->kind != MS_REF_LOCAL && ref->kind != MS_REF_PARAM) ||
      ms_facts_use(fn->facts, name->id) != MS_USE_MOVE) {
    return false;
  }
  const uint32_t at = ref->kind == MS_REF_LOCAL ? ref->local : fn->nvars + ref->local;
  if (at >= fn->nvars + LOWER_MAX_CLOSING_PARAMS || fn->closing[at] == MIR_NONE) {
    return false;
  }
  /* The slot gives its value up: its scope no longer closes it, the consumer owns what is taken. */
  const MirValue slot = fn->closing[at];
  const MirTy ty = mir_b_ty(&fn->b, view);
  (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &slot, 1, (MirImm){0}, MIR_NONE);
  *taken = fn_emit(fn, mir_needs_drop(fn->cx->module, ty) ? MOP_Take : MOP_Load, &slot, 1, imm_ty(ty), ty);
  return true;
}
