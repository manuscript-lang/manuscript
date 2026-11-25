/* Owns the unchecked list operations: the index is in range or the length is known; the layout is the one the
 * runtime uses. A list is three leaves: the address of its elements, its length and its capacity. */
#include "compiler/emit_cl/cl_cx.h"

static MirTy value_type(const ClCx *cx, MirValue value) {
  return cx->func->values.ptr[value];
}

static MirTy list_elem(const ClCx *cx, MirTy list_type) {
  const MirTyData *data = mir_ty_data(cx->module, list_type);
  return data->kind == MK_BYTES ? MIR_UINT8 : data->elem;
}

/* The address of element `index` of a list at `list`, `size` bytes apart. */
static cl_val element_base(ClCx *cx, MirValue list, cl_val index, uint32_t size) {
  return cl_iadd(cx->fb, clx_get(cx, list, 0), cl_imul(cx->fb, index, clx_const(cx, size)));
}

/* The result takes the address and capacity of `from`; the caller writes the length. */
static void copy_list(ClCx *cx, const MirInst *inst, MirValue from) {
  clx_copy_leaf(cx, inst->res, 0, from, 0);
  clx_copy_leaf(cx, inst->res, MIR_LIST_CAP_LEAF, from, MIR_LIST_CAP_LEAF);
}

/* `list.new`: a block of `capacity` elements, none for capacity 0 (the null pointer owns nothing). */
static void list_new(ClCx *cx, const MirInst *inst, uint32_t size) {
  cl_fn *f = cx->fb;
  const cl_val capacity = clx_arg(cx, inst, 0);
  const ClIf branch = clx_if_begin(cx, cl_icmp(f, CL_NE, capacity, clx_const(cx, 0)), 1);
  const cl_func alloc = clx_runtime_func(cx->mod, "msrt_alloc", 1, true);
  cl_val block = cl_call1(f, alloc, (cl_val[]){cl_imul(f, capacity, clx_const(cx, size > 0 ? size : 1))}, 1);
  cl_val joined[CLX_IF_WORDS];
  clx_if_end(cx, &branch, &block, joined);
  clx_set(cx, inst->res, 0, joined[0]);
  clx_set(cx, inst->res, MIR_LIST_LEN_LEAF, clx_const(cx, 0));
  clx_copy_leaf(cx, inst->res, MIR_LIST_CAP_LEAF, inst->args[0], 0);
}

/* `list.lit`: a block holding the operands, or the empty list for none. */
static void list_lit(ClCx *cx, const MirInst *inst, uint32_t size) {
  if (inst->nargs == 0) {
    for (uint32_t leaf = 0; leaf < 3; leaf++) {
      clx_set(cx, inst->res, leaf, clx_const(cx, 0));
    }
    return;
  }
  const cl_val block = clx_alloc(cx, inst->nargs * (size > 0 ? size : 1));
  clx_set(cx, inst->res, 0, block);
  for (uint32_t arg = 0; arg < inst->nargs; arg++) {
    clx_leaves_at(cx, inst->args[arg], cl_iadd(cx->fb, block, clx_const(cx, arg * size)), false);
  }
  clx_set(cx, inst->res, MIR_LIST_LEN_LEAF, clx_const(cx, inst->nargs));
  clx_set(cx, inst->res, MIR_LIST_CAP_LEAF, clx_const(cx, inst->nargs));
}

/* `list.grow`: a block of capacity 0 is a view or empty; it is never resized, a fresh block is made. */
static void list_grow(ClCx *cx, const MirInst *inst, uint32_t size) {
  cl_fn *f = cx->fb;
  const cl_val view = cl_icmp(f, CL_EQ, clx_get(cx, inst->args[0], MIR_LIST_CAP_LEAF), clx_const(cx, 0));
  const cl_val old = cl_select(f, view, clx_const(cx, 0), clx_get(cx, inst->args[0], 0));
  const cl_val bytes = cl_imul(f, clx_arg(cx, inst, 1), clx_const(cx, size > 0 ? size : 1));
  const cl_func grow = clx_runtime_func(cx->mod, "msrt_realloc", 2, true);
  clx_set(cx, inst->res, 0, cl_call1(f, grow, (cl_val[]){old, bytes}, 2));
  clx_copy_leaf(cx, inst->res, MIR_LIST_LEN_LEAF, inst->args[0], MIR_LIST_LEN_LEAF);
  clx_copy_leaf(cx, inst->res, MIR_LIST_CAP_LEAF, inst->args[1], 0);
}

static void list_write(ClCx *cx, const MirInst *inst, uint32_t size) {
  cl_fn *f = cx->fb;
  switch ((MirOp)inst->op) {
  case MOP_ListSetU:
  case MOP_ListFillU:
    copy_list(cx, inst, inst->args[0]);
    clx_copy_leaf(cx, inst->res, MIR_LIST_LEN_LEAF, inst->args[0], MIR_LIST_LEN_LEAF);
    clx_leaves_at(cx, inst->args[2], element_base(cx, inst->args[0], clx_get(cx, inst->args[1], 0), size), false);
    return;
  case MOP_ListPushU:
    copy_list(cx, inst, inst->args[0]);
    clx_set(cx, inst->res, MIR_LIST_LEN_LEAF, cl_iadd(f, clx_get(cx, inst->args[0], MIR_LIST_LEN_LEAF), clx_const(cx, 1)));
    clx_leaves_at(cx, inst->args[1], element_base(cx, inst->args[0], clx_get(cx, inst->args[0], MIR_LIST_LEN_LEAF), size),
                 false);
    return;
  case MOP_ListDropLast:
    copy_list(cx, inst, inst->args[0]);
    clx_set(cx, inst->res, MIR_LIST_LEN_LEAF, cl_isub(f, clx_get(cx, inst->args[0], MIR_LIST_LEN_LEAF), clx_const(cx, 1)));
    return;
  default:
    list_grow(cx, inst, size);
  }
}

static void list_read(ClCx *cx, const MirInst *inst) {
  const MirTy elem = list_elem(cx, value_type(cx, inst->args[0]));
  const cl_val at = element_base(cx, inst->args[0], clx_get(cx, inst->args[1], 0), mir_type_mem(cx->layouts, elem).size);
  if (inst->op == MOP_ListAddrU) {
    clx_set(cx, inst->res, 0, at);
    return;
  }
  clx_leaves_at(cx, inst->res, at, true);
}

bool clx_list_op(ClCx *cx, const MirInst *inst, bool *handled) {
  *handled = true;
  switch ((MirOp)inst->op) {
  case MOP_ListNew:
    list_new(cx, inst, mir_list_elem_size(cx->layouts, value_type(cx, inst->res)));
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
    clx_copy_leaf(cx, inst->res, 0, inst->args[0], MIR_LIST_LEN_LEAF);
    return true;
  case MOP_ListCap:
    clx_copy_leaf(cx, inst->res, 0, inst->args[0], MIR_LIST_CAP_LEAF);
    return true;
  default:
    *handled = false;
    return true;
  }
}
