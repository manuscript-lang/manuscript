/* Owns interfaces. A value is two words: the data address and the address of its vtable with a tag in the low two bits
 * (owned, boxed, view). Slot 0 of a vtable is the payload drop, slot 1 + k the code of method k. */
#include "compiler/emit_cl/cl_cx.h"

enum { TAG_OWNED = 0, TAG_BOX = 1, TAG_VIEW = 2, TAG_MASK = 3 };

/* The vtable address of interface value `iface`, without its tag. */
static cl_val untag(ClCx *cx, MirValue iface) {
  return cl_band(cx->fb, clx_get(cx, iface, 1), clx_const(cx, -(TAG_MASK + 1)));
}

static bool vtable_word(ClCx *cx, uint32_t vtable, cl_val *out) {
  if (cx->mod->data == NULL || vtable >= cx->module->vtables.len) {
    cx->why = "vtable without static data";
    return false;
  }
  *out = cl_data_addr(cx->fb, cx->mod->syms[cx->mod->data->vtables.ptr[vtable]]);
  return true;
}

/* A call of the function at `code` with one i64 argument, giving `result` words (0 or 1). */
static cl_val call_word(ClCx *cx, cl_val code, cl_val argument, bool result) {
  cl *cl = cx->mod->cl;
  cl_sig sig = cl_sig_new(cl);
  cl_sig_param(cl, sig, CL_I64, CL_EXT_NONE);
  if (result) {
    cl_sig_ret(cl, sig, CL_I64, CL_EXT_NONE);
  }
  cl_val out = {0};
  cl_call_indirect(cx->fb, sig, code, &argument, 1, result ? &out : NULL);
  return out;
}

/* `iface.new` boxes the operand on the heap (owned); `iface.borrow` keeps it in the frame when nothing outlives it
 * (view) and on the heap otherwise (boxed, freed with the value). */
static bool iface_new(ClCx *cx, const MirInst *inst) {
  const MirTy type = clx_value_type(cx, inst->args[0]);
  const bool framed = inst->op == MOP_IfaceBorrow && cx->borrowed != NULL && cx->borrowed[inst->res];
  cl_val table = {0};
  if (!vtable_word(cx, inst->imm.a, &table)) {
    return false;
  }
  uint32_t tag = TAG_VIEW;
  cl_val object;
  if (framed) {
    object = cl_stack_addr(cx->fb, cl_stack_slot(cx->fb, clx_slot_bytes(cx, type), 3), 0);
  } else {
    tag = inst->op == MOP_IfaceNew ? TAG_OWNED : TAG_BOX;
    object = clx_alloc(cx, mir_type_mem(cx->layouts, type).size);
  }
  clx_set(cx, inst->res, 0, object);
  if (clx_leaves(cx, type).len > 0) {
    clx_leaves_at(cx, inst->args[0], object, false);
  }
  clx_set(cx, inst->res, 1, cl_iadd(cx->fb, table, clx_const(cx, tag)));
  return true;
}

/* `iface.own`: a box of its own holding a bitwise copy of the payload `iface` points at (the payload's size is the word
 * after the clone in its vtable), tagged box-only, so dropping the copy frees the box and leaves the payload to the
 * value it was borrowed from. */
static void iface_own(ClCx *cx, const MirInst *inst) {
  cl_fn *f = cx->fb;
  const MirTyData *data = mir_ty_data(cx->module, clx_value_type(cx, inst->args[0]));
  const cl_val table = untag(cx, inst->args[0]);
  const cl_val size = cl_load(f, CL_I64, CL_NOTRAP, table, (int32_t)(8 * (2 + cx->module->ifaces.ptr[data->id].nmethods)));
  const cl_val bytes = cl_select(f, cl_icmp(f, CL_EQ, size, clx_const(cx, 0)), clx_const(cx, 1), size);
  const cl_func alloc = clx_runtime_func(cx->mod, "msrt_alloc", 1, true);
  const cl_val block = cl_call1(f, alloc, &bytes, 1);
  cl_copy_dyn(f, block, clx_get(cx, inst->args[0], 0), size);
  clx_set(cx, inst->res, 0, block);
  clx_set(cx, inst->res, 1, cl_iadd(f, table, clx_const(cx, TAG_BOX)));
}

/* `clone` of an interface value: the payload copier sits in the vtable after the methods. The copy owns its payload
 * whatever the source did, so the tag bits come off. */
static bool iface_clone(ClCx *cx, const MirInst *inst) {
  const MirTyData *data = mir_ty_data(cx->module, clx_value_type(cx, inst->args[0]));
  if (data->kind != MK_IFACE) {
    return false;
  }
  const cl_val table = untag(cx, inst->args[0]);
  const cl_val copier = cl_load(cx->fb, CL_I64, CL_NOTRAP, table,
                                      (int32_t)(8 * (1 + cx->module->ifaces.ptr[data->id].nmethods)));
  clx_set(cx, inst->res, 0, call_word(cx, copier, clx_get(cx, inst->args[0], 0), true));
  clx_set(cx, inst->res, 1, table);
  return true;
}

bool clx_iface_op(ClCx *cx, const MirInst *inst, bool *handled) {
  *handled = true;
  switch ((MirOp)inst->op) {
  case MOP_IfaceNew:
  case MOP_IfaceBorrow:
    return iface_new(cx, inst);
  case MOP_IfaceOwn:
    iface_own(cx, inst);
    return true;
  case MOP_IfaceData:
    clx_copy_leaf(cx, inst->res, 0, inst->args[0], 0);
    return true;
  case MOP_IfaceTag:
    clx_set(cx, inst->res, 0, cl_band(cx->fb, clx_get(cx, inst->args[0], 1), clx_const(cx, TAG_MASK)));
    return true;
  case MOP_IfaceView:
    clx_copy_leaf(cx, inst->res, 0, inst->args[0], 0);
    clx_set(cx, inst->res, 1, cl_bor(cx->fb, untag(cx, inst->args[0]), clx_const(cx, TAG_VIEW)));
    return true;
  case MOP_Clone:
    if (iface_clone(cx, inst)) {
      return true;
    }
    break;
  case MOP_IfaceIs: {
    cl_val want = {0};
    if (!vtable_word(cx, inst->imm.a, &want)) {
      return false;
    }
    clx_set(cx, inst->res, 0, cl_icmp(cx->fb, CL_EQ, untag(cx, inst->args[0]), want));
    return true;
  }
  case MOP_IfaceDestroy: {
    const cl_val drop = cl_load(cx->fb, CL_I64, CL_NOTRAP, untag(cx, inst->args[0]), 0);
    (void)call_word(cx, drop, clx_get(cx, inst->args[0], 0), false);
    return true;
  }
  default:
    break;
  }
  *handled = false;
  return true;
}
