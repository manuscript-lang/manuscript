/* Owns alternatives and optionals; the layout is the one the runtime uses. */
#include "compiler/emit_cl/cl_cx.h"

#include "abi/layout.h"
#include "base/alloc.h"

/* The word a string's second leaf holds for none: the static tag, no length. */
#define NONE_STRING_WORD ((uint64_t)MS_STRING_TAG_STATIC << MS_STRING_TAG_SHIFT)

static MirTy value_type(const ClCx *cx, MirValue value) {
  return cx->func->values.ptr[value];
}

/* The integer `k` in the register type of `leaf`. */
static ms_cl_val leaf_const(ClCx *cx, MirLeaf leaf, int64_t k) {
  const ms_cl_type type = cl_reg_type(leaf);
  return type == MS_CL_I8 ? ms_cl_iconst(cx->fb, MS_CL_I8, k) : cl_const(cx, k);
}

/* `alt.new`, `alt.view` of an alternative held as leaves: the case index, the payload leaves in their slots, zeros
 * elsewhere. */
static void alt_inline(ClCx *cx, const MirInst *inst, const MirAltFields *fields) {
  const uint32_t case_index = inst->imm.b;
  const MsSpan leaves = cl_value_leaves(cx, inst->res);
  cl_set(cx, inst->res, 0, leaf_const(cx, (MirLeaf)leaves.ptr[0], case_index));
  for (uint32_t leaf = 1; leaf < leaves.len; leaf++) {
    uint32_t operand = 0;
    uint32_t source = 0;
    if (mir_alt_slot_source(fields, case_index, leaf, &operand, &source)) {
      cl_copy_leaf(cx, inst->res, leaf, inst->args[operand], source);
    } else {
      cl_zero_leaf(cx, inst->res, leaf, (MirLeaf)leaves.ptr[leaf]);
    }
  }
}

/* The shared unit block of a case without payload: the address of its data symbol. */
static bool alt_unit(ClCx *cx, const MirInst *inst) {
  const uint32_t symbol = cx->mod->data == NULL ? MIR_NONE : mir_data_unit(cx->mod->data, inst->imm.a, inst->imm.b);
  if (symbol == MIR_NONE) {
    cx->why = "alt.new without a unit block";
    return false;
  }
  cl_set(cx, inst->res, 0, ms_cl_data_addr(cx->fb, cx->mod->syms[symbol]));
  return true;
}

static uint32_t *block_offsets(const MirShape *shape) {
  uint32_t *offsets = ms_alloc_zeroed(((size_t)shape->block.len + 1) * sizeof *offsets);
  (void)mir_mem_layout(shape->block, offsets);
  return offsets;
}

/* `alt.new`, `alt.view` of a boxed alternative: the shared unit block of a case without payload, else a fresh block
 * holding the case index and the payload. */
static bool alt_block(ClCx *cx, const MirInst *inst, const MirAltFields *fields, const MirShape *shape) {
  const uint32_t case_index = inst->imm.b;
  if (fields->case_start[case_index + 1] == fields->case_start[case_index]) {
    return alt_unit(cx, inst);
  }
  uint32_t *offsets = block_offsets(shape);
  const ms_cl_val base = cl_alloc(cx, mir_mem_layout(shape->block, NULL).size);
  cl_set(cx, inst->res, 0, base);
  ms_cl_store(cx->fb, MS_CL_NOTRAP, cl_const(cx, case_index), base, (int32_t)offsets[0]);
  const uint32_t first = fields->case_start[case_index];
  for (uint32_t field = first; field < fields->case_start[case_index + 1]; field++) {
    for (uint32_t leaf = 0; leaf < fields->fields[field].nleaves; leaf++) {
      const uint32_t slot = fields->fields[field].leaves[leaf];
      cl_store_leaf(cx, (MirLeaf)shape->block.ptr[slot], inst->args[field - first], leaf, base, (int32_t)offsets[slot]);
    }
  }
  ms_free(offsets);
  return true;
}

static bool alt_new(ClCx *cx, const MirInst *inst) {
  const MirShape *shape = mir_shape(cx->layouts, value_type(cx, inst->res));
  const MirAltFields *fields = mir_alt_fields(cx->layouts, inst->imm.a);
  if (shape->alt == MIR_ALT_BOXED) {
    return alt_block(cx, inst, fields, shape);
  }
  alt_inline(cx, inst, fields);
  return true;
}

/* `alt.get`, `alt.take`: the leaves of one payload field, from the registers or from the block. */
static void alt_get(ClCx *cx, const MirInst *inst) {
  const MirShape *shape = mir_shape(cx->layouts, value_type(cx, inst->args[0]));
  const MirAltFields *fields = mir_alt_fields(cx->layouts, inst->imm.a);
  const MirAltField *field = &fields->fields[fields->case_start[inst->imm.b] + inst->imm.c];
  if (shape->alt != MIR_ALT_BOXED) {
    for (uint32_t leaf = 0; leaf < field->nleaves; leaf++) {
      cl_copy_leaf(cx, inst->res, leaf, inst->args[0], field->leaves[leaf]);
    }
    return;
  }
  uint32_t *offsets = block_offsets(shape);
  const ms_cl_val base = cl_arg(cx, inst, 0);
  for (uint32_t leaf = 0; leaf < field->nleaves; leaf++) {
    const uint32_t slot = field->leaves[leaf];
    cl_load_leaf(cx, (MirLeaf)shape->block.ptr[slot], inst->res, leaf, base, (int32_t)offsets[slot]);
  }
  ms_free(offsets);
}

/* `alt.tag`: leaf 0, or the first word of the block a boxed alternative points to. */
static void alt_tag(ClCx *cx, const MirInst *inst) {
  if (mir_shape(cx->layouts, value_type(cx, inst->args[0]))->alt != MIR_ALT_BOXED) {
    cl_copy_leaf(cx, inst->res, 0, inst->args[0], 0);
    return;
  }
  cl_set(cx, inst->res, 0, ms_cl_load(cx->fb, MS_CL_I64, MS_CL_NOTRAP, cl_arg(cx, inst, 0), 0));
}

/* `alt.plain` and `alt.borrow` between alternatives of a different number of cases: the same payload leaves, the tag
 * rewritten. A borrowing variant of a Result has a borrowed `error` as case 2: `alt.plain` folds case 2 into case 1
 * (tag != 0), `alt.borrow` moves case 1 to case 2 (tag * 2). */
static void alt_retag(ClCx *cx, const MirInst *inst, bool to_variant) {
  ms_cl_fn *f = cx->fb;
  const MsSpan from = cl_value_leaves(cx, inst->args[0]);
  const MsSpan to = cl_value_leaves(cx, inst->res);
  ms_cl_val tag = cl_get(cx, inst->args[0], 0);
  if (cl_reg_type((MirLeaf)from.ptr[0]) == MS_CL_I8) {
    tag = ms_cl_cast(f, MS_CL_UEXTEND, MS_CL_I64, tag);
  }
  ms_cl_val moved = to_variant ? ms_cl_ishl(f, tag, cl_const(cx, 1))
                               : ms_cl_cast(f, MS_CL_UEXTEND, MS_CL_I64, ms_cl_icmp(f, MS_CL_NE, tag, cl_const(cx, 0)));
  if (cl_reg_type((MirLeaf)to.ptr[0]) == MS_CL_I8) {
    moved = ms_cl_cast(f, MS_CL_IREDUCE, MS_CL_I8, moved);
  }
  cl_set(cx, inst->res, 0, moved);
  for (uint32_t leaf = 1; leaf < to.len; leaf++) {
    cl_copy_leaf(cx, inst->res, leaf, inst->args[0], leaf);
  }
}

/* `alt.plain` of an alternative with no borrowed `error` case keeps its tag. */
static void alt_plain(ClCx *cx, const MirInst *inst) {
  const MirTyData *from = mir_ty_data(cx->module, value_type(cx, inst->args[0]));
  const MirTyData *to = mir_ty_data(cx->module, value_type(cx, inst->res));
  if (from->kind == MK_ALT && to->kind == MK_ALT &&
      cx->module->alts.ptr[from->id].ncases != cx->module->alts.ptr[to->id].ncases) {
    alt_retag(cx, inst, false);
    return;
  }
  const uint32_t count = (uint32_t)cl_value_leaves(cx, inst->res).len;
  for (uint32_t leaf = 0; leaf < count; leaf++) {
    cl_copy_leaf(cx, inst->res, leaf, inst->args[0], leaf);
  }
}

/* `opt.none`: absent is all zero, except that a string's second word keeps the static tag. */
static void opt_none(ClCx *cx, const MirInst *inst) {
  const MsSpan leaves = cl_value_leaves(cx, inst->res);
  for (uint32_t leaf = 0; leaf < leaves.len; leaf++) {
    cl_zero_leaf(cx, inst->res, leaf, (MirLeaf)leaves.ptr[leaf]);
  }
  if (mir_is_str_like(cx->layouts, value_type(cx, inst->res))) {
    cl_set(cx, inst->res, 1, cl_const(cx, (int64_t)NONE_STRING_WORD));
  }
}

/* `opt.is_some`: the flag leaf of an optional held as [flag, value], or a non-null test of one held as a single
 * nullable pointer; a `String?` is none when it is (0, the static tag). */
static void opt_is_some(ClCx *cx, const MirInst *inst) {
  ms_cl_fn *f = cx->fb;
  const MirValue source = inst->args[0];
  const MsSpan leaves = cl_value_leaves(cx, source);
  if (mir_is_str_like(cx->layouts, value_type(cx, source))) {
    ms_cl_val tag = ms_cl_bxor(f, cl_get(cx, source, 1), cl_const(cx, (int64_t)NONE_STRING_WORD));
    cl_set(cx, inst->res, 0, ms_cl_icmp(f, MS_CL_NE, ms_cl_bor(f, cl_get(cx, source, 0), tag), cl_const(cx, 0)));
  } else if (leaves.len == 1 && leaves.ptr[0] == MIR_LEAF_I64) {
    cl_set(cx, inst->res, 0, ms_cl_icmp(f, MS_CL_NE, cl_get(cx, source, 0), cl_const(cx, 0)));
  } else {
    cl_copy_leaf(cx, inst->res, 0, source, 0);
  }
}

/* `opt.some`, `opt.view` (the same leaves; the view borrows its payload): a boxed optional is a pointer to a heap copy
 * of the payload, a nullable one is the payload itself, any other is the payload after a presence flag. */
static void opt_some(ClCx *cx, const MirInst *inst) {
  const MirTy inner = mir_ty_data(cx->module, value_type(cx, inst->res))->elem;
  if (mir_layouts_opt_boxed(cx->layouts, inner)) {
    const MsSpan leaves = cl_leaves(cx, inner);
    const ms_cl_val base = cl_alloc(cx, mir_mem_layout(leaves, NULL).size);
    cl_set(cx, inst->res, 0, base);
    if (leaves.len != 0) {
      cl_leaves_at(cx, inst->args[0], base, false);
    }
    return;
  }
  uint32_t at = 0;
  if (mir_opt_has_flag(cx->layouts, value_type(cx, inst->res))) {
    cl_set(cx, inst->res, 0, ms_cl_iconst(cx->fb, MS_CL_I8, 1));
    at = 1;
  }
  const uint32_t count = (uint32_t)cl_value_leaves(cx, inst->args[0]).len;
  for (uint32_t leaf = 0; leaf < count; leaf++) {
    cl_copy_leaf(cx, inst->res, at + leaf, inst->args[0], leaf);
  }
}

/* `opt.get`: the payload of an optional known to hold one. */
static void opt_get(ClCx *cx, const MirInst *inst) {
  const MirTy inner = mir_ty_data(cx->module, value_type(cx, inst->args[0]))->elem;
  if (mir_layouts_opt_boxed(cx->layouts, inner)) {
    cl_leaves_at(cx, inst->res, cl_arg(cx, inst, 0), true);
    return;
  }
  const uint32_t skip = mir_opt_has_flag(cx->layouts, value_type(cx, inst->args[0])) ? 1 : 0;
  const uint32_t count = (uint32_t)cl_value_leaves(cx, inst->res).len;
  for (uint32_t leaf = 0; leaf < count; leaf++) {
    cl_copy_leaf(cx, inst->res, leaf, inst->args[0], skip + leaf);
  }
}

bool cl_option_op(ClCx *cx, const MirInst *inst, bool *handled) {
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
  case MOP_AltBorrow:
    alt_retag(cx, inst, true);
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
