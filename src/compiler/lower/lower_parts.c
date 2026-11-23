/* compiler/lower/lower_parts.c: the close of a holder. A type with no close of its own closes the resources it
 * holds: its fields last declared first, the payload of an Optional, the elements of a list last first. The
 * helper `fn(move holder)` takes each part out of the holder, closes it with its own close (or its own helper),
 * and drops the rest; a part whose close fails faults, since the holder has nowhere to return the error. */
#include "compiler/check/properties.h"
#include "compiler/lower/lower_fn.h"
#include "compiler/mir/mir_analysis.h"
#include "compiler/own/closers.h"

enum { MAX_PARTS = 32, OK_CASE = 0, ERROR_CASE = 1 };

typedef struct Part {
  MirValue value;
  uint32_t close;
} Part;

static bool is_one_of(const MsCheckProgram *program, MsTy ty, MsBuiltin builtin) {
  return ms_ty_is(&program->types, ty, builtin) && ms_ty_arg_count(&program->types, ty) == 1;
}

/* Whether the own close of `ty` takes the value and leaves nothing to write back. */
static bool closes_by_value(MsCheckProgram *program, MsTy ty) {
  MsCloser closer;
  return ms_check_closeable(program, ty) && ms_own_closer_of(program, ty, &closer) &&
         (closer.flags & MS_CLOSER_CONSUMES) != 0 && (closer.flags & MS_CLOSER_WRITES_BACK) == 0;
}

static bool is_result(const MsCheckProgram *program, MsTy ty) {
  return ms_ty_is(&program->types, ty, MS_BUILTIN_Result) && ms_ty_arg_count(&program->types, ty) == 2;
}

static bool is_map(const MsCheckProgram *program, MsTy ty) {
  return ms_ty_is(&program->types, ty, MS_BUILTIN_Map) && ms_ty_arg_count(&program->types, ty) == 2;
}

/* Whether every resource `ty` holds closes by a helper this file can build. Types being checked count as
 * supported: a holder that holds itself is decided by its other parts. */
static bool supported(MsCheckProgram *program, MsTy ty, MsTyList *seen) {
  if (!ms_check_holds_resource(program, ty)) {
    return true;
  }
  if (ms_check_closeable(program, ty)) {
    return closes_by_value(program, ty);
  }
  for (size_t index = 0; index < seen->len; index++) {
    if (seen->ptr[index] == ty) {
      return true;
    }
  }
  ms_ty_list_push(seen, ty);
  if (is_one_of(program, ty, MS_BUILTIN_Optional) || is_one_of(program, ty, MS_BUILTIN_List)) {
    return supported(program, ms_ty_args(&program->types, ty)[0], seen);
  }
  if (is_result(program, ty)) {
    const MsTy *args = ms_ty_args(&program->types, ty);
    return supported(program, args[1], seen) && supported(program, args[0], seen);
  }
  if (is_map(program, ty)) {
    const MsTy *args = ms_ty_args(&program->types, ty);
    return !ms_check_holds_resource(program, args[0]) && supported(program, args[1], seen);
  }
  const MsDef *def = ms_check_def_of(program, ty);
  if (def != NULL && ms_ty_kind(&program->types, ty) == MS_TY_ALTERNATIVE) {
    for (size_t kase = 0; kase < def->cases.len; kase++) {
      if (def->cases.ptr[kase].fields.len >= MAX_PARTS) {
        return false;
      }
      for (size_t field = 0; field < def->cases.ptr[kase].fields.len; field++) {
        if (!supported(program, ms_check_part_type(program, ty, def, def->cases.ptr[kase].fields.ptr[field].ty), seen)) {
          return false;
        }
      }
    }
    return true;
  }
  if (def == NULL || ms_ty_kind(&program->types, ty) != MS_TY_TYPE || def->fields.len >= MAX_PARTS) {
    return false;
  }
  for (size_t index = 0; index < def->fields.len; index++) {
    if (!supported(program, ms_check_part_type(program, ty, def, def->fields.ptr[index].ty), seen)) {
      return false;
    }
  }
  return true;
}

bool lower_parts_supported(Lower *cx, MsTy ty) {
  MsTyList seen = {0};
  const bool ok = supported(cx->program, ty, &seen);
  ms_ty_list_free(&seen);
  return ok;
}

static uint32_t helper_for(Lower *cx, MsTy ty);

/* The function that closes a value of `ty` taken out of its holder, or MIR_NONE when it holds no resource. */
static uint32_t part_close(Lower *cx, MsTy ty) {
  if (!ms_check_holds_resource(cx->program, ty)) {
    return MIR_NONE;
  }
  if (ms_ty_kind(&cx->program->types, ty) == MS_TY_CONTRACT) {
    return lower_close_iface(cx, ty);
  }
  return ms_check_closeable(cx->program, ty) ? lower_named_method(cx, ty, "close") : helper_for(cx, ty);
}

uint32_t lower_part_close(Lower *cx, MsTy ty) {
  return lower_parts_supported(cx, ty) || ms_check_closeable(cx->program, ty) ? part_close(cx, ty) : MIR_NONE;
}

static MirImm imm_field(uint32_t type, uint32_t index) {
  return (MirImm){.tag = MI_FIELD, .a = type, .b = index};
}

/* Closes the taken parts in order; a failed close faults once every part is closed. Ends the function. */
static void close_taken(MirBuilder *b, const Part *parts, uint32_t count) {
  MirValue results[MAX_PARTS];
  for (uint32_t index = 0; index < count; index++) {
    results[index] = mir_b_call(b, parts[index].close, &parts[index].value, 1);
  }
  for (uint32_t index = 0; index < count; index++) {
    lower_close_check(b, results[index]);
  }
  mir_b_ret(b, mir_b_unit(b));
}

static void drop_value(MirBuilder *b, MirValue value) {
  if (mir_needs_drop(b->module, mir_b_ty(b, value))) {
    (void)mir_b_emit(b, MOP_Drop, &value, 1, (MirImm){0}, MIR_NONE);
  }
}

static void emit_record(Lower *cx, MirBuilder *b, MirValue holder, MsTy ty, MirTy mt) {
  const MsDef *def = ms_check_def_of(cx->program, ty);
  const uint32_t type = mir_ty_data(cx->module, mt)->id;
  Part parts[MAX_PARTS];
  uint32_t count = 0, mask = 0;
  for (size_t index = def->fields.len; index > 0; index--) {
    const MsTy field = ms_check_part_type(cx->program, ty, def, def->fields.ptr[index - 1].ty);
    const uint32_t close = part_close(cx, field);
    if (close == MIR_NONE) {
      continue;
    }
    const MirTy fty = cx->module->type_defs.ptr[type].fields[index - 1].ty;
    MirValue value = mir_b_emit(b, MOP_TypeGet, &holder, 1, imm_field(type, (uint32_t)index - 1), fty);
    if (mir_needs_drop(cx->module, fty)) {
      value = mir_b_emit(b, MOP_MoveOut, &value, 1, (MirImm){0}, fty);
      mask |= 1u << (index - 1);
    }
    parts[count++] = (Part){value, close};
  }
  if (mask != 0) {
    (void)mir_b_emit(b, MOP_TypeRelease, &holder, 1, (MirImm){.tag = MI_TYPEMASK, .a = type, .b = mask}, MIR_NONE);
  } else {
    drop_value(b, holder);
  }
  close_taken(b, parts, count);
}

/* A user alternative closes the fields of the case it holds, last declared first. */
static void emit_alt(Lower *cx, MirBuilder *b, MirValue holder, MsTy ty) {
  const MsDef *def = ms_check_def_of(cx->program, ty);
  const uint32_t alt = mir_ty_data(cx->module, mir_b_ty(b, holder))->id;
  const MirValue tag = mir_b_emit(b, MOP_AltTag, &holder, 1, (MirImm){0}, MIR_INT);
  for (uint32_t kase = 0; kase < def->cases.len; kase++) {
    const MirBlock yes = mir_b_new_block(b);
    const MirBlock no = mir_b_new_block(b);
    mir_b_br_if(b, mir_b_icmp(b, MCC_EQ, tag, mir_b_iconst(b, kase)), yes, NULL, 0, no, NULL, 0);
    mir_b_seal_block(b, yes);
    mir_b_seal_block(b, no);
    mir_b_switch_to(b, yes);
    const MirCaseDef *mir_case = &cx->module->alts.ptr[alt].cases[kase];
    Part parts[MAX_PARTS];
    uint32_t count = 0, mask = 0;
    for (size_t field = def->cases.ptr[kase].fields.len; field > 0; field--) {
      const MsTy part = ms_check_part_type(cx->program, ty, def, def->cases.ptr[kase].fields.ptr[field - 1].ty);
      const uint32_t close = part_close(cx, part);
      if (close == MIR_NONE) {
        continue;
      }
      const MirTy fty = mir_case->fields[field - 1].ty;
      const bool owns = mir_needs_drop(cx->module, fty);
      const MirImm imm = {.tag = MI_ALTFIELD, .a = alt, .b = kase, .c = (uint32_t)field - 1};
      const MirValue value = mir_b_emit(b, owns ? MOP_AltTake : MOP_AltGet, &holder, 1, imm, fty);
      mask |= owns ? 1u << (field - 1) : 0;
      parts[count++] = (Part){value, close};
    }
    if (mask != 0) {
      (void)mir_b_emit(b, MOP_AltRelease, &holder, 1, (MirImm){.tag = MI_ALTMASK, .a = alt, .b = kase, .c = mask}, MIR_NONE);
    } else {
      drop_value(b, holder);
    }
    close_taken(b, parts, count);
    mir_b_switch_to(b, no);
  }
  drop_value(b, holder);
  mir_b_ret(b, mir_b_unit(b));
}

static void emit_optional(Lower *cx, MirBuilder *b, MirValue holder, MsTy inner) {
  const MirValue some = mir_b_emit(b, MOP_OptIsSome, &holder, 1, (MirImm){0}, MIR_BOOL);
  const MirBlock yes = mir_b_new_block(b);
  const MirBlock no = mir_b_new_block(b);
  mir_b_br_if(b, some, yes, NULL, 0, no, NULL, 0);
  mir_b_seal_block(b, yes);
  mir_b_seal_block(b, no);
  mir_b_switch_to(b, no);
  drop_value(b, holder);
  mir_b_ret(b, mir_b_unit(b));
  mir_b_switch_to(b, yes);
  const MirTy payload = mir_ty_data(cx->module, mir_b_ty(b, holder))->elem;
  const MirValue value = mir_b_emit(b, MOP_OptUnbox, &holder, 1, (MirImm){0}, payload);
  const Part part = {value, part_close(cx, inner)};
  close_taken(b, &part, 1);
}

/* The elements close last first; the list shrinks past each one as it is taken, so that an unwind during a
 * close frees only the elements still in it. */
static void emit_list(Lower *cx, MirBuilder *b, MirValue holder, MsTy elem) {
  const MirTy list = mir_b_ty(b, holder);
  const MirTy elem_ty = mir_ty_data(cx->module, list)->elem;
  const uint32_t close = part_close(cx, elem);
  const MirVar rest = mir_b_declare_var(b, list, MM_MOVE);
  mir_b_def_var(b, rest, holder);
  const MirBlock header = mir_b_new_block(b);
  const MirBlock body = mir_b_new_block(b);
  const MirBlock exit = mir_b_new_block(b);
  mir_b_br(b, header, NULL, 0);
  mir_b_switch_to(b, header);
  MirValue current = mir_b_use_var(b, rest);
  const MirValue length = mir_b_emit(b, MOP_ListLen, &current, 1, (MirImm){0}, MIR_INT);
  mir_b_br_if(b, mir_b_icmp(b, MCC_GT, length, mir_b_iconst(b, 0)), body, NULL, 0, exit, NULL, 0);
  mir_b_seal_block(b, body);
  mir_b_seal_block(b, exit);
  mir_b_switch_to(b, body);
  current = mir_b_use_var(b, rest);
  const MirValue count = mir_b_emit(b, MOP_ListLen, &current, 1, (MirImm){0}, MIR_INT);
  const MirValue last = mir_b_binop(b, MOP_ISub, count, mir_b_iconst(b, 1));
  const MirValue at[2] = {current, last};
  const MirValue item = mir_b_emit(b, MOP_ListTake, at, 2, (MirImm){0}, elem_ty);
  mir_b_def_var(b, rest, mir_b_emit(b, MOP_ListDropLast, &current, 1, (MirImm){.tag = MI_INT, .i = 1}, list));
  lower_close_check(b, mir_b_call(b, close, &item, 1));
  mir_b_br(b, header, NULL, 0);
  mir_b_seal_block(b, header);
  mir_b_switch_to(b, exit);
  const MirValue release[2] = {mir_b_use_var(b, rest), mir_b_iconst(b, 0)};
  (void)mir_b_emit(b, MOP_ListRelease, release, 2, (MirImm){0}, MIR_NONE);
  mir_b_ret(b, mir_b_unit(b));
}

/* Takes the payload of case `kase` out of the Result `holder` and closes it; ends the function. A case that holds no
 * resource only drops the holder. */
static void emit_result_case(Lower *cx, MirBuilder *b, MirValue holder, uint32_t alt, uint32_t kase, MsTy ty) {
  if (!ms_check_holds_resource(cx->program, ty)) {
    drop_value(b, holder);
    mir_b_ret(b, mir_b_unit(b));
    return;
  }
  const MirTy payload = cx->module->alts.ptr[alt].cases[kase].fields[0].ty;
  const MirImm field = {.tag = MI_ALTFIELD, .a = alt, .b = kase, .c = 0};
  const bool owns = mir_needs_drop(cx->module, payload);
  const MirValue value = mir_b_emit(b, owns ? MOP_AltTake : MOP_AltGet, &holder, 1, field, payload);
  if (owns) {
    const MirImm taken = {.tag = MI_ALTMASK, .a = alt, .b = kase, .c = 1};
    (void)mir_b_emit(b, MOP_AltRelease, &holder, 1, taken, MIR_NONE);
  }
  const Part part = {value, part_close(cx, ty)};
  close_taken(b, &part, 1);
}

/* A Result closes the payload of the case it holds, when that payload holds a resource. */
static void emit_result(Lower *cx, MirBuilder *b, MirValue holder, MsTy ok_ty, MsTy error_ty) {
  const uint32_t alt = mir_ty_data(cx->module, mir_b_ty(b, holder))->id;
  const MirValue tag = mir_b_emit(b, MOP_AltTag, &holder, 1, (MirImm){0}, MIR_INT);
  const MirBlock yes = mir_b_new_block(b);
  const MirBlock no = mir_b_new_block(b);
  mir_b_br_if(b, mir_b_icmp(b, MCC_EQ, tag, mir_b_iconst(b, OK_CASE)), yes, NULL, 0, no, NULL, 0);
  mir_b_seal_block(b, yes);
  mir_b_seal_block(b, no);
  mir_b_switch_to(b, no);
  emit_result_case(cx, b, holder, alt, ERROR_CASE, error_ty);
  mir_b_switch_to(b, yes);
  emit_result_case(cx, b, holder, alt, OK_CASE, ok_ty);
}

static uint32_t map_extern(Lower *cx, const char *name, const MirParam *params, uint32_t count, MirTy ret) {
  MirParam *own = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirParam, count);
  for (uint32_t index = 0; index < count; index++) {
    own[index] = params[index];
  }
  const MirExtern def = {.name = mir_name(cx->module, ms_span_of_text(name)), .params = own, .nparams = count, .ret = ret};
  return mir_extern_intern(cx->module, &def);
}

/* The values of a map close last slot first; the map and its keys are freed once the values are gone. */
static void emit_map(Lower *cx, MirBuilder *b, MirValue holder, MsTy value_ty) {
  const MirTy map = mir_b_ty(b, holder);
  const MirTy key_ty = mir_ty_data(cx->module, map)->args[0];
  const MirTy val_ty = mir_ty_data(cx->module, map)->args[1];
  const uint32_t close = part_close(cx, value_ty);
  const MirParam on_map = {map, (uint8_t)MM_BORROW}, ptr = {MIR_PTR, (uint8_t)MM_BORROW}, num = {MIR_INT, (uint8_t)MM_BORROW};
  const MirParam entry_params[] = {on_map, ptr, ptr, num, ptr, ptr};
  const uint32_t count_fn = map_extern(cx, "msrt_map_slot_count", &on_map, 1, MIR_INT);
  const uint32_t entry_fn = map_extern(cx, "msrt_map_entry_ptrs", entry_params, 6, MIR_BOOL);
  const uint32_t drop_fn = map_extern(cx, "msrt_map_drop", entry_params, 3, MIR_VOID);
  const MirImm key_imm = {.tag = MI_TY, .a = key_ty}, val_imm = {.tag = MI_TY, .a = val_ty};
  const MirValue kd = mir_b_emit(b, MOP_TypeDesc, NULL, 0, key_imm, MIR_PTR);
  const MirValue vd = mir_b_emit(b, MOP_TypeDesc, NULL, 0, val_imm, MIR_PTR);
  const MirImm ptr_imm = {.tag = MI_TY, .a = MIR_PTR};
  const MirValue kp = mir_b_emit(b, MOP_Slot, NULL, 0, ptr_imm, MIR_PTR);
  const MirValue vp = mir_b_emit(b, MOP_Slot, NULL, 0, ptr_imm, MIR_PTR);
  const MirVar index = mir_b_declare_var(b, MIR_INT, MM_BORROW);
  mir_b_def_var(b, index, mir_b_call_rt(b, count_fn, &holder, 1));
  const MirBlock header = mir_b_new_block(b), probe = mir_b_new_block(b);
  const MirBlock body = mir_b_new_block(b), exit = mir_b_new_block(b);
  mir_b_br(b, header, NULL, 0);
  mir_b_switch_to(b, header);
  const MirValue more = mir_b_icmp(b, MCC_GT, mir_b_use_var(b, index), mir_b_iconst(b, 0));
  mir_b_br_if(b, more, probe, NULL, 0, exit, NULL, 0);
  mir_b_seal_block(b, probe);
  mir_b_switch_to(b, probe);
  const MirValue at = mir_b_binop(b, MOP_ISub, mir_b_use_var(b, index), mir_b_iconst(b, 1));
  mir_b_def_var(b, index, at);
  const MirValue entry_args[] = {holder, kd, vd, at, kp, vp};
  mir_b_br_if(b, mir_b_call_rt(b, entry_fn, entry_args, 6), body, NULL, 0, header, NULL, 0);
  mir_b_seal_block(b, body);
  mir_b_switch_to(b, body);
  const MirValue addr = mir_b_emit(b, MOP_Load, &vp, 1, ptr_imm, MIR_PTR);
  const MirValue item = mir_b_emit(b, mir_needs_drop(cx->module, val_ty) ? MOP_Take : MOP_Load, &addr, 1, val_imm, val_ty);
  lower_close_check(b, mir_b_call(b, close, &item, 1));
  mir_b_br(b, header, NULL, 0);
  mir_b_seal_block(b, header);
  mir_b_seal_block(b, exit);
  mir_b_switch_to(b, exit);
  const MirValue none = mir_b_emit(b, MOP_PtrNull, NULL, 0, (MirImm){0}, MIR_PTR);
  const MirValue drop_args[] = {holder, kd, none};
  (void)mir_b_call_rt(b, drop_fn, drop_args, 3);
  (void)mir_b_emit(b, MOP_Forget, &holder, 1, (MirImm){0}, MIR_NONE);
  mir_b_ret(b, mir_b_unit(b));
}

static MsName helper_name(Lower *cx, MsTy ty) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_printf(&text, "close.parts.%u", (unsigned)ty);
  const MsName name = mir_name(cx->module, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  return name;
}

/* A function that does nothing yet, so a holder that holds itself can call the helper being built. */
static uint32_t declare(Lower *cx, MsName name, MirTy mt) {
  const MirParam param = {mt, (uint8_t)MM_MOVE};
  MirBuilder b;
  mir_b_init(&b, cx->module, name, &param, 1, MIR_VOID);
  b.func.linkage = ML_INTERNAL;
  MirValue holder = MIR_NONE;
  mir_b_params(&b, &holder, 1);
  mir_b_ret(&b, mir_b_unit(&b));
  uint32_t id = MIR_NONE;
  return mir_b_finish(&b, &id) ? id : MIR_NONE;
}

static uint32_t helper_for(Lower *cx, MsTy ty) {
  const MsName name = helper_name(cx, ty);
  const uint32_t found = mir_func_by_name(cx->module, name);
  if (found != MIR_NONE) {
    return found;
  }
  const LowerSubst none = {0};
  const MirTy mt = lower_type(cx, &none, ty);
  const uint32_t id = declare(cx, name, mt);
  const MirParam param = {mt, (uint8_t)MM_MOVE};
  MirBuilder b;
  mir_b_init(&b, cx->module, name, &param, 1, MIR_VOID);
  b.func.linkage = ML_INTERNAL;
  MirValue holder = MIR_NONE;
  mir_b_params(&b, &holder, 1);
  const MsTyTable *types = &cx->program->types;
  if (is_one_of(cx->program, ty, MS_BUILTIN_Optional)) {
    emit_optional(cx, &b, holder, ms_ty_args(types, ty)[0]);
  } else if (is_one_of(cx->program, ty, MS_BUILTIN_List)) {
    emit_list(cx, &b, holder, ms_ty_args(types, ty)[0]);
  } else if (is_result(cx->program, ty)) {
    emit_result(cx, &b, holder, ms_ty_args(types, ty)[0], ms_ty_args(types, ty)[1]);
  } else if (is_map(cx->program, ty)) {
    emit_map(cx, &b, holder, ms_ty_args(types, ty)[1]);
  } else if (ms_ty_kind(types, ty) == MS_TY_ALTERNATIVE) {
    emit_alt(cx, &b, holder, ty);
  } else {
    emit_record(cx, &b, holder, ty, mt);
  }
  MirFunc built = {0};
  if (!mir_b_into_func(&b, &built)) {
    return MIR_NONE;
  }
  cx->module->funcs.ptr[id] = built;
  return id;
}

uint32_t lower_close_parts(Lower *cx, MsTy ty) {
  return lower_parts_supported(cx, ty) ? helper_for(cx, ty) : MIR_NONE;
}

/* ---- interface values ---- */

/* The index of the `close` operation of the interface `def`, or the operation count when it has none. */
static uint32_t close_operation(const Lower *cx, const MsDef *def) {
  const MsName close = ms_names_intern(cx->program->names, ms_span_of_text("close"));
  uint32_t index = 0;
  while (index < def->operations.len && def->operations.ptr[index].name != close) {
    index++;
  }
  return index;
}

uint32_t lower_close_iface(Lower *cx, MsTy ty) {
  const MsDef *def = ms_defs_get(&cx->program->defs, ms_ty_row(&cx->program->types, ty)->def);
  const LowerSubst none = {0};
  const MirTy mt = lower_type(cx, &none, ty);
  if (def == NULL || mir_ty_data(cx->module, mt)->kind != MK_IFACE || close_operation(cx, def) == def->operations.len) {
    return MIR_NONE;
  }
  const uint32_t op = close_operation(cx, def);
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_printf(&text, "close.iface.%u", (unsigned)mt);
  const MsName name = mir_name(cx->module, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  const uint32_t found = mir_func_by_name(cx->module, name);
  if (found != MIR_NONE) {
    return found;
  }
  const MirTy ret = lower_type(cx, &none, ms_ty_result(&cx->program->types, def->operations.ptr[op].ty));
  const MirParam param = {mt, (uint8_t)MM_MOVE};
  MirBuilder b;
  mir_b_init(&b, cx->module, name, &param, 1, ret);
  b.func.linkage = ML_INTERNAL;
  MirValue value = MIR_NONE;
  mir_b_params(&b, &value, 1);
  const MirImm method = {.tag = MI_METHOD, .a = mir_ty_data(cx->module, mt)->id, .b = op};
  mir_b_ret(&b, mir_b_emit(&b, MOP_CallMethod, &value, 1, method, ret));
  uint32_t id = MIR_NONE;
  return mir_b_finish(&b, &id) ? id : MIR_NONE;
}
