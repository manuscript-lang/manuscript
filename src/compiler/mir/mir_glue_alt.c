/* compiler/mir/mir_glue_alt.c: the drop function of an alternative. A boxed alternative that holds itself
 * again as the last such field of a case (`Cons(head, tail)`) is released by a loop, so the length of a chain
 * cannot overflow the stack. */
#include "compiler/mir/mir_glue_internal.h"

/* What the drop of one alternative does, per case. */
typedef struct AltDrop {
  uint32_t alt;
  MirTy ty;
  bool boxed;
  bool looped;       /* some case ends a chain */
  bool *owns;        /* by case: a drop releases fields (some owned field needs a drop) */
  GlTail *tails;     /* by case */
  MirValue value;    /* the alternative being released: the parameter, or the loop's block parameter */
  MirBlock loop_head;
  MirBlock done;
} AltDrop;

/* The field of case `def` that holds the same boxed alternative again, as the last such field. */
static GlTail drop_tail(const MirModule *module, bool boxed, MirTy ty, const MirCaseDef *def) {
  if (!boxed) {
    return (GlTail){0};
  }
  for (uint32_t field = def->nfields; field-- > 0;) {
    MirTy inner = MIR_NONE;
    const bool optional = mirgl_is_opt(module, def->fields[field].ty, &inner);
    if (field >= MIRGL_MAX_CHAIN_FIELD) {
      continue;
    }
    if (def->fields[field].ty == ty) {
      return (GlTail){.some = true, .field = field};
    }
    if (optional && inner == ty) {
      return (GlTail){.some = true, .field = field, .optional = true};
    }
  }
  return (GlTail){0};
}

static void plan_alt(const MirModule *module, AltDrop *drop) {
  const MirAltDef *def = &module->alts.ptr[drop->alt];
  for (uint32_t index = 0; index < def->ncases; index++) {
    bool any = false;
    for (uint32_t field = 0; field < def->cases[index].nfields && !any; field++) {
      any = mir_needs_drop(module, def->cases[index].fields[field].ty);
    }
    drop->owns[index] = !mir_owns(def->borrowed, index) && any;
    drop->tails[index] = drop_tail(module, drop->boxed, drop->ty, &def->cases[index]);
    drop->looped = drop->looped || drop->tails[index].some;
  }
}

/* The arm of a case that ends a chain link: the next block of the chain is read before this one is released
 * (the release leaves the tail field alone), then the loop goes on with it. */
static void chain_arm(MirBuilder *b, const AltDrop *drop, uint32_t index) {
  const GlTail *tail = &drop->tails[index];
  const MirValue next_block = mirgl_alt_get(b, drop->alt, index, tail->field, drop->value);
  mirgl_alt_release(b, drop->alt, index, 1u << tail->field, drop->value);
  if (!tail->optional) {
    mir_b_br(b, drop->loop_head, &next_block, 1);
    return;
  }
  const MirBlock more = mir_b_new_block(b);
  const MirBlock last = mir_b_new_block(b);
  mir_b_br_if(b, mirgl_opt_is_some(b, next_block), more, NULL, 0, last, NULL, 0);
  mir_b_switch_to(b, more);
  const MirValue next = mirgl_opt_payload(b, MOP_OptGet, next_block);
  mir_b_br(b, drop->loop_head, &next, 1);
  mir_b_switch_to(b, last);
  mir_b_br(b, drop->done, NULL, 0);
}

/* The arm of a case that is not a chain link: every field marked moved when the case owns nothing, so the
 * release only frees the block. */
static void release_arm(MirBuilder *b, const AltDrop *drop, uint32_t index) {
  const uint32_t nfields = b->module->alts.ptr[drop->alt].cases[index].nfields;
  uint32_t mask = 0;
  if (!drop->owns[index]) {
    mask = nfields >= 32 ? UINT32_MAX : (1u << nfields) - 1;
  }
  mirgl_alt_release(b, drop->alt, index, mask, drop->value);
  mir_b_br(b, drop->done, NULL, 0);
}

/* The cases that need code: payloadless cases of a boxed alternative share a static block that is never
 * freed, and a case that owns nothing needs none unless it holds a block to free. Returns the count. */
static uint32_t arm_cases(const MirModule *module, const AltDrop *drop, uint32_t *arms) {
  const MirAltDef *def = &module->alts.ptr[drop->alt];
  uint32_t count = 0;
  for (uint32_t index = 0; index < def->ncases; index++) {
    if (def->cases[index].nfields != 0 && (drop->boxed || drop->owns[index])) {
      arms[count++] = index;
    }
  }
  return count;
}

static void emit_arms(MirBuilder *b, const AltDrop *drop, const uint32_t *arms, uint32_t narms) {
  MirModule *module = b->module;
  MirBlock *blocks = MIRGL_ARRAY(module, MirBlock, narms);
  MirCase *cases = MIRGL_ARRAY(module, MirCase, narms);
  for (uint32_t index = 0; index < narms; index++) {
    blocks[index] = mir_b_new_block(b);
    cases[index] = (MirCase){(int64_t)arms[index], {blocks[index], NULL, 0}};
  }
  mir_b_switch(b, mirgl_alt_tag(b, drop->value), cases, narms, drop->done);
  for (uint32_t index = 0; index < narms; index++) {
    mir_b_switch_to(b, blocks[index]);
    if (drop->tails[arms[index]].some) {
      chain_arm(b, drop, arms[index]);
    } else {
      release_arm(b, drop, arms[index]);
    }
  }
}

uint32_t mirgl_drop_alt(const GlCx *cx) {
  MirModule *module = cx->module;
  const uint32_t ncases = module->alts.ptr[cx->data->id].ncases;
  AltDrop drop = {.alt = cx->data->id,
                  .ty = cx->ty,
                  .boxed = mirgl_alt_boxed(module, cx->data->id),
                  .owns = MIRGL_ARRAY(module, bool, ncases),
                  .tails = MIRGL_ARRAY(module, GlTail, ncases),
                  .loop_head = MIR_NONE};
  plan_alt(module, &drop);
  MirBuilder b;
  mir_b_init(&b, module, cx->name, &cx->param, 1, MIR_VOID);
  MirValue first;
  mir_b_params(&b, &first, 1);
  drop.done = mir_b_new_block(&b);
  drop.value = first;
  if (drop.looped) {
    drop.loop_head = mir_b_new_block(&b);
    drop.value = mir_b_add_block_param(&b, drop.loop_head, cx->ty, MM_MOVE);
    mir_b_br(&b, drop.loop_head, &first, 1);
    mir_b_switch_to(&b, drop.loop_head);
  }
  uint32_t *arms = MIRGL_ARRAY(module, uint32_t, ncases);
  const uint32_t narms = arm_cases(module, &drop, arms);
  if (narms == 0) {
    mir_b_ret(&b, MIR_NONE);
    return mirgl_finish(&b);
  }
  emit_arms(&b, &drop, arms, narms);
  mir_b_switch_to(&b, drop.done);
  mir_b_ret(&b, MIR_NONE);
  return mirgl_finish(&b);
}
