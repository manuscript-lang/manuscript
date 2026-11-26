/* Owns loads, stores and copies of leaves, and the memory operations on them (see emit_cx.h). */
#include "compiler/emit/emit_cx.h"

#include "base/alloc.h"
#include "base/fatal.h"

#include <string.h>

EmitAddr emit_address(EmitCx *cx, const char *base, uint32_t offset) {
  EmitAddr address;
  if (offset == 0) {
    const MsSpan name = ms_span_of_text(base);
    if (name.len >= sizeof address.text) {
      ms_fatal(MS_FATAL_OVERFLOW, "address name");
    }
    memcpy(address.text, name.ptr, name.len);
    address.text[name.len] = '\0';
    return address;
  }
  uint32_t number = cx->next++;
  ms_strbuild_printf(cx->out, "  %%a%u = getelementptr i8, ptr %s, i64 %u\n", number, base, offset);
  emit_register_name(address.text, sizeof address.text, "a", number);
  return address;
}

static const char *tbaa_text(const EmitCx *cx) {
  return cx->tbaa != NULL ? cx->tbaa : "";
}

void emit_load_leaf(EmitCx *cx, MirLeaf leaf, MirValue dst, uint32_t index, EmitAddr address) {
  MsStrBuild *out = cx->out;
  const EmitLeafKind *kind = emit_leaf_kind(leaf);
  if (kind->widen == EMIT_SAME) {
    ms_strbuild_append_text(out, "  ");
    emit_name(out, dst, index);
    ms_strbuild_printf(out, " = load %s%s, ptr %s%s\n", cx->volatile_loads ? "volatile " : "", kind->mem, address.text,
                       tbaa_text(cx));
    return;
  }
  uint32_t number = cx->next++;
  ms_strbuild_printf(out, "  %%l%u = load %s%s, ptr %s%s\n  ", number, cx->volatile_loads ? "volatile " : "", kind->mem,
                     address.text, tbaa_text(cx));
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

void emit_store_leaf(EmitCx *cx, MirLeaf leaf, MirValue src, uint32_t index, EmitAddr address) {
  MsStrBuild *out = cx->out;
  const EmitLeafKind *kind = emit_leaf_kind(leaf);
  if (kind->widen == EMIT_SAME) {
    ms_strbuild_printf(out, "  store %s ", kind->mem);
    emit_name(out, src, index);
    ms_strbuild_printf(out, ", ptr %s%s\n", address.text, tbaa_text(cx));
    return;
  }
  uint32_t number = cx->next++;
  ms_strbuild_printf(out, "  %%t%u = %s", number, narrow_instruction(kind->widen));
  emit_name(out, src, index);
  ms_strbuild_printf(out, " to %s\n  store %s %%t%u, ptr %s%s\n", kind->mem, kind->mem, number, address.text,
                     tbaa_text(cx));
}

/* The memory offsets of the leaves of `value`, from `mir_mem_layout`; free with ms_free. */
uint32_t *emit_leaf_offsets(EmitCx *cx, MirValue value) {
  MsSpan leaves = emit_value_leaves(cx, value);
  size_t bytes = 0;
  if (!ms_size_mul(leaves.len + 1, sizeof(uint32_t), &bytes)) {
    ms_fatal(MS_FATAL_OVERFLOW, "leaf count");
  }
  uint32_t *offsets = ms_alloc_zeroed(bytes);
  (void)mir_mem_layout(leaves, offsets);
  return offsets;
}

void emit_leaves_at(EmitCx *cx, MirValue value, const char *base, bool load) {
  MsSpan leaves = emit_value_leaves(cx, value);
  uint32_t *offsets = emit_leaf_offsets(cx, value);
  for (uint32_t leaf = 0; leaf < leaves.len; leaf++) {
    EmitAddr address = emit_address(cx, base, offsets[leaf]);
    if (load) {
      emit_load_leaf(cx, leaves.ptr[leaf], value, leaf, address);
    } else {
      emit_store_leaf(cx, leaves.ptr[leaf], value, leaf, address);
    }
  }
  ms_free(offsets);
}

/* Writes the leaves of `value` to memory at `base`: a held value is its cell, which has the
 * layout of that memory, so it is copied as one block. */
void emit_store_value(EmitCx *cx, MirValue value, const char *base) {
  char cell[24];
  MsSpan leaves = emit_value_leaves(cx, value);
  if (leaves.len >= 4 && emit_wide_address(cx, value, cell, sizeof cell)) {
    ms_strbuild_printf(cx->out, "  call void @llvm.memcpy.p0.p0.i64(ptr %s, ptr %s, i64 %u, i1 false)\n", base, cell,
                       mir_mem_layout(leaves, NULL).size);
    return;
  }
  emit_leaves_at(cx, value, base, false);
}

/* Reads the leaves of `value` from memory at `base`; see emit_wide_fill. */
void emit_load_value(EmitCx *cx, MirValue value, const char *base) {
  if (!emit_wide_fill(cx, value, base, NULL)) {
    emit_leaves_at(cx, value, base, true);
  }
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

/* A whole list or bytes header moves between a slot and registers: tagged as header memory, which no scalar list
 * element aliases, so a store of an element does not make the loop reload the header from its slot. */
static const char *header_tbaa(const EmitCx *cx, MirValue value) {
  const MirTyKind kind = (MirTyKind)mir_ty_data(cx->module, emit_value_type(cx, value))->kind;
  return kind == MK_LIST || kind == MK_BYTES ? ", !tbaa !900004" : NULL;
}

/* `load`, `take`: the result's leaves from the pointer in the first operand. */
static void emit_load(EmitCx *cx, const MirInst *inst) {
  char base[24];
  emit_pointer(cx, inst->args[0], base, sizeof base);
  char cell[24];
  if (emit_wide_result(cx, inst->res, cell, sizeof cell)) {
    /* A held value is one copy into its cell, not a register per leaf that the register allocator then spills. */
    ms_strbuild_printf(cx->out, "  call void @llvm.memcpy.p0.p0.i64(ptr %s, ptr %s, i64 %u, i1 false)\n", cell, base,
                       emit_slot_bytes(cx, emit_value_type(cx, inst->res)));
    return;
  }
  cx->tbaa = header_tbaa(cx, inst->res);
  emit_load_value(cx, inst->res, base);
  cx->tbaa = NULL;
}

/* `store`, `put`: the second operand's leaves to the pointer in the first. */
static void emit_store(EmitCx *cx, const MirInst *inst) {
  char base[24];
  emit_pointer(cx, inst->args[0], base, sizeof base);
  char cell[24];
  if (emit_wide_address(cx, inst->args[1], cell, sizeof cell)) {
    ms_strbuild_printf(cx->out, "  call void @llvm.memcpy.p0.p0.i64(ptr %s, ptr %s, i64 %u, i1 false)\n", base, cell,
                       emit_slot_bytes(cx, emit_value_type(cx, inst->args[1])));
    return;
  }
  cx->tbaa = header_tbaa(cx, inst->args[1]);
  if (inst->op == MOP_Put && inst->imm.tag == MI_INT) {
    /* The one leaf that differs from what the place holds (the length of a list that had room for the element). */
    uint32_t *offsets = emit_leaf_offsets(cx, inst->args[1]);
    const uint32_t leaf = (uint32_t)inst->imm.i;
    emit_store_leaf(cx, emit_value_leaves(cx, inst->args[1]).ptr[leaf], inst->args[1], leaf,
                    emit_address(cx, base, offsets[leaf]));
    ms_free(offsets);
  } else {
    emit_store_value(cx, inst->args[1], base);
  }
  cx->tbaa = NULL;
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

bool emit_memory_inst(EmitCx *cx, const MirInst *inst, const EmitSite *site, bool *handled) {
  (void)site;
  *handled = true;
  switch ((MirOp)inst->op) {
  case MOP_Slot:
    /* Allocated at the top of the entry block; it starts zeroed each time the instruction runs. */
    if (cx->pool != NULL && cx->pool[inst->res] != UINT32_MAX) {
      ms_strbuild_printf(cx->out,
                         "  call void @llvm.memset.p0.i64(ptr %%cell%u, i8 0, i64 %u, i1 false)\n"
                         "  %%v%u = ptrtoint ptr %%cell%u to i64\n",
                         cx->pool[inst->res], emit_slot_bytes(cx, inst->imm.a), inst->res, cx->pool[inst->res]);
    } else {
      /* Zeroed, so padding bytes compare equal when a descriptor compares a slot as bytes. */
      ms_strbuild_printf(cx->out,
                         "  call void @llvm.memset.p0.i64(ptr %%s%u, i8 0, i64 %u, i1 false)\n"
                         "  %%v%u = ptrtoint ptr %%s%u to i64\n",
                         inst->res, emit_slot_bytes(cx, inst->imm.a), inst->res, inst->res);
    }
    return true;
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
