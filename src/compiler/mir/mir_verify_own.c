/* The ownership half of the MIR verifier: sets of live values, linear ownership across blocks, and the check
 * that closures borrowing their maker's frame stay inside it.
 *
 * Ownership is checked on values whose type needs a drop. A value is owned when its defining instruction
 * returns an owned value (mir_result_mode), or it is a `move` parameter or block parameter; every other value is
 * borrowed. A consuming position needs an owned operand and removes it from the live set; a borrowing position
 * takes either, but an owned value must still be live. The live set must be the same on every edge into a block
 * and empty at `ret`. */
#include <stdarg.h>

#include "compiler/mir/mir_verify_internal.h"

/* ---- sets of values: sorted, ascending, no duplicates ---- */


/* The index of the first member that is not below `id`. */
uint32_t mvs_lower_bound(const MvSet *s, uint32_t id) {
  uint32_t lo = 0, hi = s->count;
  while (lo < hi) {
    uint32_t mid = lo + (hi - lo) / 2;
    if (s->ids[mid] < id) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

bool mvs_has(const MvSet *s, uint32_t id) {
  uint32_t at = mvs_lower_bound(s, id);
  return at < s->count && s->ids[at] == id;
}

void mvs_reserve(MsArena *arena, MvSet *s, uint32_t extra) {
  if (s->count + extra <= s->cap) {
    return;
  }
  uint32_t cap = s->cap == 0 ? 8 : s->cap;
  while (cap < s->count + extra) {
    cap *= 2;
  }
  uint32_t *grown = MS_ARENA_NEW_ARRAY(arena, uint32_t, cap);
  if (s->count > 0) {
    __builtin_memcpy(grown, s->ids, sizeof *grown * s->count);
  }
  s->ids = grown;
  s->cap = cap;
}

void mvs_add(MsArena *arena, MvSet *s, uint32_t id) {
  uint32_t at = mvs_lower_bound(s, id);
  if (at < s->count && s->ids[at] == id) {
    return;
  }
  mvs_reserve(arena, s, 1);
  __builtin_memmove(&s->ids[at + 1], &s->ids[at], sizeof *s->ids * (s->count - at));
  s->ids[at] = id;
  s->count++;
}

/* Removes `id`; false when it was not a member. */
bool mvs_remove(MvSet *s, uint32_t id) {
  uint32_t at = mvs_lower_bound(s, id);
  if (at >= s->count || s->ids[at] != id) {
    return false;
  }
  __builtin_memmove(&s->ids[at], &s->ids[at + 1], sizeof *s->ids * (s->count - at - 1));
  s->count--;
  return true;
}

MvSet mvs_clone(MsArena *arena, const MvSet *s) {
  MvSet c = {0};
  mvs_reserve(arena, &c, s->count);
  if (s->count > 0) {
    __builtin_memcpy(c.ids, s->ids, sizeof *c.ids * s->count);
  }
  c.count = s->count;
  return c;
}

bool mvs_equal(const MvSet *a, const MvSet *b) {
  return a->count == b->count && (a->count == 0 || __builtin_memcmp(a->ids, b->ids, sizeof *a->ids * a->count) == 0);
}

/* `%a, %b, ...` for the values in exactly one of the two sets, ascending. */
MsSpan mvs_difference_text(MsArena *arena, const MvSet *a, const MvSet *b) {
  MsStrBuild text = ms_strbuild_new();
  uint32_t i = 0, j = 0;
  while (i < a->count || j < b->count) {
    bool take_a = j >= b->count || (i < a->count && a->ids[i] <= b->ids[j]);
    uint32_t id = take_a ? a->ids[i] : b->ids[j];
    bool both = i < a->count && j < b->count && a->ids[i] == b->ids[j];
    i += (take_a || both) ? 1 : 0;
    j += (!take_a || both) ? 1 : 0;
    if (both) {
      continue;
    }
    ms_strbuild_printf(&text, ms_strbuild_length(&text) == 0 ? "%%%u" : ", %%%u", id);
  }
  MsSpan result = ms_arena_copy(arena, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  return result;
}

/* ---- closures that borrow their maker's frame must not outlive it ---- */

static bool mv_is_clone_into(const MirInst *in, const MirBits *family, MirValue *res) {
  if (in->op != MOP_Clone || in->nargs == 0 || in->res == MIR_NONE ||
    !mir_bits_test(family, in->args[0])) {
    return false;
  }
  *res = in->res;
  return true;
}

static bool mv_seed_family(const Mv *v, MirBits *family) {
  const MirFunc *f = v->cx.f;
  bool any = false;
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      const MirInst *in = &f->blocks.ptr[b].insts.ptr[i];
      if (in->op == MOP_ClosureNew && in->imm.tag == MI_FUNC && in->res != MIR_NONE &&
        in->imm.a < v->cx.m->funcs.len && v->cx.m->funcs.ptr[in->imm.a].scoped) {
        mir_bits_set(family, in->res);
        any = true;
      }
    }
  }
  return any;
}

/* One pass over the blocks adding copies and block parameters; true when the family grew. */
static bool mv_grow_family(const Mv *v, MirBits *family) {
  const MirFunc *f = v->cx.f;
  bool grew = false;
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    const MirBlockData *blk = &f->blocks.ptr[b];
    for (uint32_t i = 0; i < blk->insts.len; i++) {
      MirValue res = 0;
      if (mv_is_clone_into(&blk->insts.ptr[i], family, &res) && !mir_bits_test(family, res)) {
        mir_bits_set(family, res);
        grew = true;
      }
    }
    for (uint32_t k = 0; k < mir_term_ntargets(&blk->term); k++) {
      const MirTarget *t = mir_term_target_const(&blk->term, k);
      const MirBlockData *dest = &f->blocks.ptr[t->block];
      for (uint32_t a = 0; a < t->nargs && a < dest->params.len; a++) {
        MirValue p = dest->params.ptr[a].value;
        if (mir_bits_test(family, t->args[a]) && !mir_bits_test(family, p)) {
          mir_bits_set(family, p);
          grew = true;
        }
      }
    }
  }
  return grew;
}

static bool mv_keeps_closure(const Mv *v, const MirInst *in, uint32_t pos, MirMode mode,
              const MirBits *frame_slots) {
  /* A call to a function that keeps its closures, or the closure such a function builds around
   * one, is held by the checker until the promise is dropped. */
  bool entry = (in->op == MOP_Call || in->op == MOP_ClosureNew) && in->imm.tag == MI_FUNC &&
        v->cx.m->funcs.ptr[in->imm.a].keeps_scoped;
  if (entry) {
    return false;
  }
  switch ((MirOp)in->op) {
  case MOP_Drop: case MOP_Forget: case MOP_DropIf: case MOP_Clone: case MOP_CallInd:
    return false;
  case MOP_Store:
    /* A stack slot of this frame cannot outlive it. */
    return pos == 1 && !mir_bits_test(frame_slots, in->args[0]);
  default:
    return mode == MM_MOVE;
  }
}

static void mv_check_closure_uses(Mv *v, const MirBits *family, const MirBits *frame_slots) {
  const MirFunc *f = v->cx.f;
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    const MirBlockData *blk = &f->blocks.ptr[b];
    for (uint32_t i = 0; i < blk->insts.len; i++) {
      const MirInst *in = &blk->insts.ptr[i];
      const MirMode *modes = mv_modes(v, in);
      for (uint32_t k = 0; k < in->nargs; k++) {
        if (mir_bits_test(family, in->args[k]) &&
          mv_keeps_closure(v, in, k, modes[k], frame_slots)) {
          mv_err(v, b, "a closure that borrows its maker's variables is kept by %s",
             mv_op_name(in));
        }
      }
    }
    if (blk->term.kind == MT_RET && blk->term.value != MIR_NONE &&
      mir_bits_test(family, blk->term.value)) {
      mv_err(v, b, "a closure that borrows its maker's variables is returned");
    }
  }
}

void mv_scoped_closures(Mv *v) {
  const MirFunc *f = v->cx.f;
  MirBits family = mir_bits_new(&v->scratch, (uint32_t)f->values.len);
  if (!mv_seed_family(v, &family)) {
    return;
  }
  while (mv_grow_family(v, &family)) {
  }
  MirBits slots = mir_bits_new(&v->scratch, (uint32_t)f->values.len);
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      const MirInst *in = &f->blocks.ptr[b].insts.ptr[i];
      if (in->op == MOP_Slot && in->res != MIR_NONE) {
        mir_bits_set(&slots, in->res);
      }
    }
  }
  mv_check_closure_uses(v, &family, &slots);
}

/* ---- ownership ---- */

typedef struct MvOwn {
  Mv *v;
  bool *owned_def;        /* the value is defined owned */
  MirValue *owner_of;     /* the owned value a borrow points into, or MIR_NONE */
  bool *views;            /* the value points into its operands */
  MirValue *pointer_owner; /* the owner a pointer from a runtime lookup points into */
  bool *watched;          /* some borrow points into the owner: its drops matter */
  uint64_t **dropped_in;  /* per block: bit set of owners an explicit drop released on some path there, or NULL */
  uint64_t *dropped;      /* the block being walked: the same set, reused across blocks */
  uint32_t words;         /* 64-bit words in one bit set over the function's values */
  MvSet *entry_state;     /* per block: the live set on its first incoming edge */
  bool *has_entry;
  bool *back_target;      /* some edge into the block comes from a later block: its entry state is read again */
  MirValue *scratch_values; /* room for the largest operand list */
} MvOwn;

static bool *mv_flags(Mv *v, uint32_t n) {
  bool *p = MS_ARENA_NEW_ARRAY(&v->scratch, bool, n + 1);
  __builtin_memset(p, 0, sizeof *p * (n + 1));
  return p;
}

static MirValue *mv_values_none(Mv *v, uint32_t n) {
  MirValue *p = MS_ARENA_NEW_ARRAY(&v->scratch, MirValue, n + 1);
  for (uint32_t i = 0; i <= n; i++) {
    p[i] = MIR_NONE;
  }
  return p;
}

static uint32_t mv_max_operands(const MirFunc *f) {
  uint32_t most = 0;
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    const MirBlockData *blk = &f->blocks.ptr[b];
    for (uint32_t i = 0; i < blk->insts.len; i++) {
      most = blk->insts.ptr[i].nargs > most ? blk->insts.ptr[i].nargs : most;
    }
    for (uint32_t k = 0; k < mir_term_ntargets(&blk->term); k++) {
      uint32_t n = mir_term_target_const(&blk->term, k)->nargs;
      most = n > most ? n : most;
    }
  }
  return most;
}

/* Ownership mode of every value from its definition, and which block parameters take a borrowing
 * variant's views. */
static void mv_own_init(Mv *v, MvOwn *o) {
  const MirModule *m = v->cx.m;
  const MirFunc *f = v->cx.f;
  o->v = v;
  o->owned_def = mv_flags(v, (uint32_t)f->values.len);
  o->views = mv_flags(v, (uint32_t)f->values.len);
  o->watched = mv_flags(v, (uint32_t)f->values.len);
  o->owner_of = mv_values_none(v, (uint32_t)f->values.len);
  o->pointer_owner = mv_values_none(v, (uint32_t)f->values.len);
  o->words = (uint32_t)(f->values.len / 64) + 1;
  o->dropped_in = MS_ARENA_NEW_ARRAY(&v->scratch, uint64_t *, f->blocks.len + 1);
  o->dropped = MS_ARENA_NEW_ARRAY(&v->scratch, uint64_t, o->words);
  o->entry_state = MS_ARENA_NEW_ARRAY(&v->scratch, MvSet, f->blocks.len + 1);
  __builtin_memset(o->dropped_in, 0, sizeof *o->dropped_in * (f->blocks.len + 1));
  __builtin_memset(o->dropped, 0, sizeof *o->dropped * o->words);
  __builtin_memset(o->entry_state, 0, sizeof *o->entry_state * (f->blocks.len + 1));
  o->has_entry = mv_flags(v, (uint32_t)f->blocks.len);
  o->back_target = mv_flags(v, (uint32_t)f->blocks.len);
  o->scratch_values = mv_values_none(v, mv_max_operands(f));
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    const MirBlockData *blk = &f->blocks.ptr[b];
    for (uint32_t i = 0; i < blk->params.len; i++) {
      MirValue p = blk->params.ptr[i].value;
      o->owned_def[p] = mv_rc(v, p) && blk->params.ptr[i].mode == MM_MOVE;
      const MirTyData *d = mir_ty_data(m, mv_ty(v, p));
      o->views[p] = d->kind == MK_ALT && m->alts.ptr[d->id].borrowed != 0;
    }
    for (uint32_t i = 0; i < blk->insts.len; i++) {
      MirMode mode = MM_BORROW;
      const MirInst *in = &blk->insts.ptr[i];
      if (mir_result_mode(m, f, in, &mode) && mode == MM_MOVE) {
        o->owned_def[in->res] = true;
      }
    }
  }
}

/* The owned value `x` is, or the one it points into. */
static MirValue mv_owner_or_self(const MvOwn *o, MirValue x) {
  return o->owned_def[x] ? x : o->owner_of[x];
}

/* The dropped owners are a bit set over value ids, not a sorted array: a long function drops
 * thousands of watched owners and every block carries them, so the array form made verification
 * quadratic in memory with a large constant. */
static bool mvd_has(const uint64_t *bits, uint32_t id) {
  return (bits[id / 64] >> (id % 64) & 1) != 0;
}

/* Adds the set `from` to the one a successor block starts with. */
static void mvd_merge_into(MvOwn *o, MirBlock target, const uint64_t *from) {
  uint32_t last = o->words;
  while (last > 0 && from[last - 1] == 0) {
    last--;
  }
  if (last == 0) {
    return;
  }
  uint64_t **into = &o->dropped_in[target];
  if (*into == NULL) {
    *into = MS_ARENA_NEW_ARRAY(&o->v->scratch, uint64_t, o->words);
    __builtin_memset(*into, 0, sizeof **into * o->words);
  }
  for (uint32_t i = 0; i < last; i++) {
    (*into)[i] |= from[i];
  }
}

static void mv_report_dead_borrow(Mv *v, MirBlock bi, const MirInst *in, const uint64_t *dropped,
                 const MvOwn *o) {
  for (uint32_t k = 0; k < in->nargs; k++) {
    MirValue owner = o->owner_of[in->args[k]];
    if (owner != MIR_NONE && mvd_has(dropped, owner)) {
      mv_err(v, bi, "%s: %%%u points into %%%u, which was consumed before this use",
         mv_op_name(in), in->args[k], owner);
    }
  }
}

/* Records what the result of `in` points into. */
static void mv_track_result(MvOwn *o, const MirInst *in) {
  const Mv *v = o->v;
  MirValue r = in->res;
  if (r == MIR_NONE) {
    return;
  }
  o->views[r] = mir_result_views(v->cx.m, v->cx.f, in);
  if (in->nargs == 0) {
    return;
  }
  MirValue first = in->args[0];
  bool borrows_first = mv_rc(v, first) && !o->views[first];
  if (mv_rc(v, r) && !o->owned_def[r] && borrows_first) {
    o->owner_of[r] = mv_owner_or_self(o, first);
    if (o->owner_of[r] != MIR_NONE) {
      o->watched[o->owner_of[r]] = true;
    }
  }
  /* A runtime lookup (a map entry) returns a pointer into its first operand's storage, and a
   * `load` of that pointer reads a borrow of the same owner. */
  if (in->op == MOP_CallRt && !mv_rc(v, r) && borrows_first) {
    o->pointer_owner[r] = mv_owner_or_self(o, first);
  } else if (in->op == MOP_Load && mv_rc(v, r) && !o->owned_def[r] &&
       o->pointer_owner[first] != MIR_NONE) {
    o->owner_of[r] = o->pointer_owner[first];
    o->watched[o->owner_of[r]] = true;
  }
}

static bool mv_seen(const MirValue *list, uint32_t n, MirValue x) {
  for (uint32_t i = 0; i < n; i++) {
    if (list[i] == x) {
      return true;
    }
  }
  return false;
}

/* The operands of `in` against the live set: uses of consumed values, borrows passed to a moving
 * position and values consumed twice. */
static void mv_check_operands(MvOwn *o, MirBlock bi, const MirInst *in, MvSet *live) {
  Mv *v = o->v;
  const MirMode *modes = mv_modes(v, in);
  MirValue *consumed = o->scratch_values;
  uint32_t nconsumed = 0;
  for (uint32_t k = 0; k < in->nargs; k++) {
    MirValue a = in->args[k];
    if (!mv_rc(v, a)) {
      continue;
    }
    if (o->owned_def[a] && !mvs_has(live, a)) {
      mv_err(v, bi, "%s: %%%u used after it was consumed", mv_op_name(in), a);
    } else if (modes[k] != MM_MOVE) {
      continue;
    } else if (!o->owned_def[a]) {
      mv_err(v, bi, "%s: moving position needs an owned value, %%%u is borrowed (retain it first)",
         mv_op_name(in), a);
    } else if (mv_seen(consumed, nconsumed, a)) {
      mv_err(v, bi, "%s: %%%u consumed twice", mv_op_name(in), a);
    } else {
      consumed[nconsumed++] = a;
    }
  }
  for (uint32_t k = 0; k < in->nargs; k++) {
    if (modes[k] == MM_BORROW && mv_seen(consumed, nconsumed, in->args[k])) {
      mv_err(v, bi, "%s: %%%u is consumed and borrowed by the same instruction",
         mv_op_name(in), in->args[k]);
    }
  }
  for (uint32_t k = 0; k < nconsumed; k++) {
    (void)mvs_remove(live, consumed[k]);
  }
}

static void mv_own_inst(MvOwn *o, MirBlock bi, const MirInst *in, MvSet *live, uint64_t *dropped) {
  Mv *v = o->v;
  mv_report_dead_borrow(v, bi, in, dropped, o);
  if ((in->op == MOP_Drop || in->op == MOP_DropIf) && in->nargs > 0 && o->watched[in->args[0]]) {
    dropped[in->args[0] / 64] |= (uint64_t)1 << (in->args[0] % 64);
  }
  mv_track_result(o, in);
  mv_check_operands(o, bi, in, live);
  if (in->res != MIR_NONE && o->owned_def[in->res]) {
    mvs_add(&v->scratch, live, in->res);
  }
}

static void mv_own_ret(MvOwn *o, MirBlock bi, const MirTerm *t, MvSet *live) {
  Mv *v = o->v;
  MirValue x = t->value;
  if (x != MIR_NONE && mv_rc(v, x)) {
    if (v->cx.f->ret_borrowed) {
      if (o->owned_def[x]) {
        mv_err(v, bi, "ret: %%%u is owned, but this function returns a borrow; it would leak", x);
      }
    } else if (!o->owned_def[x]) {
      mv_err(v, bi, "ret: %%%u is borrowed; return an owned value (retain it first)", x);
    } else if (!mvs_remove(live, x)) {
      mv_err(v, bi, "ret: %%%u used after it was consumed", x);
    }
  }
  if (live->count > 0) {
    mv_err(v, bi, "ret: owned value %%%u is never released", live->ids[0]);
  }
}

/* The live set a successor starts with, after the edge's arguments are passed. */
static MvSet mv_edge_live(MvOwn *o, MirBlock bi, const MirTarget *t, const MvSet *live, bool last) {
  Mv *v = o->v;
  const MirBlockData *dest = &v->cx.f->blocks.ptr[t->block];
  /* The last edge out of a block takes the block's set as it is when it passes no values: the block
   * is finished with it, and copying it for every block made a long function quadratic. */
  MvSet after = last && t->nargs == 0 ? *live : mvs_clone(&v->scratch, live);
  MirValue *seen = o->scratch_values;
  uint32_t nseen = 0;
  for (uint32_t k = 0; k < t->nargs; k++) {
    MirValue a = t->args[k];
    if (!mv_rc(v, a)) {
      continue;
    }
    if (o->owned_def[a] && !mvs_has(live, a)) {
      mv_err(v, bi, "branch: %%%u used after it was consumed", a);
    } else if (dest->params.ptr[k].mode != MM_MOVE) {
      continue;
    } else if (!o->owned_def[a]) {
      mv_err(v, bi, "branch to b%u: parameter %%%u takes ownership but %%%u is borrowed",
         t->block, dest->params.ptr[k].value, a);
    } else if (mv_seen(seen, nseen, a)) {
      mv_err(v, bi, "branch to b%u: %%%u passed to two owning parameters", t->block, a);
    } else {
      seen[nseen++] = a;
      (void)mvs_remove(&after, a);
    }
  }
  return after;
}

/* Merges the live set `after` arriving over an edge into the successor's entry state. */
static void mv_merge_entry(MvOwn *o, MirBlock bi, MirBlock dest, MvSet after) {
  Mv *v = o->v;
  if (!o->has_entry[dest]) {
    o->has_entry[dest] = true;
    o->entry_state[dest] = after;
    return;
  }
  if (!mvs_equal(&o->entry_state[dest], &after)) {
    MsSpan diff = mvs_difference_text(&v->errs->arena, &o->entry_state[dest], &after);
    mv_err(v, bi, "branch to b%u: owned values differ between incoming edges (%S)", dest, diff);
  }
}

static void mv_own_edges(MvOwn *o, MirBlock bi, const MirTerm *term, const MvSet *live,
            const uint64_t *dropped) {
  Mv *v = o->v;
  uint32_t n = mir_term_ntargets(term);
  /* A borrow handed to a successor reads its owner's storage there, so the owner must not have
   * been dropped on the way. */
  for (uint32_t k = 0; k < n; k++) {
    const MirTarget *t = mir_term_target_const(term, k);
    for (uint32_t a = 0; a < t->nargs; a++) {
      MirValue owner = o->owner_of[t->args[a]];
      if (owner != MIR_NONE && mvd_has(dropped, owner)) {
        mv_err(v, bi, "branch: %%%u points into %%%u, which was consumed before this use",
           t->args[a], owner);
      }
    }
  }
  for (uint32_t k = 0; k < n; k++) {
    const MirTarget *t = mir_term_target_const(term, k);
    mvd_merge_into(o, t->block, dropped);
    mv_merge_entry(o, bi, t->block, mv_edge_live(o, bi, t, live, k + 1 == n));
  }
}

/* The blocks reachable from the entry in order; `live` starts as the entry state of the block. */
static bool mv_own_block_start(MvOwn *o, MirBlock bi, MvSet *live) {
  const MirBlockData *blk = &o->v->cx.f->blocks.ptr[bi];
  if (o->has_entry[bi]) {
    /* Every forward edge into the block has been merged by now, so only a later (back) edge
     * reads its entry state again; otherwise the block works on it in place. */
    *live = o->back_target[bi] ? mvs_clone(&o->v->scratch, &o->entry_state[bi]) : o->entry_state[bi];
  } else if (bi != 0) {
    return false;
  }
  for (uint32_t i = 0; i < blk->params.len; i++) {
    if (o->owned_def[blk->params.ptr[i].value]) {
      mvs_add(&o->v->scratch, live, blk->params.ptr[i].value);
    }
  }
  return true;
}

static void mv_own_block(MvOwn *o, MirBlock bi) {
  const MirBlockData *blk = &o->v->cx.f->blocks.ptr[bi];
  MvSet live = {0};
  if (!mv_own_block_start(o, bi, &live)) {
    return;
  }
  uint64_t *dropped = o->dropped;
  if (o->dropped_in[bi] != NULL) {
    __builtin_memcpy(dropped, o->dropped_in[bi], sizeof *dropped * o->words);
  } else {
    __builtin_memset(dropped, 0, sizeof *dropped * o->words);
  }
  for (uint32_t i = 0; i < blk->insts.len; i++) {
    mv_own_inst(o, bi, &blk->insts.ptr[i], &live, dropped);
  }
  if (blk->term.kind == MT_RET) {
    mv_own_ret(o, bi, &blk->term, &live);
  }
  mv_own_edges(o, bi, &blk->term, &live, dropped);
}

void mv_check_ownership(Mv *v, const MirBlock *rpo, uint32_t count) {
  MvOwn o;
  mv_own_init(v, &o);
  uint32_t *rank = MS_ARENA_NEW_ARRAY(&v->scratch, uint32_t, v->cx.f->blocks.len + 1);
  for (uint32_t i = 0; i < count; i++) {
    rank[rpo[i]] = i;
  }
  for (uint32_t i = 0; i < count; i++) {
    const MirTerm *term = &v->cx.f->blocks.ptr[rpo[i]].term;
    for (uint32_t k = 0; k < mir_term_ntargets(term); k++) {
      const MirBlock to = mir_term_target_const(term, k)->block;
      if (rank[to] <= i) {
        o.back_target[to] = true;
      }
    }
  }
  for (uint32_t i = 0; i < count; i++) {
    mv_own_block(&o, rpo[i]);
  }
}

