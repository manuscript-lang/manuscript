/* The `viewfast` pass: `String.view(start, end)` runs as a few instructions in the caller instead of a
 * runtime call.
 *
 * Lowering calls `msrt_string_view(text, start, end, out)`, which checks the bounds and writes a view of the
 * receiver's bytes through `out`. The common case is decided from the receiver's two words: a range inside
 * the text that starts and ends on scalar boundaries (an ASCII flag, or a look at the two bytes). A piece of
 * up to fifteen bytes is copied into the two words of an inline string; a longer one is a view over the
 * bytes. Everything else (an empty range, a negative bound, a fault) calls the runtime.
 *
 * The fast path is one generated function marked `inline(always)`, shared by every call site.
 * Port of the former Rust crates/ms-lower/src/rtinline.rs `view_fn`; the bit layout is
 * runtime/include/ms_rt/string.h. */
#include "opt/opt_build.h"

enum {
    VF_TAG_SHIFT = 62,
    VF_INLINE_LEN_SHIFT = 56,
    VF_INLINE_MAX = 15,
    VF_WORD = 8,
    VF_LEN_MASK = 0x7fffffff,
};

/* The words of one view: the receiver spilled to a slot, its second word, the bounds and where the view goes. */
typedef struct VfView {
    MirValue text, start, end, out;
    MirValue slot, w1;
    MirBlock slow;
} VfView;

static MirValue vf_icmp_const(MirBuilder *b, MirCc cc, MirValue x, int64_t y) {
    return mir_b_icmp(b, cc, x, mir_b_iconst(b, y));
}

/* Writes the two words of a string to `out`. */
static void vf_store_words(MirBuilder *b, MirValue out, MirValue first, MirValue second) {
    const MirValue lo[2] = {out, first};
    (void)mir_b_emit(b, MOP_Store, lo, 2, (MirImm){0}, MIR_NONE);
    const MirValue hi[2] = {ob_add(b, out, VF_WORD), second};
    (void)mir_b_emit(b, MOP_Store, hi, 2, (MirImm){0}, MIR_NONE);
}

/* The start of an inline text is a boundary of its bytes when every byte is below 0x80, so a range of an inline
 * text that is in bounds can be packed straight from the slot. Continues in a new block, else goes to `slow`. */
static void vf_inline_guard(MirBuilder *b, const VfView *v) {
    const MirValue len = ob_int(b, MOP_And, ob_int(b, MOP_Ushr, v->w1, VF_INLINE_LEN_SHIFT), VF_INLINE_MAX);
    const MirValue zero = mir_b_iconst(b, 0);
    const MirValue not_negative = mir_b_icmp(b, MCC_GE, v->start, zero);
    const MirValue ordered = mir_b_icmp(b, MCC_LE, v->start, v->end);
    const MirValue inside = mir_b_icmp(b, MCC_LE, v->end, len);
    const MirValue low = ob_load(b, v->slot, 0, MIR_INT);
    const MirValue high = ob_int(b, MOP_And, v->w1, ((int64_t)1 << VF_INLINE_LEN_SHIFT) - 1);
    const MirValue any = mir_b_binop(b, MOP_Or, low, high);
    const MirValue top_bits = ob_int(b, MOP_And, any, (int64_t)0x8080808080808080ULL);
    const MirValue ascii = mir_b_icmp(b, MCC_EQ, top_bits, zero);
    MirValue ok = ob_and(b, not_negative, ordered);
    ok = ob_and(b, ok, inside);
    ok = ob_and(b, ok, ascii);
    const MirBlock fast = mir_b_new_block(b);
    mir_b_br_if(b, ok, fast, NULL, 0, v->slow, NULL, 0);
    mir_b_seal_block(b, fast);
    mir_b_switch_to(b, fast);
}

/* Whether the byte at `at` of the flat text starts a scalar: it is not a continuation byte. */
static MirValue vf_boundary(MirBuilder *b, MirValue bytes, MirValue at) {
    const MirValue byte = ob_loadu(b, ob_past(b, bytes, at), 1);
    const MirValue continuation = ob_int(b, MOP_And, byte, 0xC0);
    return mir_b_icmp(b, MCC_NE, continuation, mir_b_iconst(b, 0x80));
}

/* A flat text: the range is inside it and both ends start a scalar, which an ASCII flag proves at once and a look
 * at the two bytes proves otherwise (every string is followed by a NUL, so the byte at `end` is readable).
 * Continues in a new block, else goes to `slow`. */
static void vf_flat_guard(MirBuilder *b, const VfView *v) {
    const MirValue w1 = ob_load(b, v->slot, VF_WORD, MIR_INT);
    const MirValue tag = ob_int(b, MOP_Ushr, w1, VF_TAG_SHIFT);
    const MirValue flat = mir_b_icmp(b, MCC_NE, tag, mir_b_iconst(b, 1));
    const MirValue ascii_bit = ob_int(b, MOP_And, w1, (int64_t)1 << 61);
    const MirValue zero = mir_b_iconst(b, 0);
    const MirValue flagged = mir_b_icmp(b, MCC_NE, ascii_bit, zero);
    const MirValue len = ob_int(b, MOP_And, w1, VF_LEN_MASK);
    const MirValue not_negative = mir_b_icmp(b, MCC_GE, v->start, zero);
    const MirValue ordered = mir_b_icmp(b, MCC_LE, v->start, v->end);
    const MirValue inside = mir_b_icmp(b, MCC_LE, v->end, len);
    MirValue ok = ob_and(b, flat, not_negative);
    ok = ob_and(b, ok, ordered);
    ok = ob_and(b, ok, inside);
    const MirBlock fast = mir_b_new_block(b), bounded = mir_b_new_block(b), scan = mir_b_new_block(b);
    mir_b_br_if(b, ok, bounded, NULL, 0, v->slow, NULL, 0);
    mir_b_seal_block(b, bounded);
    mir_b_switch_to(b, bounded);
    mir_b_br_if(b, flagged, fast, NULL, 0, scan, NULL, 0);
    mir_b_seal_block(b, scan);
    mir_b_switch_to(b, scan);
    const MirValue bytes = ob_load(b, v->slot, 0, MIR_PTR);
    const MirValue first = vf_boundary(b, bytes, v->start);
    const MirValue last = vf_boundary(b, bytes, v->end);
    mir_b_br_if(b, ob_and(b, first, last), fast, NULL, 0, v->slow, NULL, 0);
    mir_b_seal_block(b, fast);
    mir_b_switch_to(b, fast);
}

/* The bytes `p[..n]` (`n <= 15`) as the two words of an inline string: the first eight bytes and the rest, zero
 * past the end. Overlapping loads cover every length without reading past `p + n`. */
typedef struct VfPack {
    MirBlock big, rest, mid, tiny, small, join;
    MirVar low, high;
    MirValue zero;
} VfPack;

static void vf_pack_eight(MirBuilder *b, const VfPack *k, MirValue p, MirValue n) {
    const MirValue a = ob_loadu(b, p, 8);
    const MirValue back = ob_int(b, MOP_ISub, n, 8);
    const MirValue tail = ob_loadu(b, ob_past(b, p, back), 8);
    const MirValue shifted = ob_int(b, MOP_Ushr, tail, 8);
    const MirValue by = ob_int(b, MOP_Shl, mir_b_binop(b, MOP_ISub, mir_b_iconst(b, 15), n), 3);
    mir_b_def_var(b, k->low, a);
    mir_b_def_var(b, k->high, mir_b_binop(b, MOP_Ushr, shifted, by));
    mir_b_br(b, k->join, NULL, 0);
}

static void vf_pack_four(MirBuilder *b, const VfPack *k, MirValue p, MirValue n) {
    const MirValue a = ob_loadu(b, p, 4);
    const MirValue back = ob_int(b, MOP_ISub, n, 4);
    const MirValue tail = ob_loadu(b, ob_past(b, p, back), 4);
    const MirValue by = ob_int(b, MOP_Shl, back, 3);
    mir_b_def_var(b, k->low, mir_b_binop(b, MOP_Or, a, mir_b_binop(b, MOP_Shl, tail, by)));
    mir_b_br(b, k->join, NULL, 0);
}

static void vf_pack_three(MirBuilder *b, const VfPack *k, MirValue p, MirValue n) {
    const MirValue first = ob_loadu(b, p, 1);
    const MirValue half = ob_int(b, MOP_Ushr, n, 1);
    const MirValue middle = ob_loadu(b, ob_past(b, p, half), 1);
    const MirValue last_at = ob_int(b, MOP_ISub, n, 1);
    const MirValue last = ob_loadu(b, ob_past(b, p, last_at), 1);
    const MirValue middle_up = mir_b_binop(b, MOP_Shl, middle, ob_int(b, MOP_Shl, half, 3));
    const MirValue last_up = mir_b_binop(b, MOP_Shl, last, ob_int(b, MOP_Shl, last_at, 3));
    mir_b_def_var(b, k->low, mir_b_binop(b, MOP_Or, mir_b_binop(b, MOP_Or, first, middle_up), last_up));
    mir_b_br(b, k->join, NULL, 0);
}

/* Packs `p[..n]` and leaves the builder in the join block; the words are the variables `low` and `high`. */
static void vf_pack_short(MirBuilder *b, MirValue p, MirValue n, VfPack *k) {
    k->big = mir_b_new_block(b);
    k->rest = mir_b_new_block(b);
    k->mid = mir_b_new_block(b);
    k->tiny = mir_b_new_block(b);
    k->small = mir_b_new_block(b);
    k->join = mir_b_new_block(b);
    k->low = mir_b_declare_var(b, MIR_INT, MM_BORROW);
    k->high = mir_b_declare_var(b, MIR_INT, MM_BORROW);
    k->zero = mir_b_iconst(b, 0);
    mir_b_def_var(b, k->low, k->zero);
    mir_b_def_var(b, k->high, k->zero);
    mir_b_br_if(b, vf_icmp_const(b, MCC_GE, n, 8), k->big, NULL, 0, k->rest, NULL, 0);
    mir_b_seal_block(b, k->big);
    mir_b_seal_block(b, k->rest);
    mir_b_switch_to(b, k->big);
    vf_pack_eight(b, k, p, n);
    mir_b_switch_to(b, k->rest);
    mir_b_br_if(b, vf_icmp_const(b, MCC_GE, n, 4), k->mid, NULL, 0, k->tiny, NULL, 0);
    mir_b_seal_block(b, k->mid);
    mir_b_seal_block(b, k->tiny);
    mir_b_switch_to(b, k->mid);
    vf_pack_four(b, k, p, n);
    mir_b_switch_to(b, k->tiny);
    mir_b_br_if(b, mir_b_icmp(b, MCC_GT, n, k->zero), k->small, NULL, 0, k->join, NULL, 0);
    mir_b_seal_block(b, k->small);
    mir_b_switch_to(b, k->small);
    vf_pack_three(b, k, p, n);
    mir_b_seal_block(b, k->join);
    mir_b_switch_to(b, k->join);
}

/* An inline piece, or a flat one of up to fifteen bytes, becomes the two words of an inline string. */
static void vf_short_block(MirBuilder *b, const VfView *v, MirValue p, MirValue n) {
    VfPack k;
    vf_pack_short(b, p, n, &k);
    const MirValue low = mir_b_use_var(b, k.low);
    const MirValue high = mir_b_use_var(b, k.high);
    const MirValue length_bits = ob_int(b, MOP_Shl, n, VF_INLINE_LEN_SHIFT);
    MirValue tagged = ob_int(b, MOP_Or, length_bits, (int64_t)1 << VF_TAG_SHIFT);
    tagged = mir_b_binop(b, MOP_Or, tagged, high);
    vf_store_words(b, v->out, low, tagged);
}

/* The entry: the receiver is spilled to a slot to read its words, and an inline or a flat text takes its guard. */
static void vf_entry(MirBuilder *b, VfView *v, MirBlock *inline_block, MirBlock *flat_block) {
    v->slot = mir_b_emit(b, MOP_Slot, NULL, 0, (MirImm){.tag = MI_TY, .a = MIR_STR}, MIR_PTR);
    const MirValue spill[2] = {v->slot, v->text};
    (void)mir_b_emit(b, MOP_Store, spill, 2, (MirImm){0}, MIR_NONE);
    v->w1 = ob_load(b, v->slot, VF_WORD, MIR_INT);
    const MirValue tag = ob_int(b, MOP_Ushr, v->w1, VF_TAG_SHIFT);
    const MirValue is_inline = mir_b_icmp(b, MCC_EQ, tag, mir_b_iconst(b, 1));
    mir_b_br_if(b, is_inline, *inline_block, NULL, 0, *flat_block, NULL, 0);
    mir_b_seal_block(b, *inline_block);
    mir_b_seal_block(b, *flat_block);
}

/* Builds `string_view(text, start, end, out)`, which calls `slow` (the runtime function) when the fast path does
 * not apply. */
static uint32_t vf_build(MirModule *m, uint32_t slow_ext) {
    const MirParam params[4] = {{MIR_STR, MM_BORROW}, {MIR_INT, MM_BORROW}, {MIR_INT, MM_BORROW}, {MIR_PTR, MM_BORROW}};
    MirBuilder b;
    mir_b_init_fast_path(&b, m, ms_intern_cstr(&m->names, "string_view"), params, 4, MIR_VOID);
    VfView v = {0};
    MirValue ps[4];
    mir_b_params(&b, ps, 4);
    v.text = ps[0], v.start = ps[1], v.end = ps[2], v.out = ps[3];
    v.slow = mir_b_new_block(&b);
    const MirBlock join = mir_b_new_block(&b);
    MirBlock flat_block = mir_b_new_block(&b);
    MirBlock inline_block = mir_b_new_block(&b);
    vf_entry(&b, &v, &inline_block, &flat_block);
    const MirBlock short_block = mir_b_new_block(&b), long_block = mir_b_new_block(&b);
    const MirValue short_p = mir_b_add_block_param(&b, short_block, MIR_PTR, MM_BORROW);
    const MirValue short_n = mir_b_add_block_param(&b, short_block, MIR_INT, MM_BORROW);
    mir_b_switch_to(&b, inline_block); // its bytes sit in the slot: an ASCII range of it is packed from there
    vf_inline_guard(&b, &v);
    const MirValue inline_from = ob_past(&b, v.slot, v.start);
    const MirValue inline_n = mir_b_binop(&b, MOP_ISub, v.end, v.start);
    const MirValue inline_args[2] = {inline_from, inline_n};
    mir_b_br(&b, short_block, inline_args, 2);
    mir_b_switch_to(&b, flat_block);
    vf_flat_guard(&b, &v);
    const MirValue bytes = ob_load(&b, v.slot, 0, MIR_PTR);
    const MirValue flat_from = ob_past(&b, bytes, v.start);
    const MirValue flat_n = mir_b_binop(&b, MOP_ISub, v.end, v.start);
    const MirValue fits = mir_b_icmp(&b, MCC_LE, flat_n, mir_b_iconst(&b, VF_INLINE_MAX));
    const MirValue flat_args[2] = {flat_from, flat_n};
    mir_b_br_if(&b, fits, short_block, flat_args, 2, long_block, NULL, 0);
    mir_b_seal_block(&b, short_block);
    mir_b_seal_block(&b, long_block);
    mir_b_switch_to(&b, long_block); // longer text: a view over the bytes, tagged as borrowed
    vf_store_words(&b, v.out, flat_from, ob_int(&b, MOP_Or, flat_n, (int64_t)(3ULL << VF_TAG_SHIFT)));
    mir_b_br(&b, join, NULL, 0);
    mir_b_switch_to(&b, short_block);
    vf_short_block(&b, &v, short_p, short_n);
    mir_b_br(&b, join, NULL, 0);
    mir_b_seal_block(&b, v.slow);
    mir_b_switch_to(&b, v.slow); // the runtime handles the rest
    const MirValue rest[4] = {v.text, v.start, v.end, v.out};
    (void)mir_b_call_rt(&b, slow_ext, rest, 4);
    mir_b_br(&b, join, NULL, 0);
    mir_b_seal_block(&b, join);
    mir_b_switch_to(&b, join);
    mir_b_ret(&b, mir_b_unit(&b));
    uint32_t id = MIR_NONE;
    return mir_b_finish(&b, &id) ? id : MIR_NONE;
}

/* Whether `e` is `msrt_string_view`: a borrowing native over a string, two bounds and the address the view goes to. */
static bool vf_is_view(const MirExtern *e) {
    return e->role == MR_BORROWS_ARGUMENT && e->nparams == 4 && e->ret == MIR_VOID && e->params[0].ty == MIR_STR &&
           e->params[1].ty == MIR_INT && e->params[2].ty == MIR_INT && e->params[3].ty == MIR_PTR;
}

static uint32_t vf_first_site(const MirModule *m) {
    for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
        const MirFunc *f = &m->funcs[fi];
        for (uint32_t bi = 0; bi < f->nblocks; bi++) {
            for (uint32_t ii = 0; ii < f->blocks[bi].ninsts; ii++) {
                const MirInst *inst = &f->blocks[bi].insts[ii];
                if (inst->op == MOP_CallRt && vf_is_view(&m->externs[inst->imm.a])) {
                    return inst->imm.a;
                }
            }
        }
    }
    return MIR_NONE;
}

bool mir_opt_viewfast(MirModule *m) {
    const uint32_t slow = vf_first_site(m);
    if (slow == MIR_NONE) {
        return false;
    }
    const uint32_t original = m->nfuncs; /* the helper keeps its own call to the runtime */
    const uint32_t helper = vf_build(m, slow);
    if (helper == MIR_NONE) {
        return false;
    }
    for (uint32_t fi = 0; fi < original; fi++) {
        MirFunc *f = &m->funcs[fi];
        for (uint32_t bi = 0; bi < f->nblocks; bi++) {
            for (uint32_t ii = 0; ii < f->blocks[bi].ninsts; ii++) {
                MirInst *inst = &f->blocks[bi].insts[ii];
                if (inst->op != MOP_CallRt || !vf_is_view(&m->externs[inst->imm.a])) {
                    continue;
                }
                inst->op = MOP_Call;
                inst->imm = (MirImm){.tag = MI_FUNC, .a = helper};
            }
        }
    }
    return true;
}
