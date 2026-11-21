/* range: which lists share a length.
 *
 * A list length can flow through element replacement and block arguments without the elements
 * flowing with it. Each value gets an origin: values with the same origin have the same length.
 * A list held in a type field is tracked the same way, with a node for each list field of each
 * type value (and of each slot that is only loaded from and stored into as a whole type). The
 * facts form a three-level lattice (unknown, one origin, mixed) that a worklist settles; nodes are
 * numbered, so the edges are flat arrays and a node's fact is one word. */
#include "compiler/opt/opt_range.h"

#define RL_UNKNOWN UINT32_MAX
#define RL_MIXED (UINT32_MAX - 1)

/* A map from a pair of values to the first value recorded for it. */
typedef struct RlPairMap {
  uint64_t *key;
  uint32_t *val;
  uint32_t mask;
} RlPairMap;

typedef struct RgLen {
  const MirModule *m;
  const MirFunc *f;
  MsArena *a;
  uint32_t nv, total;
  uint32_t *pair_base; /* per value: its first list-field node, MIR_NONE without list fields */
  uint32_t *slot_base, *slot_nf;
  MirBits slots, candidates, escaped, flows;
  MirValue *loaded_from;
  uint32_t *first_read; /* per node: the first list read from that field */
  uint32_t *efrom, *eto;
  uint32_t ne, cape;
  uint32_t *facts;
  uint32_t *seeds;
  uint32_t nseeds, cseeds;
  RlPairMap reads;
} RgLen;

/* ---- types ---- */

static const MirTyData *rl_ty(const RgLen *c, MirValue v) {
  return mir_ty_data(c->m, c->f->values.ptr[v]);
}

/* A list, or an optional list (a `var` list moved out and put back carries its list's length). */
static bool rl_is_list(const RgLen *c, MirValue v) {
  const MirTyData *d = rl_ty(c, v);
  if (d->kind == MK_LIST) {
    return true;
  }
  return d->kind == MK_OPT && mir_ty_data(c->m, d->elem)->kind == MK_LIST;
}

static const MirTypeDef *rl_def(const RgLen *c, MirValue v) {
  const MirTyData *d = rl_ty(c, v);
  return d->kind == MK_TYPE ? &c->m->type_defs.ptr[d->id] : NULL;
}

static bool rl_list_field(const RgLen *c, const MirTypeDef *def, uint32_t k) {
  return mir_ty_data(c->m, def->fields[k].ty)->kind == MK_LIST;
}

static uint32_t rl_nlistf(const RgLen *c, MirValue v) {
  const MirTypeDef *def = rl_def(c, v);
  uint32_t n = 0;
  for (uint32_t k = 0; def != NULL && k < def->nfields; k++) {
    n += rl_list_field(c, def, k) ? 1u : 0u;
  }
  return n;
}

/* The node of list field `k` of the type value or slot `v`; MIR_NONE when there is none. */
static uint32_t rl_node(const RgLen *c, MirValue v, uint32_t k) {
  const MirTypeDef *def = rl_def(c, v);
  if (def == NULL) {
    return k < c->slot_nf[v] ? c->slot_base[v] + k : MIR_NONE;
  }
  if (k >= def->nfields || !rl_list_field(c, def, k)) {
    return MIR_NONE;
  }
  uint32_t rank = 0;
  for (uint32_t j = 0; j < k; j++) {
    rank += rl_list_field(c, def, j) ? 1u : 0u;
  }
  return c->pair_base[v] + rank;
}

static void rl_edge(RgLen *c, uint32_t from, uint32_t to) {
  if (from == MIR_NONE || to == MIR_NONE) {
    return;
  }
  if (c->ne == c->cape) {
    const uint32_t ncap = c->cape != 0 ? c->cape * 2 : 64;
    uint32_t *nf = RG_ZNEW(c->a, uint32_t, ncap);
    uint32_t *nt = RG_ZNEW(c->a, uint32_t, ncap);
    if (c->ne != 0) {
      __builtin_memcpy(nf, c->efrom, (size_t)c->ne * sizeof *nf);
      __builtin_memcpy(nt, c->eto, (size_t)c->ne * sizeof *nt);
    }
    c->efrom = nf;
    c->eto = nt;
    c->cape = ncap;
  }
  c->efrom[c->ne] = from;
  c->eto[c->ne++] = to;
}

static void rl_seed(RgLen *c, uint32_t node, uint32_t fact) {
  c->facts[node] = fact;
  OPT_PUSH(c->a, c->seeds, c->nseeds, c->cseeds, uint32_t, node);
}

/* ---- first-seen map ---- */

static uint32_t rl_hash(uint64_t key) { return (uint32_t)((key * UINT64_C(0x9E3779B97F4A7C15)) >> 32); }

static void rl_map_init(MsArena *a, RlPairMap *m, uint32_t count) {
  uint32_t cap = 16;
  while (cap < count * 2) {
    cap *= 2;
  }
  m->key = RG_ZNEW(a, uint64_t, cap);
  m->val = RG_ZNEW(a, uint32_t, cap);
  __builtin_memset(m->key, 0xFF, (size_t)cap * sizeof *m->key);
  m->mask = cap - 1;
}

/* The value recorded for `key`, recording `value` first when there is none. */
static uint32_t rl_map_first(RlPairMap *m, uint64_t key, uint32_t value) {
  uint32_t h = rl_hash(key) & m->mask;
  while (m->key[h] != UINT64_MAX) {
    if (m->key[h] == key) {
      return m->val[h];
    }
    h = (h + 1) & m->mask;
  }
  m->key[h] = key;
  m->val[h] = value;
  return value;
}

/* ---- setup ---- */

/* One node per value, then one per list field of each type value. */
static void rl_setup(RgLen *c) {
  c->nv = (uint32_t)c->f->values.len;
  c->total = c->nv;
  c->pair_base = RG_ZNEW(c->a, uint32_t, c->nv);
  c->slot_base = RG_ZNEW(c->a, uint32_t, c->nv);
  c->slot_nf = RG_ZNEW(c->a, uint32_t, c->nv);
  c->loaded_from = RG_ZNEW(c->a, MirValue, c->nv);
  __builtin_memset(c->loaded_from, 0xFF, (size_t)c->nv * sizeof *c->loaded_from);
  for (uint32_t v = 0; v < c->nv; v++) {
    const uint32_t n = rl_nlistf(c, v);
    c->pair_base[v] = n != 0 ? c->total : MIR_NONE;
    c->total += n;
  }
  c->slots = mir_bits_new(c->a, c->nv);
  c->candidates = mir_bits_new(c->a, c->nv);
  c->escaped = mir_bits_new(c->a, c->nv);
  c->flows = mir_bits_new(c->a, c->nv);
}

static bool rl_whole_access(const MirInst *i) {
  return i->op == MOP_Load || i->op == MOP_Take || i->op == MOP_Put || i->op == MOP_Store;
}

static void rl_term_escape(void *ctx, MirValue v) {
  RgLen *c = ctx;
  if (mir_bits_test(&c->candidates, v)) {
    mir_bits_set(&c->escaped, v);
  }
}

/* Whether no later instruction of the block reads `a`: a call that ends the function may rewrite
 * the slot, since nothing reads it after. */
static bool rl_last_read(const MirBlockData *b, uint32_t ii, MirValue a) {
  for (uint32_t j = ii + 1; j < b->insts.len; j++) {
    for (uint32_t n = 0; n < b->insts.ptr[j].nargs; n++) {
      if (b->insts.ptr[j].args[n] == a) {
        return false;
      }
    }
  }
  return true;
}

static void rl_find_escapes(RgLen *c) {
  for (uint32_t bi = 0; bi < c->f->blocks.len; bi++) {
    const MirBlockData *b = &c->f->blocks.ptr[bi];
    const bool returns = b->term.kind == MT_RET;
    for (uint32_t ii = 0; ii < b->insts.len; ii++) {
      const MirInst *i = &b->insts.ptr[ii];
      for (uint32_t n = 0; n < i->nargs; n++) {
        const MirValue a = i->args[n];
        if (!mir_bits_test(&c->candidates, a) || (rl_whole_access(i) && n == 0)) {
          continue;
        }
        if (!(i->op == MOP_Call && returns && rl_last_read(b, ii, a))) {
          mir_bits_set(&c->escaped, a);
        }
      }
    }
    mir_term_each_value(&b->term, rl_term_escape, c);
  }
}

/* Slot memory: a pointer parameter or `slot` that is only loaded from, taken from and stored into
 * as a whole type is one variable. Every type loaded from it shares its list fields' origins,
 * which are the join of the field origins of the types stored. */
static void rl_slots(RgLen *c) {
  const MirFunc *f = c->f;
  for (uint32_t p = 0; p < f->blocks.ptr[0].params.len; p++) {
    mir_bits_set(&c->slots, f->blocks.ptr[0].params.ptr[p].value);
  }
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    for (uint32_t ii = 0; ii < f->blocks.ptr[bi].insts.len; ii++) {
      const MirInst *i = &f->blocks.ptr[bi].insts.ptr[ii];
      if (i->op == MOP_Slot && i->res != MIR_NONE) {
        mir_bits_set(&c->slots, i->res);
      }
    }
  }
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    for (uint32_t ii = 0; ii < f->blocks.ptr[bi].insts.len; ii++) {
      const MirInst *i = &f->blocks.ptr[bi].insts.ptr[ii];
      if ((i->op == MOP_Load || i->op == MOP_Take) && i->res != MIR_NONE &&
        mir_bits_test(&c->slots, i->args[0]) && rl_nlistf(c, i->res) != 0) {
        mir_bits_set(&c->candidates, i->args[0]);
        c->loaded_from[i->res] = i->args[0];
      }
    }
  }
  rl_find_escapes(c);
  for (uint32_t p = 0; p < c->nv; p++) {
    if (mir_bits_test(&c->escaped, p)) {
      mir_bits_clear(&c->candidates, p);
    }
  }
  for (uint32_t r = 0; r < c->nv; r++) {
    const MirValue p = c->loaded_from[r];
    const MirTypeDef *def = rl_def(c, r);
    if (p == MIR_NONE || !mir_bits_test(&c->candidates, p) || def == NULL) {
      continue;
    }
    for (uint32_t k = 0; k < def->nfields; k++) {
      if (rl_list_field(c, def, k) && c->slot_nf[p] < k + 1) {
        c->slot_nf[p] = k + 1;
      }
    }
  }
  for (uint32_t p = 0; p < c->nv; p++) {
    c->slot_base[p] = c->total;
    c->total += c->slot_nf[p];
  }
}

/* ---- edges ---- */

/* Put and store into a candidate slot: the stored type's list fields flow into the slot's. */
static bool rl_store(RgLen *c, const MirInst *i) {
  if ((i->op != MOP_Put && i->op != MOP_Store) || i->nargs < 2 ||
    !mir_bits_test(&c->candidates, i->args[0])) {
    return false;
  }
  const MirTypeDef *def = rl_def(c, i->args[1]);
  for (uint32_t k = 0; def != NULL && k < def->nfields; k++) {
    rl_edge(c, rl_node(c, i->args[1], k), rl_node(c, i->args[0], k));
  }
  return true;
}

/* Every list field of `to` takes its fact from the same field of `from`. */
static void rl_copy_fields(RgLen *c, MirValue from, MirValue to) {
  const MirTypeDef *def = rl_def(c, to);
  for (uint32_t k = 0; def != NULL && k < def->nfields; k++) {
    rl_edge(c, rl_node(c, from, k), rl_node(c, to, k));
  }
}

static bool rl_load(RgLen *c, const MirInst *i) {
  const MirValue r = i->res;
  if ((i->op != MOP_Load && i->op != MOP_Take) || c->loaded_from[r] == MIR_NONE ||
    !mir_bits_test(&c->candidates, c->loaded_from[r])) {
    return false;
  }
  mir_bits_set(&c->flows, r);
  rl_copy_fields(c, c->loaded_from[r], r);
  return true;
}

static void rl_type_new(RgLen *c, const MirInst *i) {
  mir_bits_set(&c->flows, i->res);
  if (i->imm.tag != MI_TYPE) {
    return;
  }
  const MirTypeDef *def = &c->m->type_defs.ptr[i->imm.a];
  for (uint32_t k = 0; k < def->nfields && k < i->nargs; k++) {
    if (rl_list_field(c, def, k)) {
      rl_edge(c, i->args[k], rl_node(c, i->res, k));
    }
  }
}

static void rl_type_set(RgLen *c, const MirInst *i) {
  const MirValue r = i->res;
  mir_bits_set(&c->flows, r);
  if (i->imm.tag != MI_FIELD) {
    return;
  }
  const MirTypeDef *def = rl_def(c, r);
  for (uint32_t k = 0; def != NULL && k < def->nfields; k++) {
    const uint32_t to = rl_node(c, r, k);
    if (to == MIR_NONE) {
      continue;
    }
    if (k == i->imm.b) {
      rl_edge(c, i->args[1], to);
    } else {
      rl_edge(c, rl_node(c, i->args[0], k), to);
    }
  }
}

/* Reading a list field: the first read of each field is the origin of a field nothing defines. */
static void rl_type_get(RgLen *c, const MirInst *i) {
  if (i->imm.tag != MI_FIELD) {
    return;
  }
  const uint32_t k = i->imm.b;
  const uint32_t node = rl_node(c, i->args[0], k);
  if (node != MIR_NONE && c->first_read[node] == MIR_NONE) {
    c->first_read[node] = i->res;
  }
  const MirValue p = c->loaded_from[i->args[0]];
  const uint32_t slot = p != MIR_NONE ? rl_node(c, p, k) : MIR_NONE;
  if (slot != MIR_NONE && c->first_read[slot] == MIR_NONE) {
    c->first_read[slot] = i->res;
  }
  rl_edge(c, node, i->res);
}

static bool rl_type_ops(RgLen *c, const MirInst *i) {
  const MirValue r = i->res;
  switch ((MirOp)i->op) {
  case MOP_TypeNew:
    rl_type_new(c, i);
    return true;
  case MOP_TypeFill: case MOP_TypeSet:
    rl_type_set(c, i);
    return true;
  case MOP_Clone:
    if (rl_nlistf(c, r) == 0) {
      return false;
    }
    mir_bits_set(&c->flows, r);
    rl_copy_fields(c, i->args[0], r);
    return true;
  case MOP_TypeGet:
    if (!rl_is_list(c, r)) {
      return false;
    }
    rl_type_get(c, i);
    return true;
  default:
    return false;
  }
}

/* Mutators hand their list's length on; a fresh list is an origin of its own. */
static bool rl_keeps_length(MirOp op) {
  switch (op) {
  case MOP_ListSet: case MOP_ListSetNn: case MOP_ListSetU: case MOP_ListFill: case MOP_MoveOut:
  case MOP_Clone: case MOP_OptSome: case MOP_OptView: case MOP_OptViewAt: case MOP_OptGet:
  case MOP_OptUnwrap: case MOP_OptUnbox:
    return true;
  default:
    return false;
  }
}

static void rl_list_result(RgLen *c, const MirInst *i) {
  const MirValue r = i->res;
  if (rl_keeps_length((MirOp)i->op)) {
    rl_edge(c, i->args[0], r);
    return;
  }
  uint32_t origin = r;
  if ((i->op == MOP_ListGet || i->op == MOP_ListGetNn || i->op == MOP_ListGetU) && i->nargs > 1) {
    /* Reading the same element of the same (immutable) list twice yields lists of one length. */
    origin = rl_map_first(&c->reads, ((uint64_t)i->args[0] << 32) | i->args[1], r);
  }
  rl_seed(c, r, origin);
}

static void rl_inst(RgLen *c, const MirInst *i) {
  if (rl_store(c, i) || i->res == MIR_NONE || rl_load(c, i) || rl_type_ops(c, i)) {
    return;
  }
  /* `none` holds no list, so no length to share. */
  if (!rl_is_list(c, i->res) || i->op == MOP_OptNone || i->op == MOP_OptNoneOwned) {
    return;
  }
  rl_list_result(c, i);
}

static void rl_term_edges(RgLen *c, const MirTerm *term) {
  for (uint32_t t = 0; t < mir_term_ntargets(term); t++) {
    const MirTarget *tg = mir_term_target_const(term, t);
    const MirBlockData *to = &c->f->blocks.ptr[tg->block];
    for (uint32_t j = 0; j < tg->nargs && j < to->params.len; j++) {
      const MirValue a = tg->args[j], p = to->params.ptr[j].value;
      if (rl_is_list(c, p)) {
        rl_edge(c, a, p);
      }
      rl_copy_fields(c, a, p);
    }
  }
}

static void rl_collect(RgLen *c) {
  const MirFunc *f = c->f;
  for (uint32_t bi = 1; bi < f->blocks.len; bi++) {
    for (uint32_t p = 0; p < f->blocks.ptr[bi].params.len; p++) {
      mir_bits_set(&c->flows, f->blocks.ptr[bi].params.ptr[p].value);
    }
  }
  for (uint32_t p = 0; p < c->nv; p++) {
    if (mir_bits_test(&c->candidates, p)) {
      mir_bits_set(&c->flows, p);
    }
  }
  for (uint32_t p = 0; p < f->blocks.ptr[0].params.len; p++) {
    const MirValue v = f->blocks.ptr[0].params.ptr[p].value;
    if (rl_is_list(c, v)) {
      rl_seed(c, v, v);
    }
  }
  uint32_t nget = 0;
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    nget += f->blocks.ptr[bi].insts.len;
  }
  rl_map_init(c->a, &c->reads, nget);
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    for (uint32_t ii = 0; ii < f->blocks.ptr[bi].insts.len; ii++) {
      rl_inst(c, &f->blocks.ptr[bi].insts.ptr[ii]);
    }
    rl_term_edges(c, &f->blocks.ptr[bi].term);
  }
}

/* A pointer parameter's contents start every list field at its first read; type values nothing
 * flows into start every list field at its first read, or at the type itself when the field is
 * never read (a value no list shares an origin with). */
static void rl_seed_fields(RgLen *c) {
  const MirFunc *f = c->f;
  for (uint32_t p = 0; p < f->blocks.ptr[0].params.len; p++) {
    const MirValue q = f->blocks.ptr[0].params.ptr[p].value;
    for (uint32_t k = 0; mir_bits_test(&c->candidates, q) && k < c->slot_nf[q]; k++) {
      const uint32_t node = c->slot_base[q] + k;
      if (c->first_read[node] != MIR_NONE) {
        rl_seed(c, node, c->first_read[node]);
      }
    }
  }
  for (uint32_t v = 0; v < c->nv; v++) {
    const MirTypeDef *def = rl_def(c, v);
    for (uint32_t k = 0; def != NULL && !mir_bits_test(&c->flows, v) && k < def->nfields; k++) {
      const uint32_t node = rl_node(c, v, k);
      if (node != MIR_NONE) {
        rl_seed(c, node, c->first_read[node] != MIR_NONE ? c->first_read[node] : v);
      }
    }
  }
}

/* ---- solving ---- */

typedef struct RlGraph {
  uint32_t *ustart, *users;   /* the nodes each node feeds */
  uint32_t *sstart, *sources; /* the nodes that feed each node */
} RlGraph;

static void rl_csr(MsArena *a, uint32_t total, const uint32_t *key, const uint32_t *item,
         uint32_t ne, uint32_t **start, uint32_t **list) {
  uint32_t *s = RG_ZNEW(a, uint32_t, (size_t)total + 2);
  for (uint32_t e = 0; e < ne; e++) {
    s[key[e] + 1]++;
  }
  for (uint32_t n = 0; n < total; n++) {
    s[n + 1] += s[n];
  }
  uint32_t *fill = RG_ZNEW(a, uint32_t, (size_t)total + 1);
  uint32_t *l = RG_ZNEW(a, uint32_t, (size_t)ne + 1);
  for (uint32_t e = 0; e < ne; e++) {
    l[s[key[e]] + fill[key[e]]++] = item[e];
  }
  *start = s;
  *list = l;
}

static uint32_t rl_join(uint32_t old, uint32_t incoming) {
  if (old == RL_UNKNOWN) {
    return incoming;
  }
  return old == incoming ? old : RL_MIXED;
}

/* Runs the worklist from the seeds (and `pinned`, each its own origin) to a fixpoint. */
static void rl_propagate(RgLen *c, const RlGraph *g, const uint32_t *seeded, const MirBits *pinned,
            const uint32_t *params, uint32_t nparams, uint32_t *work) {
  __builtin_memcpy(c->facts, seeded, (size_t)c->total * sizeof *seeded);
  uint32_t nw = 0;
  for (uint32_t s = 0; s < c->nseeds; s++) {
    work[nw++] = c->seeds[s];
  }
  for (uint32_t i = 0; i < nparams; i++) {
    if (mir_bits_test(pinned, params[i])) {
      c->facts[params[i]] = params[i];
      work[nw++] = params[i];
    }
  }
  while (nw != 0) {
    const uint32_t v = work[--nw];
    for (uint32_t k = g->ustart[v]; k < g->ustart[v + 1]; k++) {
      const uint32_t u = g->users[k];
      if (u < c->nv && mir_bits_test(pinned, u)) {
        continue;
      }
      const uint32_t next = rl_join(c->facts[u], c->facts[v]);
      if (next != c->facts[u]) {
        c->facts[u] = next;
        work[nw++] = u;
      }
    }
  }
}

/* Block parameters that join lists of different origins are pinned: a fresh origin of their own,
 * which every list derived from them by element replacement shares. Without this the join poisons
 * everything downstream and a loop that updates the list in place cannot share an origin with the
 * list it started as. Pinning can expose a further join downstream, so repeat a few rounds. */
static void rl_solve(RgLen *c, const RlGraph *g) {
  const MirFunc *f = c->f;
  uint32_t *params = RG_ZNEW(c->a, uint32_t, c->nv);
  uint32_t nparams = 0;
  for (uint32_t bi = 1; bi < f->blocks.len; bi++) {
    for (uint32_t p = 0; p < f->blocks.ptr[bi].params.len; p++) {
      const MirValue v = f->blocks.ptr[bi].params.ptr[p].value;
      if (rl_is_list(c, v)) {
        params[nparams++] = v;
      }
    }
  }
  uint32_t *seeded = RG_ZNEW(c->a, uint32_t, c->total);
  __builtin_memcpy(seeded, c->facts, (size_t)c->total * sizeof *seeded);
  uint32_t *work = RG_ZNEW(c->a, uint32_t, (size_t)c->nseeds + (size_t)c->total * 3 + 8);
  MirBits pinned = mir_bits_new(c->a, c->nv);
  uint32_t npinned = 0;
  for (uint32_t round = 0; round < 6; round++) {
    rl_propagate(c, g, seeded, &pinned, params, nparams, work);
    /* Pin only a join with a source that is not itself mixed: a parameter that is mixed
     * merely downstream of a join takes that join's origin once the join is pinned. */
    const uint32_t before = npinned;
    MirBits now = mir_bits_new(c->a, c->nv);
    for (uint32_t i = 0; i < nparams; i++) {
      const uint32_t p = params[i];
      for (uint32_t k = g->sstart[p]; c->facts[p] == RL_MIXED && k < g->sstart[p + 1]; k++) {
        if (c->facts[g->sources[k]] != RL_MIXED) {
          mir_bits_set(&now, p);
          break;
        }
      }
    }
    for (uint32_t i = 0; i < nparams; i++) {
      if (mir_bits_test(&now, params[i]) && !mir_bits_test(&pinned, params[i])) {
        mir_bits_set(&pinned, params[i]);
        npinned++;
      }
    }
    if (round == 5 || npinned == before) {
      break;
    }
  }
}

MirValue *rg_length_origins(MsArena *arena, const MirModule *m, const MirFunc *f) {
  MsArena scratch = ms_arena_new();
  RgLen c = {.m = m, .f = f, .a = &scratch};
  rl_setup(&c);
  rl_slots(&c);
  c.first_read = RG_ZNEW(&scratch, uint32_t, c.total);
  __builtin_memset(c.first_read, 0xFF, (size_t)c.total * sizeof *c.first_read);
  c.facts = RG_ZNEW(&scratch, uint32_t, c.total);
  __builtin_memset(c.facts, 0xFF, (size_t)c.total * sizeof *c.facts);
  rl_collect(&c);
  rl_seed_fields(&c);
  RlGraph g;
  rl_csr(&scratch, c.total, c.efrom, c.eto, c.ne, &g.ustart, &g.users);
  rl_csr(&scratch, c.total, c.eto, c.efrom, c.ne, &g.sstart, &g.sources);
  rl_solve(&c, &g);
  MirValue *out = RG_ZNEW(arena, MirValue, c.nv + 1);
  for (uint32_t v = 0; v < c.nv; v++) {
    const bool one = c.facts[v] != RL_UNKNOWN && c.facts[v] != RL_MIXED;
    out[v] = one ? c.facts[v] : v;
  }
  ms_arena_free(&scratch);
  return out;
}

/* ---- byte lists ---- */

/* Lists whose elements all lie in `0..=255` because they came from `Bytes.values()`.
 *
 * A list value is immutable: `list.set` and the other mutators return a new value, which is not
 * marked. A block parameter qualifies when every incoming argument does, so the fact survives
 * loops that thread the list around unchanged. The analysis starts optimistic for non-entry
 * parameters and removes the ones an edge disproves. */
uint8_t *rg_byte_lists(MsArena *arena, const MirModule *m, const MirFunc *f) {
  uint8_t *facts = RG_ZNEW(arena, uint8_t, f->values.len + 1);
  uint32_t *incoming = RG_ZNEW(arena, uint32_t, f->blocks.len);
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    const MirBlockData *b = &f->blocks.ptr[bi];
    for (uint32_t ii = 0; ii < b->insts.len; ii++) {
      const MirInst *i = &b->insts.ptr[ii];
      if (i->op == MOP_CallRt && i->imm.tag == MI_EXT && i->res != MIR_NONE &&
        m->externs.ptr[i->imm.a].role == MR_BYTES_VALUES) {
        facts[i->res] = 1;
      }
    }
    for (uint32_t t = 0; t < mir_term_ntargets(&b->term); t++) {
      incoming[mir_term_target_const(&b->term, t)->block]++;
    }
  }
  for (uint32_t bi = 1; bi < f->blocks.len; bi++) {
    for (uint32_t p = 0; p < f->blocks.ptr[bi].params.len; p++) {
      const MirValue v = f->blocks.ptr[bi].params.ptr[p].value;
      const bool list = mir_ty_data(m, f->values.ptr[v])->kind == MK_LIST;
      facts[v] = list && incoming[bi] != 0 ? 1 : 0;
    }
  }
  for (bool changed = true; changed;) {
    changed = false;
    for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
      const MirTerm *term = &f->blocks.ptr[bi].term;
      for (uint32_t t = 0; t < mir_term_ntargets(term); t++) {
        const MirTarget *tg = mir_term_target_const(term, t);
        const MirBlockData *to = &f->blocks.ptr[tg->block];
        for (uint32_t j = 0; j < tg->nargs && j < to->params.len; j++) {
          const MirValue p = to->params.ptr[j].value;
          const bool list = mir_ty_data(m, f->values.ptr[p])->kind == MK_LIST;
          if (list && facts[p] != 0 && facts[tg->args[j]] == 0) {
            facts[p] = 0;
            changed = true;
          }
        }
      }
    }
  }
  return facts;
}

/* ---- loop lists ---- */

/* The one value a block parameter receives other than itself: MIR_NONE - 1 once two differ. */
#define RL_MANY (MIR_NONE - 1)

static void rl_note_source(const MirModule *m, const MirFunc *f, const MirTarget *t,
             uint32_t *source) {
  const MirBlockData *to = &f->blocks.ptr[t->block];
  for (uint32_t j = 0; j < t->nargs && j < to->params.len; j++) {
    const MirValue p = to->params.ptr[j].value, a = t->args[j];
    if (a == p || f->values.ptr[a] != f->values.ptr[p] ||
      mir_ty_data(m, f->values.ptr[a])->kind != MK_LIST) {
      continue;
    }
    if (source[p] == MIR_NONE) {
      source[p] = a;
    } else if (source[p] != a) {
      source[p] = RL_MANY;
    }
  }
}

/* A block parameter that only ever receives one other value (or itself, around a loop) is that
 * value: a list threaded unchanged through a loop keeps the origin of the list it started as,
 * even when that list's own origin is mixed. Only lists matter; `lengths` is the identity for
 * everything else. */
void rg_alias_loop_lists(MsArena *scratch, const MirModule *m, const MirFunc *f,
            MirValue *lengths) {
  uint32_t *source = RG_ZNEW(scratch, uint32_t, f->values.len + 1);
  __builtin_memset(source, 0xFF, ((size_t)f->values.len + 1) * sizeof *source);
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    const MirTerm *term = &f->blocks.ptr[bi].term;
    for (uint32_t t = 0; t < mir_term_ntargets(term); t++) {
      rl_note_source(m, f, mir_term_target_const(term, t), source);
    }
  }
  for (uint32_t round = 0; round < 8; round++) {
    bool changed = false;
    for (uint32_t p = 0; p < f->values.len; p++) {
      const uint32_t a = source[p];
      if (a == MIR_NONE || a == RL_MANY) {
        continue;
      }
      if (lengths[p] == p && lengths[a] != p && lengths[p] != lengths[a]) {
        lengths[p] = lengths[a];
        changed = true;
      }
    }
    if (!changed) {
      break;
    }
  }
}

/* ---- counted lists ---- */

static const MirInst *rcl_def(const RgFa *fa, MirValue v) { return rg_def_inst(fa, v); }

/* Whether the incoming arguments of block `bi` keep integer parameter `ci` equal to the length of
 * list parameter `li`: both start at zero, or the list is pushed to while the integer adds one. */
static bool rcl_paired(const RgFa *fa, uint32_t bi, uint32_t li, uint32_t ci) {
  const MirValue l = fa->f->blocks.ptr[bi].params.ptr[li].value, c = fa->f->blocks.ptr[bi].params.ptr[ci].value;
  for (uint32_t e = fa->in_start[bi]; e < fa->in_start[bi + 1]; e++) {
    const MirValue al = fa->in[e].args[li], ac = fa->in[e].args[ci];
    const MirInst *dl = rcl_def(fa, al), *dc = rcl_def(fa, ac);
    int64_t k = 0, one = 0;
    const bool fresh = dl != NULL &&
             (dl->op == MOP_ListNew || (dl->op == MOP_ListLit && dl->nargs == 0)) &&
             rg_constant(fa, ac, &k) && k == 0;
    const bool step = dl != NULL && dl->op == MOP_ListPush && dl->args[0] == l && dc != NULL &&
             (dc->op == MOP_IAdd || dc->op == MOP_IAddChk) && dc->args[0] == c &&
             rg_constant(fa, dc->args[1], &one) && one == 1;
    if (!fresh && !step) {
      return false;
    }
  }
  return true;
}

/* A loop that starts with an empty list and a counter at zero and pushes one element while adding
 * one to the counter keeps the counter equal to the list's length: the counter parameter takes the
 * list parameter's length origin. */
void rg_counted_lists(const RgFa *fa, MirValue *lenof) {
  const MirFunc *f = fa->f;
  for (uint32_t bi = 1; bi < f->blocks.len; bi++) {
    if (fa->in_start[bi] == fa->in_start[bi + 1]) {
      continue;
    }
    const MirBlockData *blk = &f->blocks.ptr[bi];
    for (uint32_t li = 0; li < blk->params.len; li++) {
      if (mir_ty_data(fa->m, f->values.ptr[blk->params.ptr[li].value])->kind != MK_LIST) {
        continue;
      }
      for (uint32_t ci = 0; ci < blk->params.len; ci++) {
        if (f->values.ptr[blk->params.ptr[ci].value] == MIR_INT && rcl_paired(fa, bi, li, ci)) {
          lenof[blk->params.ptr[ci].value] = fa->lengths[blk->params.ptr[li].value];
        }
      }
    }
  }
}
