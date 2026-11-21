/* compiler/mir/mir_data_const.c: the constants a function uses: long string literals, constant byte strings
 * and constant lists. */
#include "abi/layout.h"
#include "compiler/mir/mir_data_internal.h"

/* The words of a string literal; the layout is the runtime's string (abi/layout.h). */
void mir_str_lit_words(MsSpan text, bool *is_static, uint64_t *lo, uint64_t *hi) {
  *is_static = text.len > MS_STRING_INLINE_MAX;
  if (*is_static) {
    bool ascii = true;
    for (size_t index = 0; index < text.len; index++) {
      ascii = ascii && text.ptr[index] < 0x80;
    }
    *lo = 0;
    *hi = text.len | ((uint64_t)MS_STRING_TAG_STATIC << MS_STRING_TAG_SHIFT) | (ascii ? MS_STRING_ASCII_FLAG : 0);
    return;
  }
  uint8_t words[16] = {0};
  for (size_t index = 0; index < text.len; index++) {
    words[index] = text.ptr[index];
  }
  uint64_t first = 0, second = 0;
  for (uint32_t index = 0; index < 8; index++) {
    first |= (uint64_t)words[index] << (8 * index);
    second |= (uint64_t)words[8 + index] << (8 * index);
  }
  *lo = first;
  *hi = second | ((uint64_t)MS_STRING_TAG_INLINE << MS_STRING_TAG_SHIFT) |
        ((uint64_t)text.len << MS_STRING_INLINE_SHIFT);
}

/* The bytes of every long literal a function uses, each followed by a NUL. */
static void visit_string(DataCx *cx, const MirFunc *func, const MirInst *inst) {
  (void)func;
  const uint32_t id = inst->imm.a;
  if (inst->op != MOP_StrLit || cx->data->strings.ptr[id] != MIR_NONE) {
    return;
  }
  const MsSpan text = ms_names_span(&cx->module->strings, id);
  if (text.len <= MS_STRING_INLINE_MAX) {
    return;
  }
  uint8_t *bytes = MS_ARENA_NEW_ARRAY(&cx->module->arena, uint8_t, text.len + 1);
  __builtin_memcpy(bytes, text.ptr, text.len);
  const MirDataSym sym = {.name = mird_name(cx, "lit", id),
                          .size = (uint32_t)text.len + 1,
                          .align = 1,
                          .bytes = ms_span_of(bytes, text.len + 1)};
  cx->data->strings.ptr[id] = mird_add_sym(cx, &sym);
}

/* The bytes of one constant list: each value in the width of the element's leaf, little-endian; a Float32
 * element holds the bits of a double that are narrowed. */
static MsSpan list_bytes(MirModule *module, MirLeaf leaf, const MirListConst *list) {
  const uint32_t width = mir_leaf_size(leaf);
  const size_t size = (size_t)width * list->count;
  uint8_t *bytes = MS_ARENA_NEW_ARRAY(&module->arena, uint8_t, size);
  for (uint32_t index = 0; index < list->count; index++) {
    uint64_t bits = (uint64_t)module->list_const_values.ptr[list->start + index];
    if (leaf == MIR_LEAF_F32) {
      double wide = 0;
      __builtin_memcpy(&wide, &bits, sizeof wide);
      const float narrow = (float)wide;
      uint32_t word = 0;
      __builtin_memcpy(&word, &narrow, sizeof word);
      bits = word;
    }
    for (uint32_t byte = 0; byte < width; byte++) {
      bytes[(size_t)index * width + byte] = (uint8_t)(bits >> (8 * byte));
    }
  }
  return ms_span_of(bytes, size);
}

static void visit_blob(DataCx *cx, const MirInst *inst) {
  const size_t id = (size_t)inst->imm.i;
  const MirModule *module = cx->module;
  if (id >= module->blobs.len || cx->data->blobs.ptr[id] != MIR_NONE || module->blobs.ptr[id].len == 0) {
    return;
  }
  const MirDataSym sym = {.name = mird_name(cx, "blob", (uint32_t)id),
                          .size = (uint32_t)module->blobs.ptr[id].len,
                          .align = 1,
                          .bytes = module->blobs.ptr[id]};
  cx->data->blobs.ptr[id] = mird_add_sym(cx, &sym);
}

static void visit_list(DataCx *cx, const MirFunc *func, const MirInst *inst) {
  const size_t id = (size_t)inst->imm.i;
  MirModule *module = cx->module;
  if (id >= module->list_consts.len || cx->data->list_consts.ptr[id] != MIR_NONE ||
      module->list_consts.ptr[id].count == 0) {
    return;
  }
  const MirTy elem = mir_ty_data(module, mir_value_ty(func, inst->res))->elem;
  const MsSpan leaves = mir_leaves(cx->layouts, elem);
  const MsSpan bytes = list_bytes(module, leaves.ptr[0], &module->list_consts.ptr[id]);
  const MirDataSym sym = {.name = mird_name(cx, "list", (uint32_t)id),
                          .size = (uint32_t)bytes.len,
                          .align = 16,
                          .bytes = bytes};
  cx->data->list_consts.ptr[id] = mird_add_sym(cx, &sym);
}

static void visit_constant(DataCx *cx, const MirFunc *func, const MirInst *inst) {
  if (inst->op == MOP_StrLit) {
    visit_string(cx, func, inst);
  } else if (inst->op == MOP_BytesLit) {
    visit_blob(cx, inst);
  } else if (inst->op == MOP_ListConst || inst->op == MOP_ListConstView) {
    visit_list(cx, func, inst);
  }
}

void mird_constants(DataCx *cx) {
  mird_fill_none(&cx->data->strings, ms_names_count(&cx->module->strings));
  mird_fill_none(&cx->data->blobs, cx->module->blobs.len);
  mird_fill_none(&cx->data->list_consts, cx->module->list_consts.len);
  mird_each_inst(cx, visit_constant);
}
