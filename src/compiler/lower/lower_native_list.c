/* compiler/lower/lower_native_list.c: the list natives that edit in place or close what they replace: `append`, `set`,
 * and the `_take` forms of `remove`, `splice` and a map's `add`, `remove` and `clear` on resources. */
#include "compiler/lower/lower_fn.h"
#include "compiler/natives/native_sigs.h"
#include "compiler/mir/mir_analysis.h"

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

/* The address of the list that `place` names when it is a field of a record that lies in its cell (`context.rows.append(x)`)
 * or an element of a list lying in a variable, field or element (`rows[i].append(x)`), else MIR_NONE. */
static MirValue list_element_slot(LowerFn *fn, const MsExpr *place) {
  MsExpr *container = NULL;
  MsExpr *key = NULL;
  MirValue field = MIR_NONE;
  if (place != NULL && place->kind == MS_E_MEMBER && fn_field_address(fn, place, &field)) {
    return field;
  }
  if (place != NULL && place->kind == MS_E_MEMBER && fn_element_field_address(fn, place, &field)) {
    return field; /* a field of an element of a list or map held in place */
  }
  MirTy entry_ty;
  if (place != NULL && ms_expr_index(place, &container, &key) && !fn_is_list(fn, container) && fn_place_address(fn, place, &field, &entry_ty)) {
    return field; /* an entry of a map held in place (`m[k].append(x)`) */
  }
  if (place == NULL || !ms_expr_index(place, &container, &key) || !fn_is_list(fn, container)) {
    return MIR_NONE;
  }
  if (!lists_in_place(fn, container)) { /* an element of a list in a map entry (`g[k][i].append(x)`) */
    return fn_place_changeable(fn, container) && fn_place_address(fn, place, &field, &entry_ty) ? field : MIR_NONE;
  }
  const MirValue list = fn_expr(fn, container, LW_BORROW);
  const MirValue at = list == MIR_NONE ? MIR_NONE : fn_expr(fn, key, LW_BORROW);
  if (at == MIR_NONE) {
    return MIR_NONE;
  }
  const MirValue operands[2] = {list, at};
  return fn_checked_emit(fn, MOP_ListAddr, operands, 2, (MirImm){0}, MIR_PTR);
}

/* `list.append(value)`: the list grows in line (a full list calls the grow block) and the updated list goes back. */
bool fn_list_append(LowerFn *fn, const MsExpr *place, MirValue slot, const MirValue *args, MirValue *out) {
  const MirTy list_ty = mir_b_ty(&fn->b, args[0]);
  const MirTyData *list = mir_ty_data(fn->cx->module, list_ty);
  MirValue owned;
  MirValue record;
  if (list->kind != MK_LIST || mir_b_ty(&fn->b, args[1]) != list->elem) {
    return false;
  }
  if (slot == MIR_NONE) {
    slot = list_element_slot(fn, place);
  }
  if (!list_changeable(fn, place, slot) || !list_take(fn, place, slot, list_ty, &owned, &record)) {
    return false;
  }
  const MirValue operands[2] = {owned, args[1]};
  const MirValue updated = mir_b_emit(&fn->b, MOP_ListPush, operands, 2, (MirImm){0}, list_ty);
  *out = mir_b_emit(&fn->b, MOP_VoidConst, NULL, 0, (MirImm){0}, MIR_VOID);
  return list_put(fn, place, slot, record, updated);
}

/* `list.pop()`: the last element moves out into a `some`, the length drops by one and the list goes back; an empty list
 * goes back unchanged and the answer is `none`. */
bool fn_list_pop(LowerFn *fn, const MsExpr *place, MirValue slot, const MirValue *args, MirTy ret, MirValue *out) {
  const MirTy list_ty = mir_b_ty(&fn->b, args[0]);
  const MirTyData *list = mir_ty_data(fn->cx->module, list_ty);
  const MirTyData *result = mir_ty_data(fn->cx->module, ret);
  if (list->kind != MK_LIST || result->kind != MK_OPT || result->elem != list->elem) {
    return false;
  }
  if (slot == MIR_NONE) {
    slot = list_element_slot(fn, place);
  }
  MirValue owned;
  MirValue record;
  if (!list_changeable(fn, place, slot) || !list_take(fn, place, slot, list_ty, &owned, &record)) {
    return false;
  }
  const MirBlock some = mir_b_new_block(&fn->b), none = mir_b_new_block(&fn->b), join = mir_b_new_block(&fn->b);
  const MirValue answer = mir_b_add_block_param(&fn->b, join, ret, MM_MOVE);
  const MirValue length = mir_b_emit(&fn->b, MOP_ListLen, &owned, 1, (MirImm){0}, MIR_INT);
  mir_b_br_if(&fn->b, mir_b_icmp(&fn->b, MCC_GT, length, mir_b_iconst(&fn->b, 0)), some, NULL, 0, none, NULL, 0);
  mir_b_seal_block(&fn->b, some);
  mir_b_seal_block(&fn->b, none);
  mir_b_switch_to(&fn->b, some);
  const MirValue at[2] = {owned, mir_b_binop(&fn->b, MOP_ISub, length, mir_b_iconst(&fn->b, 1))};
  const MirValue item = mir_b_emit(&fn->b, MOP_ListTake, at, 2, (MirImm){0}, list->elem);
  const MirValue shorter = mir_b_emit(&fn->b, MOP_ListDropLast, &owned, 1, (MirImm){.tag = MI_INT, .i = 1}, list_ty);
  if (!list_put(fn, place, slot, record, shorter)) {
    return false;
  }
  const MirValue found = mir_b_emit(&fn->b, MOP_OptSome, &item, 1, (MirImm){0}, ret);
  mir_b_br(&fn->b, join, &found, 1);
  mir_b_switch_to(&fn->b, none);
  if (!list_put(fn, place, slot, record, owned)) {
    return false;
  }
  const MirValue missing = mir_b_emit(&fn->b, MOP_OptNone, NULL, 0, (MirImm){0}, ret);
  mir_b_br(&fn->b, join, &missing, 1);
  mir_b_seal_block(&fn->b, join);
  mir_b_switch_to(&fn->b, join);
  if (mir_needs_drop(fn->cx->module, ret)) {
    fn_own(fn, fn_scope(fn), answer);
  }
  *out = answer;
  return true;
}

/* `index` counted from the end when negative, checked against `length`: out of range faults with `kind` (the runtime's
 * `List` fault kind of the operation) and the code after it runs only for an index inside the list. */
static MirValue checked_index(LowerFn *fn, MirValue index, MirValue length, int64_t kind) {
  /* An index inside the list is one unsigned comparison; only another one takes the block that counts from the end. */
  const MirBlock slow = mir_b_new_block(&fn->b);
  const MirBlock hit = mir_b_new_block(&fn->b);
  const MirBlock miss = mir_b_new_block(&fn->b);
  const MirValue at = mir_b_add_block_param(&fn->b, hit, MIR_INT, MM_MOVE);
  const MirValue pair[2] = {index, length};
  const MirValue inside = mir_b_emit(&fn->b, MOP_UICmp, pair, 2, (MirImm){.tag = MI_CC, .a = (uint32_t)MCC_LT}, MIR_BOOL);
  mir_b_br_if(&fn->b, inside, hit, &index, 1, slow, NULL, 0);
  mir_b_seal_block(&fn->b, slow);
  mir_b_switch_to(&fn->b, slow);
  const MirValue wrapped = mir_b_binop(&fn->b, MOP_IAdd, index, length);
  const MirValue wrapped_pair[2] = {wrapped, length};
  const MirValue wrapped_inside =
      mir_b_emit(&fn->b, MOP_UICmp, wrapped_pair, 2, (MirImm){.tag = MI_CC, .a = (uint32_t)MCC_LT}, MIR_BOOL);
  mir_b_br_if(&fn->b, wrapped_inside, hit, &wrapped, 1, miss, NULL, 0);
  mir_b_seal_block(&fn->b, hit);
  mir_b_seal_block(&fn->b, miss);
  mir_b_switch_to(&fn->b, miss);
  const MirValue fault_args[3] = {mir_b_iconst(&fn->b, kind), index, length};
  (void)fn_runtime_call(fn, mir_name(fn->cx->module, ms_span_of_text("msrt_post_list_index")), fault_args, 3, MIR_VOID);
  fn_unwind_exit(fn); /* the posted fault leaves by the exit that closes what is owned here */
  mir_b_switch_to(&fn->b, hit);
  return at;
}

/* A list native that takes an owned argument and faults on a bad one (`@checks=`) would leave the argument owned by
 * no one: the check runs first, in lowering, while the caller still covers it. The check is the native's own, called
 * with the list's length and the call's integer arguments. A resource argument stays owned by its closing slot, which
 * the exit of a failed check closes. */
void fn_native_precheck(LowerFn *fn, const MsNativeSig *sig, MsTy owner, uint32_t argc, const MirValue *args) {
  MsTyTable *types = &fn->cx->program->types;
  if (sig == NULL || sig->checks == NULL || argc < 2 || !ms_ty_is(types, owner, MS_BUILTIN_List)) {
    return;
  }
  if (!mir_needs_drop(fn->cx->module, mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, args[0]))->elem)) {
    return;
  }
  MirValue checked[4];
  uint32_t count = 0;
  checked[count++] = mir_b_emit(&fn->b, MOP_ListLen, &args[0], 1, (MirImm){0}, MIR_INT);
  for (uint32_t at = 1; at < argc && count < 4; at++) {
    if (mir_b_ty(&fn->b, args[at]) == MIR_INT) {
      checked[count++] = args[at];
    }
  }
  (void)fn_runtime_call(fn, mir_name(fn->cx->module, ms_span_of_text(sig->checks)), checked, count, MIR_VOID);
  /* A bad bound posts: the exit closes the incoming element before the list's own. An argument taken out of its
   * closing slot goes back into it, so that slot closes it. */
  LowerTaken taken[LOWER_MAX_ARGS];
  uint32_t ntaken = 0;
  const MirInstList *insts = &fn->b.func.blocks.ptr[fn->b.cur].insts;
  for (uint32_t at = 1; at < argc && ntaken < LOWER_MAX_ARGS; at++) {
    for (size_t index = insts->len; index > 0; index--) {
      const MirInst *inst = &insts->ptr[index - 1];
      if (inst->res == args[at]) {
        if ((MirOp)inst->op == MOP_Take) {
          taken[ntaken++] = (LowerTaken){.slot = inst->args[0], .value = args[at]};
        }
        break;
      }
    }
  }
  fn_unwind_site_forgetting(fn, MIR_NONE, taken, ntaken);
}

/* `list.set(index, value)` on a list of plain values (an element that owns something needs the runtime to drop the
 * old one): the receiver is taken out of its place or slot, the index is checked with the runtime's `List.set`
 * fault, the element is stored by `list.set.u`, and the updated list goes back. */
bool fn_list_set(LowerFn *fn, const MsExpr *place, MirValue slot, const MirValue *args, MirValue *out) {
  const MirTy list_ty = mir_b_ty(&fn->b, args[0]);
  const MirTyData *list = mir_ty_data(fn->cx->module, list_ty);
  if (list->kind != MK_LIST || mir_needs_drop(fn->cx->module, list->elem) || mir_b_ty(&fn->b, args[2]) != list->elem) {
    return false;
  }
  if (slot == MIR_NONE) {
    slot = list_element_slot(fn, place);
  }
  if (!list_changeable(fn, place, slot)) {
    return false;
  }
  const MirValue length = mir_b_emit(&fn->b, MOP_ListLen, &args[0], 1, (MirImm){0}, MIR_INT);
  const MirValue at = checked_index(fn, args[1], length, 2);
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

/* `list.swap(i, j)` on a list of plain values: both indices are checked with the runtime's `List.swap` fault, then
 * the two elements are read and stored crosswise in line. Elements that own something go through the runtime. */
bool fn_list_swap(LowerFn *fn, const MsExpr *place, MirValue slot, const MirValue *args, MirValue *out) {
  const MirTy list_ty = mir_b_ty(&fn->b, args[0]);
  const MirTyData *list = mir_ty_data(fn->cx->module, list_ty);
  if (list->kind != MK_LIST || mir_needs_drop(fn->cx->module, list->elem)) {
    return false;
  }
  if (slot == MIR_NONE) {
    slot = list_element_slot(fn, place);
  }
  if (!list_changeable(fn, place, slot)) {
    return false;
  }
  const MirValue length = mir_b_emit(&fn->b, MOP_ListLen, &args[0], 1, (MirImm){0}, MIR_INT);
  const MirValue first = checked_index(fn, args[1], length, 3);
  const MirValue second = checked_index(fn, args[2], length, 3);
  MirValue owned;
  MirValue record;
  if (!list_take(fn, place, slot, list_ty, &owned, &record)) {
    return false;
  }
  const MirValue from_first[2] = {owned, first};
  const MirValue from_second[2] = {owned, second};
  const MirValue a = mir_b_emit(&fn->b, MOP_ListGetU, from_first, 2, (MirImm){0}, list->elem);
  const MirValue b = mir_b_emit(&fn->b, MOP_ListGetU, from_second, 2, (MirImm){0}, list->elem);
  const MirValue put_first[3] = {owned, first, b};
  const MirValue half = mir_b_emit(&fn->b, MOP_ListSetU, put_first, 3, (MirImm){0}, list_ty);
  const MirValue put_second[3] = {half, second, a};
  const MirValue updated = mir_b_emit(&fn->b, MOP_ListSetU, put_second, 3, (MirImm){0}, list_ty);
  *out = mir_b_emit(&fn->b, MOP_VoidConst, NULL, 0, (MirImm){0}, MIR_VOID);
  return list_put(fn, place, slot, record, updated);
}

/* `list.set(index, value)` on resources: the element it replaces closes, so the set is a `replace` whose old element
 * the scope closes (the incoming value is still held by its closing slot until the replace stored it). */
bool fn_list_set_closing(LowerFn *fn, const MsExpr *place, MirValue slot, MsTy owner, uint32_t argc,
                             const MirValue *args, MirValue *out) {
  MsTyTable *types = &fn->cx->program->types;
  if (argc != 3 || !ms_ty_is(types, owner, MS_BUILTIN_List) || fn->closing == NULL) {
    return false;
  }
  const MsTy elem = ms_ty_subst(types, ms_ty_args(types, owner)[0], fn->subst.vars, fn->subst.args, fn->subst.count);
  if (!fn_temp_closes(fn, elem)) {
    return false;
  }
  MirValue old = MIR_NONE;
  if (!native_on(fn, place, slot, owner, ms_span_of_text("replace"), argc, args, mir_b_ty(&fn->b, args[2]), &old) ||
      old == MIR_NONE) {
    return false;
  }
  fn_unwind_site(fn, old); /* a bad index posts: the incoming value is still owned, and the result is dead */
  if (!fn_close_replaced(fn, elem, old)) {
    return false;
  }
  *out = mir_b_emit(&fn->b, MOP_VoidConst, NULL, 0, (MirImm){0}, MIR_VOID);
  return true;
}

/* The list type `List[elem]`, built from any list type of the program. */
static MsTy list_of(LowerFn *fn, MsTy elem) {
  MsTyTable *types = &fn->cx->program->types;
  for (size_t at = 1; at < types->rows.len; at++) {
    const MsTyRow *row = &types->rows.ptr[at];
    if (row->builtin == MS_BUILTIN_List && row->arg_count == 1) {
      const MsTyDesc desc = {.name = row->name, .id = row->id, .kind = (MsTyKind)row->kind, .builtin = MS_BUILTIN_List,
                             .def = row->def, .args = &elem, .arg_count = 1};
      return ms_ty_intern(types, &desc);
    }
  }
  return MS_TY_NONE;
}

/* A native that drops what it removes (`remove`, `splice`, a map's `add` over a key, `remove`, `clear`), on resources:
 * the `_take` form moves the removed values out in a list, and the list closes where the scope ends, last first. */
bool fn_native_closing_take(LowerFn *fn, const MsExpr *place, MirValue slot, MsTy owner, MsSpan operation, uint32_t argc,
                                  const MirValue *args, MirValue *out) {
  MsTyTable *types = &fn->cx->program->types;
  const bool is_list = ms_ty_is(types, owner, MS_BUILTIN_List);
  const bool is_map = ms_ty_is(types, owner, MS_BUILTIN_Map);
  const bool wanted = (is_list && ((ms_span_is_text(operation, "remove") && argc == 2) ||
                                   (ms_span_is_text(operation, "splice") && argc == 4))) ||
                      (is_map && ((ms_span_is_text(operation, "remove") && argc == 2) ||
                                  (ms_span_is_text(operation, "add") && argc == 3) ||
                                  (ms_span_is_text(operation, "clear") && argc == 1)));
  if (!wanted || fn->closing == NULL || (!is_list && ms_ty_arg_count(types, owner) != 2)) {
    return false;
  }
  const MsTy elem = ms_ty_subst(types, ms_ty_args(types, owner)[is_list ? 0 : 1], fn->subst.vars, fn->subst.args, fn->subst.count);
  if (!fn_temp_closes(fn, elem)) {
    return false;
  }
  const MsTy removed = is_list ? owner : list_of(fn, elem);
  if (removed == MS_TY_NONE) {
    return false;
  }
  const MirTy taken_ty = fn_type(fn, ms_ty_subst(types, removed, fn->subst.vars, fn->subst.args, fn->subst.count));
  const char *name = ms_span_is_text(operation, "remove") ? "remove_take"
                     : ms_span_is_text(operation, "splice") ? "splice_take"
                     : ms_span_is_text(operation, "add")    ? "add_take"
                                                            : "clear_take";
  MirValue taken = MIR_NONE;
  if (!native_on(fn, place, slot, owner, ms_span_of_text(name), argc, args, taken_ty, &taken) || taken == MIR_NONE) {
    return false;
  }
  fn_unwind_site(fn, taken); /* before the removed values are owned: a fault leaves them dead */
  if (!fn_close_replaced(fn, removed, taken)) {
    return false;
  }
  *out = mir_b_emit(&fn->b, MOP_VoidConst, NULL, 0, (MirImm){0}, MIR_VOID);
  return true;
}

/* `fn(comparator, ptr, ptr) -> int` for the runtime sort: loads the two element slots and calls the source comparator
 * on them. `sort.cmp` is what `opt_inline_specialize_sort_thunks` and `opt_sortgen` recognise; a comparator the module
 * knows is called directly there. MIR_NONE when the build fails. */
uint32_t fn_sort_thunk(LowerFn *fn, MirTy elem, MirTy closure) {
  const MirParam params[3] = {{closure, MM_BORROW}, {MIR_PTR, MM_BORROW}, {MIR_PTR, MM_BORROW}};
  MirBuilder b;
  mir_b_init(&b, fn->cx->module, mir_name(fn->cx->module, ms_span_of_text("sort.cmp")), params, 3, MIR_INT);
  mir_b_func(&b)->sort = MSORT_GENERIC;
  MirValue args[3];
  mir_b_params(&b, args, 3);
  const MirImm of_elem = {.tag = MI_TY, .a = elem};
  const MirValue call[3] = {args[0], mir_b_emit(&b, MOP_Load, &args[1], 1, of_elem, elem),
                            mir_b_emit(&b, MOP_Load, &args[2], 1, of_elem, elem)};
  mir_b_ret(&b, mir_b_emit(&b, MOP_CallInd, call, 3, (MirImm){0}, MIR_INT));
  uint32_t id = MIR_NONE;
  return mir_b_finish(&b, &id) ? id : MIR_NONE;
}

/* `fn(change, ptr) -> void` for the runtime `Map.update`: reads the value in the slot, calls the source `change` on it,
 * and puts the result in its place (dropping the old value first). `change` runs while the slot still holds the old
 * value, so a fault in it leaves the map whole. Marked like a sort comparator thunk so a known `change` is called
 * directly. MIR_NONE when the build fails. */
uint32_t fn_update_thunk(LowerFn *fn, MirTy value, MirTy closure) {
  const MirParam params[2] = {{closure, MM_BORROW}, {MIR_PTR, MM_BORROW}};
  MirBuilder b;
  mir_b_init(&b, fn->cx->module, mir_name(fn->cx->module, ms_span_of_text("sort.cmp.update")), params, 2, MIR_VOID);
  mir_b_func(&b)->sort = MSORT_GENERIC;
  MirValue args[2];
  mir_b_params(&b, args, 2);
  const MirImm of_value = {.tag = MI_TY, .a = value};
  const MirValue old = mir_b_emit(&b, MOP_Load, &args[1], 1, of_value, value);
  const MirValue call[2] = {args[0], old};
  const MirValue next = mir_b_emit(&b, MOP_CallInd, call, 2, (MirImm){0}, value);
  const bool owns = mir_needs_drop(fn->cx->module, value);
  if (owns) { /* the old value is released where it lies: it is borrowed here, not owned */
    MirParam drop_params[2] = {{MIR_PTR, MM_BORROW}, {MIR_PTR, MM_BORROW}};
    const MirExtern drop = {.name = mir_name(fn->cx->module, ms_span_of_text("msrt_slot_drop")), .params = drop_params,
                            .nparams = 2, .ret = MIR_VOID};
    const MirValue release[2] = {mir_b_emit(&b, MOP_TypeDesc, NULL, 0, of_value, MIR_PTR), args[1]};
    (void)mir_b_call_rt(&b, mir_extern_intern(fn->cx->module, &drop), release, 2);
  }
  const MirValue stored[2] = {args[1], next};
  (void)mir_b_emit(&b, owns ? MOP_Put : MOP_Store, stored, 2, (MirImm){0}, MIR_NONE);
  mir_b_ret(&b, mir_b_emit(&b, MOP_VoidConst, NULL, 0, (MirImm){0}, MIR_VOID));
  uint32_t id = MIR_NONE;
  return mir_b_finish(&b, &id) ? id : MIR_NONE;
}
