/* Owns the string byte operations and constant byte and list data. A string is two words: the address (or, inline,
 * its first eight bytes) and the tagged word: bit 63 static, bit 62 inline, bit 61 ASCII, an inline length in bits 56
 * to 59, a long string's byte length in the low 31 bits. */
#include "compiler/emit_cl/cl_cx.h"

#include "abi/layout.h"

#define STRING_STATIC_WORD ((uint64_t)MS_STRING_TAG_STATIC << MS_STRING_TAG_SHIFT)

static ms_cl_val kind_is_inline(ClCx *cx, MirValue text) {
  ms_cl_fn *f = cx->fb;
  return ms_cl_icmp(f, MS_CL_EQ, ms_cl_ushr(f, cl_get(cx, text, 1), cl_const(cx, MS_STRING_TAG_SHIFT)),
                    cl_const(cx, MS_STRING_TAG_INLINE));
}

static ms_cl_val inline_length(ClCx *cx, MirValue text) {
  ms_cl_fn *f = cx->fb;
  return ms_cl_band(f, ms_cl_ushr(f, cl_get(cx, text, 1), cl_const(cx, MS_STRING_INLINE_SHIFT)),
                    cl_const(cx, MS_STRING_INLINE_MAX));
}

static ms_cl_val long_length(ClCx *cx, MirValue text) {
  return ms_cl_band(cx->fb, cl_get(cx, text, 1), cl_const(cx, (int64_t)MS_STRING_LENGTH_MASK));
}

/* `str.bytes`: the byte length, from the inline length bits or the long length bits. */
static void string_bytes(ClCx *cx, const MirInst *inst) {
  const MirValue text = inst->args[0];
  cl_set(cx, inst->res, 0, ms_cl_select(cx->fb, kind_is_inline(cx, text), inline_length(cx, text), long_length(cx, text)));
}

/* `str.ascii_len`: the byte length when the string is known to be ASCII (an inline string with no byte of 0x80 or
 * more, or one flagged ASCII), else -1. */
static void string_ascii_len(ClCx *cx, const MirInst *inst) {
  ms_cl_fn *f = cx->fb;
  const MirValue text = inst->args[0];
  ms_cl_val high = ms_cl_bor(f, ms_cl_band(f, cl_get(cx, text, 0), cl_const(cx, (int64_t)0x8080808080808080ULL)),
                             ms_cl_band(f, cl_get(cx, text, 1), cl_const(cx, 0x0080808080808080LL)));
  ms_cl_val clean = ms_cl_icmp(f, MS_CL_EQ, high, cl_const(cx, 0));
  ms_cl_val inline_len = ms_cl_select(f, clean, inline_length(cx, text), cl_const(cx, -1));
  ms_cl_val flags = ms_cl_band(f, ms_cl_ushr(f, cl_get(cx, text, 1), cl_const(cx, 61)), cl_const(cx, 3));
  ms_cl_val flagged = ms_cl_icmp(f, MS_CL_EQ, flags, cl_const(cx, 1));
  ms_cl_val other = ms_cl_select(f, flagged, long_length(cx, text), cl_const(cx, -1));
  cl_set(cx, inst->res, 0, ms_cl_select(f, kind_is_inline(cx, text), inline_len, other));
}

/* `str.ascii`: the shared one-byte string of byte `b` (a table of two bytes each). */
static void string_ascii(ClCx *cx, const MirInst *inst) {
  ms_cl_fn *f = cx->fb;
  const MirRef table = {.kind = MREF_RUNTIME, .runtime = ms_span_of_text("msrt_ascii_chars")};
  cl_set(cx, inst->res, 0, ms_cl_iadd(f, cl_ref_address(cx, table), ms_cl_imul(f, cl_arg(cx, inst, 0), cl_const(cx, 2))));
  cl_set(cx, inst->res, 1, cl_const(cx, (int64_t)(STRING_STATIC_WORD | 1)));
}

/* The address of the bytes of `text`: an inline string's bytes are its two words, written to the 16 bytes at `cell`
 * first; any other string is read at its address. */
static ms_cl_val text_address(ClCx *cx, MirValue text, ms_cl_val cell) {
  ms_cl_fn *f = cx->fb;
  ms_cl_store(f, MS_CL_NOTRAP, cl_get(cx, text, 0), cell, 0);
  ms_cl_store(f, MS_CL_NOTRAP, cl_get(cx, text, 1), cell, 8);
  return ms_cl_select(f, kind_is_inline(cx, text), cell, cl_get(cx, text, 0));
}

static ms_cl_val text_cell(ClCx *cx) {
  return ms_cl_stack_addr(cx->fb, ms_cl_stack_slot(cx->fb, 16, 3), 0);
}

/* `str.byte`: byte `i`. The cell is used at once, so every `str.byte` could share one. */
static void string_byte(ClCx *cx, const MirInst *inst) {
  ms_cl_fn *f = cx->fb;
  const ms_cl_val base = text_address(cx, inst->args[0], text_cell(cx));
  cl_set(cx, inst->res, 0,
         ms_cl_load_ext(f, 8, 0, MS_CL_I64, MS_CL_NOTRAP, ms_cl_iadd(f, base, cl_arg(cx, inst, 1)), 0));
}

/* `str.data`: the address of the bytes, in a cell of the frame of its own: the address may be kept. */
static void string_data(ClCx *cx, const MirInst *inst) {
  cl_set(cx, inst->res, 0, text_address(cx, inst->args[0], text_cell(cx)));
}

/* `bytes.push`: appends byte `v` to the builder at the address in the first operand when it is a byte and there is
 * room; the result says whether it did. */
static void bytes_push(ClCx *cx, const MirInst *inst) {
  ms_cl_fn *f = cx->fb;
  const ms_cl_val builder = cl_arg(cx, inst, 0);
  ms_cl_val byte = cl_arg(cx, inst, 1);
  if (cl_value_reg_type(cx, inst->args[1]) == MS_CL_I8) {
    byte = ms_cl_cast(f, MS_CL_UEXTEND, MS_CL_I64, byte);
  }
  const ms_cl_val length = ms_cl_load(f, MS_CL_I64, MS_CL_NOTRAP, builder, 8);
  const ms_cl_val capacity = ms_cl_load(f, MS_CL_I64, MS_CL_NOTRAP, builder, 16);
  const ms_cl_val fits = ms_cl_band(f, ms_cl_icmp(f, MS_CL_ULE, byte, cl_const(cx, 255)),
                                    ms_cl_icmp(f, MS_CL_ULT, length, capacity));
  cl_set(cx, inst->res, 0, fits);
  const ClIf branch = cl_if_begin(cx, fits, 0);
  ms_cl_val data = ms_cl_load(f, MS_CL_I64, MS_CL_NOTRAP, builder, 0);
  ms_cl_store_trunc(f, 8, MS_CL_NOTRAP, byte, ms_cl_iadd(f, data, length), 0);
  ms_cl_store(f, MS_CL_NOTRAP, ms_cl_iadd(f, length, cl_const(cx, 1)), builder, 8);
  ms_cl_val joined[CL_IF_WORDS];
  cl_if_end(cx, &branch, NULL, joined);
}

/* `bytes`, `list.const`, `list.const.view`: constant data. The view and the bytes borrow it (capacity 0, nothing
 * frees them); `list.const` copies it into a fresh block. */
static bool const_data(ClCx *cx, const MirInst *inst) {
  const uint32_t id = (uint32_t)inst->imm.i;
  const bool is_bytes = inst->op == MOP_BytesLit;
  const uint32_t count = is_bytes ? (uint32_t)cx->module->blobs.ptr[id].len : cx->module->list_consts.ptr[id].count;
  if (count == 0) {
    for (uint32_t leaf = 0; leaf < 3; leaf++) {
      cl_set(cx, inst->res, leaf, cl_const(cx, 0));
    }
    return true;
  }
  uint32_t symbol = MIR_NONE;
  if (cx->mod->data != NULL) {
    symbol = is_bytes ? cx->mod->data->blobs.ptr[id] : cx->mod->data->list_consts.ptr[id];
  }
  if (symbol == MIR_NONE) {
    cx->why = "constant data without a symbol";
    return false;
  }
  const ms_cl_val source = ms_cl_data_addr(cx->fb, cx->mod->syms[symbol]);
  if (inst->op == MOP_ListConst) {
    const uint32_t size = count * mir_list_elem_size(cx->layouts, cl_value_type(cx, inst->res));
    const ms_cl_val block = cl_alloc(cx, size);
    ms_cl_copy(cx->fb, block, source, size);
    cl_set(cx, inst->res, 0, block);
    cl_set(cx, inst->res, 2, cl_const(cx, count));
  } else {
    cl_set(cx, inst->res, 0, source);
    cl_set(cx, inst->res, 2, cl_const(cx, 0));
  }
  cl_set(cx, inst->res, 1, cl_const(cx, count));
  return true;
}

bool cl_string_op(ClCx *cx, const MirInst *inst, bool *handled) {
  *handled = true;
  switch ((MirOp)inst->op) {
  case MOP_StrBytes:
    string_bytes(cx, inst);
    return true;
  case MOP_StrAsciiLen:
    string_ascii_len(cx, inst);
    return true;
  case MOP_StrAscii:
    string_ascii(cx, inst);
    return true;
  case MOP_StrByte:
    string_byte(cx, inst);
    return true;
  case MOP_StrData:
    string_data(cx, inst);
    return true;
  case MOP_MemCopy:
    ms_cl_copy_dyn(cx->fb, cl_arg(cx, inst, 0), cl_arg(cx, inst, 1), cl_arg(cx, inst, 2));
    return true;
  case MOP_BytesLit:
  case MOP_ListConst:
  case MOP_ListConstView:
    return const_data(cx, inst);
  case MOP_OptViewAt:
  case MOP_OptAddr:
    cl_copy_leaf(cx, inst->res, 0, inst->args[0], 0);
    return true;
  case MOP_BytesPush:
    bytes_push(cx, inst);
    return true;
  default:
    *handled = false;
    return true;
  }
}
