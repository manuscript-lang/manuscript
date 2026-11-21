/* opt_copyelim_unbox.c: see opt_copyelim.h. */
#include "compiler/opt/opt_copyelim.h"

/* ---- moving a payload out of a dying shell ---- */


static void cpe_term_find(void *ctx, MirValue v) {
  CpeFind *f = ctx;
  f->hit |= v == f->v;
}

static bool cpe_term_uses(const MirBlockData *b, MirValue v) {
  CpeFind find = {v, false};
  mir_term_each_value(&b->term, cpe_term_find, &find);
  return find.hit;
}

/* Replaces `insts[at]`'s operands by one value. */
static void cpe_set_single_arg(MirModule *m, MirInst *inst, MirValue v) {
  inst->args = MS_ARENA_NEW_ARRAY(&m->arena, MirValue, 1);
  inst->args[0] = v;
  inst->nargs = 1;
}

/* Turns `p = opt.get v; c = clone p; ...; drop v` into `c = opt.unbox v` when `v` is not touched in
 * between and `p` has no other use: the payload moves out and the shell is freed instead of the
 * payload being deep-copied and then dropped with its source. This is the shape of unwrapping a
 * recursive result, which would otherwise copy every subtree once per level. */
bool cpe_unbox_dead_options(MsArena *arena, MirModule *m, MirFunc *f) {
  const bool *tainted = cpe_view_tainted(arena, m, f);
  const uint32_t *uses = mir_use_counts(arena, f);
  bool changed = false;
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    MirBlockData *b = &f->blocks.ptr[bi];
    bool again = true;
    while (again) {
      again = false;
      const CpeBlockUses idx = cpe_block_uses(arena, b);
      for (uint32_t gi = 0; gi < b->insts.len && !again; gi++) {
        const MirInst *get = &b->insts.ptr[gi];
        if (get->op != MOP_OptGet || get->res == MIR_NONE) {
          continue;
        }
        const MirValue p = get->res, v = get->args[0];
        uint32_t ci = 0, di = 0;
        if (uses[p] != 1 || tainted[v] || !cpe_first_after(&idx, b, p, gi, MOP_Clone, &ci) ||
          !cpe_first_after(&idx, b, v, ci, MOP_Drop, &di)) {
          continue;
        }
        /* The drop must be the only use of `v` after the load (`ci` reads `p`). */
        uint32_t cursor = cpe_after_start(&idx, v, gi), at = 0;
        bool other = cpe_term_uses(b, v);
        while (!other && cpe_after_next(&idx, v, &cursor, &at)) {
          other = at != di;
        }
        if (other) {
          continue;
        }
        b->insts.ptr[ci].op = MOP_OptUnbox;
        cpe_set_single_arg(m, &b->insts.ptr[ci], v);
        const uint32_t dead[2] = {gi, di};
        mir_block_remove(b, dead, 2);
        changed = true;
        again = true;
      }
    }
  }
  return changed;
}

/* The positions after `gi` that use `v` apart from the copy and the drop: each must be an
 * `alt.get` of a field that needs no drop (those are hoisted above the unbox). Collected in
 * `hoist`; false when another use exists, or one comes after the drop. */
static bool cpe_hoistable_loads(const MirBlockData *b, const CpeBlockUses *idx, const bool *nd,
               MirValue v, uint32_t gi, uint32_t ci, uint32_t di, CpeDead *hoist,
               MsArena *arena) {
  bool ok = true;
  uint32_t cursor = cpe_after_start(idx, v, gi), k = 0, last = UINT32_MAX;
  while (cpe_after_next(idx, v, &cursor, &k)) {
    if (last == k) {
      continue;
    }
    last = k;
    if (k > di) {
      return false;
    }
    if (k == ci || k == di) {
      continue;
    }
    const MirInst *n = &b->insts.ptr[k];
    if (n->op == MOP_AltGet && n->res != MIR_NONE && !nd[n->res]) {
      cpe_dead_push(arena, hoist, 0, k);
    } else {
      ok = false;
    }
  }
  return ok;
}

/* Rebuilds the block with the hoisted loads where the original `alt.get` was and the drop gone:
 * the unbox frees the block. */
static void cpe_hoist_rebuild(MirModule *m, MirBlockData *b, uint32_t gi, uint32_t di,
              const CpeDead *hoist) {
  MirInst *out = MS_ARENA_NEW_ARRAY(&m->arena, MirInst, (size_t)b->insts.len + 1);
  uint32_t n = 0;
  for (uint32_t k = 0; k < b->insts.len; k++) {
    bool hoisted = false;
    for (uint32_t h = 0; h < hoist->n; h++) {
      hoisted |= hoist->at[h].index == k;
    }
    if (k == gi) {
      for (uint32_t h = 0; h < hoist->n; h++) {
        out[n++] = b->insts.ptr[hoist->at[h].index];
      }
    } else if (k != di && !hoisted) {
      out[n++] = b->insts.ptr[k];
    }
  }
  opt_block_set_insts(b, out, n);
}

/* Turns `p = alt.get f v; c = clone p; ...; drop v` into `c = alt.unbox f v` when `v` is otherwise
 * only read through `alt.get`s of fields that need no drop (those are hoisted above it). This is
 * the shape of `match cur: Link(_, next): cur = next` in a loop, which would otherwise deep-copy
 * the whole tail on every iteration. */
bool cpe_unbox_dead_sources(MsArena *arena, MirModule *m, MirFunc *f) {
  const bool *tainted = cpe_view_tainted(arena, m, f);
  const uint32_t *uses = mir_use_counts(arena, f);
  bool *nd = cpe_new_flags(arena, f);
  for (uint32_t v = 0; v < f->values.len; v++) {
    nd[v] = mir_needs_drop(m, f->values.ptr[v]);
  }
  bool changed = false;
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    MirBlockData *b = &f->blocks.ptr[bi];
    bool again = true;
    while (again) {
      again = false;
      const CpeBlockUses idx = cpe_block_uses(arena, b);
      for (uint32_t gi = 0; gi < b->insts.len && !again; gi++) {
        const MirInst *get = &b->insts.ptr[gi];
        if (get->op != MOP_AltGet || get->res == MIR_NONE) {
          continue;
        }
        const MirValue p = get->res, v = get->args[0];
        uint32_t ci = 0, di = 0;
        CpeDead hoist = {0};
        if (uses[p] != 1 || !nd[p] || tainted[v] ||
          !cpe_first_after(&idx, b, p, gi, MOP_Clone, &ci) ||
          !cpe_first_after(&idx, b, v, ci, MOP_Drop, &di) ||
          !cpe_hoistable_loads(b, &idx, nd, v, gi, ci, di, &hoist, arena)) {
          continue;
        }
        b->insts.ptr[ci].op = MOP_AltUnbox;
        b->insts.ptr[ci].imm = get->imm;
        cpe_set_single_arg(m, &b->insts.ptr[ci], v);
        cpe_hoist_rebuild(m, b, gi, di, &hoist);
        changed = true;
        again = true;
      }
    }
  }
  return changed;
}

/* ---- taking fields out of a dying type ---- */


static uint32_t cpe_field_of(const MirInst *inst) {
  return inst->imm.tag == MI_FIELD ? inst->imm.b : UINT32_MAX;
}

/* The `type.get`s of `v` before its drop at `di`, in order; false when another instruction reads
 * `v` first or nothing can be taken (no get, a read between the first get and the drop that can
 * fault or unwind). */
static bool cpe_type_gets(const MirBlockData *b, MirValue v, uint32_t di, uint32_t *gets,
            uint32_t *ngets) {
  *ngets = 0;
  for (uint32_t k = 0; k < di; k++) {
    bool reads = false;
    for (uint32_t a = 0; a < b->insts.ptr[k].nargs; a++) {
      reads |= b->insts.ptr[k].args[a] == v;
    }
    if (!reads) {
      continue;
    }
    if (b->insts.ptr[k].op != MOP_TypeGet) {
      return false;
    }
    gets[(*ngets)++] = k;
  }
  if (*ngets == 0) {
    return false;
  }
  for (uint32_t k = gets[0]; k < di; k++) {
    if (b->insts.ptr[k].op != MOP_TypeGet && b->insts.ptr[k].op != MOP_Clone) {
      return false;
    }
  }
  return true;
}

/* The loads whose copy can become a move out of the dying type. */
static uint32_t cpe_taken_fields(const MirBlockData *b, const CpeBlockUses *idx, const uint32_t *uses,
                const bool *nd, const uint32_t *gets, uint32_t ngets, uint32_t di,
                CpeTaken *taken) {
  uint32_t n = 0;
  for (uint32_t g = 0; g < ngets; g++) {
    const uint32_t gi = gets[g];
    const MirValue p = b->insts.ptr[gi].res;
    uint32_t ci = 0;
    if (p == MIR_NONE || uses[p] != 1 || !nd[p] || !cpe_first_after(idx, b, p, gi, MOP_Clone, &ci)) {
      continue;
    }
    const uint32_t fld = cpe_field_of(&b->insts.ptr[gi]);
    uint32_t same = 0;
    for (uint32_t h = 0; h < ngets; h++) {
      same += cpe_field_of(&b->insts.ptr[gets[h]]) == fld ? 1u : 0u;
    }
    /* A field taken once must not also be read through another `type.get`. */
    if (ci < di && same == 1) {
      taken[n++] = (CpeTaken){gi, ci, fld};
    }
  }
  return n;
}

/* Turns `p = type.get f v; c = clone p; ...; drop v` into `c = type.get f v` plus drops of the
 * other droppable fields of `v`, when `v` is only read through `type.get`s until its drop. The
 * field moves out of the dying type instead of being deep-copied and then freed with it, so
 * `w.inner.clone()` on a type that is dead afterwards costs no allocation. Nothing that can fault
 * or unwind may sit between the first load and the drop, so no cleanup sees the field both moved
 * and still owned by the type. Rewrites the first site found. */
bool cpe_take_type_fields(MsArena *arena, const MirModule *m, MirFunc *f) {
  const bool *tainted = cpe_view_tainted(arena, m, f);
  const uint32_t *uses = mir_use_counts(arena, f);
  bool *nd = cpe_new_flags(arena, f);
  for (uint32_t v = 0; v < f->values.len; v++) {
    nd[v] = mir_needs_drop(m, f->values.ptr[v]);
  }
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    MirBlockData *b = &f->blocks.ptr[bi];
    const CpeBlockUses idx = cpe_block_uses(arena, b);
    uint32_t *gets = MS_ARENA_NEW_ARRAY(arena, uint32_t, (size_t)b->insts.len + 1);
    CpeTaken *taken = MS_ARENA_NEW_ARRAY(arena, CpeTaken, (size_t)b->insts.len + 1);
    for (uint32_t di = 0; di < b->insts.len; di++) {
      const MirInst *drop = &b->insts.ptr[di];
      if (drop->op != MOP_Drop || drop->nargs == 0) {
        continue;
      }
      const MirValue v = drop->args[0];
      uint32_t ngets = 0, cursor = cpe_after_start(&idx, v, di), at = 0;
      if (mir_ty_data(m, mir_value_ty(f, v))->kind != MK_TYPE || tainted[v] ||
        cpe_after_next(&idx, v, &cursor, &at) || !cpe_type_gets(b, v, di, gets, &ngets)) {
        continue;
      }
      const uint32_t n = cpe_taken_fields(b, &idx, uses, nd, gets, ngets, di, taken);
      if (n == 0 || b->insts.ptr[taken[0].get].imm.tag != MI_FIELD) {
        continue;
      }
      const uint32_t type = b->insts.ptr[taken[0].get].imm.a;
      uint32_t mask = 0;
      for (uint32_t k = 0; k < n; k++) {
        b->insts.ptr[taken[k].copy].op = MOP_MoveOut;
        mask |= UINT32_C(1) << taken[k].field;
      }
      b->insts.ptr[di].op = MOP_TypeRelease;
      b->insts.ptr[di].imm = (MirImm){.tag = MI_TYPEMASK, .a = type, .b = mask};
      return true;
    }
  }
  return false;
}
