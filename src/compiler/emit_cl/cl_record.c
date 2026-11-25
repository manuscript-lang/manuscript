/* Owns records: inline records as runs of leaves, and records behind a pointer as heap blocks laid out the way the
 * runtime lays them. A map or set field of such a block holds the address of a header block, null while the
 * collection is empty; reading, building and freeing it branch. */
#include "compiler/emit_cl/cl_cx.h"

static MirTy value_type(const ClCx *cx, MirValue value) {
  return cx->func->values.ptr[value];
}

ms_cl_val cl_alloc(ClCx *cx, uint32_t bytes) {
  const ms_cl_func alloc = cl_runtime_func(cx->mod, "msrt_alloc", 1, true);
  return ms_cl_call1(cx->fb, alloc, (ms_cl_val[]){cl_const(cx, bytes > 0 ? bytes : 1)}, 1);
}

static bool is_indirect_record(const ClCx *cx, MirTy type) {
  const MirTyData *data = mir_ty_data(cx->module, type);
  return data->kind == MK_TYPE && cx->module->type_defs.ptr[data->id].indirect;
}

/* ---- inline records ---- */

/* The leaf range `[start, start + count)` that field `field` of record type `type` occupies. */
static void field_span(ClCx *cx, MirTy type, uint32_t field, uint32_t *start, uint32_t *count) {
  const MirTypeDef *def = &cx->module->type_defs.ptr[mir_ty_data(cx->module, type)->id];
  *start = 0;
  for (uint32_t earlier = 0; earlier < field; earlier++) {
    *start += (uint32_t)cl_leaves(cx, def->fields[earlier].ty).len;
  }
  *count = (uint32_t)cl_leaves(cx, def->fields[field].ty).len;
}

static void record_new(ClCx *cx, const MirInst *inst) {
  uint32_t at = 0;
  for (uint32_t arg = 0; arg < inst->nargs; arg++) {
    const uint32_t count = (uint32_t)cl_value_leaves(cx, inst->args[arg]).len;
    for (uint32_t leaf = 0; leaf < count; leaf++) {
      cl_copy_leaf(cx, inst->res, at++, inst->args[arg], leaf);
    }
  }
}

static void record_get(ClCx *cx, const MirInst *inst) {
  uint32_t start = 0;
  uint32_t count = 0;
  field_span(cx, value_type(cx, inst->args[0]), inst->imm.b, &start, &count);
  for (uint32_t leaf = 0; leaf < count; leaf++) {
    cl_copy_leaf(cx, inst->res, leaf, inst->args[0], start + leaf);
  }
}

static void record_set(ClCx *cx, const MirInst *inst) {
  const uint32_t total = (uint32_t)cl_value_leaves(cx, inst->args[0]).len;
  uint32_t start = 0;
  uint32_t count = 0;
  field_span(cx, value_type(cx, inst->args[0]), inst->imm.b, &start, &count);
  for (uint32_t leaf = 0; leaf < total; leaf++) {
    if (leaf >= start && leaf < start + count) {
      cl_copy_leaf(cx, inst->res, leaf, inst->args[1], leaf - start);
    } else {
      cl_copy_leaf(cx, inst->res, leaf, inst->args[0], leaf);
    }
  }
}

/* ---- records behind a pointer ---- */

static int32_t at(uint32_t offset) {
  return (int32_t)offset;
}

static void store_field(ClCx *cx, const MirRecordBlock *block, ms_cl_val base, uint32_t field, MirValue value) {
  const uint32_t count = (uint32_t)cl_value_leaves(cx, value).len;
  for (uint32_t leaf = 0; leaf < count; leaf++) {
    const uint32_t slot = block->starts[field] + leaf;
    cl_store_leaf(cx, (MirLeaf)block->leaves.ptr[slot], value, leaf, base, at(block->offsets[slot]));
  }
}

/* The header block of a map or set value: null when its first and last words are zero (the empty collection), else a
 * fresh block holding the words. */
static ms_cl_val header_store(ClCx *cx, MirValue value) {
  ms_cl_fn *f = cx->fb;
  ms_cl_val either = ms_cl_bor(f, cl_get(cx, value, 0), cl_get(cx, value, MIR_MAP_WORDS - 1));
  const ClIf branch = cl_if_begin(cx, ms_cl_icmp(f, MS_CL_NE, either, cl_const(cx, 0)), 1);
  ms_cl_val header = cl_alloc(cx, MIR_MAP_WORDS * 8);
  for (uint32_t word = 0; word < MIR_MAP_WORDS; word++) {
    ms_cl_store(f, MS_CL_NOTRAP, cl_get(cx, value, word), header, at(word * 8));
  }
  ms_cl_val joined[CL_IF_WORDS];
  cl_if_end(cx, &branch, &header, joined);
  return joined[0];
}

static void indirect_new(ClCx *cx, const MirInst *inst) {
  const MirRecordBlock block = mir_record_block(cx->layouts, mir_ty_data(cx->module, value_type(cx, inst->res))->id);
  const ms_cl_val base = cl_alloc(cx, block.size);
  cl_set(cx, inst->res, 0, base);
  for (uint32_t field = 0; field < inst->nargs; field++) {
    if (!block.boxed[field]) {
      store_field(cx, &block, base, field, inst->args[field]);
      continue;
    }
    ms_cl_store(cx->fb, MS_CL_NOTRAP, header_store(cx, inst->args[field]), base,
                at(block.offsets[block.starts[field]]));
  }
}

/* `type.get` of a collection field: read through its header, or all zero when that is null. */
static void indirect_get_collection(ClCx *cx, const MirInst *inst, const MirRecordBlock *block, ms_cl_val base) {
  ms_cl_fn *f = cx->fb;
  ms_cl_val header = ms_cl_load(f, MS_CL_I64, MS_CL_NOTRAP, base, at(block->offsets[block->starts[inst->imm.b]]));
  const ClIf branch = cl_if_begin(cx, ms_cl_icmp(f, MS_CL_NE, header, cl_const(cx, 0)), MIR_MAP_WORDS);
  ms_cl_val words[MIR_MAP_WORDS];
  for (uint32_t word = 0; word < MIR_MAP_WORDS; word++) {
    words[word] = ms_cl_load(f, MS_CL_I64, MS_CL_NOTRAP, header, at(word * 8));
  }
  ms_cl_val joined[CL_IF_WORDS];
  cl_if_end(cx, &branch, words, joined);
  for (uint32_t word = 0; word < MIR_MAP_WORDS; word++) {
    cl_set(cx, inst->res, word, joined[word]);
  }
}

static void indirect_get(ClCx *cx, const MirInst *inst) {
  const MirRecordBlock block =
      mir_record_block(cx->layouts, mir_ty_data(cx->module, value_type(cx, inst->args[0]))->id);
  const ms_cl_val base = cl_arg(cx, inst, 0);
  const uint32_t field = inst->imm.b;
  if (block.boxed[field]) {
    indirect_get_collection(cx, inst, &block, base);
    return;
  }
  const uint32_t count = (uint32_t)cl_leaves(cx, block.def->fields[field].ty).len;
  for (uint32_t leaf = 0; leaf < count; leaf++) {
    const uint32_t slot = block.starts[field] + leaf;
    cl_load_leaf(cx, (MirLeaf)block.leaves.ptr[slot], inst->res, leaf, base, at(block.offsets[slot]));
  }
}

/* Frees the header block behind the collection field at `base + offset`, when it is not null. */
static void free_header(ClCx *cx, ms_cl_val base, int32_t offset) {
  ms_cl_fn *f = cx->fb;
  ms_cl_val header = ms_cl_load(f, MS_CL_I64, MS_CL_NOTRAP, base, offset);
  const ClIf branch = cl_if_begin(cx, ms_cl_icmp(f, MS_CL_NE, header, cl_const(cx, 0)), 0);
  ms_cl_call(f, cl_runtime_func(cx->mod, "msrt_free", 1, false), &header, 1, NULL);
  ms_cl_val joined[CL_IF_WORDS];
  cl_if_end(cx, &branch, NULL, joined);
}

/* `type.set`, `type.fill`: the new field value replaces the old in place and the result is the same pointer. */
static void indirect_set(ClCx *cx, const MirInst *inst) {
  const MirRecordBlock block =
      mir_record_block(cx->layouts, mir_ty_data(cx->module, value_type(cx, inst->args[0]))->id);
  const ms_cl_val base = cl_arg(cx, inst, 0);
  const uint32_t field = inst->imm.b;
  if (block.boxed[field]) {
    const int32_t slot = at(block.offsets[block.starts[field]]);
    free_header(cx, base, slot);
    ms_cl_store(cx->fb, MS_CL_NOTRAP, header_store(cx, inst->args[1]), base, slot);
  } else {
    store_field(cx, &block, base, field, inst->args[1]);
  }
  cl_set(cx, inst->res, 0, base);
}

bool cl_record_op(ClCx *cx, const MirInst *inst, bool *handled) {
  *handled = true;
  switch ((MirOp)inst->op) {
  case MOP_TypeNew:
    if (is_indirect_record(cx, value_type(cx, inst->res))) {
      indirect_new(cx, inst);
    } else {
      record_new(cx, inst);
    }
    return true;
  case MOP_TypeGet:
    if (is_indirect_record(cx, value_type(cx, inst->args[0]))) {
      indirect_get(cx, inst);
    } else {
      record_get(cx, inst);
    }
    return true;
  case MOP_TypeSet:
  case MOP_TypeFill:
    if (is_indirect_record(cx, value_type(cx, inst->args[0]))) {
      indirect_set(cx, inst);
    } else {
      record_set(cx, inst);
    }
    return true;
  case MOP_Free:
    if (inst->imm.tag != MI_NONE) {
      const MirRecordBlock block = mir_record_block(cx->layouts, inst->imm.a);
      free_header(cx, cl_arg(cx, inst, 0), at(block.offsets[block.starts[inst->imm.b]]));
      return true;
    }
    break;
  default:
    break;
  }
  *handled = false;
  return true;
}
