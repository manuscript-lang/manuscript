/* Owns the string byte operations and constant byte and list data. A string is two words: the address (or,
 * inline, its first eight bytes) and the tagged word: bit 63 static, bit 62 inline, bit 61 ASCII, an inline
 * length in bits 56 to 59, a long string's byte length in the low 31 bits. */
#include "compiler/emit/emit_cx.h"

#include "abi/layout.h"

#define STRING_STATIC_WORD ((uint64_t)MS_STRING_TAG_STATIC << MS_STRING_TAG_SHIFT)

/* Writes `%o<n>i` = whether the string is inline (kind bits 01). */
static void string_is_inline(EmitCx *cx, uint32_t number, MirValue text) {
  ms_strbuild_printf(cx->out, "  %%o%uk = lshr i64 %%v%u.1, %d\n  %%o%ui = icmp eq i64 %%o%uk, %u\n", number, text,
                     MS_STRING_TAG_SHIFT, number, number, MS_STRING_TAG_INLINE);
}

/* `str.bytes`: the byte length, from the inline length bits or the long length bits. */
static void string_bytes(EmitCx *cx, const MirInst *inst) {
  uint32_t number = cx->next++;
  MirValue text = inst->args[0];
  string_is_inline(cx, number, text);
  ms_strbuild_printf(cx->out,
                     "  %%o%us = lshr i64 %%v%u.1, %d\n  %%o%ush = and i64 %%o%us, %d\n"
                     "  %%o%ul = and i64 %%v%u.1, %llu\n"
                     "  %%v%u = select i1 %%o%ui, i64 %%o%ush, i64 %%o%ul\n",
                     number, text, MS_STRING_INLINE_SHIFT, number, number, MS_STRING_INLINE_MAX, number, text,
                     (unsigned long long)MS_STRING_LENGTH_MASK, inst->res, number, number, number);
}

/* `str.ascii_len`: the byte length when the string is known to be ASCII (an inline string with no byte of 0x80
 * or more, or one flagged ASCII), else -1. */
static void string_ascii_len(EmitCx *cx, const MirInst *inst) {
  MsStrBuild *out = cx->out;
  uint32_t number = cx->next++;
  MirValue text = inst->args[0];
  string_is_inline(cx, number, text);
  ms_strbuild_printf(out,
                     "  %%o%uh0 = and i64 %%v%u, %lld\n  %%o%uh1 = and i64 %%v%u.1, %lld\n"
                     "  %%o%uh = or i64 %%o%uh0, %%o%uh1\n",
                     number, text, (long long)0x8080808080808080ULL, number, text, 0x0080808080808080LL, number,
                     number, number);
  ms_strbuild_printf(out,
                     "  %%o%ulow = icmp eq i64 %%o%uh, 0\n  %%o%us = lshr i64 %%v%u.1, %d\n"
                     "  %%o%ush = and i64 %%o%us, %d\n",
                     number, number, number, text, MS_STRING_INLINE_SHIFT, number, number, MS_STRING_INLINE_MAX);
  ms_strbuild_printf(out, "  %%o%uil = select i1 %%o%ulow, i64 %%o%ush, i64 -1\n", number, number, number);
  ms_strbuild_printf(out,
                     "  %%o%uf = lshr i64 %%v%u.1, 61\n  %%o%uf3 = and i64 %%o%uf, 3\n"
                     "  %%o%ufl = icmp eq i64 %%o%uf3, 1\n",
                     number, text, number, number, number, number);
  ms_strbuild_printf(out, "  %%o%ulen = and i64 %%v%u.1, %llu\n  %%o%uot = select i1 %%o%ufl, i64 %%o%ulen, i64 -1\n",
                     number, text, (unsigned long long)MS_STRING_LENGTH_MASK, number, number, number);
  ms_strbuild_printf(out, "  %%v%u = select i1 %%o%ui, i64 %%o%uil, i64 %%o%uot\n", inst->res, number, number, number);
}

/* `str.ascii`: the shared one-byte string of byte `b` (a table of two bytes each). */
static void string_ascii(EmitCx *cx, const MirInst *inst) {
  uint32_t number = cx->next++;
  ms_strbuild_printf(cx->out,
                     "  %%o%ud = mul i64 %%v%u, 2\n  %%o%ub = ptrtoint ptr @msrt_ascii_chars to i64\n"
                     "  %%v%u = add i64 %%o%ub, %%o%ud\n  %%v%u.1 = add i64 0, %lld\n",
                     number, inst->args[0], number, inst->res, number, number, inst->res,
                     (long long)(STRING_STATIC_WORD | 1));
}

/* `str.byte`: byte `i`. An inline string's bytes are its two words, so they are first written to a frame slot
 * and read from there; any other string is read at its address. */
static void string_byte(EmitCx *cx, const MirInst *inst, const EmitSite *site) {
  uint32_t number = cx->next++;
  MirValue text = inst->args[0];
  uint32_t block = site->block;
  uint32_t index = site->index;
  ms_strbuild_printf(cx->out,
                     "  store i64 %%v%u, ptr %%y%u_%u\n  %%o%ua = getelementptr i8, ptr %%y%u_%u, i64 8\n"
                     "  store i64 %%v%u.1, ptr %%o%ua\n",
                     text, block, index, number, block, index, text, number);
  string_is_inline(cx, number, text);
  ms_strbuild_printf(cx->out,
                     "  %%o%uy = ptrtoint ptr %%y%u_%u to i64\n  %%o%ub = select i1 %%o%ui, i64 %%o%uy, i64 %%v%u\n"
                     "  %%o%ua2 = add i64 %%o%ub, %%v%u\n  %%o%up = inttoptr i64 %%o%ua2 to ptr\n"
                     "  %%o%uq = load i8, ptr %%o%up\n  %%v%u = zext i8 %%o%uq to i64\n",
                     number, block, index, number, number, number, text, number, number, inst->args[1], number,
                     number, number, number, inst->res, number);
}

/* `bytes.push`: appends byte `v` to the builder at the address in the first operand when it is a byte and there
 * is room; the result says whether it did. The store is a block of its own. */
static void bytes_push(EmitCx *cx, const MirInst *inst, const EmitSite *site) {
  MsStrBuild *out = cx->out;
  uint32_t number = cx->next++;
  MirValue builder = inst->args[0];
  MirValue byte = inst->args[1];
  const char *type = emit_value_register_type(cx, byte);
  bool is_bit = type[0] == 'i' && type[1] == '1' && type[2] == 0;
  ms_strbuild_printf(out,
                     "  %%o%ul = add i64 %%v%u, 8\n  %%o%ulp = inttoptr i64 %%o%ul to ptr\n"
                     "  %%o%unl = load i64, ptr %%o%ulp\n  %%o%uc = add i64 %%v%u, 16\n"
                     "  %%o%ucq = inttoptr i64 %%o%uc to ptr\n  %%o%ucp = load i64, ptr %%o%ucq\n",
                     number, builder, number, number, number, number, number, builder, number, number, number,
                     number);
  ms_strbuild_printf(out,
                     "  %%o%uby = icmp ule %s %%v%u, 255\n  %%o%urm = icmp ult i64 %%o%unl, %%o%ucp\n"
                     "  %%v%u = and i1 %%o%uby, %%o%urm\n",
                     number, type, byte, number, number, number, inst->res, number, number);
  ms_strbuild_printf(out, "  br i1 %%v%u, label %%ls%u, label %%", inst->res, number);
  *site->part += 1;
  emit_label(out, site->block, *site->part);
  ms_strbuild_printf(out, "\nls%u:\n  %%o%udp = inttoptr i64 %%v%u to ptr\n  %%o%ud = load i64, ptr %%o%udp\n", number,
                     number, builder, number, number);
  ms_strbuild_printf(out,
                     "  %%o%ua = add i64 %%o%ud, %%o%unl\n  %%o%uap = inttoptr i64 %%o%ua to ptr\n"
                     "  %%o%ubt = %s %s %%v%u to i8\n",
                     number, number, number, number, number, number, is_bit ? "bitcast" : "trunc", type, byte);
  ms_strbuild_printf(out,
                     "  store i8 %%o%ubt, ptr %%o%uap\n  %%o%uu = add i64 %%o%unl, 1\n"
                     "  store i64 %%o%uu, ptr %%o%ulp\n  br label %%",
                     number, number, number, number, number, number);
  emit_label(out, site->block, *site->part);
  ms_strbuild_append_byte(out, '\n');
  emit_label(out, site->block, *site->part);
  ms_strbuild_append_text(out, ":\n");
}

/* `bytes`, `list.const`, `list.const.view`: constant data. The view and the bytes borrow it (capacity 0,
 * nothing frees them); `list.const` copies it into a fresh block. */
static bool const_data(EmitCx *cx, const MirInst *inst) {
  MsStrBuild *out = cx->out;
  uint32_t id = (uint32_t)inst->imm.i;
  bool is_bytes = inst->op == MOP_BytesLit;
  uint32_t count = is_bytes ? (uint32_t)cx->module->blobs.ptr[id].len : cx->module->list_consts.ptr[id].count;
  if (count == 0) {
    ms_strbuild_printf(out, "  %%v%u = add i64 0, 0\n  %%v%u.1 = add i64 0, 0\n  %%v%u.2 = add i64 0, 0\n", inst->res,
                       inst->res, inst->res);
    return true;
  }
  uint32_t symbol = MIR_NONE;
  if (cx->data != NULL) {
    symbol = is_bytes ? cx->data->blobs.ptr[id] : cx->data->list_consts.ptr[id];
  }
  if (symbol == MIR_NONE) {
    cx->why = "constant data without a symbol";
    return false;
  }
  uint32_t number = cx->next++;
  ms_strbuild_printf(out, "  %%t%u = ptrtoint ptr ", number);
  emit_symbol(out, cx->data->syms.ptr[symbol].name);
  ms_strbuild_append_text(out, " to i64\n");
  if (inst->op == MOP_ListConst) {
    uint32_t size = count * mir_list_elem_size(cx->layouts, emit_value_type(cx, inst->res));
    ms_strbuild_printf(out,
                       "  %%v%u = call i64 @msrt_alloc(i64 %u)\n  %%d%u = inttoptr i64 %%v%u to ptr\n"
                       "  %%cs%u = inttoptr i64 %%t%u to ptr\n",
                       inst->res, size, number, inst->res, number, number);
    ms_strbuild_printf(out, "  call void @llvm.memcpy.p0.p0.i64(ptr %%d%u, ptr %%cs%u, i64 %u, i1 false)\n", number,
                       number, size);
    ms_strbuild_printf(out, "  %%v%u.1 = add i64 0, %u\n  %%v%u.2 = add i64 0, %u\n", inst->res, count, inst->res,
                       count);
    return true;
  }
  ms_strbuild_printf(out, "  %%v%u = add i64 %%t%u, 0\n  %%v%u.1 = add i64 0, %u\n  %%v%u.2 = add i64 0, 0\n", inst->res,
                     number, inst->res, count, inst->res);
  return true;
}

bool emit_string_op(EmitCx *cx, const MirInst *inst, const EmitSite *site, bool *handled) {
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
    string_byte(cx, inst, site);
    return true;
  case MOP_BytesLit:
  case MOP_ListConst:
  case MOP_ListConstView:
    return const_data(cx, inst);
  case MOP_OptViewAt:
  case MOP_OptAddr:
    emit_copy_leaf(cx, inst->res, 0, inst->args[0], 0);
    return true;
  case MOP_BytesPush:
    bytes_push(cx, inst, site);
    return true;
  default:
    *handled = false;
    return true;
  }
}
