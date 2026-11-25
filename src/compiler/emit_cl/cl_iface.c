/* Owns interfaces. A value is two words: the data address and the address of its vtable with a tag in the low two bits
 * (owned, boxed, view). Slot 0 of a vtable is the payload drop, slot 1 + k the code of method k. */
#include "compiler/emit_cl/cl_cx.h"

enum { TAG_OWNED = 0, TAG_BOX = 1, TAG_VIEW = 2, TAG_MASK = 3 };

/* The vtable address of interface value `iface`, without its tag. */
static ms_cl_val untag(ClCx *cx, MirValue iface) {
  return ms_cl_band(cx->fb, cl_get(cx, iface, 1), cl_const(cx, -(TAG_MASK + 1)));
}

static bool vtable_word(ClCx *cx, uint32_t vtable, ms_cl_val *out) {
  if (cx->mod->data == NULL || vtable >= cx->module->vtables.len) {
    cx->why = "vtable without static data";
    return false;
  }
  *out = ms_cl_data_addr(cx->fb, cx->mod->syms[cx->mod->data->vtables.ptr[vtable]]);
  return true;
}

/* A call of the function at `code` with one i64 argument, giving `result` words (0 or 1). */
static ms_cl_val call_word(ClCx *cx, ms_cl_val code, ms_cl_val argument, bool result) {
  ms_cl *cl = cx->mod->cl;
  ms_cl_sig sig = ms_cl_sig_new(cl);
  ms_cl_sig_param(cl, sig, MS_CL_I64, MS_CL_EXT_NONE);
  if (result) {
    ms_cl_sig_ret(cl, sig, MS_CL_I64, MS_CL_EXT_NONE);
  }
  ms_cl_val out = {0};
  ms_cl_call_indirect(cx->fb, sig, code, &argument, 1, result ? &out : NULL);
  return out;
}

/* `iface.new` boxes the operand on the heap (owned); `iface.borrow` keeps it in the frame when nothing outlives it
 * (view) and on the heap otherwise (boxed, freed with the value). */
static bool iface_new(ClCx *cx, const MirInst *inst) {
  const MirTy type = cl_value_type(cx, inst->args[0]);
  const bool framed = inst->op == MOP_IfaceBorrow && cx->borrowed != NULL && cx->borrowed[inst->res];
  ms_cl_val table = {0};
  if (!vtable_word(cx, inst->imm.a, &table)) {
    return false;
  }
  uint32_t tag = TAG_VIEW;
  ms_cl_val object;
  if (framed) {
    object = ms_cl_stack_addr(cx->fb, ms_cl_stack_slot(cx->fb, cl_slot_bytes(cx, type), 3), 0);
  } else {
    tag = inst->op == MOP_IfaceNew ? TAG_OWNED : TAG_BOX;
    object = cl_alloc(cx, mir_type_mem(cx->layouts, type).size);
  }
  cl_set(cx, inst->res, 0, object);
  if (cl_leaves(cx, type).len > 0) {
    cl_leaves_at(cx, inst->args[0], object, false);
  }
  cl_set(cx, inst->res, 1, ms_cl_iadd(cx->fb, table, cl_const(cx, tag)));
  return true;
}

/* `iface.own`: a box of its own holding a bitwise copy of the payload `iface` points at (the payload's size is the word
 * after the clone in its vtable), tagged box-only, so dropping the copy frees the box and leaves the payload to the
 * value it was borrowed from. */
static void iface_own(ClCx *cx, const MirInst *inst) {
  ms_cl_fn *f = cx->fb;
  const MirTyData *data = mir_ty_data(cx->module, cl_value_type(cx, inst->args[0]));
  const ms_cl_val table = untag(cx, inst->args[0]);
  const ms_cl_val size = ms_cl_load(f, MS_CL_I64, MS_CL_NOTRAP, table, (int32_t)(8 * (2 + cx->module->ifaces.ptr[data->id].nmethods)));
  const ms_cl_val bytes = ms_cl_select(f, ms_cl_icmp(f, MS_CL_EQ, size, cl_const(cx, 0)), cl_const(cx, 1), size);
  const ms_cl_func alloc = cl_runtime_func(cx->mod, "msrt_alloc", 1, true);
  const ms_cl_val block = ms_cl_call1(f, alloc, &bytes, 1);
  ms_cl_copy_dyn(f, block, cl_get(cx, inst->args[0], 0), size);
  cl_set(cx, inst->res, 0, block);
  cl_set(cx, inst->res, 1, ms_cl_iadd(f, table, cl_const(cx, TAG_BOX)));
}

/* `clone` of an interface value: the payload copier sits in the vtable after the methods. The copy owns its payload
 * whatever the source did, so the tag bits come off. */
static bool iface_clone(ClCx *cx, const MirInst *inst) {
  const MirTyData *data = mir_ty_data(cx->module, cl_value_type(cx, inst->args[0]));
  if (data->kind != MK_IFACE) {
    return false;
  }
  const ms_cl_val table = untag(cx, inst->args[0]);
  const ms_cl_val copier = ms_cl_load(cx->fb, MS_CL_I64, MS_CL_NOTRAP, table,
                                      (int32_t)(8 * (1 + cx->module->ifaces.ptr[data->id].nmethods)));
  cl_set(cx, inst->res, 0, call_word(cx, copier, cl_get(cx, inst->args[0], 0), true));
  cl_set(cx, inst->res, 1, table);
  return true;
}

bool cl_iface_op(ClCx *cx, const MirInst *inst, bool *handled) {
  *handled = true;
  switch ((MirOp)inst->op) {
  case MOP_IfaceNew:
  case MOP_IfaceBorrow:
    return iface_new(cx, inst);
  case MOP_IfaceOwn:
    iface_own(cx, inst);
    return true;
  case MOP_IfaceData:
    cl_copy_leaf(cx, inst->res, 0, inst->args[0], 0);
    return true;
  case MOP_IfaceTag:
    cl_set(cx, inst->res, 0, ms_cl_band(cx->fb, cl_get(cx, inst->args[0], 1), cl_const(cx, TAG_MASK)));
    return true;
  case MOP_IfaceView:
    cl_copy_leaf(cx, inst->res, 0, inst->args[0], 0);
    cl_set(cx, inst->res, 1, ms_cl_bor(cx->fb, untag(cx, inst->args[0]), cl_const(cx, TAG_VIEW)));
    return true;
  case MOP_Clone:
    if (iface_clone(cx, inst)) {
      return true;
    }
    break;
  case MOP_IfaceIs: {
    ms_cl_val want = {0};
    if (!vtable_word(cx, inst->imm.a, &want)) {
      return false;
    }
    cl_set(cx, inst->res, 0, ms_cl_icmp(cx->fb, MS_CL_EQ, untag(cx, inst->args[0]), want));
    return true;
  }
  case MOP_IfaceDestroy: {
    const ms_cl_val drop = ms_cl_load(cx->fb, MS_CL_I64, MS_CL_NOTRAP, untag(cx, inst->args[0]), 0);
    (void)call_word(cx, drop, cl_get(cx, inst->args[0], 0), false);
    return true;
  }
  default:
    break;
  }
  *handled = false;
  return true;
}
