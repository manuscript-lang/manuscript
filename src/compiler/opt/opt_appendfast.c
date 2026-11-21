/* The `appendfast` pass: `s += piece` on an owned string with room left runs as a few
 * instructions in the caller instead of a runtime call.
 *
 * strfuse turns a concatenation whose left side dies into `string_append`, which grows the block
 * in place. The runtime call decodes both strings, asks the allocator how much room the block has
 * and copies. An owned string records its spare room in its second word, so the common case is
 * decided from the two words: an owned receiver, a piece of 1 to 16 bytes (inline, or flat not
 * inside the receiver), room for it, and an ASCII flag that stays true. That case writes the
 * piece, the NUL and the new length word. Every other case calls the runtime.
 *
 * The fast path is one generated function marked `inline(always)`, shared by every call site.
 * The bit layout is src/runtime/include/ms_rt/string.h. */

#include "compiler/mir/mir_analysis.h"
#include "compiler/mir/mir_builder.h"
#include "compiler/opt/opt_pass.h"
#include "compiler/opt/opt_build.h"

enum {
  AF_MAX_PIECE = 16,         /* longest piece the fast path copies */
  AF_TAG_SHIFT = 62,
  AF_INLINE_LEN_SHIFT = 56,
  AF_INLINE_MAX = 15,
  AF_SPARE_SHIFT = 31
};
#define AF_LEN_MASK ((INT64_C(1) << 31) - 1)
#define AF_SPARE_FIELD ((INT64_C(1) << 30) - 1)
#define AF_ASCII (INT64_C(1) << 61)

static void af_storeu(MirBuilder *b, MirValue p, MirValue v, int64_t width) {
  const MirValue args[2] = {p, v};
  (void)mir_b_emit(b, MOP_PtrStoreU, args, 2, (MirImm){.tag = MI_INT, .i = width}, MIR_NONE);
}

/* Copies `width` bytes at the start and at `n - back` of `src` to `dst`, loading both before
 * storing so the ranges may touch; then branches to `done`. */
static void af_copy_ends(MirBuilder *b, MirValue src, MirValue dst, MirValue n, int64_t width,
            MirBlock done) {
  const MirValue back = ob_int(b, MOP_ISub, n, width);
  const MirValue src_hi = ob_past(b, src, back), dst_hi = ob_past(b, dst, back);
  const MirValue lo = ob_loadu(b, src, width), hi = ob_loadu(b, src_hi, width);
  af_storeu(b, dst, lo, width);
  af_storeu(b, dst_hi, hi, width);
  mir_b_br(b, done, NULL, 0);
}

/* One to three bytes: the first, middle and last. */
static void af_copy_small(MirBuilder *b, MirValue src, MirValue dst, MirValue n, MirBlock done) {
  const MirValue half = ob_int(b, MOP_Ushr, n, 1), last = ob_int(b, MOP_ISub, n, 1);
  const MirValue src_mid = ob_past(b, src, half), src_last = ob_past(b, src, last);
  const MirValue dst_mid = ob_past(b, dst, half), dst_last = ob_past(b, dst, last);
  const MirValue x0 = ob_loadu(b, src, 1), x1 = ob_loadu(b, src_mid, 1);
  const MirValue x2 = ob_loadu(b, src_last, 1);
  af_storeu(b, dst, x0, 1);
  af_storeu(b, dst_mid, x1, 1);
  af_storeu(b, dst_last, x2, 1);
  mir_b_br(b, done, NULL, 0);
}

/* Copies `n` (1 to 16) bytes from `src` to `dst` with overlapping fixed-width moves. */
static void af_copy_short(MirBuilder *b, MirValue src, MirValue dst, MirValue n) {
  const MirBlock big = mir_b_new_block(b), rest = mir_b_new_block(b), mid = mir_b_new_block(b);
  const MirBlock small = mir_b_new_block(b), done = mir_b_new_block(b);
  mir_b_br_if(b, mir_b_icmp(b, MCC_GE, n, mir_b_iconst(b, 8)), big, NULL, 0, rest, NULL, 0);
  mir_b_seal_block(b, big);
  mir_b_seal_block(b, rest);
  mir_b_switch_to(b, big);
  af_copy_ends(b, src, dst, n, 8, done);
  mir_b_switch_to(b, rest);
  mir_b_br_if(b, mir_b_icmp(b, MCC_GE, n, mir_b_iconst(b, 4)), mid, NULL, 0, small, NULL, 0);
  mir_b_seal_block(b, mid);
  mir_b_seal_block(b, small);
  mir_b_switch_to(b, mid);
  af_copy_ends(b, src, dst, n, 4, done);
  mir_b_switch_to(b, small);
  af_copy_small(b, src, dst, n, done);
  mir_b_seal_block(b, done);
  mir_b_switch_to(b, done);
}

/* The two strings' words in their slots, and the facts decided from them. */
typedef struct AfWords {
  MirValue slot_a, slot_b;
  MirValue aw0, aw1, bw0, bw1;
  MirValue zero, one;
} AfWords;

static MirValue af_slot(MirBuilder *b) {
  return mir_b_emit(b, MOP_Slot, NULL, 0, (MirImm){.tag = MI_TY, .a = MIR_STR}, MIR_PTR);
}

static void af_spill(MirBuilder *b, MirValue a, MirValue piece, AfWords *w) {
  w->slot_a = af_slot(b);
  MirValue args[2] = {w->slot_a, a};
  (void)mir_b_emit(b, MOP_Put, args, 2, (MirImm){0}, MIR_NONE);
  w->slot_b = af_slot(b);
  args[0] = w->slot_b;
  args[1] = piece;
  (void)mir_b_emit(b, MOP_Store, args, 2, (MirImm){0}, MIR_NONE);
  w->aw0 = ob_load(b, w->slot_a, 0, MIR_INT);
  w->aw1 = ob_load(b, w->slot_a, 8, MIR_INT);
  w->bw0 = ob_load(b, w->slot_b, 0, MIR_INT);
  w->bw1 = ob_load(b, w->slot_b, 8, MIR_INT);
  w->zero = mir_b_iconst(b, 0);
  w->one = mir_b_iconst(b, 1);
}

static MirValue af_or(MirBuilder *b, MirValue x, MirValue y) { return mir_b_binop(b, MOP_Or, x, y); }

/* Whether the piece is ASCII, as the receiver's flag stays valid; `inline_piece` selects how the
 * piece records it. */
static MirValue af_ascii(MirBuilder *b, const AfWords *w, MirValue inline_piece) {
  const MirValue a_flag = ob_int(b, MOP_And, w->aw1, AF_ASCII);
  const MirValue b_flag = ob_int(b, MOP_And, w->bw1, AF_ASCII);
  const MirValue a_plain = mir_b_icmp(b, MCC_EQ, a_flag, w->zero);
  const MirValue b_flagged = mir_b_icmp(b, MCC_NE, b_flag, w->zero);
  const MirValue high0 = ob_int(b, MOP_And, w->bw0, (int64_t)UINT64_C(0x8080808080808080));
  const MirValue high1 = ob_int(b, MOP_And, w->bw1, INT64_C(0x0080808080808080));
  const MirValue bits_ascii = mir_b_icmp(b, MCC_EQ, af_or(b, high0, high1), w->zero);
  const MirValue b_ascii = mir_b_select(b, inline_piece, bits_ascii, b_flagged);
  return af_or(b, a_plain, b_ascii);
}

/* Emits the fast-path condition into the current block; `la` and `lb` receive the lengths. */
static MirValue af_condition(MirBuilder *b, const AfWords *w, MirValue *la, MirValue *lb,
              MirValue *inline_piece) {
  const MirValue atag = ob_int(b, MOP_Ushr, w->aw1, AF_TAG_SHIFT);
  const MirValue owned = mir_b_icmp(b, MCC_EQ, atag, w->zero);
  *la = ob_int(b, MOP_And, w->aw1, AF_LEN_MASK);
  const MirValue has_text = mir_b_icmp(b, MCC_GT, *la, w->zero);
  const MirValue btag = ob_int(b, MOP_Ushr, w->bw1, AF_TAG_SHIFT);
  *inline_piece = mir_b_icmp(b, MCC_EQ, btag, w->one);
  MirValue inline_len = ob_int(b, MOP_Ushr, w->bw1, AF_INLINE_LEN_SHIFT);
  inline_len = ob_int(b, MOP_And, inline_len, AF_INLINE_MAX);
  const MirValue flat_len = ob_int(b, MOP_And, w->bw1, AF_LEN_MASK);
  *lb = mir_b_select(b, *inline_piece, inline_len, flat_len);
  const MirValue some = mir_b_icmp(b, MCC_GT, *lb, w->zero);
  const MirValue short_piece = mir_b_icmp(b, MCC_LE, *lb, mir_b_iconst(b, AF_MAX_PIECE));
  MirValue spare = ob_int(b, MOP_Ushr, w->aw1, AF_SPARE_SHIFT);
  spare = ob_int(b, MOP_And, spare, AF_SPARE_FIELD);
  const MirValue room = mir_b_icmp(b, MCC_GE, spare, *lb);
  const MirValue end = mir_b_binop(b, MOP_IAdd, w->aw0, *la);
  const MirValue below = mir_b_icmp(b, MCC_LT, w->bw0, w->aw0);
  const MirValue above = mir_b_icmp(b, MCC_GT, w->bw0, end);
  const MirValue apart = af_or(b, *inline_piece, af_or(b, below, above));
  const MirValue ascii = af_ascii(b, w, *inline_piece);
  MirValue ok = owned;
  const MirValue rest[6] = {has_text, some, short_piece, room, apart, ascii};
  for (uint32_t i = 0; i < 6; i++) {
    ok = ob_and(b, ok, rest[i]);
  }
  return ok;
}

static MirValue af_take(MirBuilder *b, MirValue slot) {
  return mir_b_emit(b, MOP_Take, &slot, 1, (MirImm){.tag = MI_TY, .a = MIR_STR}, MIR_STR);
}

/* The fast block: copy the piece, write the NUL and the new length word, return the string. */
static void af_fast_block(MirBuilder *b, const AfWords *w, MirValue la, MirValue lb,
             MirValue inline_piece) {
  const MirValue text = ob_load(b, w->slot_a, 0, MIR_PTR);
  const MirValue flat_from = ob_load(b, w->slot_b, 0, MIR_PTR);
  const MirValue from = mir_b_select(b, inline_piece, w->slot_b, flat_from);
  const MirValue dst = ob_past(b, text, la);
  af_copy_short(b, from, dst, lb);
  af_storeu(b, ob_past(b, dst, lb), w->zero, 1);
  const MirValue grown = mir_b_binop(b, MOP_IAdd, w->aw1, lb);
  const MirValue used = ob_int(b, MOP_Shl, lb, AF_SPARE_SHIFT);
  const MirValue tagged = mir_b_binop(b, MOP_ISub, grown, used);
  const MirValue args[2] = {ob_add(b, w->slot_a, 8), tagged};
  (void)mir_b_emit(b, MOP_Store, args, 2, (MirImm){0}, MIR_NONE);
  mir_b_ret(b, af_take(b, w->slot_a));
}

/* Builds `string_append_fast(a: owned str, b: str) -> str`, which calls `slow` when the fast
 * path does not apply. */
static uint32_t af_build(MirModule *m, uint32_t slow) {
  const MirParam params[2] = {{MIR_STR, MM_MOVE}, {MIR_STR, MM_BORROW}};
  MirBuilder b;
  mir_b_init_fast_path(&b, m, mir_name(m, ms_span_of_text("string_append_fast")), params, 2, MIR_STR);
  MirValue ps[2];
  mir_b_params(&b, ps, 2);
  const MirBlock fast = mir_b_new_block(&b), slow_block = mir_b_new_block(&b);
  AfWords w = {0};
  af_spill(&b, ps[0], ps[1], &w);
  MirValue la = MIR_NONE, lb = MIR_NONE, inline_piece = MIR_NONE;
  const MirValue ok = af_condition(&b, &w, &la, &lb, &inline_piece);
  mir_b_br_if(&b, ok, fast, NULL, 0, slow_block, NULL, 0);
  mir_b_seal_block(&b, fast);
  mir_b_seal_block(&b, slow_block);
  mir_b_switch_to(&b, fast);
  af_fast_block(&b, &w, la, lb, inline_piece);
  mir_b_switch_to(&b, slow_block);
  const MirValue taken[2] = {af_take(&b, w.slot_a), ps[1]};
  mir_b_ret(&b, mir_b_call_rt(&b, slow, taken, 2));
  uint32_t id = MIR_NONE;
  return mir_b_finish(&b, &id) ? id : MIR_NONE;
}

/* The first `string_append` call site's extern, or MIR_NONE. */
static uint32_t af_first_site(const MirModule *m) {
  for (uint32_t fi = 0; fi < m->funcs.len; fi++) {
    const MirFunc *f = &m->funcs.ptr[fi];
    for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
      for (uint32_t ii = 0; ii < f->blocks.ptr[bi].insts.len; ii++) {
        const MirInst *inst = &f->blocks.ptr[bi].insts.ptr[ii];
        if (inst->op == MOP_CallRt && m->externs.ptr[inst->imm.a].role == MR_STRING_APPEND) {
          return inst->imm.a;
        }
      }
    }
  }
  return MIR_NONE;
}

bool opt_appendfast(MirModule *m) {
  const uint32_t slow = af_first_site(m);
  if (slow == MIR_NONE) {
    return false;
  }
  const uint32_t original = (uint32_t)m->funcs.len; /* the helper keeps its own call to the runtime */
  const uint32_t helper = af_build(m, slow);
  if (helper == MIR_NONE) {
    return false;
  }
  for (uint32_t fi = 0; fi < original; fi++) {
    MirFunc *f = &m->funcs.ptr[fi];
    for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
      for (uint32_t ii = 0; ii < f->blocks.ptr[bi].insts.len; ii++) {
        MirInst *inst = &f->blocks.ptr[bi].insts.ptr[ii];
        if (inst->op != MOP_CallRt || m->externs.ptr[inst->imm.a].role != MR_STRING_APPEND) {
          continue;
        }
        inst->op = MOP_Call;
        inst->imm = (MirImm){.tag = MI_FUNC, .a = helper};
      }
    }
  }
  return true;
}
