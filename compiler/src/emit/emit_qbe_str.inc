/* String byte operations for emit_qbe.c (included from it). A string is two words: the address (or,
 * inline, its first eight bytes) and the tagged word: bit 63 static, bit 62 inline, bit 61 ASCII, an
 * inline length in bits 56 to 59, a long string's byte length in the low 31 bits. QBE has no select, so
 * a choice is a mask: all ones when the condition holds. */

#define QBE_STR_LEN_MASK 0x7fffffffLL

/* Writes `%o<n>m` = all ones when the word-sized flag `cond` is 1, zero when it is 0. */
static void qbe_str_mask(QCx *c, uint32_t n, const char *cond) {
    ms_buf_printf(c->out, "\t%%o%ue =l extuw %s\n\t%%o%um =l sub 0, %%o%ue\n", n, cond, n, n);
}

/* Writes `out = mask ? a : b` for the mask `%o<n>m`, using the temporaries `%o<n>x`, `%o<n>y`. */
static void qbe_str_pick(QCx *c, uint32_t n, const char *out, const char *a, const char *b) {
    ms_buf_printf(c->out,
                  "\t%%o%ux =l and %s, %%o%um\n\t%%o%uz =l xor %%o%um, -1\n\t%%o%uy =l and %s, %%o%uz\n\t%s =l or %%o%ux, %%o%uy\n",
                  n, a, n, n, n, n, b, n, out, n, n);
}

/* Whether the string `w1` is inline (kind bits 01): writes `%o<n>i` as a word. */
static void qbe_str_is_inline(QCx *c, uint32_t n, MirValue s) {
    ms_buf_printf(c->out, "\t%%o%uk =l shr %%v%u.1, 62\n\t%%o%ui =w ceql %%o%uk, 1\n", n, s, n, n);
}

/* `str.bytes`: the byte length, from the inline length bits or the long length bits. */
static void qbe_str_bytes(QCx *c, const MirInst *inst) {
    const uint32_t n = c->next++;
    const MirValue s = inst->args[0];
    char out[24];
    qbe_str_is_inline(c, n, s);
    ms_buf_printf(c->out, "\t%%o%us =l shr %%v%u.1, %d\n\t%%o%ush =l and %%o%us, %d\n", n, s,
                  MIR_STR_INLINE_SHIFT, n, n, MIR_STR_INLINE_MAX);
    ms_buf_printf(c->out, "\t%%o%ul =l and %%v%u.1, %lld\n", n, s, QBE_STR_LEN_MASK);
    char cond[24], a[24], b[24];
    (void)snprintf(cond, sizeof cond, "%%o%ui", n);
    qbe_str_mask(c, n, cond);
    (void)snprintf(a, sizeof a, "%%o%ush", n);
    (void)snprintf(b, sizeof b, "%%o%ul", n);
    (void)snprintf(out, sizeof out, "%%v%u", inst->res);
    qbe_str_pick(c, n, out, a, b);
}

/* `str.ascii_len`: the byte length when the string is known to be ASCII (an inline string with no
 * byte of 0x80 or more, or one flagged ASCII), else -1. */
static void qbe_str_ascii_len(QCx *c, const MirInst *inst) {
    MsBuf *o = c->out;
    const uint32_t n = c->next++;
    const MirValue s = inst->args[0];
    qbe_str_is_inline(c, n, s);
    ms_buf_printf(o, "\t%%o%uh0 =l and %%v%u, %lld\n\t%%o%uh1 =l and %%v%u.1, %lld\n", n, s,
                  (long long)0x8080808080808080ULL, n, s, 0x0080808080808080LL);
    ms_buf_printf(o, "\t%%o%uh =l or %%o%uh0, %%o%uh1\n\t%%o%ulow =w ceql %%o%uh, 0\n", n, n, n, n, n);
    ms_buf_printf(o, "\t%%o%us =l shr %%v%u.1, %d\n\t%%o%ush =l and %%o%us, %d\n", n, s, MIR_STR_INLINE_SHIFT, n,
                  n, MIR_STR_INLINE_MAX);
    char cond[24], a[24], b[24], out[24];
    (void)snprintf(cond, sizeof cond, "%%o%ulow", n);
    qbe_str_mask(c, n, cond);
    (void)snprintf(a, sizeof a, "%%o%ush", n);
    (void)snprintf(out, sizeof out, "%%o%uil", n);
    qbe_str_pick(c, n, out, a, "-1");
    /* A long string flagged ASCII (bits 62 and 61 read as 0 and 1 after the static bit) has its length. */
    ms_buf_printf(o, "\t%%o%uf =l shr %%v%u.1, 61\n\t%%o%uf3 =l and %%o%uf, 3\n\t%%o%ufl =w ceql %%o%uf3, 1\n", n, s,
                  n, n, n, n);
    ms_buf_printf(o, "\t%%o%ulen =l and %%v%u.1, %lld\n", n, s, QBE_STR_LEN_MASK);
    const uint32_t m = c->next++;
    (void)snprintf(cond, sizeof cond, "%%o%ufl", n);
    qbe_str_mask(c, m, cond);
    (void)snprintf(a, sizeof a, "%%o%ulen", n);
    (void)snprintf(out, sizeof out, "%%o%uot", n);
    qbe_str_pick(c, m, out, a, "-1");
    (void)snprintf(cond, sizeof cond, "%%o%ui", n);
    const uint32_t r = c->next++;
    qbe_str_mask(c, r, cond);
    (void)snprintf(a, sizeof a, "%%o%uil", n);
    (void)snprintf(b, sizeof b, "%%o%uot", n);
    (void)snprintf(out, sizeof out, "%%v%u", inst->res);
    qbe_str_pick(c, r, out, a, b);
}

/* `str.ascii`: the shared one-byte string of byte `b` (a table of two bytes each). */
static void qbe_str_ascii(QCx *c, const MirInst *inst) {
    const uint32_t n = c->next++;
    ms_buf_printf(c->out, "\t%%o%ud =l mul %%v%u, 2\n\t%%v%u =l add $msrt_ascii_chars, %%o%ud\n\t%%v%u.1 =l copy %lld\n",
                  n, inst->args[0], inst->res, n, inst->res, (long long)(MIR_STR_STATIC | 1));
}

/* `str.byte`: byte `i`. An inline string's bytes are its two words, so they are first written to a
 * frame slot and read from there; any other string is read at its address. */
static void qbe_str_byte(QCx *c, const MirInst *inst, uint32_t block, uint32_t index) {
    const uint32_t n = c->next++;
    const MirValue s = inst->args[0];
    ms_buf_printf(c->out, "\tstorel %%v%u, %%y%u_%u\n\t%%o%ua =l add %%y%u_%u, 8\n\tstorel %%v%u.1, %%o%ua\n", s, block,
                  index, n, block, index, s, n);
    qbe_str_is_inline(c, n, s);
    char cond[24], a[24], b[24], pick[24];
    (void)snprintf(cond, sizeof cond, "%%o%ui", n);
    qbe_str_mask(c, n, cond);
    (void)snprintf(a, sizeof a, "%%y%u_%u", block, index);
    (void)snprintf(b, sizeof b, "%%v%u", s);
    (void)snprintf(pick, sizeof pick, "%%o%ub", n);
    qbe_str_pick(c, n, pick, a, b);
    ms_buf_printf(c->out, "\t%%o%ua2 =l add %%o%ub, %%v%u\n\t%%v%u =l loadub %%o%ua2\n", n, n, inst->args[1], inst->res, n);
}

/* `bytes.push`: appends byte `v` to the builder at the address in the first operand when it is a
 * byte and there is room; the result says whether it did. The store is a block of its own. */
static void qbe_bytes_push(QCx *c, const MirInst *inst, uint32_t block, uint32_t *part) {
    MsBuf *o = c->out;
    const uint32_t n = c->next++;
    const MirValue b = inst->args[0], v = inst->args[1];
    ms_buf_printf(o, "\t%%o%ul =l add %%v%u, 8\n\t%%o%unl =l loadl %%o%ul\n\t%%o%uc =l add %%v%u, 16\n\t%%o%ucp =l loadl %%o%uc\n",
                  n, b, n, n, n, b, n, n);
    ms_buf_printf(o, "\t%%o%uby =w cule%c %%v%u, 255\n\t%%o%urm =w cultl %%o%unl, %%o%ucp\n\t%%v%u =w and %%o%uby, %%o%urm\n", n, qbe_vty(c, v), v,
                  n, n, n, inst->res, n, n);
    ms_buf_printf(o, "\tjnz %%v%u, @s%u, ", inst->res, n);
    (*part)++;
    qbe_label(c, block, *part);
    ms_buf_printf(o, "\n@s%u\n\t%%o%ud =l loadl %%v%u\n\t%%o%ua =l add %%o%ud, %%o%unl\n\tstoreb %%v%u, %%o%ua\n", n, n, b, n, n, n,
                  v, n);
    ms_buf_printf(o, "\t%%o%uu =l add %%o%unl, 1\n\tstorel %%o%uu, %%o%ul\n\tjmp ", n, n, n, n);
    qbe_label(c, block, *part);
    ms_buf_putc(o, '\n');
    qbe_label(c, block, *part);
    ms_buf_putc(o, '\n');
}

/* `bytes`, `list.const`, `list.const.view`: constant data. The view and the bytes borrow it (capacity
 * 0, nothing frees them); `list.const` copies it into a fresh block. */
static bool qbe_const_data(QCx *c, const MirInst *inst) {
    MsBuf *o = c->out;
    const uint32_t id = (uint32_t)inst->imm.i;
    const bool bytes = inst->op == MOP_BytesLit;
    const uint32_t n = bytes ? c->m->blobs[id].len : c->m->list_consts[id].n;
    if (n == 0) {
        ms_buf_printf(o, "\t%%v%u =l copy 0\n\t%%v%u.1 =l copy 0\n\t%%v%u.2 =l copy 0\n", inst->res, inst->res,
                      inst->res);
        return true;
    }
    const uint32_t sym = bytes ? c->data->blobs[id] : c->data->list_consts[id];
    if (c->data == NULL || sym == MIR_NONE) {
        c->why = "constant data without a symbol";
        return false;
    }
    if (inst->op == MOP_ListConst) {
        const uint32_t size = n * mir_list_elem_size(c->layouts, c->f->values[inst->res]);
        ms_buf_printf(o, "\t%%v%u =l call $msrt_alloc(l %u)\n\tcall $memcpy(l %%v%u, l ", inst->res, size, inst->res);
        qbe_ref(c, o, (MirRef){.kind = MT_DATA, .index = sym});
        ms_buf_printf(o, ", l %u)\n\t%%v%u.1 =l copy %u\n\t%%v%u.2 =l copy %u\n", size, inst->res, n, inst->res, n);
        return true;
    }
    ms_buf_printf(o, "\t%%v%u =l copy ", inst->res);
    qbe_ref(c, o, (MirRef){.kind = MT_DATA, .index = sym});
    ms_buf_printf(o, "\n\t%%v%u.1 =l copy %u\n\t%%v%u.2 =l copy 0\n", inst->res, n, inst->res);
    return true;
}

/* The string operations here; `*handled` says whether `inst` is one. */
static bool qbe_str_op(QCx *c, const MirInst *inst, uint32_t block, uint32_t index, uint32_t *part, bool *handled) {
    *handled = true;
    switch ((MirOp)inst->op) {
    case MOP_StrBytes: qbe_str_bytes(c, inst); return true;
    case MOP_StrAsciiLen: qbe_str_ascii_len(c, inst); return true;
    case MOP_StrAscii: qbe_str_ascii(c, inst); return true;
    case MOP_StrByte: qbe_str_byte(c, inst, block, index); return true;
    case MOP_BytesLit: case MOP_ListConst: case MOP_ListConstView: return qbe_const_data(c, inst);
    case MOP_OptViewAt: case MOP_OptAddr: qbe_copy_leaf(c, inst->res, 0, inst->args[0], 0); return true;
    case MOP_BytesPush: qbe_bytes_push(c, inst, block, part); return true;
    default:
        *handled = false;
        return true;
    }
}
