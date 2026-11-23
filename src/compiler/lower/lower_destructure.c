/* compiler/lower/lower_destructure.c: the names of a record or list pattern bind to the parts of a value. */
#include "compiler/check/properties.h"
#include "compiler/lower/lower_fn.h"
#include "compiler/own/closers.h"
#include "compiler/mir/mir_analysis.h"

void fn_disown(LowerFn *fn, MirValue value) {
  (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &value, 1, (MirImm){0}, MIR_NONE);
}

/* Binds the names of `pattern` to the parts of `value`: a record pattern reads fields, a list pattern reads
 * elements. The parts are borrowed from `value`, which the binding's source keeps alive. */
bool fn_bind_parts(LowerFn *fn, const MsPattern *pattern, MirValue value, bool owned, const MirVar *owner,
                       bool reassignable, bool part_owned, MsTy checked_record) {
  const MirModule *module = fn->cx->module;
  if (pattern->kind == MS_P_NAME) {
    const MsRef *ref = ms_facts_ref(fn->facts, pattern->id);
    if (ref == NULL || ref->kind != MS_REF_LOCAL) {
      return fn_fail(fn, "a bound name has no local");
    }
    const MsTy owned_ty = ms_facts_type(fn->facts, pattern->id);
    if (reassignable && part_owned && fn_closer_for(fn, ms_facts_closer(fn->facts, pattern->id), owned_ty)) {
      /* A `var` part taken out of its record closes where this scope ends, and may be reassigned. */
      return fn_bind_closing_in(fn, fn_scope(fn), ref->local, owned_ty, value, true);
    }
    if (reassignable) { /* `var` takes its own copy of the part, which the name then owns and may reassign */
      const MirTy ty = mir_b_ty(&fn->b, value);
      if (!mir_needs_drop(module, ty)) {
        mir_b_def_var(&fn->b, fn_local(fn, ref->local, ty), value);
        return !fn->failed;
      }
      if (ref->local >= fn->nvars) {
        return fn_fail(fn, "a local binding is outside the function's locals");
      }
      const MirValue copy = part_owned ? value : fn_emit(fn, MOP_Clone, &value, 1, (MirImm){0}, ty); /* a taken part is already the name's */
      fn->vars[ref->local] = mir_b_declare_var(&fn->b, ty, MM_MOVE) + 1;
      fn_disown(fn, copy);
      mir_b_def_var(&fn->b, fn->vars[ref->local] - 1, copy);
      return fn_scope_own_var(fn, fn->vars[ref->local] - 1) && !fn->failed;
    }
    const MsTy checked = ms_facts_type(fn->facts, pattern->id);
    if (part_owned && fn_closer_for(fn, ms_facts_closer(fn->facts, pattern->id), checked)) {
      /* A part taken out of its record closes where this scope ends, like a plain binding. */
      return fn_bind_closing_in(fn, fn_scope(fn), ref->local, checked, value, false);
    }
    mir_b_def_var(&fn->b, fn_local(fn, ref->local, mir_b_ty(&fn->b, value)), value);
    return !fn->failed;
  }
  const MirTyData *data = mir_ty_data(module, mir_b_ty(&fn->b, value));
  if (pattern->kind == MS_P_LIST) {
    if (data->kind != MK_LIST) {
      return fn_fail(fn, "a list pattern binds a list");
    }
    /* The pattern binds as many names as the list has elements: any other length is a fault. */
    const MirValue length = mir_b_emit(&fn->b, MOP_ListLen, &value, 1, (MirImm){0}, MIR_INT);
    const MirValue names = mir_b_iconst(&fn->b, (int64_t)pattern->u.list.len);
    const MirBlock good = mir_b_new_block(&fn->b);
    const MirBlock bad = mir_b_new_block(&fn->b);
    mir_b_br_if(&fn->b, mir_b_icmp(&fn->b, MCC_EQ, length, names), good, NULL, 0, bad, NULL, 0);
    mir_b_seal_block(&fn->b, good);
    mir_b_seal_block(&fn->b, bad);
    mir_b_switch_to(&fn->b, bad);
    const MirValue counts[2] = {names, length};
    (void)fn_runtime_call(fn, mir_name(fn->cx->module, ms_span_of_text("msrt_fault_destructure")), counts, 2, MIR_VOID);
    mir_b_unreachable(&fn->b);
    mir_b_switch_to(&fn->b, good);
    for (uint32_t at = 0; at < pattern->u.list.len; at++) {
      const MirValue args[2] = {value, mir_b_iconst(&fn->b, (int64_t)at)};
      const MirValue element = mir_b_emit(&fn->b, MOP_ListGet, args, 2, (MirImm){0}, data->elem);
      if (!fn_bind_parts(fn, pattern->u.list.ptr[at], element, false, NULL, reassignable, false, MS_TY_NONE)) {
        return false;
      }
    }
    return true;
  }
  if (data->kind != MK_TYPE) {
    return fn_fail(fn, "a field pattern binds a record");
  }
  const MirTypeDef *def = &module->type_defs.ptr[data->id];
  uint32_t taken = 0;
  for (uint32_t at = 0; at < pattern->u.fields.len; at++) {
    const MsPatternField *field = &pattern->u.fields.ptr[at];
    const MsSpan wanted = ms_names_span(fn->cx->program->names, field->name);
    uint32_t found = def->nfields;
    for (uint32_t index = 0; index < def->nfields; index++) {
      const MsSpan have = ms_names_span(&module->names, def->fields[index].name);
      if (ms_span_equal(have, wanted)) {
        found = index;
      }
    }
    if (found == def->nfields) {
      return fn_fail(fn, "a pattern names a field the record does not have");
    }
    const MirImm imm = {.tag = MI_FIELD, .a = data->id, .b = found};
    MirValue part = mir_b_emit(&fn->b, MOP_TypeGet, &value, 1, imm, def->fields[found].ty);
    const bool name = field->pattern->kind == MS_P_NAME;
    const bool drops = mir_needs_drop(module, def->fields[found].ty);
    /* A resource part closes with the name that takes it, even when it holds nothing to drop. */
    const bool closes = owned && name &&
                        fn_closer_for(fn, ms_facts_closer(fn->facts, field->pattern->id), ms_facts_type(fn->facts, field->pattern->id));
    const bool takes = owned && name && (drops || closes);
    if (takes) { /* a fresh record hands its part to the name; what the pattern leaves out is released with it */
      if (drops) {
        part = fn_emit(fn, MOP_MoveOut, &part, 1, (MirImm){0}, def->fields[found].ty);
      }
      taken |= found < 32 ? UINT32_C(1) << found : 0;
      if (owner != NULL) { /* a `var` record keeps what is left and releases it where its scope ends */
        fn_scope_var_moved(fn, *owner, found, checked_record);
      }
    }
    if (!fn_bind_parts(fn, field->pattern, part, false, NULL, reassignable, takes, MS_TY_NONE)) {
      return false;
    }
  }
  /* A resource the pattern leaves out is taken from the record too, and closes at the statement. */
  if (owned && checked_record != MS_TY_NONE) {
    taken = fn_close_left_fields(fn, value, checked_record, taken, owner, 0, MIR_NONE);
  }
  if (taken != 0 && owner == NULL) {
    (void)mir_b_emit(&fn->b, MOP_TypeRelease, &value, 1, (MirImm){.tag = MI_TYPEMASK, .a = data->id, .b = taken}, MIR_NONE);
  }
  return true;
}

/* Closes the field `index` of `value`, or drops it when it only owns memory. */
static void settle_field(LowerFn *fn, MirValue value, uint32_t type_id, uint32_t index, MsTy left, MirTy ty, bool closes) {
  MirValue part = mir_b_emit(&fn->b, MOP_TypeGet, &value, 1, (MirImm){.tag = MI_FIELD, .a = type_id, .b = index}, ty);
  const bool drops = mir_needs_drop(fn->cx->module, ty);
  if (drops) {
    part = fn_emit(fn, MOP_MoveOut, &part, 1, (MirImm){0}, ty);
  }
  if (closes) {
    lower_close_check(&fn->b, mir_b_call(&fn->b, lower_part_close(fn->cx, left), &part, 1));
  } else if (drops) {
    (void)mir_b_emit(&fn->b, MOP_Drop, &part, 1, (MirImm){0}, MIR_NONE);
  }
}

uint32_t fn_close_left_fields(LowerFn *fn, MirValue value, MsTy record, uint32_t taken, const MirVar *owner, uint32_t maybe,
                              MirValue flag) {
  const MirModule *module = fn->cx->module;
  const MirTyData *data = mir_ty_data(module, mir_b_ty(&fn->b, value));
  record = record != MS_TY_NONE ? ms_ty_subst(&fn->cx->program->types, record, fn->subst.vars, fn->subst.args, fn->subst.count) : record;
  const MsDef *def = data->kind == MK_TYPE && record != MS_TY_NONE ? ms_check_def_of(fn->cx->program, record) : NULL;
  const MirTypeDef *fields = def != NULL ? &module->type_defs.ptr[data->id] : NULL;
  for (uint32_t at = 0; def != NULL && at < fields->nfields && at < def->fields.len && at < 32; at++) {
    const uint32_t index = fields->nfields - 1 - at; /* the last field closes first */
    const uint32_t bit = UINT32_C(1) << index;
    const MsTy left = ms_check_part_type(fn->cx->program, record, def, def->fields.ptr[index].ty);
    const MirTy ty = fields->fields[index].ty;
    const bool conditional = (maybe & bit) != 0;
    const bool closes = fn_temp_closes(fn, left) && lower_part_close(fn->cx, left) != MIR_NONE;
    if ((taken & bit) != 0 || (!closes && !(conditional && mir_needs_drop(module, ty)))) {
      continue;
    }
    if (conditional) {
      const MirValue kept = mir_b_icmp(&fn->b, MCC_EQ, mir_b_binop(&fn->b, MOP_And, flag, mir_b_iconst(&fn->b, (int64_t)bit)),
                                       mir_b_iconst(&fn->b, 0));
      const MirBlock hold = mir_b_new_block(&fn->b);
      const MirBlock join = mir_b_new_block(&fn->b);
      mir_b_br_if(&fn->b, kept, hold, NULL, 0, join, NULL, 0);
      mir_b_seal_block(&fn->b, hold);
      mir_b_switch_to(&fn->b, hold);
      settle_field(fn, value, data->id, index, left, ty, closes);
      mir_b_br(&fn->b, join, NULL, 0);
      mir_b_seal_block(&fn->b, join);
      mir_b_switch_to(&fn->b, join);
    } else {
      settle_field(fn, value, data->id, index, left, ty, closes);
    }
    taken |= bit;
    if (owner != NULL) {
      fn_scope_var_moved(fn, *owner, index, record);
    }
  }
  return taken;
}
