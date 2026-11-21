/* The `simplify` pass, block parameters: drops parameters that every incoming edge passes the same value to. */
#include "compiler/opt/opt_simplify.h"

/* ---- block parameters ---- */

/* The block each value is defined in (UINT32_MAX when none). */
static uint32_t *sf_def_blocks(MsArena *arena, const MirFunc *f) {
  uint32_t *d = MS_ARENA_NEW_ARRAY(arena, uint32_t, f->values.len);
  for (uint32_t v = 0; v < f->values.len; v++) {
    d[v] = UINT32_MAX;
  }
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    const MirBlockData *b = &f->blocks.ptr[bi];
    for (uint32_t k = 0; k < b->params.len; k++) {
      d[b->params.ptr[k].value] = bi;
    }
    for (uint32_t ii = 0; ii < b->insts.len; ii++) {
      if (b->insts.ptr[ii].res != MIR_NONE) {
        d[b->insts.ptr[ii].res] = bi;
      }
    }
  }
  return d;
}

/* The edges entering each block as targets: block b's are `edge[start[b]..start[b + 1]]`. */
static const MirTarget **sf_incoming(MsArena *arena, const MirFunc *f, uint32_t **start) {
  uint32_t *st = MS_ARENA_NEW_ARRAY(arena, uint32_t, (size_t)f->blocks.len + 1);
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    const MirTerm *t = &f->blocks.ptr[bi].term;
    for (uint32_t s = 0; s < mir_term_ntargets(t); s++) {
      st[mir_term_target_const(t, s)->block + 1]++;
    }
  }
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    st[b + 1] += st[b];
  }
  uint32_t *fill = MS_ARENA_NEW_ARRAY(arena, uint32_t, (size_t)f->blocks.len + 1);
  __builtin_memcpy(fill, st, sizeof(uint32_t) * f->blocks.len);
  const MirTarget **edge = MS_ARENA_NEW_ARRAY(arena, const MirTarget *, (size_t)st[f->blocks.len] + 1);
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    const MirTerm *t = &f->blocks.ptr[bi].term;
    for (uint32_t s = 0; s < mir_term_ntargets(t); s++) {
      const MirTarget *tg = mir_term_target_const(t, s);
      edge[fill[tg->block]++] = tg;
    }
  }
  *start = st;
  return edge;
}

/* The one value every incoming edge passes for parameter `pi` of block `bi` (other than the
 * parameter itself); MIR_NONE when they differ or there is none. */
static MirValue sf_single_incoming(const MirTarget *const *edge, const uint32_t *start,
                 uint32_t bi, uint32_t pi, MirValue self) {
  MirValue single = MIR_NONE;
  for (uint32_t k = start[bi]; k < start[bi + 1]; k++) {
    const MirValue a = edge[k]->args[pi];
    if (a == self) {
      continue;
    }
    if (single == MIR_NONE) {
      single = a;
    } else if (single != a) {
      return MIR_NONE;
    }
  }
  return single;
}

typedef struct SfParams {
  MirModule *m;
  MirFunc *f;
  MsArena *arena;
  const MirTarget **edge;
  uint32_t *start;
  uint32_t *defb;
  uint32_t *uses;
  uint8_t **drop; /* per block, per parameter: removed */
  OptSubst subst;
  bool any;
} SfParams;

static void sf_classify_params(SfParams *s, uint32_t bi) {
  const MirBlockData *b = &s->f->blocks.ptr[bi];
  for (uint32_t pi = 0; pi < b->params.len; pi++) {
    const MirBlockParam *p = &b->params.ptr[pi];
    const bool droppable = mir_needs_drop(s->m, s->f->values.ptr[p->value]);
    if (s->uses[p->value] == 0 && (p->mode != MM_MOVE || !droppable)) {
      s->drop[bi][pi] = 1;
      s->any = true;
      continue;
    }
    if (s->start[bi + 1] == s->start[bi]) {
      continue;
    }
    const MirValue v = sf_single_incoming(s->edge, s->start, bi, pi, p->value);
    if (v != MIR_NONE && s->defb[v] != bi) {
      opt_subst_set(&s->subst, p->value, v);
      s->drop[bi][pi] = 1;
      s->any = true;
    }
  }
}

static void sf_remove_args(MirTarget *t, const uint8_t *drop, uint32_t nparams) {
  uint32_t kept = 0;
  for (uint32_t k = 0; k < t->nargs; k++) {
    if (k >= nparams || !drop[k]) {
      t->args[kept++] = t->args[k];
    }
  }
  t->nargs = kept;
}

/* Removes block parameters that always receive one value (or themselves), and parameters nobody
 * reads. Droppable parameters are only removed when borrowed. */
bool opt_simplify_phis_func(MirModule *m, MirFunc *f) {
  mir_func_compact_blocks(f);
  MsArena arena = ms_arena_new();
  SfParams s = {.m = m, .f = f, .arena = &arena};
  s.edge = sf_incoming(&arena, f, &s.start);
  s.defb = sf_def_blocks(&arena, f);
  s.uses = mir_use_counts(&arena, f);
  s.subst = opt_subst_new(&arena, (uint32_t)f->values.len);
  s.drop = MS_ARENA_NEW_ARRAY(&arena, uint8_t *, (size_t)f->blocks.len + 1);
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    s.drop[bi] = MS_ARENA_NEW_ARRAY(&arena, uint8_t, f->blocks.ptr[bi].params.len);
  }
  for (uint32_t bi = 1; bi < f->blocks.len; bi++) {
    sf_classify_params(&s, bi);
  }
  if (s.any) {
    for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
      MirTerm *t = &f->blocks.ptr[bi].term;
      for (uint32_t k = 0; k < mir_term_ntargets(t); k++) {
        MirTarget *tg = mir_term_target(t, k);
        sf_remove_args(tg, s.drop[tg->block], (uint32_t)f->blocks.ptr[tg->block].params.len);
      }
    }
    for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
      MirBlockData *b = &f->blocks.ptr[bi];
      uint32_t kept = 0;
      for (uint32_t pi = 0; pi < b->params.len; pi++) {
        if (!s.drop[bi][pi]) {
          b->params.ptr[kept++] = b->params.ptr[pi];
        }
      }
      b->params.len = kept;
    }
    opt_subst_apply(f, &s.subst);
  }
  ms_arena_free(&arena);
  return s.any;
}

