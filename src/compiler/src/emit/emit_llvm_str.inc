/* String byte operations for emit_llvm.c (included from it). A string is two words: the address (or,
 * inline, its first eight bytes) and the tagged word: bit 63 static, bit 62 inline, bit 61 ASCII, an
 * inline length in bits 56 to 59, a long string's byte length in the low 31 bits. */

#define LL_STR_LEN_MASK 0x7fffffffLL

/* Writes `%o<n>i` = whether the string is inline (kind bits 01). */
static void ll_str_is_inline(LCx *c, uint32_t n, MirValue s) {
    ms_buf_printf(c->out, "  %%o%uk = lshr i64 %%v%u.1, 62\n  %%o%ui = icmp eq i64 %%o%uk, 1\n", n, s, n, n);
}

/* `str.bytes`: the byte length, from the inline length bits or the long length bits. */
static void ll_str_bytes(LCx *c, const MirInst *inst) {
    const uint32_t n = c->next++;
    const MirValue s = inst->args[0];
    ll_str_is_inline(c, n, s);
    ms_buf_printf(c->out,
                  "  %%o%us = lshr i64 %%v%u.1, %d\n  %%o%ush = and i64 %%o%us, %d\n  %%o%ul = and i64 %%v%u.1, %lld\n"
                  "  %%v%u = select i1 %%o%ui, i64 %%o%ush, i64 %%o%ul\n",
                  n, s, MIR_STR_INLINE_SHIFT, n, n, MIR_STR_INLINE_MAX, n, s, LL_STR_LEN_MASK, inst->res, n, n, n);
}

/* `str.ascii_len`: the byte length when the string is known to be ASCII (an inline string with no
 * byte of 0x80 or more, or one flagged ASCII), else -1. */
static void ll_str_ascii_len(LCx *c, const MirInst *inst) {
    MsBuf *o = c->out;
    const uint32_t n = c->next++;
    const MirValue s = inst->args[0];
    ll_str_is_inline(c, n, s);
    ms_buf_printf(o, "  %%o%uh0 = and i64 %%v%u, %lld\n  %%o%uh1 = and i64 %%v%u.1, %lld\n  %%o%uh = or i64 %%o%uh0, %%o%uh1\n",
                  n, s, (long long)0x8080808080808080ULL, n, s, 0x0080808080808080LL, n, n, n);
    ms_buf_printf(o, "  %%o%ulow = icmp eq i64 %%o%uh, 0\n  %%o%us = lshr i64 %%v%u.1, %d\n  %%o%ush = and i64 %%o%us, %d\n", n,
                  n, n, s, MIR_STR_INLINE_SHIFT, n, n, MIR_STR_INLINE_MAX);
    ms_buf_printf(o, "  %%o%uil = select i1 %%o%ulow, i64 %%o%ush, i64 -1\n", n, n, n);
    ms_buf_printf(o, "  %%o%uf = lshr i64 %%v%u.1, 61\n  %%o%uf3 = and i64 %%o%uf, 3\n  %%o%ufl = icmp eq i64 %%o%uf3, 1\n", n, s,
                  n, n, n, n);
    ms_buf_printf(o, "  %%o%ulen = and i64 %%v%u.1, %lld\n  %%o%uot = select i1 %%o%ufl, i64 %%o%ulen, i64 -1\n", n, s,
                  LL_STR_LEN_MASK, n, n, n);
    ms_buf_printf(o, "  %%v%u = select i1 %%o%ui, i64 %%o%uil, i64 %%o%uot\n", inst->res, n, n, n);
}

/* `str.ascii`: the shared one-byte string of byte `b` (a table of two bytes each). */
static void ll_str_ascii(LCx *c, const MirInst *inst) {
    const uint32_t n = c->next++;
    ms_buf_printf(c->out,
                  "  %%o%ud = mul i64 %%v%u, 2\n  %%o%ub = ptrtoint ptr @msrt_ascii_chars to i64\n  %%v%u = add i64 %%o%ub, %%o%ud\n"
                  "  %%v%u.1 = add i64 0, %lld\n",
                  n, inst->args[0], n, inst->res, n, n, inst->res, (long long)(MIR_STR_STATIC | 1));
}

/* `str.byte`: byte `i`. An inline string's bytes are its two words, so they are first written to a
 * frame slot and read from there; any other string is read at its address. */
static void ll_str_byte(LCx *c, const MirInst *inst, uint32_t block, uint32_t index) {
    const uint32_t n = c->next++;
    const MirValue s = inst->args[0];
    ms_buf_printf(c->out,
                  "  store i64 %%v%u, ptr %%y%u_%u\n  %%o%ua = getelementptr i8, ptr %%y%u_%u, i64 8\n  store i64 %%v%u.1, ptr %%o%ua\n",
                  s, block, index, n, block, index, s, n);
    ll_str_is_inline(c, n, s);
    ms_buf_printf(c->out,
                  "  %%o%uy = ptrtoint ptr %%y%u_%u to i64\n  %%o%ub = select i1 %%o%ui, i64 %%o%uy, i64 %%v%u\n"
                  "  %%o%ua2 = add i64 %%o%ub, %%v%u\n  %%o%up = inttoptr i64 %%o%ua2 to ptr\n  %%o%uq = load i8, ptr %%o%up\n"
                  "  %%v%u = zext i8 %%o%uq to i64\n",
                  n, block, index, n, n, n, s, n, n, inst->args[1], n, n, n, n, inst->res, n);
}

/* `bytes.push`: appends byte `v` to the builder at the address in the first operand when it is a
 * byte and there is room; the result says whether it did. The store is a block of its own. */
static void ll_bytes_push(LCx *c, const MirInst *inst, uint32_t block, uint32_t *part) {
    MsBuf *o = c->out;
    const uint32_t n = c->next++;
    const MirValue b = inst->args[0], v = inst->args[1];
    ms_buf_printf(o,
                  "  %%o%ul = add i64 %%v%u, 8\n  %%o%ulp = inttoptr i64 %%o%ul to ptr\n  %%o%unl = load i64, ptr %%o%ulp\n"
                  "  %%o%uc = add i64 %%v%u, 16\n  %%o%ucq = inttoptr i64 %%o%uc to ptr\n  %%o%ucp = load i64, ptr %%o%ucq\n",
                  n, b, n, n, n, n, n, b, n, n, n, n);
    ms_buf_printf(o, "  %%o%uby = icmp ule %s %%v%u, 255\n  %%o%urm = icmp ult i64 %%o%unl, %%o%ucp\n  %%v%u = and i1 %%o%uby, %%o%urm\n",
                  n, ll_vty(c, v), v, n, n, n, inst->res, n, n);
    ms_buf_printf(o, "  br i1 %%v%u, label %%ls%u, label %%", inst->res, n);
    (*part)++;
    ll_label(c, block, *part);
    ms_buf_printf(o, "\nls%u:\n  %%o%udp = inttoptr i64 %%v%u to ptr\n  %%o%ud = load i64, ptr %%o%udp\n", n, n, b, n, n);
    ms_buf_printf(o, "  %%o%ua = add i64 %%o%ud, %%o%unl\n  %%o%uap = inttoptr i64 %%o%ua to ptr\n  %%o%ubt = %s %s %%v%u to i8\n", n, n,
                  n, n, n, n, strcmp(ll_vty(c, v), "i8") == 0 ? "bitcast" : "trunc", ll_vty(c, v), v);
    ms_buf_printf(o, "  store i8 %%o%ubt, ptr %%o%uap\n  %%o%uu = add i64 %%o%unl, 1\n  store i64 %%o%uu, ptr %%o%ulp\n  br label %%", n, n, n, n,
                  n, n);
    ll_label(c, block, *part);
    ms_buf_putc(o, '\n');
    ll_label(c, block, *part);
    ms_buf_puts(o, ":\n");
}

/* `bytes`, `list.const`, `list.const.view`: constant data. The view and the bytes borrow it (capacity
 * 0, nothing frees them); `list.const` copies it into a fresh block. */
static bool ll_const_data(LCx *c, const MirInst *inst) {
    MsBuf *o = c->out;
    const uint32_t id = (uint32_t)inst->imm.i;
    const bool bytes = inst->op == MOP_BytesLit;
    const uint32_t n = bytes ? c->m->blobs[id].len : c->m->list_consts[id].n;
    if (n == 0) {
        ms_buf_printf(o, "  %%v%u = add i64 0, 0\n  %%v%u.1 = add i64 0, 0\n  %%v%u.2 = add i64 0, 0\n", inst->res,
                      inst->res, inst->res);
        return true;
    }
    uint32_t sym = MIR_NONE;
    if (c->data != NULL) sym = bytes ? c->data->blobs[id] : c->data->list_consts[id];
    if (sym == MIR_NONE) {
        c->why = "constant data without a symbol";
        return false;
    }
    const uint32_t t = c->next++;
    ms_buf_printf(o, "  %%t%u = ptrtoint ptr ", t);
    ll_data_name(o, c->data->syms[sym].name);
    ms_buf_puts(o, " to i64\n");
    if (inst->op == MOP_ListConst) {
        const uint32_t size = n * mir_list_elem_size(c->layouts, c->f->values[inst->res]);
        ms_buf_printf(o, "  %%v%u = call i64 @\"msrt_alloc\"(i64 %u)\n  %%d%u = inttoptr i64 %%v%u to ptr\n  %%cs%u = inttoptr i64 %%t%u to ptr\n",
                      inst->res, size, t, inst->res, t, t);
        ms_buf_printf(o, "  call void @llvm.memcpy.p0.p0.i64(ptr %%d%u, ptr %%cs%u, i64 %u, i1 false)\n", t, t, size);
        ms_buf_printf(o, "  %%v%u.1 = add i64 0, %u\n  %%v%u.2 = add i64 0, %u\n", inst->res, n, inst->res, n);
        return true;
    }
    ms_buf_printf(o, "  %%v%u = add i64 %%t%u, 0\n  %%v%u.1 = add i64 0, %u\n  %%v%u.2 = add i64 0, 0\n", inst->res, t,
                  inst->res, n, inst->res);
    return true;
}

/* The string operations here; `*handled` says whether `inst` is one. */
static bool ll_str_op(LCx *c, const MirInst *inst, uint32_t block, uint32_t index, uint32_t *part, bool *handled) {
    *handled = true;
    switch ((MirOp)inst->op) {
    case MOP_StrBytes: ll_str_bytes(c, inst); return true;
    case MOP_StrAsciiLen: ll_str_ascii_len(c, inst); return true;
    case MOP_StrAscii: ll_str_ascii(c, inst); return true;
    case MOP_StrByte: ll_str_byte(c, inst, block, index); return true;
    case MOP_BytesLit: case MOP_ListConst: case MOP_ListConstView: return ll_const_data(c, inst);
    case MOP_OptViewAt: case MOP_OptAddr: ll_copy_leaf(c, inst->res, 0, inst->args[0], 0); return true;
    case MOP_BytesPush: ll_bytes_push(c, inst, block, part); return true;
    default:
        *handled = false;
        return true;
    }
}
