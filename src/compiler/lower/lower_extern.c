/* compiler/lower/lower_extern.c: calls to extern declarations whose runtime function takes more than the written
 * operands: a status and an out slot (`T!`), the shape table of the value it reads, or the descriptor and address
 * of a generic value. The extern's `ms-sig` header says which. */
#include "compiler/lower/lower_fn.h"
#include "compiler/lower/native_sigs.h"
#include "compiler/mir/mir_analysis.h"

/* ---- externs that return `T!` ---- */

/* The stdlib function that builds the `Error` of a failed status, or MIR_NONE when core is not loaded. */
static uint32_t status_error_function(LowerFn *fn) {
  Lower *cx = fn->cx;
  const MsSymbolList *symbols = &cx->program->symbols;
  for (MsSymbolId id = 1; id < symbols->len; id++) {
    const MsSymbol *symbol = &symbols->ptr[id];
    if (symbol->kind == MS_SYMBOL_FN && symbol->native == MS_NATIVE_SOURCE &&
        ms_span_is_text(ms_names_span(cx->program->names, symbol->name), "msstd_status_error")) {
      const LowerTarget target = lower_symbol_target(cx, id);
      return lower_instance(cx, &target, NULL, 0, &fn->subst);
    }
  }
  return MIR_NONE;
}

static MirValue stack_slot(LowerFn *fn, MirTy ty) {
  const MirImm of_type = {.tag = MI_TY, .a = ty};
  return mir_b_emit(&fn->b, MOP_Slot, NULL, 0, of_type, MIR_PTR);
}

static MirValue string_span_literal(LowerFn *fn, MsSpan text) {
  const MirImm imm = {.tag = MI_STR, .a = mir_add_string(fn->cx->module, text)};
  return mir_b_emit(&fn->b, MOP_StrLit, NULL, 0, imm, MIR_STR);
}

static MirValue string_literal(LowerFn *fn, const char *text) {
  return string_span_literal(fn, ms_span_of_text(text));
}

/* The Result alternative of `ret` and its ok payload type, or false when `ret` is not a Result. */
static bool result_alt(const LowerFn *fn, MirTy ret, uint32_t *alt, MirTy *payload) {
  const MirModule *module = fn->cx->module;
  const MirTyData *data = mir_ty_data(module, ret);
  if (data->kind != MK_ALT || module->alts.ptr[data->id].std != MSTD_RESULT) {
    return false;
  }
  const MirCaseDef *ok = &module->alts.ptr[data->id].cases[0];
  *alt = data->id;
  *payload = ok->nfields > 0 ? ok->fields[0].ty : MIR_VOID;
  return true;
}

static MirValue build_result(LowerFn *fn, uint32_t alt, uint32_t which, MirValue payload, MirTy ret) {
  const MirImm imm = {.tag = MI_CASE, .a = alt, .b = which};
  return mir_b_emit(&fn->b, MOP_AltNew, &payload, 1, imm, ret);
}

/* How the native's declaration words a status: its `@words=<status> "<text>"` annotation as one `<status> <text>`
 * line ("" when it has none, or the native is the runtime's own). */
static MirValue status_words_text(LowerFn *fn, const MsDecl *decl) {
  if (decl == NULL || decl->kind != MS_D_FN || decl->u.fn.words_status == 0) {
    return string_literal(fn, "");
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_printf(&text, "%u ", decl->u.fn.words_status);
  ms_strbuild_append(&text, decl->u.fn.words_text);
  MsString owned = ms_strbuild_finish(&text);
  const MirValue literal = string_span_literal(fn, ms_string_span(&owned));
  ms_string_release(&owned);
  return literal;
}

bool fn_status_call(LowerFn *fn, MsName name, const MsDecl *decl, const MirValue *args, uint32_t nargs, MirTy ret,
                    MirValue *out) {
  uint32_t alt = 0;
  MirTy payload_ty = MIR_VOID;
  const MsNativeSig *sig = ms_native_sig_find(ms_names_span(&fn->cx->module->names, name));
  if (sig == NULL || !sig->status || !result_alt(fn, ret, &alt, &payload_ty) || nargs + 2 > NS_MAX_PARAMS) {
    return false;
  }
  const bool has_err = sig->count > 0 && sig->kinds[sig->count - 1] == NS_ERR_SLOT;
  const bool has_out = payload_ty != MIR_VOID;
  const uint32_t tail = (has_err ? 1u : 0u) + (has_out ? 1u : 0u);
  if (sig->count < tail) {
    return false;
  }
  const uint32_t error_function = status_error_function(fn);
  if (error_function == MIR_NONE) {
    return false;
  }
  MirValue wanted[NS_MAX_PARAMS];
  uint32_t count = 0;
  uint32_t source = 0;
  uint32_t shape_at = NS_MAX_PARAMS;
  MirTy shape_ty = payload_ty;
  bool shape_from_operand = false;
  bool by_shape = false;
  for (uint32_t at = 0; at < sig->count; at++) {
    by_shape = by_shape || sig->kinds[at] == NS_SHAPE;
  }
  for (uint32_t at = 0; at < sig->count - tail; at++) {
    const uint8_t kind = sig->kinds[at];
    if (count + 4 > NS_MAX_PARAMS) {
      return false;
    }
    if (kind == NS_SHAPE) {
      shape_at = count++;
    } else if (kind == NS_HAS_RAW && source < nargs) {
      const MirValue operand = args[source++];
      const MirTyData *record = mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, operand));
      if (record->kind != MK_TYPE) {
        if (!fn_has_raw_pair(fn, operand, &wanted[count])) {
          return false;
        }
        count += 2;
        at++;
        continue;
      }
      /* A record of optional Ints (`JsonLimits`) is one operand for one pair per field. */
      const MirTypeDef *def = &fn->cx->module->type_defs.ptr[record->id];
      for (uint32_t field = 0; field < def->nfields; field++) {
        if (at + 1 >= sig->count - tail || sig->kinds[at] != NS_HAS_RAW || count + 4 > NS_MAX_PARAMS) {
          return false;
        }
        const MirImm imm = {.tag = MI_FIELD, .a = record->id, .b = field};
        const MirValue value = mir_b_emit(&fn->b, MOP_TypeGet, &operand, 1, imm, def->fields[field].ty);
        if (!fn_has_raw_pair(fn, value, &wanted[count])) {
          return false;
        }
        count += 2;
        at += 2;
      }
      at--;
    } else if (kind == NS_ADDR_IN && by_shape && source < nargs) {
      const MirValue operand = args[source++];
      const MirTy ty = mir_b_ty(&fn->b, operand);
      if (!shape_from_operand) {
        shape_ty = ty;
        shape_from_operand = true;
      }
      const MirImm of_type = {.tag = MI_TY, .a = ty};
      const MirValue slot = mir_b_emit(&fn->b, MOP_Slot, NULL, 0, of_type, MIR_PTR);
      const MirValue store[2] = {slot, operand};
      (void)mir_b_emit(&fn->b, MOP_Store, store, 2, (MirImm){0}, MIR_NONE);
      wanted[count++] = slot;
    } else if (source < nargs) {
      wanted[count++] = args[source++];
    } else {
      return false;
    }
  }
  if (source != nargs) {
    return false;
  }
  if (shape_at != NS_MAX_PARAMS) {
    const MirImm of_type = {.tag = MI_TY, .a = shape_ty};
    wanted[shape_at] = mir_b_emit(&fn->b, MOP_Shape, NULL, 0, of_type, MIR_PTR);
  }
  MirValue out_slot = MIR_NONE;
  MirValue err_slot = MIR_NONE;
  if (has_out) {
    out_slot = stack_slot(fn, payload_ty);
    wanted[count++] = out_slot;
  }
  if (has_err) {
    err_slot = stack_slot(fn, MIR_STR);
    const MirValue empty = string_literal(fn, "");
    const MirValue store[2] = {err_slot, empty};
    (void)mir_b_emit(&fn->b, MOP_Store, store, 2, (MirImm){0}, MIR_NONE);
    wanted[count++] = err_slot;
  }
  const uint32_t external = fn_runtime_extern(fn, name, wanted, count, MIR_UINT8);
  const MirValue status = mir_b_call_rt(&fn->b, external, wanted, count);
  const MirValue zero = mir_b_emit(&fn->b, MOP_IConst, NULL, 0, (MirImm){.tag = MI_INT, .i = 0}, MIR_UINT8);
  const MirValue failed = mir_b_icmp(&fn->b, MCC_NE, status, zero);
  const MirBlock ok_block = mir_b_new_block(&fn->b);
  const MirBlock fail_block = mir_b_new_block(&fn->b);
  const MirBlock join = mir_b_new_block(&fn->b);
  const MirValue result = mir_b_add_block_param(&fn->b, join, ret, MM_MOVE);
  mir_b_br_if(&fn->b, failed, fail_block, NULL, 0, ok_block, NULL, 0);
  mir_b_seal_block(&fn->b, ok_block);
  mir_b_seal_block(&fn->b, fail_block);
  mir_b_switch_to(&fn->b, ok_block);
  MirValue value = mir_b_unit(&fn->b);
  if (has_out) {
    const MirImm of_type = {.tag = MI_TY, .a = payload_ty};
    value = mir_b_emit(&fn->b, mir_needs_drop(fn->cx->module, payload_ty) ? MOP_Take : MOP_Load, &out_slot, 1, of_type,
                       payload_ty);
  }
  const MirValue success = build_result(fn, alt, 0, value, ret);
  mir_b_br(&fn->b, join, &success, 1);
  mir_b_switch_to(&fn->b, fail_block);
  MirValue said = string_literal(fn, "");
  if (has_err) {
    const MirImm of_type = {.tag = MI_TY, .a = MIR_STR};
    said = mir_b_emit(&fn->b, MOP_Take, &err_slot, 1, of_type, MIR_STR);
  }
  const char *domain_text = sig->domain != NULL ? sig->domain : "runtime";
  const MirValue error_args[4] = {status, string_literal(fn, domain_text), said, status_words_text(fn, decl)};
  const MirValue error = mir_b_call(&fn->b, error_function, error_args, 4);
  const MirValue failure = build_result(fn, alt, 1, error, ret);
  mir_b_br(&fn->b, join, &failure, 1);
  mir_b_seal_block(&fn->b, join);
  mir_b_switch_to(&fn->b, join);
  if (mir_needs_drop(fn->cx->module, ret)) {
    fn_own(fn, fn_scope(fn), result);
  }
  *out = result;
  return true;
}

/* ---- externs that read a value through its shape ---- */

/* `msstd_test_repr[T](value)`: a native whose first parameter is the shape table gets the table of its first
 * operand's type, and an operand it reads through an address goes into a slot (a borrow). False when `sig` does not
 * take a shape table. */
bool fn_shape_extern_call(LowerFn *fn, MsName name, const MirValue *args, uint32_t nargs, MirTy ret, MirValue *out) {
  const MsNativeSig *sig = ms_native_sig_find(ms_names_span(&fn->cx->module->names, name));
  if (sig == NULL || sig->status || sig->count == 0 || sig->kinds[0] != NS_SHAPE || nargs == 0 || nargs + 2 > NS_MAX_PARAMS) {
    return false;
  }
  const MirTy shape_ty = mir_b_ty(&fn->b, args[0]);
  const MirImm shape_type = {.tag = MI_TY, .a = shape_ty};
  MirValue wanted[NS_MAX_PARAMS];
  uint32_t count = 0;
  wanted[count++] = mir_b_emit(&fn->b, MOP_Shape, NULL, 0, shape_type, MIR_PTR);
  for (uint32_t source = 0; source < nargs; source++) {
    const MirTy ty = mir_b_ty(&fn->b, args[source]);
    if (count < sig->count && sig->kinds[count] == NS_ADDR_IN) {
      const MirImm of_type = {.tag = MI_TY, .a = ty};
      const MirValue slot = mir_b_emit(&fn->b, MOP_Slot, NULL, 0, of_type, MIR_PTR);
      const MirValue store[2] = {slot, args[source]};
      (void)mir_b_emit(&fn->b, MOP_Store, store, 2, (MirImm){0}, MIR_NONE);
      wanted[count++] = slot;
    } else {
      wanted[count++] = args[source];
    }
  }
  *out = fn_runtime_call(fn, name, wanted, count, ret);
  return true;
}

/* ---- externs that move one value of a generic type in or out ---- */

/* A generic value `msrt_promise_put[T](id, move value: T, failed)` hands the runtime the address of an owned slot
 * holding the value and the descriptor of its type; `msrt_promise_take[T](id) T?` gets a slot of the payload type
 * and answers whether it filled it. Returns false when `sig` takes no value descriptor. */
bool fn_value_extern_call(LowerFn *fn, MsName name, const MirValue *args, uint32_t nargs, MirTy ret, MirValue *out) {
  const MsNativeSig *sig = ms_native_sig_find(ms_names_span(&fn->cx->module->names, name));
  if (sig == NULL || sig->count > NS_MAX_PARAMS) {
    return false;
  }
  bool described = false;
  for (uint32_t at = 0; at < sig->count; at++) {
    described = described || sig->kinds[at] == NS_VALUE_DESC || sig->kinds[at] == NS_SHAPE;
  }
  if (!described) {
    return false;
  }
  const MirTyData *optional = mir_ty_data(fn->cx->module, ret);
  const bool takes_out = optional->kind == MK_OPT && sig->count > 0 && sig->kinds[sig->count - 1] == NS_ADDR_MUT;
  MirValue wanted[NS_MAX_PARAMS];
  uint32_t used = 0;
  uint32_t next = 0;
  MirTy value_ty = takes_out ? optional->elem : MIR_NONE;
  MirValue out_slot = MIR_NONE;
  uint32_t shape_at = NS_MAX_PARAMS;
  for (uint32_t at = 0; at < sig->count; at++) {
    const uint8_t kind = sig->kinds[at];
    if (kind == NS_SHAPE) {
      shape_at = used++; /* the table of the value the next address operand holds, filled once its type is known */
    } else if (kind == NS_ADDR_IN && shape_at != NS_MAX_PARAMS && next < nargs) {
      /* A borrowed value read through the shape table: it goes into a slot of its own. */
      value_ty = mir_b_ty(&fn->b, args[next]);
      const MirValue slot = stack_slot(fn, value_ty);
      const MirValue stored[2] = {slot, args[next++]};
      (void)mir_b_emit(&fn->b, MOP_Store, stored, 2, (MirImm){0}, MIR_NONE);
      wanted[used++] = slot;
    } else if (kind == NS_STR_MUT && shape_at != NS_MAX_PARAMS && at + 1 == sig->count && ret == MIR_STR) {
      continue; /* the String result the runtime writes */
    } else if (kind == NS_VALUE_DESC) {
      if (value_ty == MIR_NONE) {
        for (uint32_t scan = at; scan < sig->count && value_ty == MIR_NONE; scan++) {
          value_ty = sig->kinds[scan] == NS_ADDR_MUT && next < nargs ? mir_b_ty(&fn->b, args[next]) : MIR_NONE;
        }
        if (value_ty == MIR_NONE && next < nargs) {
          value_ty = mir_b_ty(&fn->b, args[next]);
        }
      }
      const MirImm imm = {.tag = MI_TY, .a = value_ty};
      wanted[used++] = mir_b_emit(&fn->b, MOP_TypeDesc, NULL, 0, imm, MIR_PTR);
    } else if (takes_out && at + 1 == sig->count) {
      out_slot = stack_slot(fn, value_ty);
      wanted[used++] = out_slot;
    } else if (kind == NS_ADDR_MUT && next < nargs) {
      const MirTy ty = mir_b_ty(&fn->b, args[next]);
      value_ty = ty;
      const MirImm of_type = {.tag = MI_TY, .a = ty};
      const MirValue slot = mir_b_emit(&fn->b, MOP_Slot, NULL, 0, of_type, MIR_PTR);
      const MirValue stored[2] = {slot, args[next++]};
      (void)mir_b_emit(&fn->b, mir_needs_drop(fn->cx->module, ty) ? MOP_Put : MOP_Store, stored, 2, (MirImm){0}, MIR_NONE);
      wanted[used++] = slot;
    } else if (next < nargs) {
      wanted[used++] = args[next++];
    } else {
      return false;
    }
  }
  if (next != nargs) {
    return false;
  }
  if (shape_at != NS_MAX_PARAMS) {
    const MirImm of_type = {.tag = MI_TY, .a = value_ty};
    wanted[shape_at] = mir_b_emit(&fn->b, MOP_Shape, NULL, 0, of_type, MIR_PTR);
  }
  if (!takes_out) {
    *out = fn_runtime_call(fn, name, wanted, used, ret);
    return true;
  }
  const uint32_t external = fn_runtime_extern(fn, name, wanted, used, MIR_UINT8);
  const MirValue status = mir_b_call_rt(&fn->b, external, wanted, used);
  const MirValue zero = mir_b_emit(&fn->b, MOP_IConst, NULL, 0, (MirImm){.tag = MI_INT, .i = 0}, MIR_UINT8);
  const MirValue present = mir_b_icmp(&fn->b, MCC_NE, status, zero);
  const MirBlock some_block = mir_b_new_block(&fn->b);
  const MirBlock none_block = mir_b_new_block(&fn->b);
  const MirBlock join = mir_b_new_block(&fn->b);
  const MirValue result = mir_b_add_block_param(&fn->b, join, ret, MM_MOVE);
  mir_b_br_if(&fn->b, present, some_block, NULL, 0, none_block, NULL, 0);
  mir_b_seal_block(&fn->b, some_block);
  mir_b_seal_block(&fn->b, none_block);
  mir_b_switch_to(&fn->b, some_block);
  const MirImm of_type = {.tag = MI_TY, .a = value_ty};
  const MirValue value = mir_b_emit(&fn->b, mir_needs_drop(fn->cx->module, value_ty) ? MOP_Take : MOP_Load, &out_slot, 1,
                                    of_type, value_ty);
  const MirValue some = mir_b_emit(&fn->b, MOP_OptSome, &value, 1, (MirImm){0}, ret);
  mir_b_br(&fn->b, join, &some, 1);
  mir_b_switch_to(&fn->b, none_block);
  const MirValue none = mir_b_emit(&fn->b, MOP_OptNone, NULL, 0, (MirImm){0}, ret);
  mir_b_br(&fn->b, join, &none, 1);
  mir_b_seal_block(&fn->b, join);
  mir_b_switch_to(&fn->b, join);
  if (mir_needs_drop(fn->cx->module, ret)) {
    fn_own(fn, fn_scope(fn), result);
  }
  *out = result;
  return true;
}
