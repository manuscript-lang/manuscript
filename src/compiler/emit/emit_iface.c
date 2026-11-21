/* Owns interfaces. A value is two words: the data address and the address of its vtable with a tag in the low two
 * bits (owned, boxed, view). Slot 0 of a vtable is the payload drop, slot 1 + k the code of method k. */
#include "compiler/emit/emit_cx.h"

enum { TAG_OWNED = 0, TAG_BOX = 1, TAG_VIEW = 2, TAG_MASK = 3 };

/* Writes `%t<n> = and i64 <word>, -4` (the vtable address) and names it in `out`. */
static void untag(EmitCx *cx, MirValue iface, char *out, size_t capacity) {
  uint32_t number = cx->next++;
  ms_strbuild_printf(cx->out, "  %%t%u = and i64 %%v%u.1, %d\n", number, iface, -(TAG_MASK + 1));
  emit_register_name(out, capacity, "t", number);
}

/* Writes `%t<n> = ptrtoint ptr @vtable to i64` and names it in `out`. */
static bool vtable_word(EmitCx *cx, uint32_t vtable, char *out, size_t capacity) {
  if (cx->data == NULL || vtable >= cx->module->vtables.len) {
    cx->why = "vtable without static data";
    return false;
  }
  uint32_t number = cx->next++;
  ms_strbuild_printf(cx->out, "  %%t%u = ptrtoint ptr ", number);
  emit_symbol(cx->out, cx->data->syms.ptr[cx->data->vtables.ptr[vtable]].name);
  ms_strbuild_append_text(cx->out, " to i64\n");
  emit_register_name(out, capacity, "t", number);
  return true;
}

/* `iface.new` boxes the operand on the heap (owned); `iface.borrow` keeps it in the frame when nothing outlives
 * it (view) and on the heap otherwise (boxed, freed with the value). */
static bool iface_new(EmitCx *cx, const MirInst *inst, const EmitSite *site) {
  MirTy type = emit_value_type(cx, inst->args[0]);
  bool framed = inst->op == MOP_IfaceBorrow && cx->borrowed != NULL && cx->borrowed[inst->res];
  uint32_t tag = TAG_OWNED;
  char table[24];
  char object[24];
  if (!vtable_word(cx, inst->imm.a, table, sizeof table)) {
    return false;
  }
  if (framed) {
    tag = TAG_VIEW;
    emit_text_name(object, sizeof object, "i", site->block, "_", site->index);
    ms_strbuild_printf(cx->out, "  %%v%u = ptrtoint ptr %s to i64\n", inst->res, object);
  } else {
    tag = inst->op == MOP_IfaceNew ? TAG_OWNED : TAG_BOX;
    uint32_t size = mir_type_mem(cx->layouts, type).size;
    ms_strbuild_printf(cx->out, "  %%v%u = call i64 @msrt_alloc(i64 %u)\n", inst->res, size > 0 ? size : 1);
    emit_pointer(cx, inst->res, object, sizeof object);
  }
  if (emit_leaves(cx, type).len > 0) {
    emit_leaves_at(cx, inst->args[0], object, false);
  }
  ms_strbuild_printf(cx->out, "  %%v%u.1 = add i64 %s, %u\n", inst->res, table, tag);
  return true;
}

/* `call.method`: the code word of the method's slot, called with the data address first. */
static void call_method(EmitCx *cx, const MirInst *inst, const EmitSite *site) {
  char table[24];
  char slot[24];
  char lead[24];
  char callee[24];
  untag(cx, inst->args[0], table, sizeof table);
  uint32_t number = cx->next++;
  ms_strbuild_printf(cx->out, "  %%p%u = inttoptr i64 %s to ptr\n", number, table);
  emit_register_name(table, sizeof table, "p", number);
  emit_offset_pointer(cx, table, 8 * (1 + inst->imm.b), slot, sizeof slot);
  uint32_t code = cx->next++;
  ms_strbuild_printf(cx->out, "  %%k%u = load ptr, ptr %s\n", code, slot);
  emit_register_name(callee, sizeof callee, "k", code);
  lead[0] = 'i';
  lead[1] = '6';
  lead[2] = '4';
  lead[3] = ' ';
  emit_register_name(lead + 4, sizeof lead - 4, "v", inst->args[0]);
  emit_call_to(cx, inst, site, callee, lead);
}

/* `iface.destroy`: calls the payload drop in slot 0 with the data address. */
static void iface_destroy(EmitCx *cx, const MirInst *inst) {
  char table[24];
  untag(cx, inst->args[0], table, sizeof table);
  uint32_t number = cx->next++;
  ms_strbuild_printf(cx->out, "  %%p%u = inttoptr i64 %s to ptr\n  %%k%u = load ptr, ptr %%p%u\n", number, table, number,
                     number);
  ms_strbuild_printf(cx->out, "  call void %%k%u(i64 %%v%u)\n", number, inst->args[0]);
}

/* `clone` of an interface value: the payload copier sits in the vtable after the methods. The copy owns its
 * payload whatever the source did, so the tag bits come off. */
static bool iface_clone(EmitCx *cx, const MirInst *inst) {
  const MirTyData *data = mir_ty_data(cx->module, emit_value_type(cx, inst->args[0]));
  if (data->kind != MK_IFACE) {
    return false;
  }
  char table[24];
  untag(cx, inst->args[0], table, sizeof table);
  uint32_t number = cx->next++;
  ms_strbuild_printf(cx->out,
                     "  %%t%ua = add i64 %s, %u\n  %%p%u = inttoptr i64 %%t%ua to ptr\n"
                     "  %%k%u = load ptr, ptr %%p%u\n",
                     number, table, 8 * (1 + cx->module->ifaces.ptr[data->id].nmethods), number, number, number,
                     number);
  ms_strbuild_printf(cx->out, "  %%v%u = call i64 %%k%u(i64 %%v%u)\n  %%v%u.1 = add i64 %s, 0\n", inst->res, number,
                     inst->args[0], inst->res, table);
  return true;
}

bool emit_iface_op(EmitCx *cx, const MirInst *inst, const EmitSite *site, bool *handled) {
  *handled = true;
  char table[24];
  switch ((MirOp)inst->op) {
  case MOP_IfaceNew:
  case MOP_IfaceBorrow:
    return iface_new(cx, inst, site);
  case MOP_CallMethod:
    call_method(cx, inst, site);
    return true;
  case MOP_IfaceData:
    ms_strbuild_printf(cx->out, "  %%v%u = add i64 %%v%u, 0\n", inst->res, inst->args[0]);
    return true;
  case MOP_IfaceTag:
    ms_strbuild_printf(cx->out, "  %%v%u = and i64 %%v%u.1, %d\n", inst->res, inst->args[0], TAG_MASK);
    return true;
  case MOP_IfaceView:
    untag(cx, inst->args[0], table, sizeof table);
    ms_strbuild_printf(cx->out, "  %%v%u = add i64 %%v%u, 0\n  %%v%u.1 = or i64 %s, %d\n", inst->res, inst->args[0],
                       inst->res, table, TAG_VIEW);
    return true;
  case MOP_Clone:
    if (iface_clone(cx, inst)) {
      return true;
    }
    *handled = false;
    return true;
  case MOP_IfaceIs: {
    char want[24];
    untag(cx, inst->args[0], table, sizeof table);
    if (!vtable_word(cx, inst->imm.a, want, sizeof want)) {
      return false;
    }
    ms_strbuild_printf(cx->out, "  %%v%u = icmp eq i64 %s, %s\n", inst->res, table, want);
    return true;
  }
  case MOP_IfaceDestroy:
    iface_destroy(cx, inst);
    return true;
  default:
    *handled = false;
    return true;
  }
}
