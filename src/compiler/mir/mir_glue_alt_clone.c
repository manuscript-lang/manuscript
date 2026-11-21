/* compiler/mir/mir_glue_alt_clone.c: the clone function of an alternative. A boxed alternative with a chain (a
 * case holding the alternative again as its last such field) is copied by a loop that goes front to back, so a
 * long chain does not use the stack. */
#include "compiler/mir/mir_glue_internal.h"

/* The chain tail of each case of boxed alternative `alt` (type `ty`): the field, whether it is optional, and
 * the byte offset in the block of the leaf that holds the next block's pointer. */
static GlTail case_tail(const MirModule *module, const MirAltFields *fields, const uint32_t *offsets,
                        MirTy ty, uint32_t alt, uint32_t case_index) {
  const MirCaseDef *def = &module->alts.ptr[alt].cases[case_index];
  for (uint32_t field = def->nfields; field-- > 0;) {
    MirTy inner = MIR_NONE;
    const MirTy field_ty = def->fields[field].ty;
    const bool optional = mirgl_is_opt(module, field_ty, &inner);
    const bool chains = field_ty == ty || (optional && inner == ty);
    if (field >= MIRGL_MAX_CHAIN_FIELD || !chains) {
      continue;
    }
    const MirAltField *leaf = &fields->fields[fields->case_start[case_index] + field];
    if (leaf->nleaves != 0) {
      return (GlTail){.some = true,
                      .field = field,
                      .optional = field_ty != ty,
                      .offset = offsets[leaf->leaves[leaf->nleaves - 1]]};
    }
  }
  return (GlTail){0};
}

/* Fills `tails` (one per case); false for any alternative that is not a boxed chain. */
static bool boxed_chain(const MirModule *module, MirTy ty, uint32_t alt, GlTail *tails) {
  MirLayouts layouts;
  mir_layouts_init(&layouts, module);
  bool any = false;
  const MirShape *shape = mir_layouts_alt_boxed(&layouts, alt) ? mir_shape(&layouts, ty) : NULL;
  if (shape != NULL && shape->alt == MIR_ALT_BOXED) {
    uint32_t *offsets = MS_ARENA_NEW_ARRAY(&layouts.arena, uint32_t, shape->block.len + 1);
    (void)mir_mem_layout(shape->block, offsets);
    const MirAltFields *fields = mir_alt_fields(&layouts, alt);
    for (uint32_t index = 0; index < module->alts.ptr[alt].ncases; index++) {
      tails[index] = case_tail(module, fields, offsets, ty, alt, index);
      any = any || tails[index].some;
    }
  }
  mir_layouts_free(&layouts);
  return any;
}

/* ---- the chain loop ---- */

typedef struct ChainClone {
  uint32_t alt;
  const GlTail *tails;
  MirValue src, dst;       /* the block parameters of the loop head */
  MirBlock head, exit;
} ChainClone;

/* Clones the other fields of case `index`, makes the new block, stores it where the previous block's tail
 * leaf (or the result slot) points, and goes on with the source's tail. */
static void chain_case(MirBuilder *b, const ChainClone *chain, uint32_t index) {
  const uint32_t nfields = b->module->alts.ptr[chain->alt].cases[index].nfields;
  const GlTail *tail = &chain->tails[index];
  MirValue *fields = MIRGL_ARRAY(b->module, MirValue, nfields);
  MirValue tail_value = MIR_NONE;
  for (uint32_t field = 0; field < nfields; field++) {
    const MirValue value = mirgl_alt_get(b, chain->alt, index, field, chain->src);
    const bool is_tail = tail->some && tail->field == field;
    /* The source's tail is copied as it is; the next round replaces it. */
    tail_value = is_tail ? value : tail_value;
    fields[field] = is_tail ? value : mirgl_clone(b, value);
  }
  mirgl_put(b, chain->dst, mirgl_alt_new(b, chain->alt, index, fields, nfields));
  if (tail_value == MIR_NONE) {
    mir_b_br(b, chain->exit, NULL, 0);
    return;
  }
  const MirValue block_ptr = mirgl_load(b, chain->dst, MIR_PTR);
  MirValue next_args[2] = {tail_value, mirgl_ptr_at(b, block_ptr, tail->offset)};
  if (!tail->optional) {
    mir_b_br(b, chain->head, next_args, 2);
    return;
  }
  const MirBlock more = mir_b_new_block(b);
  const MirBlock last = mir_b_new_block(b);
  mir_b_br_if(b, mirgl_opt_is_some(b, tail_value), more, NULL, 0, last, NULL, 0);
  mir_b_switch_to(b, more);
  next_args[0] = mirgl_opt_payload(b, MOP_OptGet, tail_value);
  mir_b_br(b, chain->head, next_args, 2);
  mir_b_switch_to(b, last);
  mir_b_br(b, chain->exit, NULL, 0);
}

/* The switch over the case of the source block, one block per case and an unreachable fallback. */
static MirBlock *case_switch(MirBuilder *b, uint32_t ncases, MirValue tag) {
  MirBlock *blocks = MIRGL_ARRAY(b->module, MirBlock, ncases);
  MirCase *cases = MIRGL_ARRAY(b->module, MirCase, ncases);
  for (uint32_t index = 0; index < ncases; index++) {
    blocks[index] = mir_b_new_block(b);
  }
  const MirBlock fallback = mir_b_new_block(b);
  for (uint32_t index = 0; index < ncases; index++) {
    cases[index] = (MirCase){(int64_t)index, {blocks[index], NULL, 0}};
  }
  mir_b_switch(b, tag, cases, ncases, fallback);
  mir_b_switch_to(b, fallback);
  mir_b_unreachable(b);
  return blocks;
}

static uint32_t clone_chain(const GlCx *cx, const GlTail *tails) {
  const uint32_t alt = cx->data->id;
  const uint32_t ncases = cx->module->alts.ptr[alt].ncases;
  MirBuilder b;
  mir_b_init(&b, cx->module, cx->name, &cx->param, 1, cx->ty);
  MirValue first;
  mir_b_params(&b, &first, 1);
  ChainClone chain = {.alt = alt, .tails = tails, .head = mir_b_new_block(&b), .exit = mir_b_new_block(&b)};
  chain.src = mir_b_add_block_param(&b, chain.head, cx->ty, MM_BORROW);
  chain.dst = mir_b_add_block_param(&b, chain.head, MIR_PTR, MM_BORROW);
  const MirValue result = mirgl_slot(&b, cx->ty);
  const MirValue entry_args[2] = {first, result};
  mir_b_br(&b, chain.head, entry_args, 2);
  mir_b_switch_to(&b, chain.head);
  MirBlock *blocks = case_switch(&b, ncases, mirgl_alt_tag(&b, chain.src));
  for (uint32_t index = 0; index < ncases; index++) {
    mir_b_switch_to(&b, blocks[index]);
    chain_case(&b, &chain, index);
  }
  mir_b_switch_to(&b, chain.exit);
  mir_b_ret(&b, mirgl_take(&b, result, cx->ty));
  return mirgl_finish(&b);
}

/* ---- the plain clone ---- */

static uint32_t clone_cases(const GlCx *cx) {
  const uint32_t alt = cx->data->id;
  const MirAltDef *def = &cx->module->alts.ptr[alt];
  MirBuilder b;
  mir_b_init(&b, cx->module, cx->name, &cx->param, 1, cx->ty);
  MirValue value;
  mir_b_params(&b, &value, 1);
  MirBlock *blocks = case_switch(&b, def->ncases, mirgl_alt_tag(&b, value));
  for (uint32_t index = 0; index < def->ncases; index++) {
    mir_b_switch_to(&b, blocks[index]);
    const uint32_t nfields = def->cases[index].nfields;
    MirValue *fields = MIRGL_ARRAY(cx->module, MirValue, nfields);
    for (uint32_t field = 0; field < nfields; field++) {
      fields[field] = mirgl_clone(&b, mirgl_alt_get(&b, alt, index, field, value));
    }
    mir_b_ret(&b, mirgl_alt_new(&b, alt, index, fields, nfields));
  }
  return mirgl_finish(&b);
}

uint32_t mirgl_clone_alt(const GlCx *cx) {
  const uint32_t ncases = cx->module->alts.ptr[cx->data->id].ncases;
  GlTail *tails = MIRGL_ARRAY(cx->module, GlTail, ncases);
  if (boxed_chain(cx->module, cx->ty, cx->data->id, tails)) {
    return clone_chain(cx, tails);
  }
  return clone_cases(cx);
}
