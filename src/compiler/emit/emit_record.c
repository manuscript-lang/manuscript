/* Owns records: inline records as runs of leaves, and records behind a pointer as heap blocks the way the
 * runtime lays them out. Reading, building or freeing a collection field branches, which ends the current
 * piece of the block (emit_record_pieces). */
#include "compiler/emit/emit_cx.h"

#include "base/alloc.h"
#include "base/fatal.h"
#include "compiler/mir/mir_pass.h"

static MirTy value_type(const EmitCx *cx, MirValue value) {
  return cx->func->values.ptr[value];
}

/* ---- the one-block `if` ---- */

static EmitIf emit_if_begin(EmitCx *cx, const char *condition, const EmitSite *site) {
  EmitIf branch = {.id = cx->next++, .head = *site->part, .join = ++*site->part};
  ms_strbuild_printf(cx->out, "  br i1 %s, label %%i%u, label %%", condition, branch.id);
  emit_label(cx->out, site->block, branch.join);
  ms_strbuild_printf(cx->out, "\ni%u:\n", branch.id);
  return branch;
}

static void emit_if_end(EmitCx *cx, const EmitIf *branch, const EmitSite *site) {
  ms_strbuild_append_text(cx->out, "  br label %");
  emit_label(cx->out, site->block, branch->join);
  ms_strbuild_append_byte(cx->out, '\n');
  emit_label(cx->out, site->block, branch->join);
  ms_strbuild_append_text(cx->out, ":\n");
}

/* `<dst> = phi i64 [0, %head], [<value>, %i<id>]`: a word that is zero when the side was skipped. */
static void emit_if_phi(EmitCx *cx, const EmitIf *branch, const EmitSite *site, const char *dst, const char *value) {
  ms_strbuild_printf(cx->out, "  %s = phi i64 [0, %%", dst);
  emit_label(cx->out, site->block, branch->head);
  ms_strbuild_printf(cx->out, "], [%s, %%i%u]\n", value, branch->id);
}

/* ---- inline records ---- */

/* The leaf range `[start, start + count)` that field `field` of record type `type` occupies in a value of that
 * type. False when `type` is not a record held as leaves. */
static bool field_span(EmitCx *cx, MirTy type, uint32_t field, uint32_t *start, uint32_t *count) {
  const MirTyData *data = mir_ty_data(cx->module, type);
  if (data->kind != MK_TYPE || cx->module->type_defs.ptr[data->id].indirect) {
    cx->why = "record behind a pointer";
    return false;
  }
  const MirTypeDef *def = &cx->module->type_defs.ptr[data->id];
  *start = 0;
  for (uint32_t earlier = 0; earlier < field; earlier++) {
    *start += (uint32_t)emit_leaves(cx, def->fields[earlier].ty).len;
  }
  *count = (uint32_t)emit_leaves(cx, def->fields[field].ty).len;
  return true;
}

/* The memory offsets of the leaves of `value`, from `mir_mem_layout`; free with ms_free. */
static uint32_t *leaf_offsets(EmitCx *cx, MirValue value) {
  MsSpan leaves = emit_value_leaves(cx, value);
  size_t bytes = 0;
  if (!ms_size_mul(leaves.len + 1, sizeof(uint32_t), &bytes)) {
    ms_fatal(MS_FATAL_OVERFLOW, "leaf count");
  }
  uint32_t *offsets = ms_alloc_zeroed(bytes);
  (void)mir_mem_layout(leaves, offsets);
  return offsets;
}

/* Bytes of the leaves of `value` without the padding after the last (a copy of it must not reach the next field);
 * `aligned` receives whether a copy at `at` keeps each leaf's natural alignment. */
static uint32_t packed_bytes(EmitCx *cx, MirValue value, uint32_t at, bool *aligned) {
  MsSpan leaves = emit_value_leaves(cx, value);
  uint32_t *offsets = leaf_offsets(cx, value);
  const MirMemLayout layout = mir_mem_layout(leaves, NULL);
  *aligned = at % layout.align == 0;
  const uint32_t bytes = leaves.len == 0 ? 0 : offsets[leaves.len - 1] + mir_leaf_size(leaves.ptr[leaves.len - 1]);
  ms_free(offsets);
  return bytes;
}

/* `type.new` of a held record: each field's leaves stored into the result's cell, a held field copied from its own,
 * not loaded and copied one by one. */
static bool held_record_new(EmitCx *cx, const MirInst *inst) {
  if (!emit_wide_held(cx, inst->res)) {
    return false;
  }
  MsSpan leaves = emit_value_leaves(cx, inst->res);
  uint32_t *offsets = leaf_offsets(cx, inst->res);
  uint32_t at = 0;
  bool ok = true;
  for (uint32_t arg = 0; ok && arg < inst->nargs; arg++) {
    bool aligned = true;
    char from[24];
    if (emit_wide_address(cx, inst->args[arg], from, sizeof from)) {
      (void)packed_bytes(cx, inst->args[arg], offsets[at], &aligned);
      /* A field that shares the result's cell would be overwritten by the stores before it is copied. */
      aligned = aligned && !emit_wide_shares_cell(cx, inst->args[arg], inst->res);
    }
    ok = aligned;
    at += (uint32_t)emit_value_leaves(cx, inst->args[arg]).len;
  }
  char cell[24];
  if (!ok || !emit_wide_result(cx, inst->res, cell, sizeof cell)) {
    ms_free(offsets);
    return false;
  }
  at = 0;
  for (uint32_t arg = 0; arg < inst->nargs; arg++) {
    const MirValue field = inst->args[arg];
    const uint32_t count = (uint32_t)emit_value_leaves(cx, field).len;
    char from[24];
    if (count > 0 && emit_wide_address(cx, field, from, sizeof from)) {
      bool aligned = true;
      const uint32_t bytes = packed_bytes(cx, field, offsets[at], &aligned);
      const EmitAddr to = emit_address(cx, cell, offsets[at]);
      ms_strbuild_printf(cx->out, "  call void @llvm.memcpy.p0.p0.i64(ptr %s, ptr %s, i64 %u, i1 false)\n", to.text, from,
                         bytes);
      at += count;
      continue;
    }
    for (uint32_t leaf = 0; leaf < count; leaf++, at++) {
      emit_store_leaf(cx, leaves.ptr[at], field, leaf, emit_address(cx, cell, offsets[at]));
    }
  }
  ms_free(offsets);
  return true;
}

/* `type.set` of a held record: the record's cell copied whole into the result's, then the field's leaves stored. */
static bool held_record_set(EmitCx *cx, const MirInst *inst, uint32_t start, uint32_t count) {
  char from[24];
  char to[24];
  if (!emit_wide_address(cx, inst->args[0], from, sizeof from) || emit_wide_held(cx, inst->args[1]) ||
      !emit_wide_result(cx, inst->res, to, sizeof to)) {
    return false;
  }
  if (!emit_wide_same_cell(cx, inst->args[0], inst->res)) {
    ms_strbuild_printf(cx->out, "  call void @llvm.%s.p0.p0.i64(ptr %s, ptr %s, i64 %u, i1 false)\n",
                       emit_wide_shares_cell(cx, inst->args[0], inst->res) ? "memmove" : "memcpy", to, from,
                       emit_slot_bytes(cx, value_type(cx, inst->res)));
  }
  MsSpan leaves = emit_value_leaves(cx, inst->res);
  uint32_t *offsets = leaf_offsets(cx, inst->res);
  for (uint32_t leaf = 0; leaf < count; leaf++) {
    emit_store_leaf(cx, leaves.ptr[start + leaf], inst->args[1], leaf, emit_address(cx, to, offsets[start + leaf]));
  }
  ms_free(offsets);
  return true;
}

/* `type.new`: the leaves of the fields in order. */
static void record_new(EmitCx *cx, const MirInst *inst) {
  if (held_record_new(cx, inst)) {
    return;
  }
  uint32_t at = 0;
  for (uint32_t arg = 0; arg < inst->nargs; arg++) {
    uint32_t count = (uint32_t)emit_value_leaves(cx, inst->args[arg]).len;
    for (uint32_t leaf = 0; leaf < count; leaf++) {
      emit_copy_leaf(cx, inst->res, at++, inst->args[arg], leaf);
    }
  }
}

/* `type.get` of a field that is itself wide, out of a held record: the field's bytes copied from the record's cell
 * to the result's, when the leaves sit the same distance apart in both (they are not loaded and stored one by one,
 * which in a Debug build costs a volatile load per leaf). */
static bool held_record_get(EmitCx *cx, const MirInst *inst, uint32_t start, uint32_t count) {
  char from[24];
  char to[24];
  if (count == 0 || !emit_wide_held(cx, inst->res) || !emit_wide_address(cx, inst->args[0], from, sizeof from)) {
    return false;
  }
  uint32_t *source = leaf_offsets(cx, inst->args[0]);
  uint32_t *result = leaf_offsets(cx, inst->res);
  bool same = source[start] >= result[0] && result[0] == 0;
  for (uint32_t leaf = 1; leaf < count && same; leaf++) {
    same = source[start + leaf] - source[start] == result[leaf] - result[0];
  }
  const uint32_t offset = source[start];
  bool aligned = true;
  const uint32_t bytes = packed_bytes(cx, inst->res, 0, &aligned);
  same = same &&
         emit_wide_result(cx, inst->res, to, sizeof to);
  ms_free(source);
  ms_free(result);
  if (!same) {
    return false;
  }
  if (offset != 0 || !emit_wide_same_cell(cx, inst->args[0], inst->res)) {
    const EmitAddr at = emit_address(cx, from, offset);
    ms_strbuild_printf(cx->out, "  call void @llvm.memmove.p0.p0.i64(ptr %s, ptr %s, i64 %u, i1 false)\n", to, at.text,
                       bytes);
  }
  return true;
}

/* `type.get`: the leaves of one field. */
static bool record_get(EmitCx *cx, const MirInst *inst) {
  uint32_t start = 0;
  uint32_t count = 0;
  if (!field_span(cx, value_type(cx, inst->args[0]), inst->imm.b, &start, &count)) {
    return false;
  }
  if (held_record_get(cx, inst, start, count)) {
    return true;
  }
  for (uint32_t leaf = 0; leaf < count; leaf++) {
    emit_copy_leaf(cx, inst->res, leaf, inst->args[0], start + leaf);
  }
  return true;
}

/* `type.set`: the record with one field's leaves replaced by the second operand's. */
static bool record_set(EmitCx *cx, const MirInst *inst) {
  uint32_t total = (uint32_t)emit_value_leaves(cx, inst->args[0]).len;
  uint32_t start = 0;
  uint32_t count = 0;
  if (!field_span(cx, value_type(cx, inst->args[0]), inst->imm.b, &start, &count)) {
    return false;
  }
  if (held_record_set(cx, inst, start, count)) {
    return true;
  }
  for (uint32_t leaf = 0; leaf < total; leaf++) {
    if (leaf >= start && leaf < start + count) {
      emit_copy_leaf(cx, inst->res, leaf, inst->args[1], leaf - start);
    } else {
      emit_copy_leaf(cx, inst->res, leaf, inst->args[0], leaf);
    }
  }
  return true;
}

/* ---- records behind a pointer ---- */

static bool is_indirect_record(const EmitCx *cx, MirTy type) {
  const MirTyData *data = mir_ty_data(cx->module, type);
  return data->kind == MK_TYPE && cx->module->type_defs.ptr[data->id].indirect;
}

/* Stores the leaves of `value` as field `field` of the block at `base`. */
static void store_field(EmitCx *cx, const MirRecordBlock *block, const char *base, uint32_t field,
                        MirValue value) {
  uint32_t count = (uint32_t)emit_value_leaves(cx, value).len;
  for (uint32_t leaf = 0; leaf < count; leaf++) {
    uint32_t slot = block->starts[field] + leaf;
    emit_store_leaf(cx, block->leaves.ptr[slot], value, leaf, emit_address(cx, base, block->offsets[slot]));
  }
}

/* The header block of a map or set value: null when its first and last words are zero (the empty collection),
 * else a fresh block holding the words. Leaves the address in `%h<id>`. */
static uint32_t header_store(EmitCx *cx, MirValue value, const EmitSite *site) {
  MsStrBuild *out = cx->out;
  uint32_t number = cx->next++;
  ms_strbuild_printf(out, "  %%u%u = or i64 %%v%u, %%v%u.%u\n  %%u%ub = icmp ne i64 %%u%u, 0\n", number, value, value,
                     MIR_MAP_WORDS - 1, number, number);
  char condition[24];
  emit_text_name(condition, sizeof condition, "u", number, "b", MIR_NONE);
  EmitIf branch = emit_if_begin(cx, condition, site);
  ms_strbuild_printf(out, "  %%q%u = call i64 @msrt_alloc(i64 %u)\n  %%p%u = inttoptr i64 %%q%u to ptr\n", branch.id,
                     MIR_MAP_WORDS * 8, branch.id, branch.id);
  char base[24];
  emit_register_name(base, sizeof base, "p", branch.id);
  for (uint32_t word = 0; word < MIR_MAP_WORDS; word++) {
    const EmitAddr at = emit_address(cx, base, word * 8);
    ms_strbuild_append_text(out, "  store i64 ");
    emit_name(out, value, word);
    ms_strbuild_printf(out, ", ptr %s\n", at.text);
  }
  emit_if_end(cx, &branch, site);
  char header[24];
  char made[24];
  emit_register_name(header, sizeof header, "h", branch.id);
  emit_register_name(made, sizeof made, "q", branch.id);
  emit_if_phi(cx, &branch, site, header, made);
  return branch.id;
}

/* `type.new`: a heap block holding the fields. */
static void indirect_new(EmitCx *cx, const MirInst *inst, const EmitSite *site) {
  MirRecordBlock block = mir_record_block(cx->layouts, mir_ty_data(cx->module, value_type(cx, inst->res))->id);
  ms_strbuild_printf(cx->out, "  %%v%u = call i64 @msrt_alloc(i64 %u)\n", inst->res, block.size > 0 ? block.size : 1);
  char base[24];
  emit_pointer(cx, inst->res, base, sizeof base);
  for (uint32_t field = 0; field < inst->nargs; field++) {
    if (!block.boxed[field]) {
      store_field(cx, &block, base, field, inst->args[field]);
      continue;
    }
    uint32_t header = header_store(cx, inst->args[field], site);
    const EmitAddr at = emit_address(cx, base, block.offsets[block.starts[field]]);
    ms_strbuild_printf(cx->out, "  store i64 %%h%u, ptr %s\n", header, at.text);
  }
}

/* `type.get` of a collection field: read through its header, or all zero when that is null. */
static void indirect_get_collection(EmitCx *cx, const MirInst *inst, const MirRecordBlock *block, const char *base,
                                    const EmitSite *site) {
  MsStrBuild *out = cx->out;
  uint32_t field = inst->imm.b;
  uint32_t number = cx->next++;
  const EmitAddr slot = emit_address(cx, base, block->offsets[block->starts[field]]);
  ms_strbuild_printf(out, "  %%g%u = load i64, ptr %s\n  %%g%ub = icmp ne i64 %%g%u, 0\n", number, slot.text, number,
                     number);
  char condition[24];
  emit_text_name(condition, sizeof condition, "g", number, "b", MIR_NONE);
  EmitIf branch = emit_if_begin(cx, condition, site);
  ms_strbuild_printf(out, "  %%gp%u = inttoptr i64 %%g%u to ptr\n", number, number);
  char header[24];
  emit_register_name(header, sizeof header, "gp", number);
  for (uint32_t word = 0; word < MIR_MAP_WORDS; word++) {
    const EmitAddr at = emit_address(cx, header, word * 8);
    ms_strbuild_printf(out, "  %%w%u_%u = load i64, ptr %s\n", branch.id, word, at.text);
  }
  emit_if_end(cx, &branch, site);
  for (uint32_t word = 0; word < MIR_MAP_WORDS; word++) {
    char destination[24];
    char loaded[24];
    emit_text_name(destination, sizeof destination, "v", inst->res, word == 0 ? NULL : ".", word == 0 ? MIR_NONE : word);
    emit_text_name(loaded, sizeof loaded, "w", branch.id, "_", word);
    emit_if_phi(cx, &branch, site, destination, loaded);
  }
}

/* `type.get`: the leaves of one field, loaded from the block. */
static void indirect_get(EmitCx *cx, const MirInst *inst, const EmitSite *site) {
  MirRecordBlock block =
      mir_record_block(cx->layouts, mir_ty_data(cx->module, value_type(cx, inst->args[0]))->id);
  char base[24];
  emit_pointer(cx, inst->args[0], base, sizeof base);
  uint32_t field = inst->imm.b;
  if (block.boxed[field]) {
    indirect_get_collection(cx, inst, &block, base, site);
    return;
  }
  uint32_t count = (uint32_t)emit_leaves(cx, block.def->fields[field].ty).len;
  if (emit_wide_fill(cx, inst->res, base, block.offsets + block.starts[field])) {
    return;
  }
  for (uint32_t leaf = 0; leaf < count; leaf++) {
    uint32_t slot = block.starts[field] + leaf;
    emit_load_leaf(cx, block.leaves.ptr[slot], inst->res, leaf, emit_address(cx, base, block.offsets[slot]));
  }
}

/* The branch that frees the header block behind the collection field at `slot`, when it is not null. */
static void free_header(EmitCx *cx, EmitAddr slot, const EmitSite *site) {
  uint32_t number = cx->next++;
  ms_strbuild_printf(cx->out, "  %%g%u = load i64, ptr %s\n  %%g%ub = icmp ne i64 %%g%u, 0\n", number, slot.text, number,
                     number);
  char condition[24];
  emit_text_name(condition, sizeof condition, "g", number, "b", MIR_NONE);
  EmitIf branch = emit_if_begin(cx, condition, site);
  ms_strbuild_printf(cx->out, "  call void @msrt_free(i64 %%g%u)\n", number);
  emit_if_end(cx, &branch, site);
}

/* `type.set`, `type.fill`: the new field value replaces the old in place, and the result is the same pointer. A
 * collection field frees its old header first. The old value's own drop is a separate `drop` that lowering puts
 * before a `type.set`, which it turns into `type.fill`. */
static void indirect_set(EmitCx *cx, const MirInst *inst, const EmitSite *site) {
  MirRecordBlock block =
      mir_record_block(cx->layouts, mir_ty_data(cx->module, value_type(cx, inst->args[0]))->id);
  char base[24];
  emit_pointer(cx, inst->args[0], base, sizeof base);
  uint32_t field = inst->imm.b;
  if (block.boxed[field]) {
    const EmitAddr slot = emit_address(cx, base, block.offsets[block.starts[field]]);
    free_header(cx, slot, site);
    uint32_t header = header_store(cx, inst->args[1], site);
    ms_strbuild_printf(cx->out, "  store i64 %%h%u, ptr %s\n", header, slot.text);
  } else {
    store_field(cx, &block, base, field, inst->args[1]);
  }
  ms_strbuild_printf(cx->out, "  %%v%u = add i64 %%v%u, 0\n", inst->res, inst->args[0]);
}

/* `free` of a collection field: the header block behind the field of the record block, if any. */
static void free_field(EmitCx *cx, const MirInst *inst, const EmitSite *site) {
  MirRecordBlock block = mir_record_block(cx->layouts, inst->imm.a);
  char base[24];
  emit_pointer(cx, inst->args[0], base, sizeof base);
  free_header(cx, emit_address(cx, base, block.offsets[block.starts[inst->imm.b]]), site);
}

uint32_t emit_record_pieces(const MirModule *module, const MirFunc *func, const MirInst *inst) {
  if (inst->op == MOP_Free && inst->imm.tag != MI_NONE) {
    return 1;
  }
  MirTy subject = MIR_NONE;
  if (inst->op == MOP_TypeNew) {
    subject = func->values.ptr[inst->res];
  } else if (inst->nargs > 0) {
    subject = func->values.ptr[inst->args[0]];
  }
  if (subject == MIR_NONE || mir_ty_data(module, subject)->kind != MK_TYPE ||
      !module->type_defs.ptr[mir_ty_data(module, subject)->id].indirect) {
    return 0;
  }
  const MirTypeDef *def = &module->type_defs.ptr[mir_ty_data(module, subject)->id];
  uint32_t boxed = 0;
  switch ((MirOp)inst->op) {
  case MOP_TypeNew:
    for (uint32_t field = 0; field < def->nfields; field++) {
      boxed += mir_ty_is_map_or_set(module, def->fields[field].ty) ? 1u : 0u;
    }
    return boxed;
  case MOP_TypeGet:
    return mir_ty_is_map_or_set(module, def->fields[inst->imm.b].ty) ? 1u : 0u;
  case MOP_TypeSet:
  case MOP_TypeFill:
    return mir_ty_is_map_or_set(module, def->fields[inst->imm.b].ty) ? 2u : 0u;
  default:
    return 0;
  }
}

bool emit_record_op(EmitCx *cx, const MirInst *inst, const EmitSite *site, bool *handled) {
  *handled = true;
  switch ((MirOp)inst->op) {
  case MOP_TypeNew:
    if (is_indirect_record(cx, value_type(cx, inst->res))) {
      indirect_new(cx, inst, site);
    } else {
      record_new(cx, inst);
    }
    return true;
  case MOP_TypeGet:
    if (is_indirect_record(cx, value_type(cx, inst->args[0]))) {
      indirect_get(cx, inst, site);
      return true;
    }
    return record_get(cx, inst);
  case MOP_TypeSet:
  case MOP_TypeFill:
    if (is_indirect_record(cx, value_type(cx, inst->args[0]))) {
      indirect_set(cx, inst, site);
      return true;
    }
    return record_set(cx, inst);
  case MOP_Free:
    if (inst->imm.tag != MI_NONE) {
      free_field(cx, inst, site);
      return true;
    }
    break;
  default:
    break;
  }
  *handled = false;
  return true;
}
