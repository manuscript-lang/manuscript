/* compiler/lower/lower_native.c: calls to bodiless standard operations (`fn String.trim() String`, the
 * operations of intrinsics.ms). The runtime function an operation maps to is named from its declaration: the
 * receiver type's lowercase name, then the operation (`msrt_string_trim`, `msrt_int_to_string`). The few that are
 * one MIR instruction are written out here: copying a string is `clone`, and joining two strings is the concat
 * function with its result fresh. */
#include "compiler/lower/lower_fn.h"
#include "compiler/lower/native_sigs.h"
#include "compiler/mir/mir_analysis.h"

/* `msrt_<receiver>_<operation>`: the receiver's type name lowercased. */
static MsName runtime_name(LowerFn *fn, MsTy receiver, MsSpan operation) {
  const MsTyTable *types = &fn->cx->program->types;
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "msrt_");
  const char *type_name = ms_builtin_name(ms_ty_builtin(types, receiver));
  for (const char *at = type_name; *at != '\0'; at++) {
    ms_strbuild_append_byte(&text, (uint8_t)(*at >= 'A' && *at <= 'Z' ? *at - 'A' + 'a' : *at));
  }
  ms_strbuild_append_byte(&text, '_');
  ms_strbuild_append(&text, operation);
  const MsName name = mir_name(fn->cx->module, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  return name;
}

/* The `index`th type argument of a collection type (a map's key, value; a set's element), or MIR_NONE. */
static MirTy collection_arg(const LowerFn *fn, const MirTyData *data, uint32_t index) {
  if (data->kind == MK_LIST) {
    return index == 0 ? data->elem : MIR_NONE;
  }
  (void)fn;
  return index < data->nargs ? data->args[index] : MIR_NONE;
}

/* Whether `type` is a list, a map or a set: what the descriptor parameters of a native describe. */
static bool is_collection(const LowerFn *fn, MirTy type) {
  const MirTyData *data = mir_ty_data(fn->cx->module, type);
  return data->kind == MK_LIST || (data->kind == MK_OBJ && data->obj_class == MIR_OBJ_COLLECTION);
}

/* The descriptor argument `kind` asks for, from the first collection among `args`; false when there is none. */
bool fn_descriptor_argument(LowerFn *fn, uint8_t kind, const MirValue *args, uint32_t nargs, MirValue *out) {
  for (uint32_t at = 0; at < nargs; at++) {
    const MirTy type = mir_b_ty(&fn->b, args[at]);
    if (!is_collection(fn, type)) {
      continue;
    }
    const MirTyData *data = mir_ty_data(fn->cx->module, type);
    const MirTy element = collection_arg(fn, data, kind == NS_VAL_DESC ? 1 : 0);
    if (element == MIR_NONE) {
      return false;
    }
    const MirImm imm = {.tag = MI_TY, .a = element};
    *out = fn_emit(fn, MOP_TypeDesc, NULL, 0, imm, MIR_PTR);
    return true;
  }
  return false;
}

static bool is_result_kind(uint8_t kind) {
  return kind == NS_VEC_MUT || kind == NS_STR_MUT || kind == NS_MAP_MUT || kind == NS_ADDR_MUT ||
         kind == NS_OUT_SCALAR;
}

/* Whether `value` is a closure, an interface or an optional of plain data, which a native is given by address
 * though its leaves would pass by value. */
static bool spilled_by_address(LowerFn *fn, MirValue value) {
  const MirTy ty = mir_b_ty(&fn->b, value);
  const MirTyKind kind = (MirTyKind)mir_ty_data(fn->cx->module, ty)->kind;
  return kind == MK_FN || kind == MK_IFACE || (kind == MK_OPT && !mir_needs_drop(fn->cx->module, ty));
}

/* `value` as an owned copy the scope no longer owns, because a native takes it from its address. */
MirValue fn_move_out_of_scope(LowerFn *fn, MirValue value) {
  const bool fresh = fn_fresh_owner(fn, value);
  if (!fresh) {
    value = fn_implicit_clone(fn, value, false);
  }
  (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &value, 1, (MirImm){0}, MIR_NONE);
  return value;
}

/* A scalar operand a native reads through an address (`e: *const u8`): it goes into a stack slot. */
static MirValue spill_scalar(LowerFn *fn, MirValue value) {
  const MirTy ty = mir_b_ty(&fn->b, value);
  /* A closure or interface value is a pointer the runtime copies by address, as it does a scalar. */
  if (!mir_is_scalar(fn->cx->module, ty) && !spilled_by_address(fn, value)) {
    return value;
  }
  const MirImm of_type = {.tag = MI_TY, .a = ty};
  const MirValue slot = fn_emit(fn, MOP_Slot, NULL, 0, of_type, MIR_PTR);
  const MirValue store[2] = {slot, value};
  (void)fn_emit(fn, MOP_Store, store, 2, (MirImm){0}, MIR_NONE);
  return slot;
}

/* Whether `ty` is an enum whose cases carry no data: it is passed as its case index. */
static bool is_plain_enum(const MirModule *module, MirTy ty) {
  const MirTyData *data = mir_ty_data(module, ty);
  if (data->kind != MK_ALT) {
    return false;
  }
  const MirAltDef *alt = &module->alts.ptr[data->id];
  for (uint32_t index = 0; index < alt->ncases; index++) {
    if (alt->cases[index].nfields > 0) {
      return false;
    }
  }
  return alt->ncases > 0;
}

/* A plain enum handed to a native that takes a number: its case index. */
MirValue fn_native_scalar(LowerFn *fn, MirValue operand) {
  if (!is_plain_enum(fn->cx->module, mir_b_ty(&fn->b, operand))) {
    return operand;
  }
  return mir_b_emit(&fn->b, MOP_AltTag, &operand, 1, (MirImm){0}, MIR_INT);
}

/* An `Int?` or optional plain enum operand as the two parameters of a `HasRaw` pair: whether it holds a value,
 * and the value (the case index for an enum; 0 when none). False when the operand is neither. */
bool fn_has_raw_pair(LowerFn *fn, MirValue optional, MirValue *out) {
  const MirTyData *data = mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, optional));
  if (data->kind == MK_OPT && data->elem == MIR_STR) {
    /* A `String?`: whether it holds a value, and the address of the text (read only when it does). */
    const MirValue held = fn_emit(fn, MOP_OptIsSome, &optional, 1, (MirImm){0}, MIR_BOOL);
    const MirValue text = fn_emit(fn, MOP_OptGet, &optional, 1, (MirImm){0}, MIR_STR);
    const MirImm of_type = {.tag = MI_TY, .a = MIR_STR};
    const MirValue slot = mir_b_emit(&fn->b, MOP_Slot, NULL, 0, of_type, MIR_PTR);
    const MirValue store[2] = {slot, text};
    (void)mir_b_emit(&fn->b, MOP_Store, store, 2, (MirImm){0}, MIR_NONE);
    out[0] = held;
    out[1] = slot;
    return true;
  }
  if (data->kind != MK_OPT) {
    return false;
  }
  /* An optional record of one Int (`Duration?`) passes that Int. */
  const MirTyData *elem = mir_ty_data(fn->cx->module, data->elem);
  const MirTypeDef *def = elem->kind == MK_TYPE ? &fn->cx->module->type_defs.ptr[elem->id] : NULL;
  const bool wrapped = def != NULL && def->nfields == 1 && def->fields[0].ty == MIR_INT;
  if (data->elem != MIR_INT && !wrapped && !is_plain_enum(fn->cx->module, data->elem)) {
    return false;
  }
  const MirValue present = fn_emit(fn, MOP_OptIsSome, &optional, 1, (MirImm){0}, MIR_BOOL);
  MirValue payload = fn_emit(fn, MOP_OptGet, &optional, 1, (MirImm){0}, data->elem);
  if (wrapped) {
    const MirImm field = {.tag = MI_FIELD, .a = elem->id, .b = 0};
    payload = mir_b_emit(&fn->b, MOP_TypeGet, &payload, 1, field, MIR_INT);
  } else if (data->elem != MIR_INT) {
    payload = fn_emit(fn, MOP_AltTag, &payload, 1, (MirImm){0}, MIR_INT);
  }
  out[0] = present;
  out[1] = mir_b_select(&fn->b, present, payload, mir_b_iconst(&fn->b, 0));
  return true;
}

/* The operands the runtime function `sig` wants for a call with the source operands `args`: the descriptors
 * its signature names are added after the collection they describe, and the trailing result parameter is the
 * call's result. False when the source operands do not fit the signature. */
static bool signature_arguments(LowerFn *fn, const MsNativeSig *sig, const MirValue *args, uint32_t nargs,
                                MirTy ret, MirValue *out, uint32_t *count) {
  uint32_t params = sig->count;
  if (ret != MIR_VOID && params > 0 && is_result_kind(sig->kinds[params - 1])) {
    params--;
  }
  uint32_t next = 0;
  uint32_t used = 0;
  fn->native_moves = 0;
  for (uint32_t at = 0; at < params; at++) {
    const uint8_t kind = sig->kinds[at];
    if (kind == NS_ELEM_DESC || kind == NS_KEY_DESC || kind == NS_VAL_DESC) {
      if (!fn_descriptor_argument(fn, kind, args, nargs, &out[used++])) {
        return false;
      }
    } else if (kind == NS_HAS_RAW && next < nargs) {
      if (!fn_has_raw_pair(fn, args[next++], &out[used])) {
        return false;
      }
      used += 2;
      at++; /* the payload parameter is the second half of the pair */
    } else if (next < nargs) {
      /* The runtime takes an owned operand it is given by address (`msrt_map_add`'s key and value). */
      const bool declared = next > 0 && next < 32 && (fn->native_arg_moves >> next & 1u) != 0;
      if ((declared || (kind == NS_ADDR_MUT && at > 0)) && used < 32 &&
          mir_needs_drop(fn->cx->module, mir_b_ty(&fn->b, args[next]))) {
        fn->native_moves |= 1u << used;
      }
      MirValue operand = args[next];
      if ((fn->native_moves >> used & 1u) != 0 && spilled_by_address(fn, operand)) {
        operand = fn_move_out_of_scope(fn, operand);
      }
      out[used++] = kind == NS_ADDR_IN || kind == NS_ADDR_MUT ? spill_scalar(fn, operand)
                    : kind == NS_VALUE                         ? fn_native_scalar(fn, operand)
                                                               : operand;
      next++;
    } else {
      return false;
    }
  }
  *count = used;
  return next == nargs;
}

/* A scalar result a native writes through its trailing `*mut u8` parameter: the call gets a slot of the result's
 * type in place of the result, returned here, and the value is loaded from it once the call is made. */
static MirValue scalar_result_slot(LowerFn *fn, const MsNativeSig *sig, MirTy ret) {
  const bool scalar = ret == MIR_INT || ret == MIR_BOOL || ret == MIR_FLOAT || ret == MIR_FLOAT32;
  const MirTyData *data = mir_ty_data(fn->cx->module, ret);
  const bool optional = data->kind == MK_OPT && sig->status; /* answers whether it filled the slot */
  const uint8_t last = sig->count > 0 ? sig->kinds[sig->count - 1] : NS_VALUE;
  const bool text = optional && data->elem == MIR_STR && last == NS_STR_MUT; /* `to_string_radix`: a flag and a String */
  /* An optional that is the whole value (`replace` on a list of optionals): the native writes all of it. */
  const bool whole = data->kind == MK_OPT && !sig->status && sig->count > 0 && last == NS_ADDR_MUT;
  const bool listed = optional && last == NS_VEC_MUT && data->elem != MIR_STR; /* `find_span`: a flag and a list */
  if (!(scalar || optional || whole) || (last != NS_ADDR_MUT && last != NS_OUT_SCALAR && !text && !listed)) {
    return MIR_NONE;
  }
  const MirImm of_type = {.tag = MI_TY, .a = optional ? data->elem : ret};
  const MirValue slot = fn_emit(fn, MOP_Slot, NULL, 0, of_type, MIR_PTR);
  if (text) { /* the runtime writes the String over an empty one */
    const MirImm empty = {.tag = MI_STR, .a = mir_add_string(fn->cx->module, ms_span_of_text(""))};
    const MirValue stored[2] = {slot, mir_b_emit(&fn->b, MOP_StrLit, NULL, 0, empty, MIR_STR)};
    (void)mir_b_emit(&fn->b, MOP_Store, stored, 2, (MirImm){0}, MIR_NONE);
  }
  return slot;
}


/* A native that answers whether it filled the payload slot `slot`: the Optional holds the payload, or is none. */
static MirValue optional_from_status(LowerFn *fn, MsName name, MirValue *wanted, uint32_t count, MirTy ret, MirValue slot) {
  const uint32_t external = fn_runtime_extern(fn, name, wanted, count, MIR_UINT8);
  const MirValue status = mir_b_call_rt(&fn->b, external, wanted, count);
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
  const MirTy payload = mir_ty_data(fn->cx->module, ret)->elem;
  const MirImm of_type = {.tag = MI_TY, .a = payload};
  const MirValue value = mir_b_emit(&fn->b, mir_needs_drop(fn->cx->module, payload) ? MOP_Take : MOP_Load, &slot, 1, of_type, payload);
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
  return result;
}

/* Calls `name` with `wanted`, through a result slot when `slot` is set. */
static MirValue call_native(LowerFn *fn, MsName name, MirValue *wanted, uint32_t count, MirTy ret, MirValue slot) {
  if (slot == MIR_NONE) {
    return fn_runtime_call(fn, name, wanted, count, ret);
  }
  wanted[count++] = slot;
  const MirTyData *data = mir_ty_data(fn->cx->module, ret);
  const MsNativeSig *answers = ms_native_sig_find(ms_names_span(&fn->cx->module->names, name));
  if (data->kind == MK_OPT && (answers == NULL || answers->status)) {
    return optional_from_status(fn, name, wanted, count, ret, slot);
  }
  (void)fn_runtime_call(fn, name, wanted, count, MIR_VOID);
  const MirImm of_type = {.tag = MI_TY, .a = ret};
  return fn_emit(fn, MOP_Load, &slot, 1, of_type, ret);
}

/* The runtime function `name` taking the types of `args` and returning `ret`. */
/* The role of a runtime string function the optimiser answers inline for the common case (`opt_strfast`). */
static MirRole string_role(MsSpan name) {
  static const struct {
    const char *name;
    MirRole role;
  } table[] = {{"msrt_string_eq", MR_STRING_EQ},
               {"msrt_string_compare", MR_STRING_COMPARE},
               {"msrt_string_starts_with", MR_STRING_STARTS_WITH},
               {"msrt_string_ends_with", MR_STRING_ENDS_WITH}};
  for (size_t at = 0; at < sizeof table / sizeof table[0]; at++) {
    if (ms_span_is_text(name, table[at].name)) {
      return table[at].role;
    }
  }
  return MR_NONE;
}

uint32_t fn_runtime_extern(LowerFn *fn, MsName name, const MirValue *args, uint32_t nargs, MirTy ret) {
  MirParam *params = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, MirParam, (size_t)nargs + 1);
  for (uint32_t index = 0; index < nargs; index++) {
    params[index] = (MirParam){mir_b_ty(&fn->b, args[index]),
                               (uint8_t)(index < 32 && (fn->native_moves >> index & 1u) != 0 ? MM_MOVE : MM_BORROW)};
  }
  fn->native_moves = 0;
  const MsSpan text = ms_names_span(&fn->cx->module->names, name);
  const MsNativeSig *sig = ms_native_sig_find(text);
  const bool views = sig != NULL && sig->borrows;
  const MirExtern def = {.name = name, .params = params, .nparams = nargs, .ret = ret,
                         .fresh = !views && mir_needs_drop(fn->cx->module, ret),
                         .role = (uint8_t)(views ? MR_VIEW_RESULT : string_role(text))};
  return mir_extern_intern(fn->cx->module, &def);
}

MirValue fn_runtime_call(LowerFn *fn, MsName name, const MirValue *args, uint32_t nargs, MirTy ret) {
  const uint32_t external = fn_runtime_extern(fn, name, args, nargs, ret);
  const MirValue result = mir_b_call_rt(&fn->b, external, args, nargs);
  fn_own_result(fn, result);
  return result;
}

/* Whether the first parameter of `sig` is the receiver the native writes in place (a `var` list, string or
 * map), rather than the result slot. */
static bool mutates_receiver(const MsNativeSig *sig, MirTy ret) {
  const uint8_t kind = sig->count > 0 ? sig->kinds[0] : NS_VALUE;
  const bool mutable_kind = kind == NS_VEC_MUT || kind == NS_STR_MUT || kind == NS_MAP_MUT;
  return mutable_kind && !(ret != MIR_VOID && sig->count == 1);
}

/* The local a call's receiver names, or NULL when the receiver is not a plain local. */

/* An operand in a new slot of its own: the runtime function takes the value from the slot's address. A `lookup`
 * only reads the value (a map key it searches for), so the slot borrows it and nothing is copied. */
static MirValue operand_slot(LowerFn *fn, const MsExpr *expr, bool lookup) {
  MirValue value = fn_expr(fn, expr, lookup ? LW_BORROW : LW_MOVE);
  if (value == MIR_NONE) {
    return MIR_NONE;
  }
  const MirTy ty = mir_b_ty(&fn->b, value);
  const bool owns = !lookup && mir_needs_drop(fn->cx->module, ty);
  if (owns) {
    const bool fresh = fn_fresh_owner(fn, value);
    value = fresh ? value : fn_implicit_clone(fn, value, false);
    if (fresh) {
      (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &value, 1, (MirImm){0}, MIR_NONE);
    }
  }
  const MirImm of_type = {.tag = MI_TY, .a = ty};
  const MirValue slot = mir_b_emit(&fn->b, MOP_Slot, NULL, 0, of_type, MIR_PTR);
  const MirValue stored[2] = {slot, value};
  (void)mir_b_emit(&fn->b, owns ? MOP_Put : MOP_Store, stored, 2, (MirImm){0}, MIR_NONE);
  return slot;
}

MirValue fn_map_literal(LowerFn *fn, const MsExpr *expr) {
  MirTy ty = fn_type(fn, ms_facts_type(fn->facts, expr->id));
  const MirTyData *data = mir_ty_data(fn->cx->module, ty);
  if (fn->hint != MIR_VOID && (data->kind != MK_OBJ || data->obj_class != MIR_OBJ_COLLECTION || data->nargs < 2)) {
    ty = fn->hint; /* the checker left the literal's type open: the parameter it fills gives it */
    data = mir_ty_data(fn->cx->module, ty);
  }
  if (data->kind != MK_OBJ || data->obj_class != MIR_OBJ_COLLECTION || data->nargs < 2) {
    (void)fn_fail(fn, "a map literal is not typed as a map");
    return MIR_NONE;
  }
  const MirValue empty = fn_runtime_call(fn, mir_name(fn->cx->module, ms_span_of_text("msrt_map_new")), NULL, 0, ty);
  (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &empty, 1, (MirImm){0}, MIR_NONE);
  const MirImm of_map = {.tag = MI_TY, .a = ty};
  const MirValue map = mir_b_emit(&fn->b, MOP_Slot, NULL, 0, of_map, MIR_PTR);
  const MirValue created[2] = {map, empty};
  (void)mir_b_emit(&fn->b, MOP_Put, created, 2, (MirImm){0}, MIR_NONE);
  const MirImm key_ty = {.tag = MI_TY, .a = data->args[0]};
  const MirImm value_ty = {.tag = MI_TY, .a = data->args[1]};
  const MsName add = mir_name(fn->cx->module, ms_span_of_text("msrt_map_add"));
  for (uint32_t at = 0; at < expr->u.map.len; at++) {
    const MirValue key = operand_slot(fn, expr->u.map.ptr[at].key, false);
    const MirValue value = key == MIR_NONE ? MIR_NONE : operand_slot(fn, expr->u.map.ptr[at].value, false);
    if (value == MIR_NONE) {
      return MIR_NONE;
    }
    const MirValue key_desc = mir_b_emit(&fn->b, MOP_TypeDesc, NULL, 0, key_ty, MIR_PTR);
    const MirValue value_desc = mir_b_emit(&fn->b, MOP_TypeDesc, NULL, 0, value_ty, MIR_PTR);
    const MirValue operands[5] = {map, key_desc, value_desc, key, value};
    (void)fn_runtime_call(fn, add, operands, 5, MIR_VOID);
  }
  return fn_emit(fn, MOP_Take, &map, 1, of_map, ty);
}

/* `map[key]`: an owned copy of the value; a missing key faults with the key's text. */
MirValue fn_map_index(LowerFn *fn, MirValue map, const MsExpr *key_expr, MirTy ty) {
  const MirTyData *data = mir_ty_data(fn->cx->module, ty);
  const MirValue key = operand_slot(fn, key_expr, true);
  if (key == MIR_NONE) {
    return MIR_NONE;
  }
  const MirImm key_ty = {.tag = MI_TY, .a = data->args[0]};
  const MirImm value_ty = {.tag = MI_TY, .a = data->args[1]};
  const MirValue key_desc = mir_b_emit(&fn->b, MOP_TypeDesc, NULL, 0, key_ty, MIR_PTR);
  const MirValue value_desc = mir_b_emit(&fn->b, MOP_TypeDesc, NULL, 0, value_ty, MIR_PTR);
  const MirValue out = mir_b_emit(&fn->b, MOP_Slot, NULL, 0, value_ty, MIR_PTR);
  const MirValue operands[5] = {map, key_desc, value_desc, key, out};
  const MirValue found = fn_runtime_call(fn, mir_name(fn->cx->module, ms_span_of_text("msrt_map_get")), operands, 5, MIR_BOOL);
  const bool owns_value = mir_needs_drop(fn->cx->module, data->args[1]);
  const MirBlock hit = mir_b_new_block(&fn->b);
  const MirBlock miss = mir_b_new_block(&fn->b);
  mir_b_br_if(&fn->b, found, hit, NULL, 0, miss, NULL, 0);
  mir_b_seal_block(&fn->b, hit);
  mir_b_seal_block(&fn->b, miss);
  mir_b_switch_to(&fn->b, miss);
  const MirValue missing = mir_b_emit(&fn->b, MOP_Load, &key, 1, key_ty, data->args[0]);
  const MirValue text = fn_value_repr(fn, missing, data->args[0]);
  const MirValue prefix_lit = mir_b_emit(&fn->b, MOP_StrLit, NULL, 0,
                                         (MirImm){.tag = MI_STR, .a = mir_add_string(fn->cx->module, ms_span_of_text("map key not found: "))},
                                         MIR_STR);
  const MirValue parts[2] = {prefix_lit, text};
  const MirValue message = fn_runtime_call(fn, mir_name(fn->cx->module, ms_span_of_text("msrt_string_concat")), parts, 2, MIR_STR);
  (void)fn_runtime_call(fn, mir_name(fn->cx->module, ms_span_of_text("msrt_fault_string")), &message, 1, MIR_VOID);
  mir_b_unreachable(&fn->b);
  mir_b_switch_to(&fn->b, hit);
  return mir_b_emit(&fn->b, owns_value ? MOP_Take : MOP_Load, &out, 1, value_ty, data->args[1]);
}

/* The address of the entry `place[key]?` names in a list or map, or a null pointer when there is none (a list index
 * out of range counts from nothing: a negative index is no entry). `entry_ty` is the entry's type. */
MirValue fn_entry_address(LowerFn *fn, MirValue container, const MsExpr *key_expr, MirTy *entry_ty) {
  const MirTy ty = mir_b_ty(&fn->b, container);
  const MirTyData *data = mir_ty_data(fn->cx->module, ty);
  if (data->kind == MK_OBJ && data->obj_class == MIR_OBJ_COLLECTION && data->nargs >= 2) {
    const MirValue key = operand_slot(fn, key_expr, true);
    if (key == MIR_NONE) {
      return MIR_NONE;
    }
    const MirImm key_ty = {.tag = MI_TY, .a = data->args[0]};
    const MirImm value_ty = {.tag = MI_TY, .a = data->args[1]};
    const MirValue key_desc = mir_b_emit(&fn->b, MOP_TypeDesc, NULL, 0, key_ty, MIR_PTR);
    const MirValue value_desc = mir_b_emit(&fn->b, MOP_TypeDesc, NULL, 0, value_ty, MIR_PTR);
    const MirValue operands[4] = {container, key_desc, value_desc, key};
    const MirValue address = fn_runtime_call(fn, mir_name(fn->cx->module, ms_span_of_text("msrt_map_get_ptr")), operands, 4, MIR_PTR);
    *entry_ty = data->args[1];
    return address;
  }
  if (data->kind != MK_LIST) {
    (void)fn_fail(fn, "only a list or a map can be probed");
    return MIR_NONE;
  }
  const MirValue at = fn_expr(fn, key_expr, LW_BORROW);
  if (at == MIR_NONE) {
    return MIR_NONE;
  }
  const MirValue zero = mir_b_iconst(&fn->b, 0);
  const MirValue length = mir_b_emit(&fn->b, MOP_ListLen, &container, 1, (MirImm){0}, MIR_INT);
  const MirValue not_negative = mir_b_icmp(&fn->b, MCC_GE, at, zero);
  const MirValue below = mir_b_icmp(&fn->b, MCC_LT, at, length);
  const MirValue inside = mir_b_select(&fn->b, not_negative, below, mir_b_bconst(&fn->b, false));
  const MirBlock hit = mir_b_new_block(&fn->b);
  const MirBlock miss = mir_b_new_block(&fn->b);
  const MirBlock join = mir_b_new_block(&fn->b);
  const MirValue address = mir_b_add_block_param(&fn->b, join, MIR_PTR, MM_BORROW);
  mir_b_br_if(&fn->b, inside, hit, NULL, 0, miss, NULL, 0);
  mir_b_seal_block(&fn->b, hit);
  mir_b_seal_block(&fn->b, miss);
  mir_b_switch_to(&fn->b, hit);
  const MirValue operands[2] = {container, at};
  const MirValue found = mir_b_emit(&fn->b, MOP_ListAddrU, operands, 2, (MirImm){0}, MIR_PTR);
  mir_b_br(&fn->b, join, &found, 1);
  mir_b_switch_to(&fn->b, miss);
  const MirValue absent = mir_b_emit(&fn->b, MOP_PtrNull, NULL, 0, (MirImm){0}, MIR_PTR);
  mir_b_br(&fn->b, join, &absent, 1);
  mir_b_seal_block(&fn->b, join);
  mir_b_switch_to(&fn->b, join);
  *entry_ty = data->elem;
  return address;
}

/* Whether `expr` names a list through variables, fields and list elements only: borrowing it gives the list
 * where it lies, not a copy (a map element is read out as a copy). */
static bool lists_in_place(LowerFn *fn, const MsExpr *expr) {
  MsExpr *container = NULL;
  MsExpr *key = NULL;
  if (expr->kind == MS_E_NAME) {
    return true;
  }
  if (expr->kind == MS_E_MEMBER) {
    return lists_in_place(fn, expr->u.member.left);
  }
  if (!ms_expr_index(expr, &container, &key)) {
    return false;
  }
  MsTyTable *types = &fn->cx->program->types;
  const MsTy owner = ms_ty_subst(types, ms_facts_type(fn->facts, container->id), fn->subst.vars, fn->subst.args, fn->subst.count);
  return ms_ty_is(types, owner, MS_BUILTIN_List) && lists_in_place(fn, container);
}

/* `place?` where `place` can be changed: the method changes the optional's payload in place. */
static bool is_try_place(LowerFn *fn, const MsExpr *place) {
  return place != NULL && place->kind == MS_E_UNARY && place->op == MS_U_TRY && fn_place_changeable(fn, place->u.bin.left);
}

/* `xs[i]` of a list held in place: whether `place` is one, and then `*addr` is the element's address (MIR_NONE
 * when the list or the index has no value). A method that changes the element does so where it lies. */
bool fn_list_element_addr(LowerFn *fn, const MsExpr *place, MirValue *addr) {
  MsExpr *container = NULL;
  MsExpr *key = NULL;
  *addr = MIR_NONE;
  if (!ms_expr_index(place, &container, &key) || !fn_is_list(fn, container) || !lists_in_place(fn, container)) {
    return false;
  }
  const MirValue list = fn_expr(fn, container, LW_BORROW);
  if (list == MIR_NONE) {
    return false;
  }
  const MirValue at = fn_expr(fn, key, LW_BORROW);
  if (at != MIR_NONE) {
    const MirValue operands[2] = {list, at};
    *addr = mir_b_emit(&fn->b, MOP_ListAddr, operands, 2, (MirImm){0}, MIR_PTR);
  }
  return true;
}

/* A native that changes its receiver (`var` list or string): the receiver's value moves into a slot, the native
 * writes through the slot's address, and the value in the slot goes back to the place. `wanted[0]` is replaced. */
static MirValue call_changing(LowerFn *fn, const MsExpr *place, MsName name, MirValue *wanted, uint32_t count,
                              MirTy ret, MirValue result_slot) {
  /* An element of a list: the native changes it where it lies, through the element's address. */
  MirValue element = MIR_NONE;
  if (fn_list_element_addr(fn, place, &element)) {
    if (element == MIR_NONE) {
      return MIR_NONE;
    }
    wanted[0] = element;
    return call_native(fn, name, wanted, count, ret, result_slot);
  }
  if (is_try_place(fn, place)) {
    VarSlot var;
    const MirValue slot = fn_try_var_slot(fn, place, &var);
    if (slot == MIR_NONE) {
      return MIR_NONE;
    }
    wanted[0] = slot;
    const MirValue result = call_native(fn, name, wanted, count, ret, result_slot);
    return fn_var_slots_back(fn, &var, 1) ? result : MIR_NONE;
  }
  MirValue owned;
  MirValue record = MIR_NONE;
  const bool in_place = fn_take_field(fn, place, &record, &owned);
  if (!in_place && !fn_take_place(fn, place, &owned)) {
    return MIR_NONE;
  }
  const MirTy ty = mir_b_ty(&fn->b, owned);
  const MirImm of_type = {.tag = MI_TY, .a = ty};
  const MirValue slot = mir_b_emit(&fn->b, MOP_Slot, NULL, 0, of_type, MIR_PTR);
  const MirValue stored[2] = {slot, owned};
  (void)mir_b_emit(&fn->b, MOP_Put, stored, 2, (MirImm){0}, MIR_NONE);
  wanted[0] = slot;
  const MirValue result = call_native(fn, name, wanted, count, ret, result_slot);
  const MirValue updated = mir_b_emit(&fn->b, MOP_Take, &slot, 1, of_type, ty);
  if (in_place ? !fn_put_field(fn, place, record, updated) : !fn_put_place(fn, place, updated)) {
    return MIR_NONE;
  }
  return result;
}

/* `list.get(index)`: the element, a negative index counting from the end; an index out of range faults. */
/* A native declared `@op=<name>` is one MIR instruction on Int operands: the standard wrapper has already checked a
 * shift count, and a rotation takes its count modulo 64. */
bool fn_inline_scalar_op(LowerFn *fn, const char *name, const MirValue *args, uint32_t argc, MirValue *out) {
  static const struct {
    const char *name;
    MirOp op;
    uint32_t operands;
  } ops[] = {{"and", MOP_And, 2},       {"or", MOP_Or, 2},     {"xor", MOP_Xor, 2},       {"shl", MOP_Shl, 2},
             {"sshr", MOP_Sshr, 2},     {"ushr", MOP_Ushr, 2}, {"rotl", MOP_Rotl, 2},     {"rotr", MOP_Rotr, 2},
             {"popcnt", MOP_Popcnt, 1}, {"clz", MOP_Clz, 1}};
  for (size_t at = 0; at < MS_COUNT_OF(ops); at++) {
    if (!ms_span_is_text(ms_span_of_text(name), ops[at].name) || argc != ops[at].operands) {
      continue;
    }
    if (mir_b_ty(&fn->b, args[0]) != MIR_INT) {
      return false;
    }
    *out = argc == 2 ? mir_b_binop(&fn->b, ops[at].op, args[0], args[1])
                     : mir_b_emit(&fn->b, ops[at].op, args, 1, (MirImm){0}, MIR_INT);
    return true;
  }
  return false;
}

static MirValue list_get(LowerFn *fn, MirValue list, MirValue index, MirTy elem) {
  const MirValue length = mir_b_emit(&fn->b, MOP_ListLen, &list, 1, (MirImm){0}, MIR_INT);
  const MirValue from_end = mir_b_binop(&fn->b, MOP_IAdd, index, length);
  const MirValue negative = mir_b_icmp(&fn->b, MCC_LT, index, mir_b_iconst(&fn->b, 0));
  const MirValue at = mir_b_select(&fn->b, negative, from_end, index);
  const MirValue args[2] = {list, at};
  return mir_b_emit(&fn->b, MOP_ListGet, args, 2, (MirImm){0}, elem);
}

/* A native that changes a list receiver in line: the list is taken out of its slot or place, and `list_put` puts
 * the updated list back. False when the receiver is neither (nothing is emitted then). */
static bool list_changeable(LowerFn *fn, const MsExpr *place, MirValue slot) {
  if (slot != MIR_NONE) {
    return true;
  }
  /* An element of a list held in place changes where it lies (`call_changing`), not through a copy put back. */
  MsExpr *container = NULL;
  MsExpr *key = NULL;
  if (place != NULL && ms_expr_index(place, &container, &key) && fn_is_list(fn, container) && lists_in_place(fn, container)) {
    return false;
  }
  return place != NULL && fn_place_changeable(fn, place);
}

static bool list_take(LowerFn *fn, const MsExpr *place, MirValue slot, MirTy list_ty, MirValue *owned, MirValue *record) {
  *record = MIR_NONE;
  if (slot != MIR_NONE) {
    *owned = mir_b_emit(&fn->b, MOP_Take, &slot, 1, (MirImm){.tag = MI_TY, .a = list_ty}, list_ty);
    return true;
  }
  return fn_take_field(fn, place, record, owned) || fn_take_place(fn, place, owned);
}

static bool list_put(LowerFn *fn, const MsExpr *place, MirValue slot, MirValue record, MirValue updated) {
  if (record != MIR_NONE) {
    return fn_put_field(fn, place, record, updated);
  }
  if (slot == MIR_NONE) {
    return fn_put_place(fn, place, updated);
  }
  const MirValue stored[2] = {slot, updated};
  (void)mir_b_emit(&fn->b, MOP_Put, stored, 2, (MirImm){0}, MIR_NONE);
  return true;
}

/* `list.append(value)`: the list grows in line (a full list calls the grow block) and the updated list goes back. */
static bool list_append(LowerFn *fn, const MsExpr *place, MirValue slot, const MirValue *args, MirValue *out) {
  const MirTy list_ty = mir_b_ty(&fn->b, args[0]);
  const MirTyData *list = mir_ty_data(fn->cx->module, list_ty);
  MirValue owned;
  MirValue record;
  if (list->kind != MK_LIST || mir_b_ty(&fn->b, args[1]) != list->elem || !list_changeable(fn, place, slot) ||
      (slot == MIR_NONE && place->kind != MS_E_NAME) ||
      !list_take(fn, place, slot, list_ty, &owned, &record)) {
    return false;
  }
  const MirValue operands[2] = {owned, args[1]};
  const MirValue updated = mir_b_emit(&fn->b, MOP_ListPush, operands, 2, (MirImm){0}, list_ty);
  *out = mir_b_emit(&fn->b, MOP_VoidConst, NULL, 0, (MirImm){0}, MIR_VOID);
  return list_put(fn, place, slot, record, updated);
}

/* `list.set(index, value)` on a list of plain values (an element that owns something needs the runtime to drop the
 * old one): the receiver is taken out of its place or slot, the index is checked with the runtime's `List.set`
 * fault, the element is stored by `list.set.u`, and the updated list goes back. */
static bool list_set(LowerFn *fn, const MsExpr *place, MirValue slot, const MirValue *args, MirValue *out) {
  const MirTy list_ty = mir_b_ty(&fn->b, args[0]);
  const MirTyData *list = mir_ty_data(fn->cx->module, list_ty);
  if (list->kind != MK_LIST || mir_needs_drop(fn->cx->module, list->elem) || mir_b_ty(&fn->b, args[2]) != list->elem) {
    return false;
  }
  if (!list_changeable(fn, place, slot)) {
    return false;
  }
  const MirValue length = mir_b_emit(&fn->b, MOP_ListLen, &args[0], 1, (MirImm){0}, MIR_INT);
  const MirValue zero = mir_b_iconst(&fn->b, 0);
  const MirValue negative = mir_b_icmp(&fn->b, MCC_LT, args[1], zero);
  const MirValue at = mir_b_select(&fn->b, negative, mir_b_binop(&fn->b, MOP_IAdd, args[1], length), args[1]);
  const MirValue pair[2] = {at, length};
  const MirValue inside = mir_b_emit(&fn->b, MOP_UICmp, pair, 2, (MirImm){.tag = MI_CC, .a = (uint32_t)MCC_LT}, MIR_BOOL);
  const MirBlock hit = mir_b_new_block(&fn->b);
  const MirBlock miss = mir_b_new_block(&fn->b);
  mir_b_br_if(&fn->b, inside, hit, NULL, 0, miss, NULL, 0);
  mir_b_seal_block(&fn->b, hit);
  mir_b_seal_block(&fn->b, miss);
  mir_b_switch_to(&fn->b, miss);
  const MirValue fault_args[3] = {mir_b_iconst(&fn->b, 2), args[1], length};
  (void)fn_runtime_call(fn, mir_name(fn->cx->module, ms_span_of_text("msrt_list_index_fault")), fault_args, 3, MIR_VOID);
  mir_b_unreachable(&fn->b);
  mir_b_switch_to(&fn->b, hit);
  MirValue owned;
  MirValue record;
  if (!list_take(fn, place, slot, list_ty, &owned, &record)) {
    return false;
  }
  const MirValue operands[3] = {owned, at, args[2]};
  const MirValue updated = mir_b_emit(&fn->b, MOP_ListSetU, operands, 3, (MirImm){0}, list_ty);
  *out = mir_b_emit(&fn->b, MOP_VoidConst, NULL, 0, (MirImm){0}, MIR_VOID);
  return list_put(fn, place, slot, record, updated);
}

/* `String.scalar_at(offset)`: the scalar at a byte offset is the byte itself when it is ASCII, so that case is read
 * in line; any other offset (inside a multibyte scalar, out of range, or a default to answer) calls the runtime. */
static MirValue scalar_at_inline(LowerFn *fn, MsName name, const MsNativeSig *sig, const MirValue *args, MirValue *wanted,
                                 uint32_t count, MirTy ret) {
  const MirValue length = mir_b_emit(&fn->b, MOP_StrBytes, &args[0], 1, (MirImm){0}, MIR_INT);
  const MirValue pair[2] = {args[1], length};
  const MirValue inside = mir_b_emit(&fn->b, MOP_UICmp, pair, 2, (MirImm){.tag = MI_CC, .a = (uint32_t)MCC_LT}, MIR_BOOL);
  const MirBlock probe = mir_b_new_block(&fn->b);
  const MirBlock slow = mir_b_new_block(&fn->b);
  const MirBlock join = mir_b_new_block(&fn->b);
  const MirValue result = mir_b_add_block_param(&fn->b, join, MIR_INT, MM_BORROW);
  mir_b_br_if(&fn->b, inside, probe, NULL, 0, slow, NULL, 0);
  mir_b_seal_block(&fn->b, probe);
  mir_b_switch_to(&fn->b, probe);
  const MirValue byte = mir_b_emit(&fn->b, MOP_StrByte, args, 2, (MirImm){0}, MIR_INT);
  const MirValue ascii = mir_b_icmp(&fn->b, MCC_LT, byte, mir_b_iconst(&fn->b, 128));
  mir_b_br_if(&fn->b, ascii, join, &byte, 1, slow, NULL, 0);
  mir_b_seal_block(&fn->b, slow);
  mir_b_switch_to(&fn->b, slow);
  const MirValue other = call_native(fn, name, wanted, count, ret, scalar_result_slot(fn, sig, ret));
  mir_b_br(&fn->b, join, &other, 1);
  mir_b_seal_block(&fn->b, join);
  mir_b_switch_to(&fn->b, join);
  return result;
}

/* Whether the operation is declared on a type variable (`v.to_string()` with a bound): the native has no name of
 * its own, the concrete receiver of the instance decides. */
static bool generic_receiver(const LowerFn *fn, const MsCall *call) {
  const MsTyTable *types = &fn->cx->program->types;
  return ms_ty_kind(types, call->callee.owner) != MS_TY_NATIVE && ms_builtin_name(ms_ty_builtin(types, call->callee.owner))[0] == 0;
}

/* The standard form of a bodiless operation every value has (intrinsics.ms), read from its signature: an operation
 * that returns the receiver's own type is the structural copy, one that returns String is the text of the value. */
static bool standard_form(LowerFn *fn, const MirValue *args, uint32_t count, MirTy ret, MirValue *out) {
  if (count != 1) {
    return false;
  }
  const MirTy type = mir_b_ty(&fn->b, args[0]);
  if (ret == type) {
    *out = mir_needs_drop(fn->cx->module, type) ? fn_emit(fn, MOP_Clone, args, 1, (MirImm){0}, type) : args[0];
    return true;
  }
  if (ret == MIR_STR) {
    *out = type == MIR_STR ? fn_emit(fn, MOP_Clone, args, 1, (MirImm){0}, MIR_STR) : fn_value_text(fn, args[0], type);
    return true;
  }
  return false;
}

/* `to_string` and `clone` on a value whose type the instance knows: the type's own method when it has one,
 * else the standard form (text through the shape, a structural copy). */
static MirValue bound_native(LowerFn *fn, const MsExpr *callee, const MsCall *call, const MirValue *args, MirTy ret) {
  const MsSpan operation = ms_names_span(fn->cx->program->names, callee->u.member.name);
  const MsTy receiver = ms_ty_subst(&fn->cx->program->types, ms_facts_type(fn->facts, callee->u.member.left->id),
                                    fn->subst.vars, fn->subst.args, fn->subst.count);
  const uint32_t method = lower_operation_method(fn->cx, receiver, callee->u.member.name);
  if (method != MIR_NONE && fn->cx->module->funcs.ptr[method].ret == ret) { /* a method of another result type is not the operation */
    const MirValue result = mir_b_call(&fn->b, method, args, call->arg_count);
    fn_own_result(fn, result);
    return result;
  }
  MirValue standard;
  if (standard_form(fn, args, call->arg_count, ret, &standard)) {
    return standard;
  }
  (void)fn_fail(fn, "the operation `%.*s` on a value of a bound type is not lowered yet", (int)operation.len, (const char *)operation.ptr);
  return MIR_NONE;
}

MirValue fn_builtin_call(LowerFn *fn, const MsCall *call, const MirValue *args, MirTy ret) {
  return fn_builtin_named(fn, fn_symbol_at(fn->cx, call->callee.decl), call->arg_count, args, ret);
}

MirValue fn_builtin_named(LowerFn *fn, MsSymbolId id, uint32_t arg_count, const MirValue *args, MirTy ret) {
  const MsSymbol *symbol = &fn->cx->program->symbols.ptr[id];
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "msrt_");
  ms_strbuild_append(&text, ms_names_span(fn->cx->program->names, symbol->name));
  const MsName name = mir_name(fn->cx->module, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  const MsNativeSig *sig = ms_native_sig_find(ms_names_span(&fn->cx->module->names, name));
  MirValue expanded;
  /* The runtime cannot read a record of the program's own type, so building a map from entries is expanded here. */
  if (sig == NULL && arg_count == 1 && ms_span_is_text(ms_names_span(fn->cx->program->names, symbol->name), "map_from_entries") &&
      fn_map_from_entries(fn, args, ret, &expanded)) {
    return expanded;
  }
  MirValue wanted[NS_MAX_PARAMS];
  uint32_t count = 0;
  if (sig != NULL && arg_count <= NS_MAX_PARAMS &&
      signature_arguments(fn, sig, args, arg_count, ret, wanted, &count)) {
    return call_native(fn, name, wanted, count, ret, scalar_result_slot(fn, sig, ret));
  }
  return fn_runtime_call(fn, name, args, arg_count, ret);
}

/* The runtime signature of `operation` on `owner`, and the runtime function's name. */
static const MsNativeSig *native_sig_of(LowerFn *fn, MsTy owner, MsSpan operation, MsName *name) {
  const MsTyTable *types = &fn->cx->program->types;
  /* A standard type with no builtin id (an extern type such as StringBuilder) is named by its declaration. */
  const char *builtin_name = ms_builtin_name(ms_ty_builtin(types, owner));
  const MsSpan type_name = builtin_name[0] != '\0' ? ms_span_of_text(builtin_name)
                                                   : ms_names_span(fn->cx->program->names, ms_ty_row(types, owner)->name);
  const MsNativeSig *named = ms_native_sig_find_method(type_name, operation);
  *name = named != NULL ? mir_name(fn->cx->module, ms_span_of_text(named->name)) : runtime_name(fn, owner, operation);
  return named != NULL ? named : ms_native_sig_find(ms_names_span(&fn->cx->module->names, *name));
}

bool fn_native_changes_receiver(LowerFn *fn, MsTy owner, MsSpan operation, MirTy ret) {
  MsName name;
  const MsNativeSig *sig = native_sig_of(fn, owner, operation, &name);
  return sig != NULL && mutates_receiver(sig, ret);
}

/* `slot` is the address of the receiver's storage when the receiver is not a place of this function (a bound
 * method value): a native that changes its receiver writes through it. */
static bool native_on(LowerFn *fn, const MsExpr *place, MirValue slot, MsTy owner, MsSpan operation, uint32_t argc,
                      const MirValue *args, MirTy ret, MirValue *out) {
  MsName name;
  const MsNativeSig *sig = native_sig_of(fn, owner, operation, &name);
  if (sig == NULL && argc == 2 && ms_span_is_text(operation, "group_by") && fn_list_group_by(fn, args, ret, out)) {
    return true;
  }
  if (sig == NULL) {
    /* An operation every value has (`to_string`) is done by the walker over its shape. */
    if (argc == 0 || mir_is_scalar(fn->cx->module, mir_b_ty(&fn->b, args[0]))) {
      return false; /* a scalar has its own forms of these */
    }
    *out = fn_value_operation(fn, operation, args, argc, ret);
    return *out != MIR_NONE;
  }
  if (sig->inline_op != NULL && fn_inline_scalar_op(fn, sig->inline_op, args, argc, out)) {
    return true;
  }
  if (sig->inline_op != NULL && ms_span_is_text(ms_span_of_text(sig->inline_op), "list_get") && argc == 2) {
    *out = list_get(fn, args[0], args[1], ret);
    return true;
  }
  if (sig->inline_op != NULL && ms_span_is_text(ms_span_of_text(sig->inline_op), "list_set") && argc == 3 &&
      list_set(fn, place, slot, args, out)) {
    return true;
  }
  if (sig->inline_op != NULL && ms_span_is_text(ms_span_of_text(sig->inline_op), "list_append") && argc == 2 &&
      list_append(fn, place, slot, args, out)) {
    return true;
  }
  if (sig->status && mir_ty_data(fn->cx->module, ret)->kind == MK_ALT && slot == MIR_NONE &&
      fn_status_call(fn, name, UINT32_MAX, args, argc, ret, out)) {
    return true; /* a `T!` operation: the runtime answers a status, the error is built from it */
  }
  MirValue wanted[NS_MAX_PARAMS];
  uint32_t count = 0;
  if (argc <= NS_MAX_PARAMS && signature_arguments(fn, sig, args, argc, ret, wanted, &count)) {
    if (sig->inline_op != NULL && ms_span_is_text(ms_span_of_text(sig->inline_op), "scalar_at") && argc >= 2 &&
        ret == MIR_INT && mir_b_ty(&fn->b, args[0]) == MIR_STR) {
      *out = scalar_at_inline(fn, name, sig, args, wanted, count, ret);
      return true;
    }
    if (slot != MIR_NONE && mutates_receiver(sig, ret)) {
      wanted[0] = slot;
      *out = call_native(fn, name, wanted, count, ret, scalar_result_slot(fn, sig, ret));
    } else if (mutates_receiver(sig, ret) && (fn_place_changeable(fn, place) || is_try_place(fn, place))) {
      *out = call_changing(fn, place, name, wanted, count, ret, scalar_result_slot(fn, sig, ret));
    } else if (mutates_receiver(sig, ret) && argc > 0 && wanted[0] == args[0] && fn_fresh_owner(fn, args[0])) {
      /* A temporary receiver (`[0].append(9)`): the native may regrow it through its slot, so the temporary's owner
       * becomes the value the slot holds afterwards. */
      const MirTy ty = mir_b_ty(&fn->b, args[0]);
      const MirImm of_type = {.tag = MI_TY, .a = ty};
      const MirValue held = mir_b_emit(&fn->b, MOP_Slot, NULL, 0, of_type, MIR_PTR);
      const MirValue stored[2] = {held, args[0]};
      (void)mir_b_emit(&fn->b, MOP_Put, stored, 2, (MirImm){0}, MIR_NONE);
      (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &args[0], 1, (MirImm){0}, MIR_NONE);
      wanted[0] = held;
      *out = call_native(fn, name, wanted, count, ret, scalar_result_slot(fn, sig, ret));
      fn_own(fn, fn_scope(fn), mir_b_emit(&fn->b, MOP_Take, &held, 1, of_type, ty));
    } else {
      *out = call_native(fn, name, wanted, count, ret, scalar_result_slot(fn, sig, ret));
    }
    return true;
  }
  *out = fn_runtime_call(fn, name, args, argc, ret);
  return true;
}

bool fn_native_on(LowerFn *fn, const MsExpr *place, MsTy owner, MsSpan operation, uint32_t argc, const MirValue *args,
                  MirTy ret, MirValue *out) {
  return native_on(fn, place, MIR_NONE, owner, operation, argc, args, ret, out);
}

bool fn_native_through(LowerFn *fn, MirValue slot, MsTy owner, MsSpan operation, uint32_t argc, const MirValue *args,
                       MirTy ret, MirValue *out) {
  return native_on(fn, NULL, slot, owner, operation, argc, args, ret, out);
}

/* An extern function a standard-library body calls by its runtime name (`msrt_list_distinct(self)`): when its
 * signature names element, key or value descriptors, or a trailing result, the operands are built as for the
 * method it implements. False when the signature needs none of that. */
bool fn_signature_extern_call(LowerFn *fn, MsName name, const MirValue *args, uint32_t nargs, MirTy ret, MirValue *out) {
  const MsNativeSig *sig = ms_native_sig_find(ms_names_span(&fn->cx->module->names, name));
  if (sig == NULL || nargs > NS_MAX_PARAMS) {
    return false;
  }
  bool described = false;
  for (uint32_t at = 0; at < sig->count; at++) {
    described = described || sig->kinds[at] == NS_ELEM_DESC || sig->kinds[at] == NS_KEY_DESC || sig->kinds[at] == NS_VAL_DESC;
  }
  MirValue wanted[NS_MAX_PARAMS];
  uint32_t count = 0;
  /* A trailing result parameter the plain call would leave out. */
  described = described || (sig->count == nargs + 1 && is_result_kind(sig->kinds[sig->count - 1]) && ret != MIR_VOID);
  if (!described || !signature_arguments(fn, sig, args, nargs, ret, wanted, &count)) {
    return false;
  }
  *out = call_native(fn, name, wanted, count, ret, scalar_result_slot(fn, sig, ret));
  return true;
}

/* Whether `operation` is one the checker gives every value of the receiver type (`ValueOperations`,
 * `CloneOperations` of intrinsics.ms): it has no runtime function of its own. */
static bool is_universal_operation(const LowerFn *fn, MsTy receiver, MsSpan operation) {
  MsCheckProgram *program = fn->cx->program;
  MsMethodMatchList found = {0};
  ms_check_find_native(program, receiver, ms_names_intern(program->names, operation), &found);
  bool universal = false;
  for (size_t at = 0; at < found.len && !universal; at++) {
    const MsSpan interface = ms_names_span(program->names, ms_ty_row(&program->types, found.ptr[at].contract)->name);
    universal = ms_span_is_text(interface, "ValueOperations") || ms_span_is_text(interface, "CloneOperations");
  }
  ms_method_match_list_free(&found);
  return universal;
}

MirValue fn_native_call(LowerFn *fn, const MsExpr *expr, const MsCall *call, const MirValue *args, MirTy ret) {
  const MsExpr *callee = expr->u.call.callee;
  if (callee->kind != MS_E_MEMBER || call->arg_count == 0) {
    (void)fn_fail(fn, "a standard operation is called through a receiver");
    return MIR_NONE;
  }
  /* The declaration names the operation: a written `xs[i] = v` is a call of `set`, not of a member `[]=`. */
  const MsTyTable *declared_types = &fn->cx->program->types;
  const MsMethodEntry *declared = fn_method_entry(fn->cx, call->callee.decl.module, call->callee.decl.node);
  /* An interface operation's declaration is not a method: only an entry of the callee's own type names the call. */
  if (declared != NULL && ms_ty_row(declared_types, declared->receiver)->name != ms_ty_row(declared_types, call->callee.owner)->name) {
    declared = NULL;
  }
  const MsSpan operation = declared != NULL ? ms_names_span(fn->cx->program->names, declared->source->func.name)
                                            : ms_names_span(fn->cx->program->names, callee->u.member.name);
  MsTy owner = call->callee.owner;
  const bool via_bound = generic_receiver(fn, call);
  if (via_bound) {
    /* The instance knows the receiver: a standard type's operation is that type's own native. */
    const MsTy receiver = ms_ty_subst(&fn->cx->program->types, ms_facts_type(fn->facts, callee->u.member.left->id),
                                      fn->subst.vars, fn->subst.args, fn->subst.count);
    const MsTyTable *table = &fn->cx->program->types;
    if (ms_ty_kind(table, receiver) != MS_TY_NATIVE && ms_builtin_name(ms_ty_builtin(table, receiver))[0] == 0) {
      return bound_native(fn, callee, call, args, ret);
    }
    owner = receiver;
  }
  MirValue result;
  fn->native_arg_moves = 0; /* the operands the declaration takes (`move value: T`) */
  for (uint32_t index = 1; index < call->arg_count && index < 32; index++) {
    fn->native_arg_moves |= (call->args[index].flags & MS_PARAM_MOVE) != 0 ? 1u << index : 0;
  }
  /* A `move fn` receiver in a closing slot was taken out of it when the arguments ran: the native consumes that value
   * through a slot of its own, and nothing is put back. */
  const MsExpr *receiver = callee->u.member.left;
  const MsRef *receiver_ref = receiver->kind == MS_E_NAME ? ms_facts_ref(fn->facts, receiver->id) : NULL;
  const bool taken = receiver_ref != NULL && fn_arg_moves(fn, expr, call, 0, receiver) &&
                     fn_closing_at(fn, receiver_ref, receiver->u.sym) != UINT32_MAX && !via_bound &&
                     fn_native_changes_receiver(fn, owner, operation, ret);
  MirValue through = MIR_NONE;
  if (taken) {
    const MirTy receiver_ty = mir_b_ty(&fn->b, args[0]);
    const MirImm of_type = {.tag = MI_TY, .a = receiver_ty};
    through = mir_b_emit(&fn->b, MOP_Slot, NULL, 0, of_type, MIR_PTR);
    (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &args[0], 1, (MirImm){0}, MIR_NONE);
    const MirValue stored[2] = {through, args[0]};
    (void)mir_b_emit(&fn->b, MOP_Put, stored, 2, (MirImm){0}, MIR_NONE);
  }
  const bool done = taken ? fn_native_through(fn, through, owner, operation, call->arg_count, args, ret, &result)
                          : fn_native_on(fn, receiver, owner, operation, call->arg_count, args, ret, &result);
  fn->native_arg_moves = 0;
  if (done) {
    return result;
  }
  const bool universal = via_bound || (ms_native_sig_find(ms_names_span(&fn->cx->module->names, runtime_name(fn, owner, operation))) == NULL &&
                                       is_universal_operation(fn, owner, operation));
  if (universal && standard_form(fn, args, call->arg_count, ret, &result)) {
    return result; /* the operation every value has, with no runtime function of its own */
  }
  const MsName runtime = runtime_name(fn, owner, operation);
  /* A conversion to the receiver's own scalar type (`Int.to_int()`) has no runtime function: it is the value. */
  const MsSpan conversion = ms_span_of_text("to_");
  if (ms_native_sig_find(ms_names_span(&fn->cx->module->names, runtime)) == NULL && call->arg_count == 1 &&
      operation.len > conversion.len && __builtin_memcmp(operation.ptr, conversion.ptr, conversion.len) == 0 &&
      mir_b_ty(&fn->b, args[0]) == ret && mir_is_scalar(fn->cx->module, ret)) {
    return args[0];
  }
  return fn_runtime_call(fn, runtime, args, call->arg_count, ret);
}
