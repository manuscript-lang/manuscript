/* Owns the string byte operations and constant byte and list data. A string is two words: the address (or, inline,
 * its first eight bytes) and the tagged word: bit 63 static, bit 62 inline, bit 61 ASCII, an inline length in bits 56
 * to 59, a long string's byte length in the low 31 bits. */
#include "compiler/emit_cl/cl_cx.h"

#include "abi/layout.h"

#define STRING_STATIC_WORD ((uint64_t)MS_STRING_TAG_STATIC << MS_STRING_TAG_SHIFT)

static cl_val kind_is_inline(ClCx *cx, MirValue text) {
  cl_fn *f = cx->fb;
  return cl_icmp(f, CL_EQ, cl_ushr(f, clx_get(cx, text, 1), clx_const(cx, MS_STRING_TAG_SHIFT)),
                    clx_const(cx, MS_STRING_TAG_INLINE));
}

static cl_val inline_length(ClCx *cx, MirValue text) {
  cl_fn *f = cx->fb;
  return cl_band(f, cl_ushr(f, clx_get(cx, text, 1), clx_const(cx, MS_STRING_INLINE_SHIFT)),
                    clx_const(cx, MS_STRING_INLINE_MAX));
}

static cl_val long_length(ClCx *cx, MirValue text) {
  return cl_band(cx->fb, clx_get(cx, text, 1), clx_const(cx, (int64_t)MS_STRING_LENGTH_MASK));
}

/* `str.bytes`: the byte length, from the inline length bits or the long length bits. */
static void string_bytes(ClCx *cx, const MirInst *inst) {
  const MirValue text = inst->args[0];
  clx_set(cx, inst->res, 0, cl_select(cx->fb, kind_is_inline(cx, text), inline_length(cx, text), long_length(cx, text)));
}

/* `str.ascii_len`: the byte length when the string is known to be ASCII (an inline string with no byte of 0x80 or
 * more, or one flagged ASCII), else -1. */
static void string_ascii_len(ClCx *cx, const MirInst *inst) {
  cl_fn *f = cx->fb;
  const MirValue text = inst->args[0];
  cl_val high = cl_bor(f, cl_band(f, clx_get(cx, text, 0), clx_const(cx, (int64_t)0x8080808080808080ULL)),
                             cl_band(f, clx_get(cx, text, 1), clx_const(cx, 0x0080808080808080LL)));
  cl_val clean = cl_icmp(f, CL_EQ, high, clx_const(cx, 0));
  cl_val inline_len = cl_select(f, clean, inline_length(cx, text), clx_const(cx, -1));
  cl_val flags = cl_band(f, cl_ushr(f, clx_get(cx, text, 1), clx_const(cx, 61)), clx_const(cx, 3));
  cl_val flagged = cl_icmp(f, CL_EQ, flags, clx_const(cx, 1));
  cl_val other = cl_select(f, flagged, long_length(cx, text), clx_const(cx, -1));
  clx_set(cx, inst->res, 0, cl_select(f, kind_is_inline(cx, text), inline_len, other));
}

/* `str.ascii`: the shared one-byte string of byte `b` (a table of two bytes each). */
static void string_ascii(ClCx *cx, const MirInst *inst) {
  cl_fn *f = cx->fb;
  const MirRef table = {.kind = MREF_RUNTIME, .runtime = ms_span_of_text("msrt_ascii_chars")};
  clx_set(cx, inst->res, 0, cl_iadd(f, clx_ref_address(cx, table), cl_imul(f, clx_arg(cx, inst, 0), clx_const(cx, 2))));
  clx_set(cx, inst->res, 1, clx_const(cx, (int64_t)(STRING_STATIC_WORD | 1)));
}

/* The address of the bytes of `text`: an inline string's bytes are its two words, written to the 16 bytes at `cell`
 * first; any other string is read at its address. */
static cl_val text_address(ClCx *cx, MirValue text, cl_val cell) {
  cl_fn *f = cx->fb;
  cl_store(f, CL_NOTRAP, clx_get(cx, text, 0), cell, 0);
  cl_store(f, CL_NOTRAP, clx_get(cx, text, 1), cell, 8);
  return cl_select(f, kind_is_inline(cx, text), cell, clx_get(cx, text, 0));
}

static cl_val text_cell(ClCx *cx) {
  return cl_stack_addr(cx->fb, cl_stack_slot(cx->fb, 16, 3), 0);
}

/* `str.byte`: byte `i`. The cell is used at once, so every `str.byte` could share one. */
static void string_byte(ClCx *cx, const MirInst *inst) {
  cl_fn *f = cx->fb;
  const cl_val base = text_address(cx, inst->args[0], text_cell(cx));
  clx_set(cx, inst->res, 0,
         cl_load_ext(f, 8, 0, CL_I64, CL_NOTRAP, cl_iadd(f, base, clx_arg(cx, inst, 1)), 0));
}

/* `str.data`: the address of the bytes, in a cell of the frame of its own: the address may be kept. */
static void string_data(ClCx *cx, const MirInst *inst) {
  clx_set(cx, inst->res, 0, text_address(cx, inst->args[0], text_cell(cx)));
}

/* `bytes.push`: appends byte `v` to the builder at the address in the first operand when it is a byte and there is
 * room; the result says whether it did. */
static void bytes_push(ClCx *cx, const MirInst *inst) {
  cl_fn *f = cx->fb;
  const cl_val builder = clx_arg(cx, inst, 0);
  cl_val byte = clx_arg(cx, inst, 1);
  if (clx_value_reg_type(cx, inst->args[1]) == CL_I8) {
    byte = cl_cast(f, CL_UEXTEND, CL_I64, byte);
  }
  const cl_val length = cl_load(f, CL_I64, CL_NOTRAP, builder, 8);
  const cl_val capacity = cl_load(f, CL_I64, CL_NOTRAP, builder, 16);
  const cl_val fits = cl_band(f, cl_icmp(f, CL_ULE, byte, clx_const(cx, 255)),
                                    cl_icmp(f, CL_ULT, length, capacity));
  clx_set(cx, inst->res, 0, fits);
  const ClIf branch = clx_if_begin(cx, fits, 0);
  cl_val data = cl_load(f, CL_I64, CL_NOTRAP, builder, 0);
  cl_store_trunc(f, 8, CL_NOTRAP, byte, cl_iadd(f, data, length), 0);
  cl_store(f, CL_NOTRAP, cl_iadd(f, length, clx_const(cx, 1)), builder, 8);
  cl_val joined[CLX_IF_WORDS];
  clx_if_end(cx, &branch, NULL, joined);
}

/* `bytes`, `list.const`, `list.const.view`: constant data. The view and the bytes borrow it (capacity 0, nothing
 * frees them); `list.const` copies it into a fresh block. */
static bool const_data(ClCx *cx, const MirInst *inst) {
  const uint32_t id = (uint32_t)inst->imm.i;
  const bool is_bytes = inst->op == MOP_BytesLit;
  const uint32_t count = is_bytes ? (uint32_t)cx->module->blobs.ptr[id].len : cx->module->list_consts.ptr[id].count;
  if (count == 0) {
    for (uint32_t leaf = 0; leaf < 3; leaf++) {
      clx_set(cx, inst->res, leaf, clx_const(cx, 0));
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
  const cl_val source = cl_data_addr(cx->fb, cx->mod->syms[symbol]);
  if (inst->op == MOP_ListConst) {
    const uint32_t size = count * mir_list_elem_size(cx->layouts, clx_value_type(cx, inst->res));
    const cl_val block = clx_alloc(cx, size);
    cl_copy(cx->fb, block, source, size);
    clx_set(cx, inst->res, 0, block);
    clx_set(cx, inst->res, 2, clx_const(cx, count));
  } else {
    clx_set(cx, inst->res, 0, source);
    clx_set(cx, inst->res, 2, clx_const(cx, 0));
  }
  clx_set(cx, inst->res, 1, clx_const(cx, count));
  return true;
}

bool clx_string_op(ClCx *cx, const MirInst *inst, bool *handled) {
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
    cl_copy_dyn(cx->fb, clx_arg(cx, inst, 0), clx_arg(cx, inst, 1), clx_arg(cx, inst, 2));
    return true;
  case MOP_BytesLit:
  case MOP_ListConst:
  case MOP_ListConstView:
    return const_data(cx, inst);
  case MOP_OptViewAt:
  case MOP_OptAddr:
    clx_copy_leaf(cx, inst->res, 0, inst->args[0], 0);
    return true;
  case MOP_BytesPush:
    bytes_push(cx, inst);
    return true;
  default:
    *handled = false;
    return true;
  }
}
