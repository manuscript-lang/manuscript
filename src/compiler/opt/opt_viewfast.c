/* The `viewfast` pass: `String.view(start, end)`, `String.slice(start, end)` and `Bytes.view(start, end)` run as a
 * few instructions in the caller instead of a runtime call.
 *
 * Lowering calls `msrt_string_view(text, start, end, out)`, which checks the bounds and writes a view of the
 * receiver's bytes through `out`. The common case is decided from the receiver's two words: a range inside
 * the text that starts and ends on scalar boundaries (an ASCII flag, or a look at the two bytes). A piece of
 * up to fifteen bytes is copied into the two words of an inline string; a longer one is a view over the
 * bytes. Everything else (an empty range, a negative bound, a fault) calls the runtime.
 *
 * The fast path is one generated function marked `inline(always)`, shared by every call site.
 * The bit layout is
 * src/runtime/include/ms_rt/string.h. */
#include "compiler/opt/opt_pass.h"
#include "compiler/opt/opt_build.h"

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
 * at the two bytes proves otherwise. A byte is read only at an offset below `len`: a string is not promised a
 * byte after its last (a heap text can end at the end of a page), and the end of the text is a boundary anyway.
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
  const MirBlock after_start = mir_b_new_block(b), check_start = mir_b_new_block(b), check_end = mir_b_new_block(b);
  mir_b_br_if(b, ok, bounded, NULL, 0, v->slow, NULL, 0);
  mir_b_seal_block(b, bounded);
  mir_b_switch_to(b, bounded);
  mir_b_br_if(b, flagged, fast, NULL, 0, scan, NULL, 0);
  mir_b_seal_block(b, scan);
  mir_b_switch_to(b, scan);
  const MirValue bytes = ob_load(b, v->slot, 0, MIR_PTR);
  mir_b_br_if(b, mir_b_icmp(b, MCC_EQ, v->start, len), fast, NULL, 0, check_start, NULL, 0); /* empty, at the end */
  mir_b_seal_block(b, check_start);
  mir_b_switch_to(b, check_start);
  mir_b_br_if(b, vf_boundary(b, bytes, v->start), after_start, NULL, 0, v->slow, NULL, 0);
  mir_b_seal_block(b, after_start);
  mir_b_switch_to(b, after_start);
  mir_b_br_if(b, mir_b_icmp(b, MCC_EQ, v->end, len), fast, NULL, 0, check_end, NULL, 0);
  mir_b_seal_block(b, check_end);
  mir_b_switch_to(b, check_end);
  mir_b_br_if(b, vf_boundary(b, bytes, v->end), fast, NULL, 0, v->slow, NULL, 0);
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
static void vf_entry(MirBuilder *b, VfView *v, MirBlock inline_block, MirBlock flat_block) {
  v->slot = mir_b_emit(b, MOP_Slot, NULL, 0, (MirImm){.tag = MI_TY, .a = MIR_STR}, MIR_PTR);
  const MirValue spill[2] = {v->slot, v->text};
  (void)mir_b_emit(b, MOP_Store, spill, 2, (MirImm){0}, MIR_NONE);
  v->w1 = ob_load(b, v->slot, VF_WORD, MIR_INT);
  const MirValue tag = ob_int(b, MOP_Ushr, v->w1, VF_TAG_SHIFT);
  const MirValue is_inline = mir_b_icmp(b, MCC_EQ, tag, mir_b_iconst(b, 1));
  mir_b_br_if(b, is_inline, inline_block, NULL, 0, flat_block, NULL, 0);
  mir_b_seal_block(b, inline_block);
  mir_b_seal_block(b, flat_block);
}

/* The string the view was written to: a view is only read (it answers no owner), a slice is taken out of its slot. */
static MirValue vf_piece(MirBuilder *b, MirValue out) {
  return mir_b_emit(b, b->func.ret_borrowed ? MOP_Load : MOP_Take, &out, 1, (MirImm){.tag = MI_TY, .a = MIR_STR}, MIR_STR);
}

/* The short result: the bytes packed inline, then on to `join`. */
static void vf_short_join(MirBuilder *bp, const VfView *vp, MirBlock short_block, MirValue short_p, MirValue short_n,
                          MirBlock join, bool slice) {
  const VfView v = *vp;
  mir_b_switch_to(bp, short_block);
  vf_short_block(bp, &v, short_p, short_n);
  if (slice) {
    const MirValue piece = vf_piece(bp, v.out);
    mir_b_br(bp, join, &piece, 1);
  } else {
    mir_b_br(bp, join, NULL, 0);
  }
}

/* The block that hands the range to the runtime function `slow_ext`. */
static void vf_slow_block(MirBuilder *bp, const VfView *v_, uint32_t slow_ext, MirBlock join, bool slice) {
  const VfView v = *v_;
  mir_b_seal_block(bp, v.slow);
  mir_b_switch_to(bp, v.slow); // the runtime handles the rest
  if (slice) {
    const MirValue rest[3] = {v.text, v.start, v.end};
    const MirValue copy = mir_b_call_rt(bp, slow_ext, rest, 3);
    mir_b_br(bp, join, &copy, 1);
  } else {
    const MirValue rest[4] = {v.text, v.start, v.end, v.out};
    (void)mir_b_call_rt(bp, slow_ext, rest, 4);
    mir_b_br(bp, join, NULL, 0);
  }
}

/* The runtime functions this pass replaces, told apart by role and signature (no name is read). `String.view` and
 * `Bytes.view` are borrowing natives of a receiver, two bounds and the address the view goes to; the receiver is a
 * string or a byte list. `String.slice` has its own role and returns the copy. */
typedef enum VfKind { VK_NONE, VK_STRING_VIEW, VK_STRING_SLICE, VK_STRING_VIEW_VALUE, VK_BYTES_VIEW } VfKind;

/* Builds `string_view(text, start, end, out)` (`slice` false) or `string_slice(text, start, end) -> String`, which
 * calls the runtime function `slow_ext` when the fast path does not apply. A view longer than fifteen bytes
 * borrows the receiver's bytes; a longer slice is an owned copy, so it takes the runtime. The slice writes its
 * piece to a slot of its own and takes it. */
static uint32_t vf_build(MirModule *m, uint32_t slow_ext, VfKind kind) {
  const bool borrowed = kind == VK_STRING_VIEW_VALUE;
  const bool slice = kind == VK_STRING_SLICE || borrowed; /* the value forms return the string */
  const MirParam params[4] = {{MIR_STR, MM_BORROW}, {MIR_INT, MM_BORROW}, {MIR_INT, MM_BORROW}, {MIR_PTR, MM_BORROW}};
  MirBuilder b;
  mir_b_init_fast_path(&b, m, mir_name(m, ms_span_of_text(borrowed ? "string_view_value" : slice ? "string_slice" : "string_view")), params,
            slice ? 3 : 4, slice ? MIR_STR : MIR_VOID);
  b.func.ret_borrowed = borrowed; /* a view answers no owner */
  VfView v = {0};
  MirValue ps[4];
  mir_b_params(&b, ps, slice ? 3 : 4);
  v.text = ps[0];
  v.start = ps[1];
  v.end = ps[2];
  v.out = ps[3];
  v.slow = mir_b_new_block(&b);
  const MirBlock join = mir_b_new_block(&b);
  MirValue result = MIR_NONE;
  if (slice) {
    result = mir_b_add_block_param(&b, join, MIR_STR, borrowed ? MM_BORROW : MM_MOVE);
  }
  const MirBlock flat_block = mir_b_new_block(&b);
  const MirBlock inline_block = mir_b_new_block(&b);
  vf_entry(&b, &v, inline_block, flat_block);
  if (slice) {
    v.out = mir_b_emit(&b, MOP_Slot, NULL, 0, (MirImm){.tag = MI_TY, .a = MIR_STR}, MIR_PTR);
  }
  const MirBlock short_block = mir_b_new_block(&b);
  const MirBlock long_block = kind == VK_STRING_SLICE ? v.slow : mir_b_new_block(&b);
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
  if (kind != VK_STRING_SLICE) {
    mir_b_seal_block(&b, long_block);
    mir_b_switch_to(&b, long_block); // longer text: a view over the bytes, tagged as borrowed
    vf_store_words(&b, v.out, flat_from, ob_int(&b, MOP_Or, flat_n, (int64_t)(3ULL << VF_TAG_SHIFT)));
    if (slice) {
      const MirValue view = vf_piece(&b, v.out);
      mir_b_br(&b, join, &view, 1);
    } else {
      mir_b_br(&b, join, NULL, 0);
    }
  }
  vf_short_join(&b, &v, short_block, short_p, short_n, join, slice);
  vf_slow_block(&b, &v, slow_ext, join, slice);
  mir_b_seal_block(&b, join);
  mir_b_switch_to(&b, join);
  mir_b_ret(&b, slice ? result : mir_b_unit(&b));
  uint32_t id = MIR_NONE;
  return mir_b_finish(&b, &id) ? id : MIR_NONE;
}

/* `Bytes.view(start, end)` on a range that is in bounds and not empty is the view `{ptr + start, end - start, 0}`;
 * an empty range, a negative bound or a fault continues in the runtime. `bytes` is the list itself, or its address
 * when it is held in memory. */
static uint32_t vf_build_bytes(MirModule *m, uint32_t slow_ext, MirTy bytes_ty) {
  const MirParam params[4] = {{bytes_ty, MM_BORROW}, {MIR_INT, MM_BORROW}, {MIR_INT, MM_BORROW}, {MIR_PTR, MM_BORROW}};
  MirBuilder b;
  mir_b_init_fast_path(&b, m, mir_name(m, ms_span_of_text(bytes_ty == MIR_PTR ? "bytes_view_at" : "bytes_view")), params, 4,
            MIR_VOID);
  MirValue ps[4];
  mir_b_params(&b, ps, 4);
  const MirValue bytes = ps[0], start = ps[1], end = ps[2], out = ps[3];
  const MirBlock fast = mir_b_new_block(&b), slow = mir_b_new_block(&b), join = mir_b_new_block(&b);
  MirValue list = bytes;
  if (bytes_ty != MIR_PTR) {
    list = mir_b_emit(&b, MOP_Slot, NULL, 0, (MirImm){.tag = MI_TY, .a = bytes_ty}, MIR_PTR);
    const MirValue spill[2] = {list, bytes};
    (void)mir_b_emit(&b, MOP_Store, spill, 2, (MirImm){0}, MIR_NONE);
  }
  const MirValue len = ob_load(&b, list, VF_WORD, MIR_INT);
  const MirValue zero = mir_b_iconst(&b, 0);
  MirValue ok = ob_and(&b, mir_b_icmp(&b, MCC_GE, start, zero), mir_b_icmp(&b, MCC_LT, start, end));
  ok = ob_and(&b, ok, mir_b_icmp(&b, MCC_LE, end, len));
  mir_b_br_if(&b, ok, fast, NULL, 0, slow, NULL, 0);
  mir_b_seal_block(&b, fast);
  mir_b_seal_block(&b, slow);
  mir_b_switch_to(&b, fast);
  const MirValue data = ob_load(&b, list, 0, MIR_PTR);
  const MirValue first = ob_past(&b, data, start);
  const MirValue n = mir_b_binop(&b, MOP_ISub, end, start);
  const MirValue lo[2] = {out, first};
  (void)mir_b_emit(&b, MOP_Store, lo, 2, (MirImm){0}, MIR_NONE);
  const MirValue mid[2] = {ob_add(&b, out, VF_WORD), n};
  (void)mir_b_emit(&b, MOP_Store, mid, 2, (MirImm){0}, MIR_NONE);
  const MirValue hi[2] = {ob_add(&b, out, (int64_t)2 * VF_WORD), zero};
  (void)mir_b_emit(&b, MOP_Store, hi, 2, (MirImm){0}, MIR_NONE);
  mir_b_br(&b, join, NULL, 0);
  mir_b_switch_to(&b, slow);
  const MirValue rest[4] = {bytes, start, end, out};
  (void)mir_b_call_rt(&b, slow_ext, rest, 4);
  mir_b_br(&b, join, NULL, 0);
  mir_b_seal_block(&b, join);
  mir_b_switch_to(&b, join);
  mir_b_ret(&b, mir_b_unit(&b));
  uint32_t id = MIR_NONE;
  return mir_b_finish(&b, &id) ? id : MIR_NONE;
}


static VfKind vf_kind(const MirExtern *e) {
  if (e->role == MR_STRING_SLICE) {
    const bool shape = e->nparams == 3 && e->ret == MIR_STR && e->params[0].ty == MIR_STR &&
             e->params[1].ty == MIR_INT && e->params[2].ty == MIR_INT;
    return shape ? VK_STRING_SLICE : VK_NONE;
  }
  if (e->role == MR_VIEW_RESULT) {
    /* The borrowing `String.view`, which lowering calls as a function returning the view. */
    const bool shape = e->nparams == 3 && e->ret == MIR_STR && e->params[0].ty == MIR_STR &&
                       e->params[1].ty == MIR_INT && e->params[2].ty == MIR_INT;
    return shape ? VK_STRING_VIEW_VALUE : VK_NONE;
  }
  if (e->role != MR_BORROWS_ARGUMENT || e->nparams != 4 || e->ret != MIR_VOID || e->params[1].ty != MIR_INT ||
    e->params[2].ty != MIR_INT || e->params[3].ty != MIR_PTR) {
    return VK_NONE;
  }
  if (e->params[0].ty == MIR_STR) {
    return VK_STRING_VIEW;
  }
  return e->params[0].ty == MIR_BYTES || e->params[0].ty == MIR_PTR ? VK_BYTES_VIEW : VK_NONE;
}

/* One generated function per kind and receiver type. */
typedef struct VfHelper {
  VfKind kind;
  MirTy ty;
  uint32_t func;
} VfHelper;

bool opt_viewfast(MirModule *m) {
  const uint32_t original = (uint32_t)m->funcs.len; /* the helpers keep their own calls to the runtime */
  VfHelper *helpers = NULL;
  uint32_t nhelpers = 0, chelpers = 0;
  bool changed = false;
  for (uint32_t fi = 0; fi < original; fi++) {
    for (uint32_t bi = 0; bi < m->funcs.ptr[fi].blocks.len; bi++) {
      for (uint32_t ii = 0; ii < m->funcs.ptr[fi].blocks.ptr[bi].insts.len; ii++) {
        MirInst *inst = &m->funcs.ptr[fi].blocks.ptr[bi].insts.ptr[ii];
        if (inst->op != MOP_CallRt) {
          continue;
        }
        const MirExtern *e = &m->externs.ptr[inst->imm.a];
        const VfKind kind = vf_kind(e);
        if (kind == VK_NONE) {
          continue;
        }
        const MirTy ty = e->params[0].ty;
        uint32_t helper = MIR_NONE;
        for (uint32_t h = 0; h < nhelpers; h++) {
          if (helpers[h].kind == kind && helpers[h].ty == ty) {
            helper = helpers[h].func;
          }
        }
        if (helper == MIR_NONE) {
          helper = kind == VK_BYTES_VIEW ? vf_build_bytes(m, inst->imm.a, ty) : vf_build(m, inst->imm.a, kind);
          if (helper == MIR_NONE) {
            continue;
          }
          OPT_PUSH(&m->arena, helpers, nhelpers, chelpers, VfHelper, ((VfHelper){kind, ty, helper}));
          inst = &m->funcs.ptr[fi].blocks.ptr[bi].insts.ptr[ii]; /* the function array may have moved */
        }
        inst->op = MOP_Call;
        inst->imm = (MirImm){.tag = MI_FUNC, .a = helper};
        changed = true;
      }
    }
  }
  return changed;
}
