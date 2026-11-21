/* compiler/mir/mir_glue_clone.c: the clone function of one type: `fn(borrow value) -> value` that copies what
 * the value owns. */
#include "compiler/mir/mir_glue_internal.h"

/* ---- records, optionals, lists and runtime objects ---- */

static uint32_t clone_type(const GlCx *cx) {
  MirModule *module = cx->module;
  const uint32_t id = cx->data->id;
  const MirTypeDef *def = &module->type_defs.ptr[id];
  MirBuilder b;
  mir_b_init(&b, module, cx->name, &cx->param, 1, cx->ty);
  MirValue value;
  mir_b_params(&b, &value, 1);
  MirValue *fields = MIRGL_ARRAY(module, MirValue, def->nfields);
  for (uint32_t index = 0; index < def->nfields; index++) {
    const MirImm imm = {.tag = MI_FIELD, .a = id, .b = index};
    fields[index] = mirgl_clone(&b, mirgl_val(&b, MOP_TypeGet, &value, 1, imm, def->fields[index].ty));
  }
  const MirImm new_imm = {.tag = MI_TYPE, .a = id};
  mir_b_ret(&b, mirgl_val(&b, MOP_TypeNew, fields, def->nfields, new_imm, mir_ty_type(module, id)));
  return mirgl_finish(&b);
}

static uint32_t clone_opt(const GlCx *cx) {
  MirBuilder b;
  mir_b_init(&b, cx->module, cx->name, &cx->param, 1, cx->ty);
  MirValue value;
  mir_b_params(&b, &value, 1);
  const MirBlock some = mir_b_new_block(&b);
  const MirBlock none = mir_b_new_block(&b);
  mir_b_br_if(&b, mirgl_opt_is_some(&b, value), some, NULL, 0, none, NULL, 0);
  mir_b_switch_to(&b, some);
  const MirValue copy = mirgl_clone(&b, mirgl_opt_payload(&b, MOP_OptGet, value));
  const MirTy some_ty = mir_ty_opt(cx->module, mir_b_ty(&b, copy));
  mir_b_ret(&b, mirgl_val(&b, MOP_OptSome, &copy, 1, (MirImm){0}, some_ty));
  mir_b_switch_to(&b, none);
  mir_b_ret(&b, mirgl_val(&b, MOP_OptNone, NULL, 0, (MirImm){0}, cx->ty));
  return mirgl_finish(&b);
}

static uint32_t clone_list(const GlCx *cx) {
  const MirTy elem = cx->data->elem;
  MirBuilder b;
  mir_b_init(&b, cx->module, cx->name, &cx->param, 1, cx->ty);
  MirValue list;
  mir_b_params(&b, &list, 1);
  const MirValue len = mirgl_list_len(&b, list);
  const MirValue fresh = mir_b_list_new(&b, elem, len);
  const MirBlock head = mir_b_new_block(&b);
  const MirBlock body = mir_b_new_block(&b);
  const MirBlock exit = mir_b_new_block(&b);
  const MirValue index = mir_b_add_block_param(&b, head, MIR_INT, MM_BORROW);
  const MirValue acc = mir_b_add_block_param(&b, head, cx->ty, MM_MOVE);
  const MirValue entry_args[2] = {mir_b_iconst(&b, 0), fresh};
  mir_b_br(&b, head, entry_args, 2);
  mir_b_switch_to(&b, head);
  mir_b_br_if(&b, mir_b_icmp(&b, MCC_LT, index, len), body, NULL, 0, exit, NULL, 0);
  mir_b_switch_to(&b, body);
  const MirValue get_args[2] = {list, index};
  const MirValue item = mirgl_val(&b, MOP_ListGetU, get_args, 2, (MirImm){0}, elem);
  const MirValue push_args[2] = {acc, mirgl_clone(&b, item)};
  const MirValue grown = mirgl_val(&b, MOP_ListPushU, push_args, 2, (MirImm){0}, cx->ty);
  const MirValue next_args[2] = {mir_b_binop(&b, MOP_IAdd, index, mir_b_iconst(&b, 1)), grown};
  mir_b_br(&b, head, next_args, 2);
  mir_b_switch_to(&b, exit);
  mir_b_ret(&b, acc);
  return mirgl_finish(&b);
}

static uint32_t clone_obj(const GlCx *cx) {
  MirModule *module = cx->module;
  const MirTy three_ptrs[3] = {MIR_PTR, MIR_PTR, MIR_PTR};
  const uint32_t copy = mirgl_extern(module, "msrt_slot_copy", three_ptrs, 3, MIR_VOID, false);
  MirBuilder b;
  mir_b_init(&b, module, cx->name, &cx->param, 1, cx->ty);
  MirValue value;
  mir_b_params(&b, &value, 1);
  const MirValue src = mirgl_slot(&b, cx->ty);
  const MirValue store_args[2] = {src, value};
  (void)mirgl_val(&b, MOP_Store, store_args, 2, (MirImm){0}, MIR_NONE);
  const MirValue dst = mirgl_slot(&b, cx->ty);
  const MirValue desc = mirgl_val(&b, MOP_TypeDesc, NULL, 0, mirgl_imm_ty(cx->ty), MIR_PTR);
  const MirValue args[3] = {desc, src, dst};
  (void)mirgl_call_rt(&b, copy, args, 3);
  mir_b_ret(&b, mirgl_take(&b, dst, cx->ty));
  return mirgl_finish(&b);
}

/* ---- the entry ---- */

uint32_t mirgl_make_clone(MirModule *module, MirGlue *glue, MirTy ty) {
  const MirTyData *data = mir_ty_data(module, ty);
  const char *suffix = mirgl_recurses(module, ty) ? "clone_body" : "clone";
  const GlCx cx = {.module = module,
                   .glue = glue,
                   .name = mirgl_name(module, mirgl_count(glue, MG_CLONE), suffix),
                   .param = {ty, MM_BORROW},
                   .ty = ty,
                   .data = data};
  switch ((MirTyKind)data->kind) {
  case MK_TYPE: return clone_type(&cx);
  case MK_ALT: return mirgl_clone_alt(&cx);
  case MK_OPT: return clone_opt(&cx);
  case MK_LIST: return clone_list(&cx);
  case MK_OBJ: return clone_obj(&cx);
  default: return MIR_NONE;
  }
}
