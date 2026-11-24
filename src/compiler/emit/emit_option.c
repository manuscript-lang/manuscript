/* Owns alternatives and optionals; the layout is the one the runtime uses. */
#include "compiler/emit/emit_cx.h"

#include "abi/layout.h"
#include "base/alloc.h"

static MirTy value_type(const EmitCx *cx, MirValue value) {
  return cx->func->values.ptr[value];
}

/* The word a string's second leaf holds for none: the static tag, no length. */
#define NONE_STRING_WORD ((uint64_t)MS_STRING_TAG_STATIC << MS_STRING_TAG_SHIFT)

/* `alt.new`, `alt.view` of an alternative held as leaves: the case index, the payload leaves in their slots,
 * zeros elsewhere. */
static void alt_inline(EmitCx *cx, const MirInst *inst, const MirAltFields *fields) {
  uint32_t case_index = inst->imm.b;
  MsSpan leaves = emit_value_leaves(cx, inst->res);
  ms_strbuild_printf(cx->out, "  %%v%u = add i64 %u, 0\n", inst->res, case_index);
  /* A payload that comes whole from one held operand, in order, moves as a block. */
  uint32_t run_first = 0;
  uint32_t run_end = 0;
  uint32_t run_operand = 0;
  uint32_t run_source = 0;
  for (uint32_t leaf = 1; leaf < leaves.len; leaf++) {
    uint32_t operand = 0;
    uint32_t source = 0;
    if (!mir_alt_slot_source(fields, case_index, leaf, &operand, &source)) {
      continue;
    }
    if (run_end == leaf && operand == run_operand && source == run_source + (leaf - run_first)) {
      run_end++;
    } else if (run_end == 0 || run_end - run_first < 2) {
      run_first = leaf;
      run_end = leaf + 1;
      run_operand = operand;
      run_source = source;
    }
  }
  if (run_end - run_first < 2 ||
      !emit_wide_move_leaves(cx, inst->res, run_first, inst->args[run_operand], run_source, run_end - run_first)) {
    run_first = run_end = 0;
  }
  for (uint32_t leaf = 1; leaf < leaves.len; leaf++) {
    uint32_t operand = 0;
    uint32_t source = 0;
    if (leaf >= run_first && leaf < run_end) {
      continue;
    }
    if (mir_alt_slot_source(fields, case_index, leaf, &operand, &source)) {
      emit_copy_leaf(cx, inst->res, leaf, inst->args[operand], source);
    } else {
      emit_zero_leaf(cx, inst->res, leaf, leaves.ptr[leaf]);
    }
  }
}

/* The shared unit block of a case without payload: the address of its data symbol. */
static bool alt_unit(EmitCx *cx, const MirInst *inst) {
  uint32_t symbol = cx->data == NULL ? MIR_NONE : mir_data_unit(cx->data, inst->imm.a, inst->imm.b);
  if (symbol == MIR_NONE) {
    cx->why = "alt.new without a unit block";
    return false;
  }
  ms_strbuild_printf(cx->out, "  %%v%u = ptrtoint ptr ", inst->res);
  emit_symbol(cx->out, cx->data->syms.ptr[symbol].name);
  ms_strbuild_append_text(cx->out, " to i64\n");
  return true;
}

/* The byte offsets of the slots of the block of a boxed alternative, in a buffer the caller frees. */
static uint32_t *block_offsets(const MirShape *shape) {
  uint32_t *offsets = ms_alloc_zeroed(((size_t)shape->block.len + 1) * sizeof *offsets);
  (void)mir_mem_layout(shape->block, offsets);
  return offsets;
}

/* `alt.new`, `alt.view` of a boxed alternative: the shared unit block of a case without payload, else a fresh
 * block holding the case index and the payload. */
static bool alt_block(EmitCx *cx, const MirInst *inst, const MirAltFields *fields, const MirShape *shape) {
  uint32_t case_index = inst->imm.b;
  if (fields->case_start[case_index + 1] == fields->case_start[case_index]) {
    return alt_unit(cx, inst);
  }
  uint32_t *offsets = block_offsets(shape);
  ms_strbuild_printf(cx->out, "  %%v%u = call i64 @msrt_alloc(i64 %u)\n", inst->res,
                     mir_mem_layout(shape->block, NULL).size);
  char base[24];
  emit_pointer(cx, inst->res, base, sizeof base);
  ms_strbuild_printf(cx->out, "  store i64 %u, ptr %s\n", case_index, emit_address(cx, base, offsets[0]).text);
  uint32_t first = fields->case_start[case_index];
  for (uint32_t field = first; field < fields->case_start[case_index + 1]; field++) {
    for (uint32_t leaf = 0; leaf < fields->fields[field].nleaves; leaf++) {
      uint32_t slot = fields->fields[field].leaves[leaf];
      emit_store_leaf(cx, shape->block.ptr[slot], inst->args[field - first], leaf,
                      emit_address(cx, base, offsets[slot]));
    }
  }
  ms_free(offsets);
  return true;
}

static bool alt_new(EmitCx *cx, const MirInst *inst) {
  const MirShape *shape = mir_shape(cx->layouts, value_type(cx, inst->res));
  const MirAltFields *fields = mir_alt_fields(cx->layouts, inst->imm.a);
  if (shape->alt == MIR_ALT_BOXED) {
    return alt_block(cx, inst, fields, shape);
  }
  alt_inline(cx, inst, fields);
  return true;
}

/* `alt.get`, `alt.take`: the leaves of one payload field, from the registers or from the block. */
static void alt_get(EmitCx *cx, const MirInst *inst) {
  const MirShape *shape = mir_shape(cx->layouts, value_type(cx, inst->args[0]));
  const MirAltFields *fields = mir_alt_fields(cx->layouts, inst->imm.a);
  const MirAltField *field = &fields->fields[fields->case_start[inst->imm.b] + inst->imm.c];
  if (shape->alt != MIR_ALT_BOXED) {
    bool contiguous = field->nleaves >= 2;
    for (uint32_t leaf = 1; leaf < field->nleaves; leaf++) {
      contiguous = contiguous && field->leaves[leaf] == field->leaves[0] + leaf;
    }
    if (contiguous && emit_wide_move_leaves(cx, inst->res, 0, inst->args[0], field->leaves[0], field->nleaves)) {
      return;
    }
    for (uint32_t leaf = 0; leaf < field->nleaves; leaf++) {
      emit_copy_leaf(cx, inst->res, leaf, inst->args[0], field->leaves[leaf]);
    }
    return;
  }
  uint32_t *offsets = block_offsets(shape);
  char base[24];
  emit_pointer(cx, inst->args[0], base, sizeof base);
  for (uint32_t leaf = 0; leaf < field->nleaves; leaf++) {
    uint32_t slot = field->leaves[leaf];
    emit_load_leaf(cx, shape->block.ptr[slot], inst->res, leaf, emit_address(cx, base, offsets[slot]));
  }
  ms_free(offsets);
}

/* `alt.tag`: leaf 0, or the first word of the block a boxed alternative points to. */
static void alt_tag(EmitCx *cx, const MirInst *inst) {
  if (mir_shape(cx->layouts, value_type(cx, inst->args[0]))->alt != MIR_ALT_BOXED) {
    emit_copy_leaf(cx, inst->res, 0, inst->args[0], 0);
    return;
  }
  char base[24];
  emit_pointer(cx, inst->args[0], base, sizeof base);
  ms_strbuild_printf(cx->out, "  %%v%u = load i64, ptr %s\n", inst->res, base);
}

/* `alt.plain`: the same leaves under the plain alternative type. */
static void alt_plain(EmitCx *cx, const MirInst *inst) {
  uint32_t count = (uint32_t)emit_value_leaves(cx, inst->res).len;
  if (emit_wide_move_leaves(cx, inst->res, 0, inst->args[0], 0, count)) {
    return;
  }
  for (uint32_t leaf = 0; leaf < count; leaf++) {
    emit_copy_leaf(cx, inst->res, leaf, inst->args[0], leaf);
  }
}

/* `opt.none`: absent is all zero, except that a string's second word keeps the static tag. */
static void opt_none(EmitCx *cx, const MirInst *inst) {
  MsSpan leaves = emit_value_leaves(cx, inst->res);
  if (mir_is_str_like(cx->layouts, value_type(cx, inst->res))) {
    ms_strbuild_printf(cx->out, "  %%v%u = add i64 0, 0\n  %%v%u.1 = add i64 %lld, 0\n", inst->res, inst->res,
                       (long long)NONE_STRING_WORD);
    return;
  }
  for (uint32_t leaf = 0; leaf < leaves.len; leaf++) {
    emit_zero_leaf(cx, inst->res, leaf, leaves.ptr[leaf]);
  }
}

/* `opt.is_some`: the flag leaf of an optional held as [flag, value], or a non-null test of one held as a single
 * nullable pointer. */
static void opt_is_some(EmitCx *cx, const MirInst *inst) {
  MirValue source = inst->args[0];
  MsSpan leaves = emit_value_leaves(cx, source);
  if (mir_is_str_like(cx->layouts, value_type(cx, source))) {
    /* A `String?` is its two string words; none is (0, the static tag). */
    uint32_t number = cx->next++;
    ms_strbuild_printf(cx->out,
                       "  %%t%u = xor i64 %%v%u.1, %lld\n  %%o%u = or i64 %%v%u, %%t%u\n"
                       "  %%v%u = icmp ne i64 %%o%u, 0\n",
                       number, source, (long long)NONE_STRING_WORD, number, source, number, inst->res, number);
  } else if (leaves.len == 1 && leaves.ptr[0] == MIR_LEAF_I64) {
    ms_strbuild_printf(cx->out, "  %%v%u = icmp ne i64 %%v%u, 0\n", inst->res, source);
  } else {
    emit_copy_leaf(cx, inst->res, 0, source, 0);
  }
}

/* `opt.some`, `opt.view` (the same leaves; the view borrows its payload): a boxed optional is a pointer to a heap
 * copy of the payload, a nullable one is the payload itself, any other is the payload after a presence flag. */
static void opt_some(EmitCx *cx, const MirInst *inst) {
  MirTy inner = mir_ty_data(cx->module, value_type(cx, inst->res))->elem;
  if (mir_layouts_opt_boxed(cx->layouts, inner)) {
    MsSpan leaves = emit_leaves(cx, inner);
    uint32_t size = mir_mem_layout(leaves, NULL).size;
    ms_strbuild_printf(cx->out, "  %%v%u = call i64 @msrt_alloc(i64 %u)\n", inst->res, size > 0 ? size : 1);
    char base[24];
    emit_pointer(cx, inst->res, base, sizeof base);
    if (leaves.len != 0) {
      emit_store_value(cx, inst->args[0], base);
    }
    return;
  }
  uint32_t at = 0;
  if (mir_opt_has_flag(cx->layouts, value_type(cx, inst->res))) {
    ms_strbuild_printf(cx->out, "  %%v%u = or i1 false, true\n", inst->res);
    at = 1;
  }
  uint32_t count = (uint32_t)emit_value_leaves(cx, inst->args[0]).len;
  if (emit_wide_move_leaves(cx, inst->res, at, inst->args[0], 0, count)) {
    return;
  }
  for (uint32_t leaf = 0; leaf < count; leaf++) {
    emit_copy_leaf(cx, inst->res, at + leaf, inst->args[0], leaf);
  }
}

/* `opt.get`: the payload of an optional known to hold one. */
static void opt_get(EmitCx *cx, const MirInst *inst) {
  MirTy inner = mir_ty_data(cx->module, value_type(cx, inst->args[0]))->elem;
  if (mir_layouts_opt_boxed(cx->layouts, inner)) {
    char base[24];
    emit_pointer(cx, inst->args[0], base, sizeof base);
    emit_load_value(cx, inst->res, base);
    return;
  }
  uint32_t skip = mir_opt_has_flag(cx->layouts, value_type(cx, inst->args[0])) ? 1 : 0;
  uint32_t count = (uint32_t)emit_value_leaves(cx, inst->res).len;
  if (emit_wide_move_leaves(cx, inst->res, 0, inst->args[0], skip, count)) {
    return;
  }
  for (uint32_t leaf = 0; leaf < count; leaf++) {
    emit_copy_leaf(cx, inst->res, leaf, inst->args[0], skip + leaf);
  }
}

bool emit_option_op(EmitCx *cx, const MirInst *inst, const EmitSite *site, bool *handled) {
  (void)site;
  *handled = true;
  switch ((MirOp)inst->op) {
  case MOP_AltNew:
  case MOP_AltView:
    return alt_new(cx, inst);
  case MOP_AltGet:
  case MOP_AltTake:
    alt_get(cx, inst);
    return true;
  case MOP_AltTag:
    alt_tag(cx, inst);
    return true;
  case MOP_AltPlain:
    alt_plain(cx, inst);
    return true;
  case MOP_OptNone:
    opt_none(cx, inst);
    return true;
  case MOP_OptIsSome:
    opt_is_some(cx, inst);
    return true;
  case MOP_OptSome:
  case MOP_OptView:
    opt_some(cx, inst);
    return true;
  case MOP_OptGet:
    opt_get(cx, inst);
    return true;
  default:
    *handled = false;
    return true;
  }
}
