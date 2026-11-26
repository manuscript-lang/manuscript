/* The `simplify` pass: constant folding, algebraic identities, strength reduction, trivial
 * block-parameter elimination, branch folding, block merging, jump threading, dominator-scoped
 * value numbering and dead code elimination. This file holds the folding and the small rewrites;
 * opt_simplify_cfg.c holds control flow, value numbering and the map-probe rewrites.
 *
 * Checked operations are only weakened when the pass proves they cannot fault (constant operands
 * that do not overflow, a constant divisor other than 0 and -1). Owned droppable values are never
 * merged or deleted, so ownership stays linear. */
#include <math.h>

#include "compiler/opt/opt_simplify.h"
#include "compiler/opt/opt_util.h"

/* ---- helpers for the rewrites below ---- */

/* Removes the instructions flagged in `dead[bi][ii]` from every block. */
static void sm_term_use_state(void *ctx, MirValue v) {
  uint8_t *state = ctx;
  if (state[v] != 0) {
    state[v] = 2;
  }
}

static void sm_term_use_add2(void *ctx, MirValue v) {
  uint32_t *uses = ctx;
  uses[v] += 2;
}

/* An `opt.none_owned` whose every use is a drop owns nothing: the `none` and its drops go. */
static bool sm_dropped_nones(MirFunc *f) {
  MsArena arena = ms_arena_new();
  uint8_t *state = MS_ARENA_NEW_ARRAY(&arena, uint8_t, f->values.len); /* 0 not a none, 1 only dropped, 2 used */
  bool any = false;
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    for (uint32_t ii = 0; ii < f->blocks.ptr[bi].insts.len; ii++) {
      const MirInst *i = &f->blocks.ptr[bi].insts.ptr[ii];
      if (i->op == MOP_OptNoneOwned && i->res != MIR_NONE) {
        state[i->res] = 1;
        any = true;
      }
    }
  }
  bool changed = false;
  for (uint32_t bi = 0; any && bi < f->blocks.len; bi++) {
    const MirBlockData *b = &f->blocks.ptr[bi];
    for (uint32_t ii = 0; ii < b->insts.len; ii++) {
      for (uint32_t k = 0; k < b->insts.ptr[ii].nargs; k++) {
        const MirValue a = b->insts.ptr[ii].args[k];
        if (state[a] != 0 && !(b->insts.ptr[ii].op == MOP_Drop && k == 0)) {
          state[a] = 2;
        }
      }
    }
    mir_term_each_value(&b->term, sm_term_use_state, state);
  }
  for (uint32_t bi = 0; any && bi < f->blocks.len; bi++) {
    MirBlockData *b = &f->blocks.ptr[bi];
    uint32_t *list = MS_ARENA_NEW_ARRAY(&arena, uint32_t, (size_t)b->insts.len + 1);
    uint32_t n = 0;
    for (uint32_t ii = 0; ii < b->insts.len; ii++) {
      const MirInst *i = &b->insts.ptr[ii];
      const bool none = i->op == MOP_OptNoneOwned && i->res != MIR_NONE && state[i->res] == 1;
      const bool drop = i->op == MOP_Drop && i->nargs > 0 && state[i->args[0]] == 1;
      if (none || drop) {
        list[n++] = ii;
      }
    }
    if (n > 0) {
      mir_block_remove(b, list, n);
      changed = true;
    }
  }
  ms_arena_free(&arena);
  return changed;
}

/* An `opt.some` whose only use is its drop never needed the box: drop the payload instead. */
static bool sm_dropped_somes(MirFunc *f) {
  MsArena arena = ms_arena_new();
  uint32_t *uses = MS_ARENA_NEW_ARRAY(&arena, uint32_t, f->values.len);
  bool *dropped = MS_ARENA_NEW_ARRAY(&arena, bool, f->values.len);
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    const MirBlockData *b = &f->blocks.ptr[bi];
    for (uint32_t ii = 0; ii < b->insts.len; ii++) {
      const MirInst *i = &b->insts.ptr[ii];
      for (uint32_t k = 0; k < i->nargs; k++) {
        uses[i->args[k]]++;
      }
      if (i->op == MOP_Drop && i->nargs > 0) {
        dropped[i->args[0]] = true;
      }
    }
    mir_term_each_value(&b->term, sm_term_use_add2, uses);
  }
  /* Boxes used once, by a drop, with the payload they hold. */
  MirValue *payload = MS_ARENA_NEW_ARRAY(&arena, MirValue, f->values.len);
  bool any = false;
  for (uint32_t v = 0; v < f->values.len; v++) {
    payload[v] = MIR_NONE;
  }
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    for (uint32_t ii = 0; ii < f->blocks.ptr[bi].insts.len; ii++) {
      const MirInst *i = &f->blocks.ptr[bi].insts.ptr[ii];
      if (i->op == MOP_OptSome && i->res != MIR_NONE && i->nargs == 1 && uses[i->res] == 1 &&
        dropped[i->res]) {
        payload[i->res] = i->args[0];
        any = true;
      }
    }
  }
  for (uint32_t bi = 0; any && bi < f->blocks.len; bi++) {
    MirBlockData *b = &f->blocks.ptr[bi];
    uint32_t *list = MS_ARENA_NEW_ARRAY(&arena, uint32_t, (size_t)b->insts.len + 1);
    uint32_t n = 0;
    for (uint32_t ii = 0; ii < b->insts.len; ii++) {
      MirInst *i = &b->insts.ptr[ii];
      if (i->op == MOP_Drop && i->nargs > 0 && payload[i->args[0]] != MIR_NONE) {
        i->args[0] = payload[i->args[0]];
      }
    }
    /* The box is gone: its payload is dropped where the box was. */
    for (uint32_t ii = 0; ii < b->insts.len; ii++) {
      const MirInst *i = &b->insts.ptr[ii];
      if (i->op == MOP_OptSome && i->res != MIR_NONE && payload[i->res] != MIR_NONE) {
        list[n++] = ii;
      }
    }
    mir_block_remove(b, list, n);
  }
  ms_arena_free(&arena);
  return any;
}

/* Removes every instruction `dead(ctx, inst)` accepts. */
typedef bool (*SmDeadFn)(const void *ctx, const MirInst *inst);

static void sm_remove_if(MirFunc *f, MsArena *arena, SmDeadFn dead, const void *ctx) {
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    MirBlockData *b = &f->blocks.ptr[bi];
    uint32_t *list = MS_ARENA_NEW_ARRAY(arena, uint32_t, (size_t)b->insts.len + 1);
    uint32_t n = 0;
    for (uint32_t ii = 0; ii < b->insts.len; ii++) {
      if (dead(ctx, &b->insts.ptr[ii])) {
        list[n++] = ii;
      }
    }
    if (n > 0) {
      mir_block_remove(b, list, n);
    }
  }
}

/* Whether no operand of `inst` needs a drop. */
static bool sm_operands_plain(MirModule *m, const MirFunc *f, const MirInst *inst) {
  for (uint32_t k = 0; k < inst->nargs; k++) {
    if (mir_needs_drop(m, f->values.ptr[inst->args[k]])) {
      return false;
    }
  }
  return true;
}

/* Whether `inst` defines a value `subst` replaces. */
static bool sm_defines_substituted(const void *ctx, const MirInst *inst) {
  const OptSubst *s = ctx;
  return inst->res != MIR_NONE && s->to[inst->res] != MIR_NONE;
}

/* ---- known alternatives ---- */

typedef struct SmAlts {
  bool *known, *dead;
  uint32_t *kcase, *knargs;
  MirValue **kargs;
  OptSubst subst;
} SmAlts;

static bool sm_alts_collect(MirModule *m, const MirFunc *f, MsArena *arena, SmAlts *a) {
  a->known = MS_ARENA_NEW_ARRAY(arena, bool, f->values.len);
  a->kcase = MS_ARENA_NEW_ARRAY(arena, uint32_t, f->values.len);
  a->kargs = MS_ARENA_NEW_ARRAY(arena, MirValue *, f->values.len);
  a->knargs = MS_ARENA_NEW_ARRAY(arena, uint32_t, f->values.len);
  bool any = false;
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    for (uint32_t ii = 0; ii < f->blocks.ptr[bi].insts.len; ii++) {
      const MirInst *i = &f->blocks.ptr[bi].insts.ptr[ii];
      if (i->op != MOP_AltNew || i->imm.tag != MI_CASE || i->res == MIR_NONE ||
        !sm_operands_plain(m, f, i)) {
        continue;
      }
      a->known[i->res] = true;
      a->kcase[i->res] = i->imm.b;
      a->kargs[i->res] = i->args;
      a->knargs[i->res] = i->nargs;
      any = true;
    }
  }
  return any;
}

/* `alt.tag` of a known alternative is its case index; `alt.get` of the same case is the payload
 * operand. Returns whether a tag was folded. */
static bool sm_alts_fold(MirFunc *f, SmAlts *a) {
  bool changed = false;
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    for (uint32_t ii = 0; ii < f->blocks.ptr[bi].insts.len; ii++) {
      MirInst *i = &f->blocks.ptr[bi].insts.ptr[ii];
      if (i->nargs == 0 || !a->known[i->args[0]]) {
        continue;
      }
      const MirValue alt = i->args[0];
      if (i->op == MOP_AltTag) {
        i->op = MOP_IConst;
        i->imm = (MirImm){.tag = MI_INT, .i = (int64_t)a->kcase[alt]};
        i->nargs = 0;
        changed = true;
      } else if (i->op == MOP_AltGet && i->imm.tag == MI_ALTFIELD &&
           i->imm.b == a->kcase[alt] && i->res != MIR_NONE &&
           i->imm.c < a->knargs[alt]) {
        opt_subst_set(&a->subst, i->res, a->kargs[alt][i->imm.c]);
      }
    }
  }
  return changed;
}

static bool sm_dead_alt(const void *ctx, const MirInst *i) {
  const SmAlts *a = ctx;
  return (i->op == MOP_Drop && a->dead[i->args[0]]) || (i->res != MIR_NONE && a->dead[i->res]);
}

/* A value left with only its drop is never observed: delete both. */
static bool sm_alts_drop_dead(MirFunc *f, MsArena *arena, SmAlts *a) {
  uint32_t *uses = mir_use_counts(arena, f);
  uint32_t *drops = MS_ARENA_NEW_ARRAY(arena, uint32_t, f->values.len);
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    for (uint32_t ii = 0; ii < f->blocks.ptr[bi].insts.len; ii++) {
      const MirInst *i = &f->blocks.ptr[bi].insts.ptr[ii];
      if (i->op == MOP_Drop && a->known[i->args[0]]) {
        drops[i->args[0]]++;
      }
    }
  }
  a->dead = MS_ARENA_NEW_ARRAY(arena, bool, f->values.len);
  bool any = false;
  for (uint32_t v = 0; v < f->values.len; v++) {
    a->dead[v] = a->known[v] && uses[v] > 0 && uses[v] == drops[v];
    any |= a->dead[v];
  }
  if (any) {
    sm_remove_if(f, arena, sm_dead_alt, a);
  }
  return any;
}

/* Folds operations on an alternative built in the same function by `alt.new` with a case whose
 * payload needs no drop: `alt.tag` becomes the case index, `alt.get` of the same case becomes the
 * payload operand, and when only drops remain the construction and the drops are deleted. */
static bool sm_known_alts(MirModule *m, MirFunc *f) {
  MsArena arena = ms_arena_new();
  SmAlts a = {0};
  bool changed = false;
  if (sm_alts_collect(m, f, &arena, &a)) {
    a.subst = opt_subst_new(&arena, (uint32_t)f->values.len);
    changed = sm_alts_fold(f, &a);
    if (a.subst.count > 0) {
      sm_remove_if(f, &arena, sm_defines_substituted, &a.subst);
      opt_subst_apply(f, &a.subst);
      changed = true;
    }
    changed |= sm_alts_drop_dead(f, &arena, &a);
  }
  ms_arena_free(&arena);
  return changed;
}

/* ---- known interface boxes ---- */

typedef struct SmBoxes {
  MirValue *boxed;    /* box -> payload, MIR_NONE when not a candidate */
  MirValue *pointers; /* `iface.data` result -> box */
  uint32_t *handled, *uses;
} SmBoxes;

/* Every `iface.new` of a payload that needs no drop, and the `iface.data` pointers into them. */
static bool sm_boxes_collect(MirModule *m, const MirFunc *f, MsArena *arena, SmBoxes *x) {
  x->boxed = MS_ARENA_NEW_ARRAY(arena, MirValue, f->values.len);
  x->pointers = MS_ARENA_NEW_ARRAY(arena, MirValue, f->values.len);
  for (uint32_t v = 0; v < f->values.len; v++) {
    x->boxed[v] = x->pointers[v] = MIR_NONE;
  }
  bool any = false;
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    for (uint32_t ii = 0; ii < f->blocks.ptr[bi].insts.len; ii++) {
      const MirInst *i = &f->blocks.ptr[bi].insts.ptr[ii];
      if (i->op == MOP_IfaceNew && i->nargs == 1 && i->res != MIR_NONE &&
        !mir_needs_drop(m, f->values.ptr[i->args[0]])) {
        x->boxed[i->res] = i->args[0];
        any = true;
      }
    }
  }
  for (uint32_t bi = 0; any && bi < f->blocks.len; bi++) {
    for (uint32_t ii = 0; ii < f->blocks.ptr[bi].insts.len; ii++) {
      const MirInst *i = &f->blocks.ptr[bi].insts.ptr[ii];
      if (i->op == MOP_IfaceData && i->nargs == 1 && i->res != MIR_NONE &&
        x->boxed[i->args[0]] != MIR_NONE) {
        x->pointers[i->res] = i->args[0];
      }
    }
  }
  return any;
}

/* Counts the uses of each box and pointer that are drops, `iface.data` reads and loads of the
 * payload type. */
static void sm_boxes_count(const MirFunc *f, MsArena *arena, SmBoxes *x) {
  x->uses = mir_use_counts(arena, f);
  x->handled = MS_ARENA_NEW_ARRAY(arena, uint32_t, f->values.len);
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    for (uint32_t ii = 0; ii < f->blocks.ptr[bi].insts.len; ii++) {
      const MirInst *i = &f->blocks.ptr[bi].insts.ptr[ii];
      if (i->nargs != 1) {
        continue;
      }
      const MirValue a = i->args[0];
      const bool box_use = (i->op == MOP_Drop || i->op == MOP_IfaceData) &&
                x->boxed[a] != MIR_NONE;
      const bool payload_load = i->op == MOP_Load && x->pointers[a] != MIR_NONE &&
                   i->res != MIR_NONE &&
                   f->values.ptr[i->res] == f->values.ptr[x->boxed[x->pointers[a]]];
      x->handled[a] += box_use || payload_load;
    }
  }
}

/* Keeps only the boxes nothing else touches; false when none is left. */
static bool sm_boxes_prune(const MirFunc *f, MsArena *arena, SmBoxes *x) {
  bool *unplain_owner = MS_ARENA_NEW_ARRAY(arena, bool, f->values.len);
  for (uint32_t p = 0; p < f->values.len; p++) {
    if (x->pointers[p] != MIR_NONE && x->handled[p] != x->uses[p]) {
      unplain_owner[x->pointers[p]] = true;
    }
  }
  bool any = false;
  for (uint32_t b = 0; b < f->values.len; b++) {
    if (x->boxed[b] != MIR_NONE && (x->handled[b] != x->uses[b] || unplain_owner[b])) {
      x->boxed[b] = MIR_NONE;
    }
    any |= x->boxed[b] != MIR_NONE;
  }
  for (uint32_t p = 0; any && p < f->values.len; p++) {
    if (x->pointers[p] != MIR_NONE && x->boxed[x->pointers[p]] == MIR_NONE) {
      x->pointers[p] = MIR_NONE;
    }
  }
  return any;
}

static bool sm_dead_box(const void *ctx, const MirInst *i) {
  const SmBoxes *x = ctx;
  const bool first = i->nargs > 0;
  const bool dropped = i->op == MOP_Drop && first && x->boxed[i->args[0]] != MIR_NONE;
  const bool defines = i->res != MIR_NONE &&
            (x->boxed[i->res] != MIR_NONE || x->pointers[i->res] != MIR_NONE);
  const bool reads = i->op == MOP_Load && first && x->pointers[i->args[0]] != MIR_NONE;
  return dropped || defines || reads;
}

/* Removes the box of an interface value built in the same function from a payload that needs no
 * drop when nothing but `iface.data` reads, `load`s of the payload type and drops touch it: each
 * load becomes the payload operand and the allocation, the pointer and the drops are deleted. */
static bool sm_known_ifaces(MirModule *m, MirFunc *f) {
  MsArena arena = ms_arena_new();
  SmBoxes x = {0};
  bool changed = false;
  if (sm_boxes_collect(m, f, &arena, &x)) {
    sm_boxes_count(f, &arena, &x);
    if (sm_boxes_prune(f, &arena, &x)) {
      /* A load of a surviving pointer yields the payload. */
      OptSubst subst = opt_subst_new(&arena, (uint32_t)f->values.len);
      for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
        for (uint32_t ii = 0; ii < f->blocks.ptr[bi].insts.len; ii++) {
          const MirInst *i = &f->blocks.ptr[bi].insts.ptr[ii];
          if (i->op == MOP_Load && i->nargs == 1 && i->res != MIR_NONE &&
            x.pointers[i->args[0]] != MIR_NONE) {
            opt_subst_set(&subst, i->res, x.boxed[x.pointers[i->args[0]]]);
          }
        }
      }
      sm_remove_if(f, &arena, sm_dead_box, &x);
      opt_subst_apply(f, &subst);
      changed = true;
    }
  }
  ms_arena_free(&arena);
  return changed;
}

/* ---- known list literals ---- */

typedef struct SmLists {
  bool *known, *is_const;
  int64_t *consts;
  const MirValue **items;
  uint32_t *nitems;
} SmLists;

/* The element of a known list literal that `i`, a read at a constant index in range, yields;
 * MIR_NONE when it is not one. */
static MirValue sm_list_element(const SmLists *x, const MirInst *i) {
  if (i->nargs != 2 || (i->op != MOP_ListGet && i->op != MOP_ListGetU)) {
    return MIR_NONE;
  }
  const MirValue list = i->args[0], at = i->args[1];
  if (!x->known[list] || !x->is_const[at] || x->consts[at] < 0 ||
    (uint64_t)x->consts[at] >= x->nitems[list]) {
    return MIR_NONE;
  }
  return x->items[list][x->consts[at]];
}

/* The integer constants, and the `list.lit`s whose elements need no drop. */
static bool sm_lists_collect(MirModule *m, const MirFunc *f, MsArena *arena, SmLists *x) {
  const uint32_t n = (uint32_t)f->values.len;
  x->is_const = MS_ARENA_NEW_ARRAY(arena, bool, n);
  x->consts = MS_ARENA_NEW_ARRAY(arena, int64_t, n);
  x->known = MS_ARENA_NEW_ARRAY(arena, bool, n);
  x->items = MS_ARENA_NEW_ARRAY(arena, const MirValue *, n);
  x->nitems = MS_ARENA_NEW_ARRAY(arena, uint32_t, n);
  bool any = false;
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    for (uint32_t ii = 0; ii < f->blocks.ptr[bi].insts.len; ii++) {
      const MirInst *i = &f->blocks.ptr[bi].insts.ptr[ii];
      if (i->res == MIR_NONE) {
        continue;
      }
      if (i->op == MOP_IConst && i->imm.tag == MI_INT) {
        x->is_const[i->res] = true;
        x->consts[i->res] = i->imm.i;
      } else if (i->op == MOP_ListLit && sm_operands_plain(m, f, i)) {
        x->known[i->res] = true;
        x->items[i->res] = i->args;
        x->nitems[i->res] = i->nargs;
        any = true;
      }
    }
  }
  return any;
}

/* Keeps only the literals nothing but folded reads, `list.len` and drops touch. */
static bool sm_lists_prune(const MirFunc *f, MsArena *arena, SmLists *x) {
  uint32_t *uses = mir_use_counts(arena, f);
  uint32_t *folded = MS_ARENA_NEW_ARRAY(arena, uint32_t, f->values.len);
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    for (uint32_t ii = 0; ii < f->blocks.ptr[bi].insts.len; ii++) {
      const MirInst *i = &f->blocks.ptr[bi].insts.ptr[ii];
      if (i->nargs == 0 || !x->known[i->args[0]]) {
        continue;
      }
      const bool simple = (i->op == MOP_ListLen || i->op == MOP_Drop) && i->nargs == 1;
      folded[i->args[0]] += simple || sm_list_element(x, i) != MIR_NONE;
    }
  }
  bool any = false;
  for (uint32_t v = 0; v < f->values.len; v++) {
    x->known[v] = x->known[v] && folded[v] > 0 && folded[v] == uses[v];
    any |= x->known[v];
  }
  return any;
}

typedef struct SmListRemoval {
  const SmLists *lists;
  const OptSubst *subst;
} SmListRemoval;

static bool sm_dead_list(const void *ctx, const MirInst *i) {
  const SmListRemoval *r = ctx;
  const bool drop = i->op == MOP_Drop && i->nargs > 0 && r->lists->known[i->args[0]];
  const bool def = i->res != MIR_NONE && r->lists->known[i->res];
  return sm_defines_substituted(r->subst, i) || drop || def;
}

/* Folds reads of a `list.lit` whose elements need no drop and that is only read: `list.len`
 * becomes the element count and a read at a constant index in range becomes that element. With
 * every read folded, the literal and its drops are deleted. */
static bool sm_known_lists(MirModule *m, MirFunc *f) {
  MsArena arena = ms_arena_new();
  SmLists x = {0};
  bool changed = false;
  if (sm_lists_collect(m, f, &arena, &x) && sm_lists_prune(f, &arena, &x)) {
    OptSubst subst = opt_subst_new(&arena, (uint32_t)f->values.len);
    for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
      for (uint32_t ii = 0; ii < f->blocks.ptr[bi].insts.len; ii++) {
        MirInst *i = &f->blocks.ptr[bi].insts.ptr[ii];
        const MirValue element = sm_list_element(&x, i);
        if (i->res != MIR_NONE && element != MIR_NONE) {
          opt_subst_set(&subst, i->res, element);
        } else if (i->op == MOP_ListLen && i->nargs > 0 && x.known[i->args[0]]) {
          i->imm = (MirImm){.tag = MI_INT, .i = (int64_t)x.nitems[i->args[0]]};
          i->op = MOP_IConst;
          i->nargs = 0;
        }
      }
    }
    const SmListRemoval removal = {&x, &subst};
    sm_remove_if(f, &arena, sm_dead_list, &removal);
    opt_subst_apply(f, &subst);
    changed = true;
  }
  ms_arena_free(&arena);
  return changed;
}

/* ---- dead code ---- */

typedef struct SmWork {
  MirValue *v;
  uint32_t n;
} SmWork;

static bool sm_dce(MirModule *m, MirFunc *f) {
  MsArena arena = ms_arena_new();
  uint32_t *uses = mir_use_counts(&arena, f);
  uint64_t *removable = MS_ARENA_NEW_ARRAY(&arena, uint64_t, f->values.len); /* position + 1 */
  bool **dead = opt_dead_flags(&arena, f);
  uint32_t total = 0;
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    total += f->blocks.ptr[bi].insts.len;
  }
  SmWork work = {MS_ARENA_NEW_ARRAY(&arena, MirValue, (size_t)f->values.len + total + 1), 0};
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    for (uint32_t ii = 0; ii < f->blocks.ptr[bi].insts.len; ii++) {
      const MirInst *inst = &f->blocks.ptr[bi].insts.ptr[ii];
      if (inst->res == MIR_NONE) {
        continue;
      }
      const uint8_t e = mir_op_info[inst->op].effects;
      MirMode mode = MM_BORROW;
      const bool owned = mir_result_mode(m, f, inst, &mode) && mode == MM_MOVE;
      const bool removable_op = (e & (MIR_E_WRITES | MIR_E_FAULTS | MIR_E_IO | MIR_E_OWNERSHIP)) == 0;
      if (removable_op && !owned) {
        removable[inst->res] = (((uint64_t)bi << 32) | ii) + 1;
        if (uses[inst->res] == 0) {
          work.v[work.n++] = inst->res;
        }
      }
    }
  }
  /* Deleting a user may make its operands dead. Each instruction and operand is visited once. */
  bool changed = false;
  while (work.n > 0) {
    const MirValue r = work.v[--work.n];
    if (removable[r] == 0) {
      continue;
    }
    const uint32_t bi = (uint32_t)((removable[r] - 1) >> 32), ii = (uint32_t)(removable[r] - 1);
    dead[bi][ii] = true;
    changed = true;
    const MirInst *inst = &f->blocks.ptr[bi].insts.ptr[ii];
    for (uint32_t k = 0; k < inst->nargs; k++) {
      if (--uses[inst->args[k]] == 0) {
        work.v[work.n++] = inst->args[k];
      }
    }
  }
  if (changed) {
    opt_sweep_dead(f, (bool *const *)dead, &arena);
  }
  ms_arena_free(&arena);
  return changed;
}

/* ---- the pass ---- */

/* The structural passes: each one's output feeds the others (a folded branch merges blocks, a merged block exposes a
 * common subexpression), so they run to a fixed point together. */
static bool sm_core_round(MirModule *m, MirFunc *f) {
  bool c = opt_simplify_fold(m, f);
  c |= opt_simplify_phis_func(m, f);
  c |= opt_simplify_branches(m, f);
  c |= opt_simplify_cse(m, f);
  c |= sm_dce(m, f);
  return c;
}

/* What a function holds that a pattern pass can match: the operations present, and the runtime calls that
 * matter. Each pattern pass is a no-op without its trigger, and most pass bodies allocate per-value tables
 * before they find out, so one scan decides which of them run. */
typedef struct SmPresent {
  uint64_t ops[(MOP_COUNT + 63) / 64];
  bool map_probe, shield_enter, fresh_call;
} SmPresent;

static bool sm_has(const SmPresent *p, MirOp op) {
  return (p->ops[op / 64] >> (op % 64) & 1) != 0;
}

static SmPresent sm_present(const MirModule *m, const MirFunc *f) {
  SmPresent p = {0};
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    const MirBlockData *b = &f->blocks.ptr[bi];
    for (uint32_t ii = 0; ii < b->insts.len; ii++) {
      const MirInst *i = &b->insts.ptr[ii];
      p.ops[i->op / 64] |= (uint64_t)1 << (i->op % 64);
      if (i->op == MOP_CallRt && i->imm.tag == MI_EXT) {
        const MirExtern *e = &m->externs.ptr[i->imm.a];
        p.shield_enter |= e->role == MR_SHIELD_ENTER;
        p.fresh_call |= e->pure && e->fresh;
        p.map_probe |= opt_simplify_is_map_probe(m, i);
      }
    }
  }
  return p;
}

/* A pattern pass and the shape it needs. */
typedef struct SmPattern {
  bool (*run)(MirModule *m, MirFunc *f);
  bool (*wanted)(const SmPresent *p);
} SmPattern;

static bool sm_run_dropped_somes(MirModule *m, MirFunc *f) { (void)m; return sm_dropped_somes(f); }
static bool sm_run_dropped_nones(MirModule *m, MirFunc *f) { (void)m; return sm_dropped_nones(f); }
static bool sm_run_roundtrips(MirModule *m, MirFunc *f) { (void)m; return opt_simplify_roundtrips(f); }
static bool sm_run_put_takes(MirModule *m, MirFunc *f) { (void)m; return opt_simplify_put_takes(f); }

static bool sm_want_alts(const SmPresent *p) { return sm_has(p, MOP_AltNew); }
static bool sm_want_somes(const SmPresent *p) { return sm_has(p, MOP_OptSome); }
static bool sm_want_nones(const SmPresent *p) { return sm_has(p, MOP_OptNoneOwned); }
static bool sm_want_ifaces(const SmPresent *p) { return sm_has(p, MOP_IfaceNew); }
static bool sm_want_lists(const SmPresent *p) { return sm_has(p, MOP_ListLit); }
static bool sm_want_roundtrips(const SmPresent *p) { return sm_has(p, MOP_Take); }
static bool sm_want_shields(const SmPresent *p) { return p->shield_enter; }
static bool sm_want_put_takes(const SmPresent *p) { return sm_has(p, MOP_Put); }
static bool sm_want_probes(const SmPresent *p) { return p->map_probe; }
static bool sm_want_dead_owned(const SmPresent *p) {
  return sm_has(p, MOP_AltNew) || sm_has(p, MOP_TypeNew) || sm_has(p, MOP_Clone) || sm_has(p, MOP_ListNew) ||
         sm_has(p, MOP_ListLit) || sm_has(p, MOP_OptSome) || p->fresh_call;
}

static const SmPattern sm_patterns[] = {
    {sm_known_alts, sm_want_alts},
    {sm_run_dropped_somes, sm_want_somes},
    {sm_run_dropped_nones, sm_want_nones},
    {sm_known_ifaces, sm_want_ifaces},
    {sm_known_lists, sm_want_lists},
    {sm_run_roundtrips, sm_want_roundtrips},
    {opt_simplify_shields, sm_want_shields},
    {sm_run_put_takes, sm_want_put_takes},
    {opt_simplify_map_probes, sm_want_probes},
    {opt_simplify_fuse_contains, sm_want_probes},
    {opt_simplify_dead_owned, sm_want_dead_owned},
};

/* The pattern passes: each looks for one shape (`known_*`, `dropped_*`, a round trip, a dead owned tree) that is
 * rare and does not enable the structural passes much. On a yaml-importing program they changed the function in
 * 2 of 441 first rounds and none of the later ones, yet cost a third of the rounds' time; a pass whose trigger
 * the function lacks no longer runs. A pass that changes the function can create another's trigger, so the scan
 * is repeated after it. */
static bool sm_pattern_round(MirModule *m, MirFunc *f) {
  SmPresent present = sm_present(m, f);
  bool c = false;
  for (size_t k = 0; k < sizeof sm_patterns / sizeof sm_patterns[0]; k++) {
    if (!sm_patterns[k].wanted(&present) || !sm_patterns[k].run(m, f)) {
      continue;
    }
    c = true;
    present = sm_present(m, f);
  }
  return c;
}

/* Structural passes to a fixed point, then the pattern passes once; a pattern that fires starts over. */
static bool sm_rounds(MirModule *m, MirFunc *f) {
  bool any = false;
  for (uint32_t round = 0; round < 24; round++) {
    uint32_t inner = 0;
    while (inner++ < 24 && sm_core_round(m, f)) {
      any = true;
    }
    if (!sm_pattern_round(m, f)) {
      break;
    }
    any = true;
  }
  return any;
}

bool opt_simplify_func(MirModule *m, MirFunc *f) {
  return sm_rounds(m, f);
}

static bool simplify_one(MirModule *view, MirFunc *f, void *context) {
  (void)context;
  return opt_simplify_func(view, f);
}

bool opt_simplify(MirModule *m) {
  return opt_for_each_func(m, simplify_one, NULL);
}
