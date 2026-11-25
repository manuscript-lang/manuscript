/* Owns the unchecked list operations: the index is in range or the length is known; the layout is the one the
 * runtime uses. Dropping an old element is the job of lowering, which runs first. */
#include "compiler/emit/emit_cx.h"

static MirTy value_type(const EmitCx *cx, MirValue value) {
  return cx->func->values.ptr[value];
}

/* The element type of the list or bytes value `list_type`. */
static MirTy list_elem(const EmitCx *cx, MirTy list_type) {
  const MirTyData *data = mir_ty_data(cx->module, list_type);
  return data->kind == MK_BYTES ? MIR_UINT8 : data->elem;
}

/* The access tag of a list of scalars, or of records made only of them (nothing in one owns anything, so
 * no list header lies inside an element), which no other memory aliases. */
static const char *elem_tbaa(const EmitCx *cx, MirTy elem) {
  switch ((MirTyKind)mir_ty_data(cx->module, elem)->kind) {
  case MK_BOOL:
  case MK_INT:
  case MK_FLOAT:
  case MK_INT8:
  case MK_INT16:
  case MK_INT32:
  case MK_FLOAT32:
  case MK_UINT8:
  case MK_UINT16:
  case MK_UINT32:
  case MK_UINT64:
    return ", !tbaa !900002";
  case MK_TYPE:
    return mir_needs_drop(cx->module, elem) ? NULL : ", !tbaa !900002";
  default:
    return NULL;
  }
}

/* Writes the address of element `index` (a register text) of list value `list` and names it in `out`. */
static void element_base(EmitCx *cx, MirValue list, const char *index, uint32_t size, char *out, size_t capacity) {
  uint32_t number = cx->next++;
  ms_strbuild_printf(cx->out,
                     "  %%t%u = mul i64 %s, %u\n  %%lb%u = inttoptr i64 %%v%u to ptr\n"
                     "  %%p%u = getelementptr i8, ptr %%lb%u, i64 %%t%u\n",
                     number, index, size, number, list, number, number, number);
  emit_register_name(out, capacity, "p", number);
}

/* The result takes the address and capacity of `from`; the caller writes the length. */
static void copy_list(EmitCx *cx, const MirInst *inst, MirValue from) {
  emit_copy_leaf(cx, inst->res, 0, from, 0);
  emit_copy_leaf(cx, inst->res, MIR_LIST_CAP_LEAF, from, MIR_LIST_CAP_LEAF);
}

/* Writes `element` at `base`, an element address of `list`, tagged with the alias class of its elements. */
static void store_element(EmitCx *cx, MirValue list, MirValue element, const char *base) {
  cx->tbaa = elem_tbaa(cx, list_elem(cx, value_type(cx, list)));
  emit_store_value(cx, element, base);
  cx->tbaa = NULL;
}

/* `list.new`: a block of `capacity` elements, none for capacity 0 (the null pointer owns nothing). The
 * allocation is a block of its own and the rest of the instruction continues in a new piece. */
static void list_new(EmitCx *cx, const MirInst *inst, uint32_t size, const EmitSite *site) {
  MsStrBuild *out = cx->out;
  uint32_t number = cx->next++;
  ms_strbuild_printf(out, "  %%o%ub = mul i64 %%v%u, %u\n  %%o%us = icmp ne i64 %%v%u, 0\n", number, inst->args[0],
                     size > 0 ? size : 1, number, inst->args[0]);
  /* The piece that holds the branch is named by the previous part; the join is the next one. */
  uint32_t from = *site->part;
  *site->part += 1;
  ms_strbuild_printf(out, "  br i1 %%o%us, label %%ln%u, label %%", number, number);
  emit_label(out, site->block, *site->part);
  ms_strbuild_printf(out, "\nln%u:\n  %%o%up = call i64 @msrt_alloc(i64 %%o%ub)\n  br label %%", number, number,
                     number);
  emit_label(out, site->block, *site->part);
  ms_strbuild_append_byte(out, '\n');
  emit_label(out, site->block, *site->part);
  ms_strbuild_append_text(out, ":\n");
  ms_strbuild_printf(out, "  %%v%u = phi i64 [ %%o%up, %%ln%u ], [ 0, %%", inst->res, number, number);
  emit_label(out, site->block, from);
  ms_strbuild_append_text(out, " ]\n");
  ms_strbuild_printf(out, "  %%v%u.%u = add i64 0, 0\n", inst->res, MIR_LIST_LEN_LEAF);
  emit_copy_leaf(cx, inst->res, MIR_LIST_CAP_LEAF, inst->args[0], 0);
}

/* `list.lit`: a block holding the operands, or the empty list for none. */
static void list_lit(EmitCx *cx, const MirInst *inst, uint32_t size) {
  MsStrBuild *out = cx->out;
  if (inst->nargs == 0) {
    ms_strbuild_printf(out, "  %%v%u = add i64 0, 0\n  %%v%u.1 = add i64 0, 0\n  %%v%u.2 = add i64 0, 0\n", inst->res,
                       inst->res, inst->res);
    return;
  }
  ms_strbuild_printf(out, "  %%v%u = call i64 @msrt_alloc(i64 %u)\n", inst->res, inst->nargs * (size > 0 ? size : 1));
  for (uint32_t arg = 0; arg < inst->nargs; arg++) {
    uint32_t number = cx->next++;
    ms_strbuild_printf(out, "  %%a%u = add i64 %%v%u, %u\n  %%p%u = inttoptr i64 %%a%u to ptr\n", number, inst->res,
                       arg * size, number, number);
    char base[24];
    emit_register_name(base, sizeof base, "p", number);
    emit_store_value(cx, inst->args[arg], base);
  }
  ms_strbuild_printf(out, "  %%v%u.1 = add i64 0, %u\n  %%v%u.2 = add i64 0, %u\n", inst->res, inst->nargs, inst->res,
                     inst->nargs);
}

/* `list.grow`: a block of capacity 0 is a view or empty; it is never resized, a fresh block is made. */
static void list_grow(EmitCx *cx, const MirInst *inst, uint32_t size) {
  uint32_t number = cx->next++;
  ms_strbuild_printf(cx->out,
                     "  %%t%u = icmp eq i64 %%v%u.%u, 0\n  %%q%u = select i1 %%t%u, i64 0, i64 %%v%u\n"
                     "  %%gb%u = mul i64 %%v%u, %u\n  %%v%u = call i64 @msrt_realloc(i64 %%q%u, i64 %%gb%u)\n",
                     number, inst->args[0], MIR_LIST_CAP_LEAF, number, number, inst->args[0], number, inst->args[1],
                     size > 0 ? size : 1, inst->res, number, number);
  emit_copy_leaf(cx, inst->res, MIR_LIST_LEN_LEAF, inst->args[0], MIR_LIST_LEN_LEAF);
  emit_copy_leaf(cx, inst->res, MIR_LIST_CAP_LEAF, inst->args[1], 0);
}

static void list_write(EmitCx *cx, const MirInst *inst, uint32_t size) {
  char base[24];
  char index[24];
  switch ((MirOp)inst->op) {
  case MOP_ListSetU:
  case MOP_ListFillU:
    emit_register_name(index, sizeof index, "v", inst->args[1]);
    element_base(cx, inst->args[0], index, size, base, sizeof base);
    copy_list(cx, inst, inst->args[0]);
    emit_copy_leaf(cx, inst->res, MIR_LIST_LEN_LEAF, inst->args[0], MIR_LIST_LEN_LEAF);
    store_element(cx, inst->args[0], inst->args[2], base);
    return;
  case MOP_ListPushU:
    emit_text_name(index, sizeof index, "v", inst->args[0], ".", MIR_LIST_LEN_LEAF);
    element_base(cx, inst->args[0], index, size, base, sizeof base);
    copy_list(cx, inst, inst->args[0]);
    ms_strbuild_printf(cx->out, "  %%v%u.%u = add i64 %%v%u.%u, 1\n", inst->res, MIR_LIST_LEN_LEAF, inst->args[0],
                       MIR_LIST_LEN_LEAF);
    store_element(cx, inst->args[0], inst->args[1], base);
    return;
  case MOP_ListDropLast:
    copy_list(cx, inst, inst->args[0]);
    ms_strbuild_printf(cx->out, "  %%v%u.%u = sub i64 %%v%u.%u, 1\n", inst->res, MIR_LIST_LEN_LEAF, inst->args[0],
                       MIR_LIST_LEN_LEAF);
    return;
  default:
    list_grow(cx, inst, size);
  }
}

/* The address of element `args[1]` of list `args[0]`, unchecked. */
static void element_address(EmitCx *cx, const MirInst *inst, MirTy elem, char *out, size_t capacity) {
  uint32_t number = cx->next++;
  uint32_t stride = mir_type_mem(cx->layouts, elem).size;
  ms_strbuild_printf(cx->out,
                     "  %%e%u = mul i64 %%v%u, %u\n  %%e%ub = inttoptr i64 %%v%u to ptr\n"
                     "  %%e%up = getelementptr i8, ptr %%e%ub, i64 %%e%u\n",
                     number, inst->args[1], stride, number, inst->args[0], number, number, number);
  emit_text_name(out, capacity, "e", number, "p", MIR_NONE);
}

static void list_read(EmitCx *cx, const MirInst *inst) {
  char at[24];
  MirTy elem = list_elem(cx, value_type(cx, inst->args[0]));
  element_address(cx, inst, elem, at, sizeof at);
  if (inst->op == MOP_ListAddrU) {
    ms_strbuild_printf(cx->out, "  %%v%u = ptrtoint ptr %s to i64\n", inst->res, at);
    return;
  }
  cx->tbaa = elem_tbaa(cx, elem);
  emit_load_value(cx, inst->res, at);
  cx->tbaa = NULL;
}

bool emit_list_op(EmitCx *cx, const MirInst *inst, const EmitSite *site, bool *handled) {
  *handled = true;
  switch ((MirOp)inst->op) {
  case MOP_ListNew:
    list_new(cx, inst, mir_list_elem_size(cx->layouts, value_type(cx, inst->res)), site);
    return true;
  case MOP_ListLit:
    list_lit(cx, inst, mir_list_elem_size(cx->layouts, value_type(cx, inst->res)));
    return true;
  case MOP_ListSetU:
  case MOP_ListFillU:
  case MOP_ListPushU:
  case MOP_ListDropLast:
  case MOP_ListGrow:
    list_write(cx, inst, mir_list_elem_size(cx->layouts, value_type(cx, inst->args[0])));
    return true;
  case MOP_ListGetU:
  case MOP_ListTake:
  case MOP_ListAddrU:
    list_read(cx, inst);
    return true;
  case MOP_ListLen:
    emit_copy_leaf(cx, inst->res, 0, inst->args[0], MIR_LIST_LEN_LEAF);
    return true;
  case MOP_ListCap:
    emit_copy_leaf(cx, inst->res, 0, inst->args[0], MIR_LIST_CAP_LEAF);
    return true;
  default:
    *handled = false;
    return true;
  }
}
