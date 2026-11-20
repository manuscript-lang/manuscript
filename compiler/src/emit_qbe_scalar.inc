/* Scalar, bit and pointer ops for emit_qbe.c (included from it). QBE has no select, no overflow
 * flags, no count or rotate instructions and no high multiply, so those are written out from the
 * instructions it has; the libm functions stand in for the float rounding ops. */

#define QBE_FAULT_RANGE "$msrt_fault_int_range()"

/* The name of leaf `k` of value `v` in `buf`. */
static void qbe_leaf_name(char *buf, size_t cap, MirValue v, uint32_t k) {
    if (k == 0) (void)snprintf(buf, cap, "%%v%u", v);
    else (void)snprintf(buf, cap, "%%v%u.%u", v, k);
}

/* One leaf of `select`: `f ^ ((t ^ f) & mask)` in the leaf's own width, floats through their
 * bits. `t` and `f` name the leaf of the two arms. */
static void qbe_select_leaf(QCx *c, const MirInst *inst, uint32_t n, uint32_t k, char type) {
    MsBuf *o = c->out;
    char t[24], f[24];
    qbe_leaf_name(t, sizeof t, inst->args[1], k);
    qbe_leaf_name(f, sizeof f, inst->args[2], k);
    const char work = type == 'w' ? 'w' : 'l';
    if (type == 'd') {
        ms_buf_printf(o, "\t%%o%ut%u =l cast %s\n\t%%o%uf%u =l cast %s\n", n, k, t, n, k, f);
        (void)snprintf(t, sizeof t, "%%o%ut%u", n, k);
        (void)snprintf(f, sizeof f, "%%o%uf%u", n, k);
    }
    ms_buf_printf(o, "\t%%o%ux%u =%c xor %s, %s\n", n, k, work, t, f);
    ms_buf_printf(o, "\t%%o%uy%u =%c and %%o%ux%u, %%o%u%c\n", n, k, work, n, k, n, work);
    if (type != 'd') {
        ms_buf_puts(o, "\t");
        qbe_name(o, inst->res, k);
        ms_buf_printf(o, " =%c xor %s, %%o%uy%u\n", work, f, n, k);
        return;
    }
    ms_buf_printf(o, "\t%%o%uz%u =l xor %s, %%o%uy%u\n\t", n, k, f, n, k);
    qbe_name(o, inst->res, k);
    ms_buf_printf(o, " =d cast %%o%uz%u\n", n, k);
}

/* `select`: the condition becomes a mask of all ones or zeros, in both widths. */
static void qbe_select(QCx *c, const MirInst *inst) {
    const uint32_t n = c->next++;
    const MirLeafSpan leaves = qbe_leaves(c, c->f->values[inst->res]);
    ms_buf_printf(c->out, "\t%%o%uw =w sub 0, %%v%u\n\t%%o%ul =l extsw %%o%uw\n", n, inst->args[0], n, n);
    for (uint32_t k = 0; k < leaves.len; k++) {
        qbe_select_leaf(c, inst, n, k, qbe_leaf_type(leaves.ptr[k]));
    }
}

/* `conv`, `f32.round`: the leaves unchanged, except a double narrowed to a Float32, which is
 * rounded through a single. */
static void qbe_convert(QCx *c, const MirInst *inst) {
    MsBuf *o = c->out;
    const MirLeafSpan out = qbe_leaves(c, c->f->values[inst->res]);
    const MirLeafSpan in = qbe_leaves(c, c->f->values[inst->args[0]]);
    const bool round = inst->op == MOP_F32Round ||
                       (out.len == 1 && out.ptr[0] == MIR_LEAF_F32 && in.ptr[0] == MIR_LEAF_F64);
    if (round) {
        const uint32_t n = c->next++;
        ms_buf_printf(o, "\t%%o%ur =s truncd %%v%u\n\t%%v%u =d exts %%o%ur\n", n, inst->args[0],
                      inst->res, n);
        return;
    }
    for (uint32_t k = 0; k < out.len; k++) {
        ms_buf_puts(o, "\t");
        qbe_name(o, inst->res, k);
        ms_buf_printf(o, " =%c copy ", qbe_leaf_type(out.ptr[k]));
        qbe_name(o, inst->args[0], k);
        ms_buf_putc(o, '\n');
    }
}

/* ---- bit operations ---- */

/* Writes the number of set bits of `src` to `dst` (names with their `%`). */
static void qbe_popcount(QCx *c, uint32_t n, const char *src, const char *dst) {
    MsBuf *o = c->out;
    ms_buf_printf(o, "\t%%o%ua =l shr %s, 1\n\t%%o%ub =l and %%o%ua, 6148914691236517205\n", n, src, n, n);
    ms_buf_printf(o, "\t%%o%uc =l sub %s, %%o%ub\n", n, src, n);
    ms_buf_printf(o, "\t%%o%ud =l and %%o%uc, 3689348814741910323\n\t%%o%ue =l shr %%o%uc, 2\n", n, n, n, n);
    ms_buf_printf(o, "\t%%o%uf =l and %%o%ue, 3689348814741910323\n\t%%o%ug =l add %%o%ud, %%o%uf\n", n, n, n, n, n);
    ms_buf_printf(o, "\t%%o%uh =l shr %%o%ug, 4\n\t%%o%ui =l add %%o%ug, %%o%uh\n", n, n, n, n, n);
    ms_buf_printf(o, "\t%%o%uj =l and %%o%ui, 1085102592571150095\n", n, n);
    ms_buf_printf(o, "\t%%o%uk =l mul %%o%uj, 72340172838076673\n\t%s =l shr %%o%uk, 56\n", n, n, dst, n);
}

/* `popcnt`, `clz`, `ctz`. clz smears the top set bit down and counts the zeros above it; ctz counts
 * the ones of `~x & (x - 1)`. Both give 64 for zero. */
static void qbe_count_bits(QCx *c, const MirInst *inst) {
    MsBuf *o = c->out;
    const uint32_t n = c->next++;
    char src[24], dst[24], pop[24];
    (void)snprintf(src, sizeof src, "%%v%u", inst->args[0]);
    (void)snprintf(dst, sizeof dst, "%%v%u", inst->res);
    if (inst->op == MOP_Popcnt) {
        qbe_popcount(c, n, src, dst);
        return;
    }
    (void)snprintf(pop, sizeof pop, "%%o%ur", n);
    if (inst->op == MOP_Ctz) {
        ms_buf_printf(o, "\t%%o%un =l xor %s, -1\n\t%%o%um =l sub %s, 1\n\t%%o%us =l and %%o%un, %%o%um\n", n,
                      src, n, src, n, n, n);
        (void)snprintf(src, sizeof src, "%%o%us", n);
        qbe_popcount(c, n + 100000, src, pop);
        ms_buf_printf(o, "\t%s =l copy %s\n", dst, pop);
        return;
    }
    ms_buf_printf(o, "\t%%o%um0 =l copy %s\n", n, src);
    for (int shift = 1; shift <= 32; shift *= 2) {
        ms_buf_printf(o, "\t%%o%us%d =l shr %%o%um%d, %d\n\t%%o%um%d =l or %%o%um%d, %%o%us%d\n", n, shift, n,
                      shift == 1 ? 0 : shift / 2, shift, n, shift, n, shift == 1 ? 0 : shift / 2, n, shift);
    }
    (void)snprintf(src, sizeof src, "%%o%um32", n);
    qbe_popcount(c, n + 100000, src, pop);
    ms_buf_printf(o, "\t%s =l sub 64, %s\n", dst, pop);
}

/* `rotl`, `rotr`: two shifts with the counts taken modulo 64, so a zero count shifts by zero. */
static void qbe_rotate(QCx *c, const MirInst *inst) {
    MsBuf *o = c->out;
    const MirValue *a = inst->args;
    const uint32_t n = c->next++;
    const bool left = inst->op == MOP_Rotl;
    ms_buf_printf(o, "\t%%o%ua =l and %%v%u, 63\n\t%%o%ub =l sub 64, %%o%ua\n\t%%o%uc =l and %%o%ub, 63\n", n,
                  a[1], n, n, n, n);
    ms_buf_printf(o, "\t%%o%ud =l %s %%v%u, %%o%ua\n\t%%o%ue =l %s %%v%u, %%o%uc\n", n, left ? "shl" : "shr",
                  a[0], n, n, left ? "shr" : "shl", a[0], n);
    ms_buf_printf(o, "\t%%v%u =l or %%o%ud, %%o%ue\n", inst->res, n, n);
}

/* `umulhi`: the high half of the unsigned product, from the four products of 32-bit halves. */
static void qbe_mul_high(QCx *c, const MirInst *inst) {
    MsBuf *o = c->out;
    const MirValue *a = inst->args;
    const uint32_t n = c->next++;
    ms_buf_printf(o, "\t%%o%ua0 =l and %%v%u, 4294967295\n\t%%o%ua1 =l shr %%v%u, 32\n", n, a[0], n, a[0]);
    ms_buf_printf(o, "\t%%o%ub0 =l and %%v%u, 4294967295\n\t%%o%ub1 =l shr %%v%u, 32\n", n, a[1], n, a[1]);
    ms_buf_printf(o, "\t%%o%up00 =l mul %%o%ua0, %%o%ub0\n\t%%o%up01 =l mul %%o%ua0, %%o%ub1\n", n, n, n, n, n, n);
    ms_buf_printf(o, "\t%%o%up10 =l mul %%o%ua1, %%o%ub0\n\t%%o%up11 =l mul %%o%ua1, %%o%ub1\n", n, n, n, n, n, n);
    ms_buf_printf(o, "\t%%o%um0 =l shr %%o%up00, 32\n\t%%o%um1 =l and %%o%up10, 4294967295\n", n, n, n, n);
    ms_buf_printf(o, "\t%%o%um2 =l and %%o%up01, 4294967295\n\t%%o%um3 =l add %%o%um0, %%o%um1\n", n, n, n, n, n);
    ms_buf_printf(o, "\t%%o%um4 =l add %%o%um3, %%o%um2\n\t%%o%um5 =l shr %%o%um4, 32\n", n, n, n, n, n);
    ms_buf_printf(o, "\t%%o%uh0 =l shr %%o%up10, 32\n\t%%o%uh1 =l shr %%o%up01, 32\n", n, n, n, n);
    ms_buf_printf(o, "\t%%o%uh2 =l add %%o%up11, %%o%uh0\n\t%%o%uh3 =l add %%o%uh2, %%o%uh1\n", n, n, n, n, n, n);
    ms_buf_printf(o, "\t%%v%u =l add %%o%uh3, %%o%um5\n", inst->res, n, n);
}

/* ---- checked and flag arithmetic ---- */

/* `ineg`, `ineg.chk`: zero minus the operand; the checked form faults on the minimum. */
static void qbe_negate(QCx *c, const MirInst *inst, uint32_t block, uint32_t *part) {
    ms_buf_printf(c->out, "\t%%v%u =l sub 0, %%v%u\n", inst->res, inst->args[0]);
    if (inst->op == MOP_INegChk) {
        const uint32_t n = c->next++;
        ms_buf_printf(c->out, "\t%%o%us =w ceql %%v%u, -9223372036854775808\n", n, inst->args[0]);
        qbe_fault_branch(c, n, QBE_FAULT_OVERFLOW, block, part);
    }
}

/* `iadd.overflow`, `imul.overflow`: only the flag is the result. */
static void qbe_overflow_flag(QCx *c, const MirInst *inst) {
    const uint32_t n = c->next++;
    char scratch[24];
    (void)snprintf(scratch, sizeof scratch, "%%o%ut", n);
    if (inst->op == MOP_IAddOverflow) qbe_add_flag(c, n, true, inst->args[0], inst->args[1], scratch);
    else qbe_mul_flag(c, n, inst->args[0], inst->args[1], scratch);
    ms_buf_printf(c->out, "\t%%v%u =w copy %%o%us\n", inst->res, n);
}

/* `int_overflow.if`: faults when the flag operand is true. */
static void qbe_overflow_if(QCx *c, const MirInst *inst, uint32_t block, uint32_t *part) {
    const uint32_t n = c->next++;
    ms_buf_printf(c->out, "\t%%o%us =w copy %%v%u\n", n, inst->args[0]);
    qbe_fault_branch(c, n, QBE_FAULT_OVERFLOW, block, part);
}

/* `uadd.chk`, `usub.chk`, `umul.chk`: unsigned 64-bit arithmetic that faults when it wraps. The
 * product is divided back by `a` (or by 1 when `a` is zero, which never overflows). */
static void qbe_unsigned_checked(QCx *c, const MirInst *inst, uint32_t block, uint32_t *part) {
    MsBuf *o = c->out;
    const MirValue *a = inst->args;
    const uint32_t n = c->next++;
    if (inst->op == MOP_UAddChk) {
        ms_buf_printf(o, "\t%%v%u =l add %%v%u, %%v%u\n\t%%o%us =w cultl %%v%u, %%v%u\n", inst->res, a[0], a[1], n,
                      inst->res, a[0]);
    } else if (inst->op == MOP_USubChk) {
        ms_buf_printf(o, "\t%%v%u =l sub %%v%u, %%v%u\n\t%%o%us =w cultl %%v%u, %%v%u\n", inst->res, a[0], a[1], n,
                      a[0], a[1]);
    } else {
        ms_buf_printf(o, "\t%%v%u =l mul %%v%u, %%v%u\n\t%%o%uz =w ceql %%v%u, 0\n", inst->res, a[0], a[1], n, a[0]);
        ms_buf_printf(o, "\t%%o%uy =l extuw %%o%uz\n\t%%o%ud =l or %%v%u, %%o%uy\n", n, n, n, a[0], n);
        ms_buf_printf(o, "\t%%o%uh =l udiv %%v%u, %%o%ud\n\t%%o%ui =w cnel %%o%uh, %%v%u\n", n, inst->res, n, n, n,
                      a[1]);
        ms_buf_printf(o, "\t%%o%unz =w cnel %%v%u, 0\n\t%%o%us =w and %%o%ui, %%o%unz\n", n, a[0], n, n, n);
    }
    qbe_fault_branch(c, n, QBE_FAULT_RANGE, block, part);
}

/* `sdiv.chk`, `srem.chk`: fault on a zero divisor; division also faults on `min / -1`, while the
 * remainder by -1 is 0 (QBE's `rem` would trap there, so the divisor is replaced by 1). */
static void qbe_checked_div(QCx *c, const MirInst *inst, uint32_t block, uint32_t *part) {
    MsBuf *o = c->out;
    const MirValue *a = inst->args;
    const bool div = inst->op == MOP_SDivChk;
    uint32_t n = c->next++;
    ms_buf_printf(o, "\t%%o%us =w ceql %%v%u, 0\n", n, a[1]);
    qbe_fault_branch(c, n, div ? "$msrt_fault_div_zero()" : "$msrt_fault_rem_zero()", block, part);
    n = c->next++;
    if (div) {
        char call[96];
        (void)snprintf(call, sizeof call, "$msrt_fault_div_overflow(l %%v%u, l %%v%u)", a[0], a[1]);
        ms_buf_printf(o, "\t%%o%um =w ceql %%v%u, -1\n\t%%o%un =w ceql %%v%u, -9223372036854775808\n", n, a[1], n,
                      a[0]);
        ms_buf_printf(o, "\t%%o%us =w and %%o%um, %%o%un\n", n, n, n);
        qbe_fault_branch(c, n, call, block, part);
        ms_buf_printf(o, "\t%%v%u =l div %%v%u, %%v%u\n", inst->res, a[0], a[1]);
        return;
    }
    ms_buf_printf(o, "\t%%o%um =w ceql %%v%u, -1\n\t%%o%uk =l extuw %%o%um\n", n, a[1], n, n);
    ms_buf_printf(o, "\t%%o%ue =l sub %%v%u, 1\n\t%%o%uf =l mul %%o%ue, %%o%uk\n", n, a[1], n, n, n);
    ms_buf_printf(o, "\t%%o%ud =l sub %%v%u, %%o%uf\n\t%%o%ur =l rem %%v%u, %%o%ud\n", n, a[1], n, n, a[0], n);
    ms_buf_printf(o, "\t%%o%ui =l sub 1, %%o%uk\n\t%%v%u =l mul %%o%ur, %%o%ui\n", n, n, inst->res, n, n);
}

/* The extension that reads the low bits of a sized integer back as the integer, per kind. */
static const char *qbe_narrow_extension(MirTyKind kind) {
    switch (kind) {
    case MK_INT8: return "extsb";
    case MK_INT16: return "extsh";
    case MK_INT32: return "extsw";
    case MK_UINT8: return "extub";
    case MK_UINT16: return "extuh";
    case MK_UINT32: return "extuw";
    default: return NULL;
    }
}

/* `narrow.chk`: faults unless the value survives a round trip through the result's width. */
static void qbe_narrow_check(QCx *c, const MirInst *inst, uint32_t block, uint32_t *part) {
    const MirTyKind kind = (MirTyKind)mir_ty_data(c->m, c->f->values[inst->res])->kind;
    const char *extension = qbe_narrow_extension(kind);
    if (extension != NULL) {
        const uint32_t n = c->next++;
        ms_buf_printf(c->out, "\t%%o%ue =l %s %%v%u\n\t%%o%us =w cnel %%o%ue, %%v%u\n", n, extension,
                      inst->args[0], n, n, inst->args[0]);
        qbe_fault_branch(c, n, QBE_FAULT_OVERFLOW, block, part);
    }
    ms_buf_printf(c->out, "\t%%v%u =l copy %%v%u\n", inst->res, inst->args[0]);
}

/* ---- pointers and floats ---- */

/* The load and store mnemonics of an unsigned access `bytes` wide (1, 2, 4, else a word). */
static const char *qbe_word_load(int64_t bytes) {
    return bytes == 1 ? "loadub" : bytes == 2 ? "loaduh" : bytes == 4 ? "loaduw" : "loadl";
}

static const char *qbe_word_store(int64_t bytes) {
    return bytes == 1 ? "storeb" : bytes == 2 ? "storeh" : bytes == 4 ? "storew" : "storel";
}

/* `ptr.*`, `free`, and the libm-backed float ops; false when `inst` is none of them. */
static bool qbe_pointer_op(QCx *c, const MirInst *inst, bool *ok) {
    MsBuf *o = c->out;
    const MirValue *a = inst->args;
    const int64_t width = inst->imm.tag == MI_INT ? inst->imm.i : 8;
    *ok = true;
    switch ((MirOp)inst->op) {
    case MOP_PtrNull: ms_buf_printf(o, "\t%%v%u =l copy 0\n", inst->res); return true;
    case MOP_PtrIsNull: ms_buf_printf(o, "\t%%v%u =w ceql %%v%u, 0\n", inst->res, a[0]); return true;
    case MOP_PtrAdd: ms_buf_printf(o, "\t%%v%u =l add %%v%u, %%v%u\n", inst->res, a[0], a[1]); return true;
    case MOP_PtrLoadU: ms_buf_printf(o, "\t%%v%u =l %s %%v%u\n", inst->res, qbe_word_load(width), a[0]); return true;
    case MOP_PtrStoreU: ms_buf_printf(o, "\t%s %%v%u, %%v%u\n", qbe_word_store(width), a[1], a[0]); return true;
    case MOP_Free:
        *ok = inst->imm.tag == MI_NONE;
        if (*ok) ms_buf_printf(o, "\tcall $msrt_free(l %%v%u)\n", a[0]);
        else c->why = "free of a collection field";
        return true;
    case MOP_FSqrt: ms_buf_printf(o, "\t%%v%u =d call $sqrt(d %%v%u)\n", inst->res, a[0]); return true;
    case MOP_FAbs: ms_buf_printf(o, "\t%%v%u =d call $fabs(d %%v%u)\n", inst->res, a[0]); return true;
    case MOP_FFloor: ms_buf_printf(o, "\t%%v%u =d call $floor(d %%v%u)\n", inst->res, a[0]); return true;
    case MOP_FCeil: ms_buf_printf(o, "\t%%v%u =d call $ceil(d %%v%u)\n", inst->res, a[0]); return true;
    case MOP_FTrunc: ms_buf_printf(o, "\t%%v%u =d call $trunc(d %%v%u)\n", inst->res, a[0]); return true;
    case MOP_VoidConst: return true;
    default: return false;
    }
}

/* How many times `inst` ends the current piece of its block with a fault branch. */
static uint32_t qbe_splits(const MirModule *m, const MirFunc *f, const MirInst *inst) {
    switch ((MirOp)inst->op) {
    case MOP_IAddChk: case MOP_ISubChk: case MOP_IMulChk: case MOP_INegChk: case MOP_IntOverflowIf:
    case MOP_UAddChk: case MOP_USubChk: case MOP_UMulChk: case MOP_SRemChk:
        return 1;
    case MOP_SDivChk:
        return 2;
    case MOP_NarrowChk:
        return qbe_narrow_extension((MirTyKind)mir_ty_data(m, f->values[inst->res])->kind) != NULL;
    default:
        return 0;
    }
}

/* The scalar, bit and pointer ops of this file; `*handled` is false for any other. */
static bool qbe_scalar_inst(QCx *c, const MirInst *inst, uint32_t block, uint32_t *part, bool *handled) {
    *handled = true;
    switch ((MirOp)inst->op) {
    case MOP_IAddChk: case MOP_ISubChk: qbe_checked_arith(c, inst, block, part); return true;
    case MOP_IMulChk: qbe_checked_mul(c, inst, block, part); return true;
    case MOP_Select: qbe_select(c, inst); return true;
    case MOP_Conv: case MOP_F32Round: qbe_convert(c, inst); return true;
    case MOP_Popcnt: case MOP_Clz: case MOP_Ctz: qbe_count_bits(c, inst); return true;
    case MOP_Rotl: case MOP_Rotr: qbe_rotate(c, inst); return true;
    case MOP_UMulHi: qbe_mul_high(c, inst); return true;
    case MOP_INeg: case MOP_INegChk: qbe_negate(c, inst, block, part); return true;
    case MOP_IAddOverflow: case MOP_IMulOverflow: qbe_overflow_flag(c, inst); return true;
    case MOP_IntOverflowIf: qbe_overflow_if(c, inst, block, part); return true;
    case MOP_UAddChk: case MOP_USubChk: case MOP_UMulChk: qbe_unsigned_checked(c, inst, block, part); return true;
    case MOP_SDivChk: case MOP_SRemChk: qbe_checked_div(c, inst, block, part); return true;
    case MOP_NarrowChk: qbe_narrow_check(c, inst, block, part); return true;
    default: break;
    }
    bool ok = true;
    if (qbe_pointer_op(c, inst, &ok)) {
        return ok;
    }
    *handled = false;
    return true;
}
