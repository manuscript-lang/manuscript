/* Owns loads, stores and copies of leaves, and the memory operations on them (see emit_cx.h). */
#include "compiler/emit/emit_cx.h"

#include "base/alloc.h"
#include "base/fatal.h"

uint32_t emit_address(EmitCx *cx, const char *base, uint32_t offset) {
  uint32_t number = cx->next++;
  ms_strbuild_printf(cx->out, "  %%a%u = getelementptr i8, ptr %s, i64 %u\n", number, base, offset);
  return number;
}

static const char *tbaa_text(const EmitCx *cx) {
  return cx->tbaa != NULL ? cx->tbaa : "";
}

void emit_load_leaf(EmitCx *cx, MirLeaf leaf, MirValue dst, uint32_t index, uint32_t address) {
  MsStrBuild *out = cx->out;
  const EmitLeafKind *kind = emit_leaf_kind(leaf);
  if (kind->widen == EMIT_SAME) {
    ms_strbuild_append_text(out, "  ");
    emit_name(out, dst, index);
    ms_strbuild_printf(out, " = load %s, ptr %%a%u%s\n", kind->mem, address, tbaa_text(cx));
    return;
  }
  uint32_t number = cx->next++;
  ms_strbuild_printf(out, "  %%l%u = load %s, ptr %%a%u%s\n  ", number, kind->mem, address, tbaa_text(cx));
  emit_name(out, dst, index);
  switch (kind->widen) {
  case EMIT_SEXT:
    ms_strbuild_printf(out, " = sext %s %%l%u to i64\n", kind->mem, number);
    break;
  case EMIT_ZEXT:
    ms_strbuild_printf(out, " = zext %s %%l%u to i64\n", kind->mem, number);
    break;
  case EMIT_BOOL:
    ms_strbuild_printf(out, " = trunc i8 %%l%u to i1\n", number);
    break;
  case EMIT_FPEXT:
  case EMIT_SAME:
    ms_strbuild_printf(out, " = fpext float %%l%u to double\n", number);
    break;
  }
}

static const char *narrow_instruction(EmitWiden widen) {
  switch (widen) {
  case EMIT_BOOL:
    return "zext i1 ";
  case EMIT_FPEXT:
    return "fptrunc double ";
  case EMIT_SAME:
  case EMIT_SEXT:
  case EMIT_ZEXT:
    return "trunc i64 ";
  }
  return "trunc i64 ";
}

void emit_store_leaf(EmitCx *cx, MirLeaf leaf, MirValue src, uint32_t index, uint32_t address) {
  MsStrBuild *out = cx->out;
  const EmitLeafKind *kind = emit_leaf_kind(leaf);
  if (kind->widen == EMIT_SAME) {
    ms_strbuild_printf(out, "  store %s ", kind->mem);
    emit_name(out, src, index);
    ms_strbuild_printf(out, ", ptr %%a%u%s\n", address, tbaa_text(cx));
    return;
  }
  uint32_t number = cx->next++;
  ms_strbuild_printf(out, "  %%t%u = %s", number, narrow_instruction(kind->widen));
  emit_name(out, src, index);
  ms_strbuild_printf(out, " to %s\n  store %s %%t%u, ptr %%a%u%s\n", kind->mem, kind->mem, number, address,
                     tbaa_text(cx));
}

void emit_leaves_at(EmitCx *cx, MirValue value, const char *base, bool load) {
  MsSpan leaves = emit_value_leaves(cx, value);
  size_t bytes = 0;
  if (!ms_size_mul(leaves.len + 1, sizeof(uint32_t), &bytes)) {
    ms_fatal(MS_FATAL_OVERFLOW, "leaf count");
  }
  uint32_t *offsets = ms_alloc_zeroed(bytes);
  (void)mir_mem_layout(leaves, offsets);
  for (uint32_t leaf = 0; leaf < leaves.len; leaf++) {
    uint32_t address = emit_address(cx, base, offsets[leaf]);
    if (load) {
      emit_load_leaf(cx, leaves.ptr[leaf], value, leaf, address);
    } else {
      emit_store_leaf(cx, leaves.ptr[leaf], value, leaf, address);
    }
  }
  ms_free(offsets);
}

void emit_pointer(EmitCx *cx, MirValue value, char *name, size_t capacity) {
  uint32_t number = cx->next++;
  ms_strbuild_printf(cx->out, "  %%p%u = inttoptr i64 %%v%u to ptr\n", number, value);
  emit_register_name(name, capacity, "p", number);
}

void emit_copy_leaf(EmitCx *cx, MirValue dst, uint32_t out_index, MirValue src, uint32_t src_index) {
  MsStrBuild *out = cx->out;
  const char *type = emit_leaf_type(emit_value_leaves(cx, dst).ptr[out_index]);
  const char *from = emit_leaf_type(emit_value_leaves(cx, src).ptr[src_index]);
  if (type[0] != from[0] || type[1] != from[1]) {
    /* A slot an alternative's cases share has the widest leaf type: read a narrower payload out of it. */
    ms_strbuild_append_text(out, "  ");
    emit_name(out, dst, out_index);
    if (type[1] == '1') {
      ms_strbuild_printf(out, " = icmp ne %s ", from);
    } else if (from[1] == '1') {
      ms_strbuild_printf(out, " = zext i1 ");
    } else {
      ms_strbuild_printf(out, " = bitcast %s ", from);
    }
    emit_name(out, src, src_index);
    if (type[1] == '1') {
      ms_strbuild_append_text(out, ", 0\n");
    } else {
      ms_strbuild_printf(out, " to %s\n", type);
    }
    return;
  }
  const char *operation = " = or ";
  const char *identity = ", 0\n";
  if (type[0] == 'd') {
    operation = " = fadd ";
    identity = ", -0.0\n";
  } else if (type[1] == '1') {
    identity = ", false\n";
  }
  ms_strbuild_append_text(out, "  ");
  emit_name(out, dst, out_index);
  ms_strbuild_printf(out, "%s%s ", operation, type);
  emit_name(out, src, src_index);
  ms_strbuild_append_text(out, identity);
}

void emit_zero_leaf(EmitCx *cx, MirValue dst, uint32_t index, MirLeaf leaf) {
  const char *type = emit_leaf_type(leaf);
  ms_strbuild_append_text(cx->out, "  ");
  emit_name(cx->out, dst, index);
  if (type[0] == 'd') {
    ms_strbuild_append_text(cx->out, " = fadd double 0.0, 0.0\n");
  } else if (type[1] == '1') {
    ms_strbuild_append_text(cx->out, " = or i1 false, false\n");
  } else {
    ms_strbuild_append_text(cx->out, " = add i64 0, 0\n");
  }
}

/* `load`, `take`: the result's leaves from the pointer in the first operand. */
static void emit_load(EmitCx *cx, const MirInst *inst) {
  char base[24];
  emit_pointer(cx, inst->args[0], base, sizeof base);
  emit_leaves_at(cx, inst->res, base, true);
}

/* `store`, `put`: the second operand's leaves to the pointer in the first. */
static void emit_store(EmitCx *cx, const MirInst *inst) {
  char base[24];
  emit_pointer(cx, inst->args[0], base, sizeof base);
  emit_leaves_at(cx, inst->args[1], base, false);
}

/* `ptr.field`: the address of a field of the inline record the operand points to. */
static bool emit_ptr_field(EmitCx *cx, const MirInst *inst) {
  if (cx->module->type_defs.ptr[inst->imm.a].indirect) {
    cx->why = "record behind a pointer";
    return false;
  }
  ms_strbuild_printf(cx->out, "  %%v%u = add i64 %%v%u, %u\n", inst->res, inst->args[0],
                     mir_field_offset(cx->layouts, inst->imm.a, inst->imm.b));
  return true;
}

bool emit_memory_inst(EmitCx *cx, const MirInst *inst, bool *handled) {
  *handled = true;
  switch ((MirOp)inst->op) {
  case MOP_Slot:
    return true; /* allocated at the top of the entry block */
  case MOP_Load:
  case MOP_Take:
    emit_load(cx, inst);
    return true;
  case MOP_Store:
  case MOP_Put:
    emit_store(cx, inst);
    return true;
  case MOP_PtrField:
    return emit_ptr_field(cx, inst);
  default:
    *handled = false;
    return true;
  }
}
