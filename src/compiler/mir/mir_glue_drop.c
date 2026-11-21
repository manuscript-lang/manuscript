/* compiler/mir/mir_glue_drop.c: the drop function of one type: `fn(move value)` that releases what the value
 * owns. */
#include "compiler/mir/mir_glue_internal.h"

/* ---- records and optionals ---- */

static uint32_t drop_type(const GlCx *cx) {
  MirBuilder b;
  mir_b_init(&b, cx->module, cx->name, &cx->param, 1, MIR_VOID);
  MirValue value;
  mir_b_params(&b, &value, 1);
  const MirImm mask = {.tag = MI_TYPEMASK, .a = cx->data->id, .b = 0};
  (void)mirgl_val(&b, MOP_TypeRelease, &value, 1, mask, MIR_NONE);
  mir_b_ret(&b, MIR_NONE);
  return mirgl_finish(&b);
}

static uint32_t drop_opt(const GlCx *cx) {
  MirBuilder b;
  const bool boxed = mirgl_opt_boxed(cx->module, cx->data->elem);
  mir_b_init(&b, cx->module, cx->name, &cx->param, 1, MIR_VOID);
  MirValue value;
  mir_b_params(&b, &value, 1);
  const MirBlock some = mir_b_new_block(&b);
  const MirBlock done = mir_b_new_block(&b);
  mir_b_br_if(&b, mirgl_opt_is_some(&b, value), some, NULL, 0, done, NULL, 0);
  mir_b_switch_to(&b, some);
  /* A boxed payload is moved out of its box, which is freed. */
  mirgl_drop(&b, mirgl_opt_payload(&b, boxed ? MOP_OptUnbox : MOP_OptGet, value));
  mir_b_br(&b, done, NULL, 0);
  mir_b_switch_to(&b, done);
  mir_b_ret(&b, MIR_NONE);
  return mirgl_finish(&b);
}

/* ---- lists ---- */

/* The loop that drops elements `[start, len)` of `list`; the builder ends in the block that frees the list. */
static void drop_elements(MirBuilder *b, MirValue list, MirValue start, MirTy elem) {
  const MirValue len = mirgl_list_len(b, list);
  const MirBlock head = mir_b_new_block(b);
  const MirBlock body = mir_b_new_block(b);
  const MirBlock free_block = mir_b_new_block(b);
  const MirValue index = mir_b_add_block_param(b, head, MIR_INT, MM_BORROW);
  mir_b_br(b, head, &start, 1);
  mir_b_switch_to(b, head);
  mir_b_br_if(b, mir_b_icmp(b, MCC_LT, index, len), body, NULL, 0, free_block, NULL, 0);
  mir_b_switch_to(b, body);
  const MirValue get_args[2] = {list, index};
  mirgl_drop(b, mirgl_val(b, MOP_ListGetU, get_args, 2, (MirImm){0}, elem));
  const MirValue next = mir_b_binop(b, MOP_IAdd, index, mir_b_iconst(b, 1));
  mir_b_br(b, head, &next, 1);
  mir_b_switch_to(b, free_block);
}

/* Drops the elements of an owned list from index `from` on and frees its block. A view (capacity 0) borrows
 * its elements and owns no block: nothing to drop or free. `from` is the second parameter of the release
 * function and the constant 0 of the drop function; a negative one counts from the start. */
static uint32_t drop_list_end(const GlCx *cx, bool with_from) {
  MirModule *module = cx->module;
  const MirParam params[2] = {cx->param, {MIR_INT, MM_BORROW}};
  MirTy elem = mirgl_elem(module, cx->ty, false);
  if (elem != MIR_NONE && !mir_needs_drop(module, elem)) {
    elem = MIR_NONE;
  }
  MirBuilder b;
  mir_b_init(&b, module, cx->name, params, with_from ? 2 : 1, MIR_VOID);
  MirValue p[2];
  mir_b_params(&b, p, with_from ? 2 : 1);
  const MirBlock owned = mir_b_new_block(&b);
  const MirBlock done = mir_b_new_block(&b);
  const MirValue cap = mirgl_val(&b, MOP_ListCap, p, 1, (MirImm){0}, MIR_INT);
  const MirValue zero = mir_b_iconst(&b, 0);
  mir_b_br_if(&b, mir_b_icmp(&b, MCC_NE, cap, zero), owned, NULL, 0, done, NULL, 0);
  mir_b_switch_to(&b, owned);
  if (elem != MIR_NONE) {
    const MirValue clamped = with_from ? mir_b_select(&b, mir_b_icmp(&b, MCC_LT, p[1], zero), zero, p[1])
                                       : zero;
    drop_elements(&b, p[0], clamped, elem);
  }
  mirgl_free(&b, p[0]);
  mir_b_br(&b, done, NULL, 0);
  mir_b_switch_to(&b, done);
  mir_b_ret(&b, MIR_NONE);
  return mirgl_finish(&b);
}

uint32_t mir_glue_list_release(MirModule *module, MirTy ty) {
  const GlCx cx = {.module = module,
                   .name = mirgl_name(module, module->funcs.len, "release"),
                   .param = {ty, MM_MOVE},
                   .ty = ty,
                   .data = mir_ty_data(module, ty)};
  return drop_list_end(&cx, true);
}

static uint32_t drop_list(const GlCx *cx) {
  return drop_list_end(cx, false);
}

/* ---- runtime objects and interfaces ---- */

static uint32_t drop_obj(const GlCx *cx) {
  MirModule *module = cx->module;
  /* The runtime drops a map or set it finds in memory, through its descriptor. */
  const MirTy two_ptrs[2] = {MIR_PTR, MIR_PTR};
  const uint32_t drop = mirgl_extern(module, "msrt_slot_drop", two_ptrs, 2, MIR_VOID, false);
  MirBuilder b;
  mir_b_init(&b, module, cx->name, &cx->param, 1, MIR_VOID);
  MirValue value;
  mir_b_params(&b, &value, 1);
  const MirValue slot = mirgl_slot(&b, cx->ty);
  mirgl_put(&b, slot, value);
  /* A map that was never filled has no slots (word 0 is null): nothing to release, so no runtime call. */
  const MirValue first = mirgl_load(&b, slot, MIR_INT);
  const MirBlock run = mir_b_new_block(&b);
  const MirBlock done = mir_b_new_block(&b);
  mir_b_br_if(&b, mir_b_icmp(&b, MCC_NE, first, mir_b_iconst(&b, 0)), run, NULL, 0, done, NULL, 0);
  mir_b_seal_block(&b, run);
  mir_b_seal_block(&b, done);
  mir_b_switch_to(&b, run);
  const MirValue desc = mirgl_val(&b, MOP_TypeDesc, NULL, 0, mirgl_imm_ty(cx->ty), MIR_PTR);
  const MirValue args[2] = {desc, slot};
  (void)mirgl_call_rt(&b, drop, args, 2);
  mir_b_br(&b, done, NULL, 0);
  mir_b_switch_to(&b, done);
  mir_b_ret(&b, MIR_NONE);
  return mirgl_finish(&b);
}

/* The vtable word's tag says what the value owns: 0 the box and its payload, 1 only the box
 * (`iface.borrow`), 2 nothing (`iface.view`). */
static uint32_t drop_iface(const GlCx *cx) {
  MirBuilder b;
  mir_b_init(&b, cx->module, cx->name, &cx->param, 1, MIR_VOID);
  MirValue value;
  mir_b_params(&b, &value, 1);
  const MirBlock owned = mir_b_new_block(&b);
  const MirBlock rest = mir_b_new_block(&b);
  const MirBlock boxed = mir_b_new_block(&b);
  const MirBlock done = mir_b_new_block(&b);
  const MirValue tag = mirgl_val(&b, MOP_IfaceTag, &value, 1, (MirImm){0}, MIR_INT);
  const MirValue is_owned = mir_b_icmp(&b, MCC_EQ, tag, mir_b_iconst(&b, 0));
  mir_b_br_if(&b, is_owned, owned, NULL, 0, rest, NULL, 0);
  mir_b_switch_to(&b, owned);
  (void)mirgl_val(&b, MOP_IfaceDestroy, &value, 1, (MirImm){0}, MIR_NONE);
  mir_b_br(&b, done, NULL, 0);
  mir_b_switch_to(&b, rest);
  const MirValue is_box = mir_b_icmp(&b, MCC_EQ, tag, mir_b_iconst(&b, 1));
  mir_b_br_if(&b, is_box, boxed, NULL, 0, done, NULL, 0);
  mir_b_switch_to(&b, boxed);
  mirgl_free(&b, mirgl_val(&b, MOP_IfaceData, &value, 1, (MirImm){0}, MIR_PTR));
  mir_b_br(&b, done, NULL, 0);
  mir_b_switch_to(&b, done);
  mir_b_ret(&b, MIR_NONE);
  return mirgl_finish(&b);
}

/* ---- the entry ---- */

uint32_t mirgl_make_drop(MirModule *module, MirGlue *glue, MirTy ty) {
  const MirTyData *data = mir_ty_data(module, ty);
  const char *suffix = mirgl_recurses(module, ty) ? "drop_body" : "drop";
  const GlCx cx = {.module = module,
                   .glue = glue,
                   .name = mirgl_name(module, module->funcs.len, suffix),
                   .param = {ty, MM_MOVE},
                   .ty = ty,
                   .data = data};
  switch ((MirTyKind)data->kind) {
  case MK_TYPE: return drop_type(&cx);
  case MK_ALT: return mirgl_drop_alt(&cx);
  case MK_OPT: return drop_opt(&cx);
  case MK_LIST:
  case MK_BYTES: return drop_list(&cx);
  case MK_OBJ: return drop_obj(&cx);
  case MK_IFACE: return drop_iface(&cx);
  default: return MIR_NONE; /* drop glue is made for the kinds mirgl_eligible accepts */
  }
}

