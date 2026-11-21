/* Owns what LLVM needs to know about leaves, value names, symbols and labels (see emit_cx.h). */
#include "compiler/emit/emit_cx.h"

static const EmitLeafKind leaf_kinds[MIR_LEAF_COUNT] = {
    [MIR_LEAF_I64] = {"i64", "i64", EMIT_SAME},     [MIR_LEAF_F64] = {"double", "double", EMIT_SAME},
    [MIR_LEAF_I8] = {"i1", "i8", EMIT_BOOL},        [MIR_LEAF_N8] = {"i64", "i8", EMIT_SEXT},
    [MIR_LEAF_N16] = {"i64", "i16", EMIT_SEXT},     [MIR_LEAF_N32] = {"i64", "i32", EMIT_SEXT},
    [MIR_LEAF_U8] = {"i64", "i8", EMIT_ZEXT},       [MIR_LEAF_U16] = {"i64", "i16", EMIT_ZEXT},
    [MIR_LEAF_U32] = {"i64", "i32", EMIT_ZEXT},     [MIR_LEAF_F32] = {"double", "float", EMIT_FPEXT},
};

const EmitLeafKind *emit_leaf_kind(MirLeaf leaf) {
  return &leaf_kinds[leaf < MIR_LEAF_COUNT ? leaf : MIR_LEAF_I64];
}

const char *emit_leaf_type(MirLeaf leaf) {
  return emit_leaf_kind(leaf)->reg;
}

MsSpan emit_leaves(EmitCx *cx, MirTy type) {
  return mir_leaves(cx->layouts, type);
}

MirTy emit_value_type(const EmitCx *cx, MirValue value) {
  return mir_value_ty(cx->func, value);
}

MsSpan emit_value_leaves(EmitCx *cx, MirValue value) {
  return emit_leaves(cx, emit_value_type(cx, value));
}

const char *emit_value_register_type(EmitCx *cx, MirValue value) {
  MsSpan leaves = emit_value_leaves(cx, value);
  return leaves.len == 1 ? emit_leaf_type(leaves.ptr[0]) : "i64";
}

void emit_name(MsStrBuild *out, MirValue value, uint32_t leaf) {
  ms_strbuild_printf(out, "%%v%u", value);
  if (leaf != 0) {
    ms_strbuild_printf(out, ".%u", leaf);
  }
}

void emit_symbol(MsStrBuild *out, MsSpan name) {
  ms_strbuild_append_text(out, "@\"");
  for (size_t index = 0; index < name.len; index++) {
    uint8_t byte = name.ptr[index];
    if (byte >= 0x20 && byte < 0x7f && byte != '"' && byte != '\\') {
      ms_strbuild_append_byte(out, byte);
      continue;
    }
    ms_strbuild_append_byte(out, '\\');
    if (byte < 16) {
      ms_strbuild_append_byte(out, '0');
    }
    ms_strbuild_append_u64_radix(out, byte, 16);
  }
  ms_strbuild_append_byte(out, '"');
}

void emit_function_symbol(const EmitCx *cx, uint32_t id) {
  emit_symbol(cx->out, ms_names_span(&cx->module->names, cx->module->funcs.ptr[id].name));
}

void emit_label(MsStrBuild *out, uint32_t block, uint32_t part) {
  if (part == 0) {
    ms_strbuild_printf(out, "b%u", block);
  } else {
    ms_strbuild_printf(out, "b%u.%u", block, part);
  }
}

bool emit_is_indirect(EmitCx *cx, MirTy type) {
  return mir_type_mem(cx->layouts, type).size > EMIT_DIRECT_BYTES;
}

uint32_t emit_slot_bytes(EmitCx *cx, MirTy type) {
  uint32_t size = mir_type_mem(cx->layouts, type).size;
  if (size < 8) {
    size = 8;
  }
  return (size + 7U) / 8U * 8U;
}

/* `%<prefix><number>` into `out` (NUL-terminated); a name that does not fit is cut. */
void emit_register_name(char *out, size_t capacity, const char *prefix, uint32_t number) {
  char digits[16];
  size_t digit_count = 0;
  do {
    digits[digit_count++] = (char)('0' + number % 10);
    number /= 10;
  } while (number != 0);
  size_t length = 0;
  if (capacity > 1) {
    out[length++] = '%';
  }
  for (const char *at = prefix; *at != '\0' && length + 1 < capacity; at++) {
    out[length++] = *at;
  }
  while (digit_count > 0 && length + 1 < capacity) {
    out[length++] = digits[--digit_count];
  }
  out[length] = '\0';
}
