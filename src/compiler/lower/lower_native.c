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
static bool descriptor_argument(LowerFn *fn, uint8_t kind, const MirValue *args, uint32_t nargs, MirValue *out) {
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

/* A scalar operand a native reads through an address (`e: *const u8`): it goes into a stack slot. */
static MirValue spill_scalar(LowerFn *fn, MirValue value) {
  const MirTy ty = mir_b_ty(&fn->b, value);
  if (ty != MIR_INT && ty != MIR_BOOL && ty != MIR_FLOAT && ty != MIR_FLOAT32) {
    return value;
  }
  const MirImm of_type = {.tag = MI_TY, .a = ty};
  const MirValue slot = fn_emit(fn, MOP_Slot, NULL, 0, of_type, MIR_PTR);
  const MirValue store[2] = {slot, value};
  (void)fn_emit(fn, MOP_Store, store, 2, (MirImm){0}, MIR_NONE);
  return slot;
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
  for (uint32_t at = 0; at < params; at++) {
    const uint8_t kind = sig->kinds[at];
    if (kind == NS_ELEM_DESC || kind == NS_KEY_DESC || kind == NS_VAL_DESC) {
      if (!descriptor_argument(fn, kind, args, nargs, &out[used++])) {
        return false;
      }
    } else if (next < nargs) {
      out[used++] = kind == NS_ADDR_IN || kind == NS_ADDR_MUT ? spill_scalar(fn, args[next]) : args[next];
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
  if (!scalar || sig->count == 0 || sig->kinds[sig->count - 1] != NS_ADDR_MUT) {
    return MIR_NONE;
  }
  const MirImm of_type = {.tag = MI_TY, .a = ret};
  return fn_emit(fn, MOP_Slot, NULL, 0, of_type, MIR_PTR);
}

/* Calls `name` with `wanted`, through a result slot when `slot` is set. */
static MirValue call_native(LowerFn *fn, MsName name, MirValue *wanted, uint32_t count, MirTy ret, MirValue slot) {
  if (slot == MIR_NONE) {
    return fn_runtime_call(fn, name, wanted, count, ret);
  }
  wanted[count++] = slot;
  (void)fn_runtime_call(fn, name, wanted, count, MIR_VOID);
  const MirImm of_type = {.tag = MI_TY, .a = ret};
  return fn_emit(fn, MOP_Load, &slot, 1, of_type, ret);
}

/* The runtime function `name` taking the types of `args` and returning `ret`. */
static uint32_t runtime_extern(LowerFn *fn, MsName name, const MirValue *args, uint32_t nargs, MirTy ret) {
  MirParam *params = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, MirParam, (size_t)nargs + 1);
  for (uint32_t index = 0; index < nargs; index++) {
    params[index] = (MirParam){mir_b_ty(&fn->b, args[index]), (uint8_t)MM_BORROW};
  }
  const MirExtern def = {.name = name, .params = params, .nparams = nargs, .ret = ret,
                         .fresh = mir_needs_drop(fn->cx->module, ret)};
  return mir_extern_intern(fn->cx->module, &def);
}

MirValue fn_runtime_call(LowerFn *fn, MsName name, const MirValue *args, uint32_t nargs, MirTy ret) {
  const uint32_t external = runtime_extern(fn, name, args, nargs, ret);
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

/* An owned operand in a new slot of its own: the runtime function takes the value from the slot's address. */
static MirValue operand_slot(LowerFn *fn, const MsExpr *expr) {
  MirValue value = fn_expr(fn, expr, LW_MOVE);
  if (value == MIR_NONE) {
    return MIR_NONE;
  }
  const MirTy ty = mir_b_ty(&fn->b, value);
  const bool owns = mir_needs_drop(fn->cx->module, ty);
  if (owns) {
    const MirInstList *insts = &fn->b.func.blocks.ptr[fn->b.cur].insts;
    MirMode mode = MM_BORROW;
    const bool fresh = insts->len > 0 && insts->ptr[insts->len - 1].res == value &&
                       mir_result_mode(fn->cx->module, &fn->b.func, &insts->ptr[insts->len - 1], &mode) &&
                       mode == MM_MOVE;
    value = fresh ? value : mir_b_emit(&fn->b, MOP_Clone, &value, 1, (MirImm){0}, ty);
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
  const MirTy ty = fn_type(fn, ms_facts_type(fn->facts, expr->id));
  const MirTyData *data = mir_ty_data(fn->cx->module, ty);
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
    const MirValue key = operand_slot(fn, expr->u.map.ptr[at].key);
    const MirValue value = key == MIR_NONE ? MIR_NONE : operand_slot(fn, expr->u.map.ptr[at].value);
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
  const MirValue key = operand_slot(fn, key_expr);
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
  const bool owns_key = mir_needs_drop(fn->cx->module, data->args[0]);
  const bool owns_value = mir_needs_drop(fn->cx->module, data->args[1]);
  const MirBlock hit = mir_b_new_block(&fn->b);
  const MirBlock miss = mir_b_new_block(&fn->b);
  mir_b_br_if(&fn->b, found, hit, NULL, 0, miss, NULL, 0);
  mir_b_seal_block(&fn->b, hit);
  mir_b_seal_block(&fn->b, miss);
  mir_b_switch_to(&fn->b, miss);
  const MirValue missing = mir_b_emit(&fn->b, owns_key ? MOP_Take : MOP_Load, &key, 1, key_ty, data->args[0]);
  const MirValue text = fn_value_repr(fn, missing, data->args[0]);
  const MirValue prefix_lit = mir_b_emit(&fn->b, MOP_StrLit, NULL, 0,
                                         (MirImm){.tag = MI_STR, .a = mir_add_string(fn->cx->module, ms_span_of_text("map key not found: "))},
                                         MIR_STR);
  const MirValue parts[2] = {prefix_lit, text};
  const MirValue message = fn_runtime_call(fn, mir_name(fn->cx->module, ms_span_of_text("msrt_string_concat")), parts, 2, MIR_STR);
  (void)fn_runtime_call(fn, mir_name(fn->cx->module, ms_span_of_text("msrt_fault_string")), &message, 1, MIR_VOID);
  mir_b_unreachable(&fn->b);
  mir_b_switch_to(&fn->b, hit);
  if (owns_key) {
    const MirValue gone = mir_b_emit(&fn->b, MOP_Take, &key, 1, key_ty, data->args[0]);
    (void)mir_b_emit(&fn->b, MOP_Drop, &gone, 1, (MirImm){0}, MIR_NONE);
  }
  return mir_b_emit(&fn->b, owns_value ? MOP_Take : MOP_Load, &out, 1, value_ty, data->args[1]);
}

/* A native that changes its receiver (`var` list or string): the receiver's value moves into a slot, the native
 * writes through the slot's address, and the value in the slot goes back to the place. `wanted[0]` is replaced. */
static MirValue call_changing(LowerFn *fn, const MsExpr *place, MsName name, MirValue *wanted, uint32_t count,
                              MirTy ret) {
  MirValue owned;
  if (!fn_take_place(fn, place, &owned)) {
    return MIR_NONE;
  }
  const MirTy ty = mir_b_ty(&fn->b, owned);
  const MirImm of_type = {.tag = MI_TY, .a = ty};
  const MirValue slot = mir_b_emit(&fn->b, MOP_Slot, NULL, 0, of_type, MIR_PTR);
  const MirValue stored[2] = {slot, owned};
  (void)mir_b_emit(&fn->b, MOP_Put, stored, 2, (MirImm){0}, MIR_NONE);
  wanted[0] = slot;
  const MirValue result = fn_runtime_call(fn, name, wanted, count, ret);
  const MirValue updated = mir_b_emit(&fn->b, MOP_Take, &slot, 1, of_type, ty);
  if (!fn_put_place(fn, place, updated)) {
    return MIR_NONE;
  }
  return result;
}

/* `list.get(index)`: the element, a negative index counting from the end; an index out of range faults. */
static MirValue list_get(LowerFn *fn, MirValue list, MirValue index, MirTy elem) {
  const MirValue length = mir_b_emit(&fn->b, MOP_ListLen, &list, 1, (MirImm){0}, MIR_INT);
  const MirValue from_end = mir_b_binop(&fn->b, MOP_IAdd, index, length);
  const MirValue negative = mir_b_icmp(&fn->b, MCC_LT, index, mir_b_iconst(&fn->b, 0));
  const MirValue at = mir_b_select(&fn->b, negative, from_end, index);
  const MirValue args[2] = {list, at};
  return mir_b_emit(&fn->b, MOP_ListGet, args, 2, (MirImm){0}, elem);
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
  if (method != MIR_NONE) {
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
  const MsSymbolId id = fn_symbol_at(fn->cx, call->callee.decl);
  const MsSymbol *symbol = &fn->cx->program->symbols.ptr[id];
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "msrt_");
  ms_strbuild_append(&text, ms_names_span(fn->cx->program->names, symbol->name));
  const MsName name = mir_name(fn->cx->module, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  const MsNativeSig *sig = ms_native_sig_find(ms_names_span(&fn->cx->module->names, name));
  MirValue wanted[NS_MAX_PARAMS];
  uint32_t count = 0;
  if (sig != NULL && call->arg_count <= NS_MAX_PARAMS &&
      signature_arguments(fn, sig, args, call->arg_count, ret, wanted, &count)) {
    return call_native(fn, name, wanted, count, ret, scalar_result_slot(fn, sig, ret));
  }
  return fn_runtime_call(fn, name, args, call->arg_count, ret);
}

bool fn_native_on(LowerFn *fn, const MsExpr *place, MsTy owner, MsSpan operation, uint32_t argc, const MirValue *args,
                  MirTy ret, MirValue *out) {
  const MsTyTable *types = &fn->cx->program->types;
  /* A standard type with no builtin id (an extern type such as StringBuilder) is named by its declaration. */
  const char *builtin_name = ms_builtin_name(ms_ty_builtin(types, owner));
  const MsSpan type_name = builtin_name[0] != '\0' ? ms_span_of_text(builtin_name)
                                                   : ms_names_span(fn->cx->program->names, ms_ty_row(types, owner)->name);
  const MsNativeSig *named = ms_native_sig_find_method(type_name, operation);
  const MsName name = named != NULL ? mir_name(fn->cx->module, ms_span_of_text(named->name))
                                    : runtime_name(fn, owner, operation);
  const MsNativeSig *sig = named != NULL ? named : ms_native_sig_find(ms_names_span(&fn->cx->module->names, name));
  if (sig == NULL) {
    return false;
  }
  if (sig->inline_op != NULL && ms_span_is_text(ms_span_of_text(sig->inline_op), "list_get") && argc == 2) {
    *out = list_get(fn, args[0], args[1], ret);
    return true;
  }
  MirValue wanted[NS_MAX_PARAMS];
  uint32_t count = 0;
  if (argc <= NS_MAX_PARAMS && signature_arguments(fn, sig, args, argc, ret, wanted, &count)) {
    if (mutates_receiver(sig, ret) && fn_place_changeable(fn, place)) {
      *out = call_changing(fn, place, name, wanted, count, ret);
    } else {
      *out = call_native(fn, name, wanted, count, ret, scalar_result_slot(fn, sig, ret));
    }
    return true;
  }
  *out = fn_runtime_call(fn, name, args, argc, ret);
  return true;
}

MirValue fn_native_call(LowerFn *fn, const MsExpr *expr, const MsCall *call, const MirValue *args, MirTy ret) {
  const MsExpr *callee = expr->u.call.callee;
  if (callee->kind != MS_E_MEMBER || call->arg_count == 0) {
    (void)fn_fail(fn, "a standard operation is called through a receiver");
    return MIR_NONE;
  }
  /* The declaration names the operation: a written `xs[i] = v` is a call of `set`, not of a member `[]=`. */
  const MsMethodEntry *declared = fn_method_entry(fn->cx, call->callee.decl.module, call->callee.decl.node);
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
  if (fn_native_on(fn, callee->u.member.left, owner, operation, call->arg_count, args, ret, &result)) {
    return result;
  }
  if (standard_form(fn, args, call->arg_count, ret, &result) && via_bound) {
    return result; /* the operation every value has, with no runtime function of its own */
  }
  return fn_runtime_call(fn, runtime_name(fn, owner, operation), args, call->arg_count, ret);
}

/* The operation word of a binary operator on a value object: its runtime function is `msstd_<type>_<word>`, the
 * receiver type's lowercase name as for every standard operation. A comparison reads the result of `compare`
 * against zero; `==` and `!=` use `equal`. */
typedef struct ObjectOp {
  const char *word;
  MirCc cc;
  bool compare;
} ObjectOp;

static bool object_op(MsBinaryOp op, ObjectOp *out) {
  switch (op) {
    case MS_B_ADD: *out = (ObjectOp){"add", MCC_EQ, false}; return true;
    case MS_B_SUB: *out = (ObjectOp){"subtract", MCC_EQ, false}; return true;
    case MS_B_MUL: *out = (ObjectOp){"multiply", MCC_EQ, false}; return true;
    case MS_B_DIV: *out = (ObjectOp){"quotient", MCC_EQ, false}; return true;
    case MS_B_REM: *out = (ObjectOp){"modulo", MCC_EQ, false}; return true;
    case MS_B_EQ: *out = (ObjectOp){"equal", MCC_EQ, false}; return true;
    case MS_B_NE: *out = (ObjectOp){"equal", MCC_NE, false}; return true;
    case MS_B_LT: *out = (ObjectOp){"compare", MCC_LT, true}; return true;
    case MS_B_GT: *out = (ObjectOp){"compare", MCC_GT, true}; return true;
    case MS_B_LE: *out = (ObjectOp){"compare", MCC_LE, true}; return true;
    case MS_B_GE: *out = (ObjectOp){"compare", MCC_GE, true}; return true;
    default: return false;
  }
}

/* `msstd_<type>_<word>` for the value object `type`. */
static MsName object_function(LowerFn *fn, const MirTyData *type, const char *word) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "msstd_");
  const MsSpan type_name = ms_names_span(&fn->cx->module->names, type->name);
  for (size_t at = 0; at < type_name.len; at++) {
    const uint8_t byte = type_name.ptr[at];
    ms_strbuild_append_byte(&text, byte >= 'A' && byte <= 'Z' ? (uint8_t)(byte - 'A' + 'a') : byte);
  }
  ms_strbuild_append_byte(&text, '_');
  ms_strbuild_append_text(&text, word);
  const MsName name = mir_name(fn->cx->module, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  return name;
}

bool fn_object_binary(LowerFn *fn, MsBinaryOp op, MirValue left, MirValue right, MirValue *out) {
  const MirTyData *data = mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, left));
  ObjectOp info;
  if (data->kind != MK_OBJ || data->obj_class != MIR_OBJ_VALUE || !object_op(op, &info)) {
    return false;
  }
  const MsName name = object_function(fn, data, info.word);
  if (ms_native_sig_find(ms_names_span(&fn->cx->module->names, name)) == NULL) {
    return false;
  }
  const MirValue operands[2] = {left, right};
  const bool equality = op == MS_B_EQ || op == MS_B_NE;
  const MirTy ret = info.compare ? MIR_INT : (equality ? MIR_BOOL : mir_b_ty(&fn->b, left));
  const MirValue result = fn_runtime_call(fn, name, operands, 2, ret);
  if (result == MIR_NONE) {
    *out = MIR_NONE;
  } else if (info.compare) {
    *out = mir_b_icmp(&fn->b, info.cc, result, mir_b_iconst(&fn->b, 0));
  } else if (op == MS_B_NE) {
    *out = mir_b_icmp(&fn->b, MCC_EQ, result, mir_b_bconst(&fn->b, false));
  } else {
    *out = result;
  }
  return true;
}

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

static MirValue string_literal(LowerFn *fn, const char *text) {
  const MirImm imm = {.tag = MI_STR, .a = mir_add_string(fn->cx->module, ms_span_of_text(text))};
  return mir_b_emit(&fn->b, MOP_StrLit, NULL, 0, imm, MIR_STR);
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

bool fn_status_call(LowerFn *fn, MsName name, const MirValue *args, uint32_t nargs, MirTy ret, MirValue *out) {
  uint32_t alt = 0;
  MirTy payload_ty = MIR_VOID;
  const MsNativeSig *sig = ms_native_sig_find(ms_names_span(&fn->cx->module->names, name));
  if (sig == NULL || !sig->status || !result_alt(fn, ret, &alt, &payload_ty) || nargs + 2 > NS_MAX_PARAMS) {
    return false;
  }
  const bool has_err = sig->count > 0 && sig->kinds[sig->count - 1] == NS_ERR_SLOT;
  const uint32_t extras = sig->count > nargs ? sig->count - nargs : 0;
  const bool has_out = extras == (has_err ? 2u : 1u) && payload_ty != MIR_VOID;
  if (sig->count < nargs || extras != (has_err ? 1u : 0u) + (has_out ? 1u : 0u)) {
    return false;
  }
  const uint32_t error_function = status_error_function(fn);
  if (error_function == MIR_NONE) {
    return false;
  }
  MirValue wanted[NS_MAX_PARAMS];
  uint32_t count = 0;
  for (; count < nargs; count++) {
    wanted[count] = args[count];
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
  const uint32_t external = runtime_extern(fn, name, wanted, count, MIR_UINT8);
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
  const MirValue error_args[3] = {status, string_literal(fn, domain_text), said};
  const MirValue error = mir_b_call(&fn->b, error_function, error_args, 3);
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
