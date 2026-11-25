/* The `simplify` pass, repeated map probes and the join of a `contains` test with the lookup after it. */
#include "compiler/opt/opt_simplify.h"

#include "base/sort.h"

/* ---- repeated map probes ---- */

static bool sb_name_eq(const MirModule *m, MsName sym, const char *text) {
  const MsSpan s = ms_names_span(&m->names, sym);
  return ms_span_equal(s, ms_span_of_text(text));
}

/* The runtime function a call instruction names; NULL when it is not a runtime call. */
static const MirExtern *sb_extern_of(const MirModule *m, const MirInst *i) {
  return i->op == MOP_CallRt && i->imm.tag == MI_EXT ? &m->externs.ptr[i->imm.a] : NULL;
}

/* The runtime lookups that return the address of a map entry (or null). */
bool opt_simplify_is_map_probe(const MirModule *m, const MirInst *i) {
  const MirExtern *e = sb_extern_of(m, i);
  return e != NULL && (sb_name_eq(m, e->name, "msrt_map_get_ptr") ||
            sb_name_eq(m, e->name, "msrt_map_get_ptr_w8") ||
            sb_name_eq(m, e->name, "msrt_map_get_ptr_sw8"));
}

/* Whether `i` can insert into, remove from or move a map. A type update drops the field it
 * replaces, never a map being probed. */
static bool sb_clobbers(const MirInst *i) {
  const uint8_t e = mir_op_info[i->op].effects;
  return (e & (MIR_E_IO | MIR_E_OWNERSHIP | MIR_E_ALLOC)) != 0 && i->op != MOP_TypeSet;
}

typedef struct SbProbe {
  uint32_t ext;
  MirValue a0, a1, a2, key, value;
} SbProbe;

/* The probes of one point in a block and the entry each found. */
typedef struct SbProbes {
  SbProbe *v;
  uint32_t n, cap;
} SbProbes;

static SbProbes sb_probes_copy(MsArena *arena, const SbProbes *src) {
  SbProbes c = {0};
  if (src != NULL && src->n > 0) {
    c.v = MS_ARENA_NEW_ARRAY(arena, SbProbe, src->n);
    __builtin_memcpy(c.v, src->v, sizeof(SbProbe) * src->n);
    c.n = c.cap = src->n;
  }
  return c;
}

static bool sb_probes_get(const SbProbes *t, const SbProbe *key, MirValue *out) {
  for (uint32_t k = 0; k < t->n; k++) {
    const SbProbe *p = &t->v[k];
    if (p->ext == key->ext && p->a0 == key->a0 && p->a1 == key->a1 && p->a2 == key->a2 &&
      p->key == key->key) {
      *out = p->value;
      return true;
    }
  }
  return false;
}

static void sb_probes_add(MsArena *arena, SbProbes *t, SbProbe p) {
  if (t->n == t->cap) {
    const uint32_t cap = t->cap ? t->cap * 2 : 4;
    SbProbe *grown = MS_ARENA_NEW_ARRAY(arena, SbProbe, cap);
    if (t->n > 0) {
      __builtin_memcpy(grown, t->v, sizeof(SbProbe) * t->n);
    }
    t->v = grown;
    t->cap = cap;
  }
  t->v[t->n++] = p;
}

/* The value stored into each key slot of the block so far: a stamp per slot, valid while it equals
 * the current generation. */
typedef struct SbStored {
  uint32_t *stamp;
  MirValue *key;
  uint32_t gen;
} SbStored;

typedef struct SbProbeRun {
  MirModule *m;
  MirFunc *f;
  MsArena *arena;
  OptSubst subst;
  bool **removed;
  OptIdList slots_dropped;
  SbStored stored;
} SbProbeRun;

static void sb_stored_set(SbStored *s, MirValue slot, MirValue key) {
  s->stamp[slot] = s->gen;
  s->key[slot] = key;
}

static bool sb_stored_get(const SbStored *s, MirValue slot, MirValue *key) {
  if (s->stamp[slot] != s->gen) {
    return false;
  }
  *key = s->key[slot];
  return true;
}

/* A probe of a map seen before in the block, with the key it was stored under: reuse the earlier
 * address, or record this probe. */
static void sb_note_probe(SbProbeRun *run, SbProbes *table, uint32_t bi, uint32_t ii,
             const MirInst *inst) {
  MirValue a[4];
  for (uint32_t k = 0; k < 4; k++) {
    a[k] = opt_subst_resolve(&run->subst, inst->args[k]);
  }
  MirValue key = 0;
  if (!sb_stored_get(&run->stored, a[3], &key) || inst->res == MIR_NONE) {
    return;
  }
  const SbProbe probe = {inst->imm.a, a[0], a[1], a[2], key, inst->res};
  MirValue prev = 0;
  if (sb_probes_get(table, &probe, &prev)) {
    opt_subst_set(&run->subst, inst->res, prev);
    run->removed[bi][ii] = true;
    opt_id_push(run->arena, &run->slots_dropped, a[3]);
  } else {
    sb_probes_add(run->arena, table, probe);
  }
}

static void sb_probe_inst(SbProbeRun *run, SbProbes *table, uint32_t bi, uint32_t ii) {
  const MirInst *inst = &run->f->blocks.ptr[bi].insts.ptr[ii];
  if (opt_simplify_is_map_probe(run->m, inst) && inst->nargs == 4) {
    sb_note_probe(run, table, bi, ii, inst);
    return;
  }
  if (inst->op == MOP_Store || inst->op == MOP_Put || inst->op == MOP_Take) {
    run->stored.stamp[inst->args[0]] = 0;
    if (inst->op == MOP_Store) {
      sb_stored_set(&run->stored, inst->args[0],
             opt_subst_resolve(&run->subst, inst->args[1]));
    }
  } else if (sb_clobbers(inst)) {
    table->n = 0;
    run->stored.gen++;
  }
}

/* A probe of the same map for the same key, with nothing between that can change the map's
 * layout, finds the same entry: the later call reuses the earlier address. The key reaches the
 * runtime through a stack slot filled just before the call, so the key is the value stored there.
 * The table follows a block into its only successor (a fault branch or an `if` arm) and is dropped
 * at a join or loop header, and at any instruction that calls out, drops, clones or allocates. */
bool opt_simplify_map_probes(MirModule *m, MirFunc *f) {
  bool any = false;
  for (uint32_t bi = 0; bi < f->blocks.len && !any; bi++) {
    for (uint32_t ii = 0; ii < f->blocks.ptr[bi].insts.len && !any; ii++) {
      any = opt_simplify_is_map_probe(m, &f->blocks.ptr[bi].insts.ptr[ii]);
    }
  }
  if (!any) {
    return false;
  }
  MsArena arena = ms_arena_new();
  const MirPreds preds = mir_preds(&arena, f);
  SbProbes **ends = MS_ARENA_NEW_ARRAY(&arena, SbProbes *, f->blocks.len);
  SbProbeRun run = {.m = m, .f = f, .arena = &arena};
  run.subst = opt_subst_new(&arena, (uint32_t)f->values.len);
  run.removed = opt_dead_flags(&arena, f);
  run.stored.stamp = MS_ARENA_NEW_ARRAY(&arena, uint32_t, f->values.len);
  run.stored.key = MS_ARENA_NEW_ARRAY(&arena, MirValue, f->values.len);
  MirBlock *order = NULL;
  const uint32_t count = mir_rpo(&arena, f, &order);
  bool removed_any = false;
  for (uint32_t k = 0; k < count; k++) {
    const uint32_t bi = order[k];
    const bool single = mir_preds_count(&preds, bi) == 1 && mir_pred(&preds, bi, 0) != bi;
    SbProbes *table = MS_ARENA_NEW(&arena, SbProbes);
    *table = sb_probes_copy(&arena, single ? ends[mir_pred(&preds, bi, 0)] : NULL);
    run.stored.gen++;
    for (uint32_t ii = 0; ii < f->blocks.ptr[bi].insts.len; ii++) {
      sb_probe_inst(&run, table, bi, ii);
    }
    ends[bi] = table;
  }
  removed_any = run.slots_dropped.n > 0 || run.subst.count > 0;
  if (removed_any) {
    /* The key slot of a removed probe is only filled and never read again: drop both. */
    uint32_t *uses = mir_use_counts(&arena, f);
    bool *dead_slot = MS_ARENA_NEW_ARRAY(&arena, bool, f->values.len);
    for (uint32_t k = 0; k < run.slots_dropped.n; k++) {
      dead_slot[run.slots_dropped.v[k]] = uses[run.slots_dropped.v[k]] == 2;
    }
    for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
      for (uint32_t ii = 0; ii < f->blocks.ptr[bi].insts.len; ii++) {
        const MirInst *i = &f->blocks.ptr[bi].insts.ptr[ii];
        const bool slot_store = i->op == MOP_Store && dead_slot[i->args[0]];
        const bool slot_def = i->op == MOP_Slot && i->res != MIR_NONE && dead_slot[i->res];
        run.removed[bi][ii] |= slot_store || slot_def;
      }
    }
    opt_sweep_dead(f, (bool *const *)run.removed, &arena);
    opt_subst_apply(f, &run.subst);
  }
  ms_arena_free(&arena);
  return removed_any;
}

/* ---- joining a `contains` test with the lookup after it ---- */

/* What one predecessor of a join passes for the map, and the earlier probe or `contains` of it. */
typedef struct SbPredPlan {
  uint32_t block;
  MirValue map;
  bool has_hit;
  uint32_t hit_block, hit_inst;
  bool hit_contains;
} SbPredPlan;

/* Facts about the function's slots and type descriptors, gathered once. */
typedef struct SbFacts {
  uint8_t *key_state; /* per slot: 0 never stored, 1 stored one value, 2 stored several */
  MirValue *key;
  MirImm *slot_imm;
  bool *is_slot;
  MirImm *desc_imm;
  MirTy *desc_ty;
  bool *is_desc;
  uint32_t *uses;
} SbFacts;

static SbFacts sb_facts(MsArena *arena, const MirFunc *f) {
  const uint32_t n = (uint32_t)f->values.len;
  SbFacts s = {MS_ARENA_NEW_ARRAY(arena, uint8_t, n), MS_ARENA_NEW_ARRAY(arena, MirValue, n),
        MS_ARENA_NEW_ARRAY(arena, MirImm, n), MS_ARENA_NEW_ARRAY(arena, bool, n),
        MS_ARENA_NEW_ARRAY(arena, MirImm, n), MS_ARENA_NEW_ARRAY(arena, MirTy, n),
        MS_ARENA_NEW_ARRAY(arena, bool, n), mir_use_counts(arena, f)};
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    for (uint32_t ii = 0; ii < f->blocks.ptr[bi].insts.len; ii++) {
      const MirInst *i = &f->blocks.ptr[bi].insts.ptr[ii];
      if (i->op == MOP_Slot && i->res != MIR_NONE) {
        s.is_slot[i->res] = true;
        s.slot_imm[i->res] = i->imm;
      } else if (i->op == MOP_TypeDesc && i->res != MIR_NONE) {
        s.is_desc[i->res] = true;
        s.desc_imm[i->res] = i->imm;
        s.desc_ty[i->res] = f->values.ptr[i->res];
      } else if (i->op == MOP_Store) {
        const MirValue slot = i->args[0];
        s.key_state[slot] = s.key_state[slot] == 0 ? 1 : 2;
        s.key[slot] = i->args[1];
      }
    }
  }
  return s;
}

/* The arguments `pb` passes to `ji` when it has exactly one edge there; false otherwise. */
static bool sb_arm_args(const MirFunc *f, uint32_t pb, uint32_t ji, const MirValue **args,
            uint32_t *nargs) {
  const MirTerm *t = &f->blocks.ptr[pb].term;
  const MirTarget *arm = NULL;
  if (t->kind == MT_BR && t->a.block == ji) {
    arm = &t->a;
  } else if (t->kind == MT_CONDBR && (t->a.block == ji) != (t->b.block == ji)) {
    arm = t->a.block == ji ? &t->a : &t->b;
  }
  if (arm == NULL) {
    return false;
  }
  *args = arm->args;
  *nargs = arm->nargs;
  return true;
}

typedef struct SbJoin {
  MirModule *m;
  MirFunc *f;
  SbFacts facts;
  MirPreds preds;
  uint32_t ji;
  MirInst probe;
  MirValue key;
  const MirExtern *probe_ext;
  char pname[160], contains_name[160];
  uint32_t map_param;
} SbJoin;

static bool sb_ext_is(const MirModule *m, const MirExtern *e, const char *text) {
  return sb_name_eq(m, e->name, text);
}

/* Whether `i` is a probe or `contains` of map `a` for the join's key, with the join's descriptors;
 * *contains tells which. */
static bool sb_matches(const SbJoin *j, const MirInst *i, MirValue a, bool *contains) {
  const MirExtern *e = sb_extern_of(j->m, i);
  const SbFacts *s = &j->facts;
  if (e == NULL || i->nargs != 4 || i->args[0] != a) {
    return false;
  }
  const MirValue slot = i->args[3];
  if (s->key_state[slot] != 1 || s->key[slot] != j->key || !s->is_desc[i->args[1]] ||
    !s->is_desc[i->args[2]]) {
    return false;
  }
  if (!opt_imm_eq(&s->desc_imm[i->args[1]], &s->desc_imm[j->probe.args[1]]) ||
    !opt_imm_eq(&s->desc_imm[i->args[2]], &s->desc_imm[j->probe.args[2]])) {
    return false;
  }
  *contains = sb_ext_is(j->m, e, j->contains_name);
  return *contains || sb_ext_is(j->m, e, j->pname);
}

/* Walks back from `pb` through single-predecessor blocks, newest instruction first, to the earlier
 * probe or `contains` of map `a`; stops at anything that can change a map. */
static bool sb_find_hit(const SbJoin *j, uint32_t pb, MirValue a, SbPredPlan *plan) {
  uint32_t cur = pb;
  for (;;) {
    const MirBlockData *b = &j->f->blocks.ptr[cur];
    for (uint32_t ii = (uint32_t)b->insts.len; ii-- > 0;) {
      bool contains = false;
      if (sb_matches(j, &b->insts.ptr[ii], a, &contains)) {
        plan->has_hit = true;
        plan->hit_block = cur;
        plan->hit_inst = ii;
        plan->hit_contains = contains;
        return true;
      }
      if (sb_clobbers(&b->insts.ptr[ii])) {
        return false;
      }
    }
    if (mir_preds_count(&j->preds, cur) != 1) {
      return false;
    }
    const uint32_t q = mir_pred(&j->preds, cur, 0);
    if (q == cur || q == j->ji) {
      return false;
    }
    cur = q;
  }
}

/* Finds the join's first probe, before anything that can change a map; false when there is none or
 * it does not qualify. Fills the join's description. */
static bool sb_join_probe(SbJoin *j) {
  const MirBlockData *jb = &j->f->blocks.ptr[j->ji];
  uint32_t pi = 0;
  bool found = false;
  for (uint32_t ii = 0; ii < jb->insts.len && !found; ii++) {
    if (opt_simplify_is_map_probe(j->m, &jb->insts.ptr[ii]) && jb->insts.ptr[ii].nargs == 4) {
      pi = ii;
      found = true;
    } else if (sb_clobbers(&jb->insts.ptr[ii])) {
      break;
    }
  }
  if (!found) {
    return false;
  }
  j->probe = jb->insts.ptr[pi];
  const SbFacts *s = &j->facts;
  const MirValue slot = j->probe.args[3];
  if (j->probe.res == MIR_NONE || s->key_state[slot] != 1) {
    return false;
  }
  j->key = s->key[slot];
  j->probe_ext = sb_extern_of(j->m, &j->probe);
  j->map_param = UINT32_MAX;
  for (uint32_t k = 0; k < jb->params.len; k++) {
    if (jb->params.ptr[k].value == j->probe.args[0]) {
      j->map_param = k;
      break;
    }
  }
  if (j->map_param == UINT32_MAX || !s->is_desc[j->probe.args[1]] ||
    !s->is_desc[j->probe.args[2]] || !s->is_slot[slot]) {
    return false;
  }
  /* The key must be defined outside the join, so it is available in each predecessor. */
  bool key_local = false;
  for (uint32_t k = 0; k < jb->params.len; k++) {
    key_local |= jb->params.ptr[k].value == j->key;
  }
  for (uint32_t ii = 0; ii < jb->insts.len; ii++) {
    key_local |= jb->insts.ptr[ii].res == j->key;
  }
  return !key_local && s->uses[slot] == 2;
}

/* Names of the probe and of the `contains` it pairs with: `get_ptr` becomes `contains`. */
static void sb_join_names(SbJoin *j) {
  const MsSpan name = ms_names_span(&j->m->names, j->probe_ext->name);
  const char *from = "get_ptr";
  const size_t from_len = ms_span_of_text(from).len;
  size_t out = 0, n = name.len < sizeof j->pname - 1 ? name.len : sizeof j->pname - 1;
  __builtin_memcpy(j->pname, name.ptr, n);
  j->pname[n] = 0;
  for (size_t k = 0; k < n && out < sizeof j->contains_name - 16;) {
    if (k + from_len <= n && __builtin_memcmp(j->pname + k, from, from_len) == 0) {
      __builtin_memcpy(j->contains_name + out, "contains", 8);
      out += 8;
      k += from_len;
    } else {
      j->contains_name[out++] = j->pname[k++];
    }
  }
  j->contains_name[out] = 0;
}

/* Per predecessor: the map it passes and an earlier probe (or `contains`) of it. */
static bool sb_plan_join(const SbJoin *j, SbPredPlan plan[2]) {
  for (uint32_t k = 0; k < 2; k++) {
    const uint32_t pb = mir_pred(&j->preds, j->ji, k);
    const MirValue *args = NULL;
    uint32_t nargs = 0;
    if (!sb_arm_args(j->f, pb, j->ji, &args, &nargs) || j->map_param >= nargs) {
      return false;
    }
    plan[k] = (SbPredPlan){.block = pb, .map = args[j->map_param]};
    sb_find_hit(j, pb, plan[k].map, &plan[k]);
  }
  return plan[0].has_hit || plan[1].has_hit;
}

/* A `contains` becomes a probe whose null test and negation define its old result; returns the
 * address it yields. */
static MirValue sb_probe_from_contains(SbJoin *j, const SbPredPlan *p) {
  MirModule *m = j->m;
  MirFunc *f = j->f;
  const MirTy ptr = f->values.ptr[j->probe.res];
  const MirInst old = f->blocks.ptr[p->hit_block].insts.ptr[p->hit_inst];
  const MirValue new_ptr = mir_new_value(f, ptr);
  const MirValue null = mir_new_value(f, f->values.ptr[old.res]);
  MirBlockData *blk = &f->blocks.ptr[p->hit_block];
  blk->insts.ptr[p->hit_inst].imm = j->probe.imm;
  blk->insts.ptr[p->hit_inst].res = new_ptr;
  const MirInst is_null = opt_inst_make(m, MOP_PtrIsNull, &new_ptr, 1, (MirImm){0}, null, old.loc);
  mir_block_insert(blk, p->hit_inst + 1, &is_null);
  const MirInst negate = opt_inst_make(m, MOP_Not, &null, 1, (MirImm){0}, old.res, old.loc);
  mir_block_insert(blk, p->hit_inst + 2, &negate);
  return new_ptr;
}

/* A predecessor with no earlier probe probes before it branches, so no path pays more than
 * before; returns the address it yields. */
static MirValue sb_probe_in_pred(SbJoin *j, const SbPredPlan *p) {
  MirModule *m = j->m;
  MirFunc *f = j->f;
  const MirTy ptr = f->values.ptr[j->probe.res];
  const SbFacts *s = &j->facts;
  const MirLoc loc = j->probe.loc;
  const MirValue key_desc_src = j->probe.args[1], val_desc_src = j->probe.args[2];
  const MirValue slot_src = j->probe.args[3];
  const MirValue kd = mir_new_value(f, s->desc_ty[key_desc_src]);
  const MirValue vd = mir_new_value(f, s->desc_ty[val_desc_src]);
  const MirValue slot = mir_new_value(f, f->values.ptr[slot_src]);
  const MirValue got = mir_new_value(f, ptr);
  const MirValue store_args[2] = {slot, j->key};
  const MirValue call_args[4] = {p->map, kd, vd, slot};
  const MirInst insts[5] = {
    opt_inst_make(m, MOP_TypeDesc, NULL, 0, s->desc_imm[key_desc_src], kd, loc),
    opt_inst_make(m, MOP_TypeDesc, NULL, 0, s->desc_imm[val_desc_src], vd, loc),
    opt_inst_make(m, MOP_Slot, NULL, 0, s->slot_imm[slot_src], slot, loc),
    opt_inst_make(m, MOP_Store, store_args, 2, (MirImm){0}, MIR_NONE, loc),
    opt_inst_make(m, MOP_CallRt, call_args, 4, j->probe.imm, got, loc),
  };
  opt_block_append(&f->blocks.ptr[p->block], insts, 5);
  return got;
}

/* Adds `v` as the last argument of every edge from `pb` into the join. */
static void opt_id_push_edge_arg(MirModule *m, MirFunc *f, uint32_t pb, uint32_t ji, MirValue v) {
  MirTerm *t = &f->blocks.ptr[pb].term;
  for (uint32_t s = 0; s < mir_term_ntargets(t); s++) {
    MirTarget *tg = mir_term_target(t, s);
    if (tg->block != ji) {
      continue;
    }
    MirValue *args = MS_ARENA_NEW_ARRAY(&m->arena, MirValue, tg->nargs + 2);
    __builtin_memcpy(args, tg->args, sizeof(MirValue) * tg->nargs);
    args[tg->nargs] = v;
    tg->args = args;
    tg->nargs++;
  }
}

/* Rewrites the join: each predecessor passes the entry address as a new block parameter. */
static void sb_fuse(SbJoin *j, const SbPredPlan plan[2]) {
  MirModule *m = j->m;
  MirFunc *f = j->f;
  const MirValue res = j->probe.res, slot = j->probe.args[3];
  const MirValue param = mir_new_value(f, f->values.ptr[res]);
  MirValue edge_vals[2];
  for (uint32_t k = 0; k < 2; k++) {
    if (plan[k].has_hit && !plan[k].hit_contains) {
      edge_vals[k] = f->blocks.ptr[plan[k].hit_block].insts.ptr[plan[k].hit_inst].res;
    } else if (plan[k].has_hit) {
      edge_vals[k] = sb_probe_from_contains(j, &plan[k]);
    } else {
      edge_vals[k] = sb_probe_in_pred(j, &plan[k]);
    }
  }
  for (uint32_t k = 0; k < 2; k++) {
    opt_id_push_edge_arg(m, f, plan[k].block, j->ji, edge_vals[k]);
  }
  MirBlockData *jb = &f->blocks.ptr[j->ji];
  const MirBlockParam bp = {param, MM_BORROW};
  mir_block_param_list_push(&jb->params, bp);
  /* The join's probe now reads the parameter; its key slot goes with it. */
  uint32_t kept = 0;
  for (uint32_t ii = 0; ii < jb->insts.len; ii++) {
    const MirInst *i = &jb->insts.ptr[ii];
    const bool gone = i->res == res || (i->op == MOP_Store && i->args[0] == slot) ||
             i->res == slot;
    if (!gone) {
      jb->insts.ptr[kept++] = *i;
    }
  }
  jb->insts.len = kept;
  MsArena arena = ms_arena_new();
  OptSubst subst = opt_subst_new(&arena, (uint32_t)f->values.len);
  opt_subst_set(&subst, res, param);
  opt_subst_apply(f, &subst);
  ms_arena_free(&arena);
}

/* `if not m.contains(k): m[k] = v` followed by `m[k].f += 1` probes twice on the common path: the
 * test finds the entry, the join's lookup finds it again. When a block with two predecessors starts
 * with a probe of a map that arrives as a block parameter, and one predecessor holds an earlier
 * probe or `contains` of its argument for the same key with nothing in between that can change the
 * map, that predecessor passes the entry address as a new block parameter instead. */
bool opt_simplify_fuse_contains(MirModule *m, MirFunc *f) {
  MsArena arena = ms_arena_new();
  SbJoin j = {.m = m, .f = f};
  j.preds = mir_preds(&arena, f);
  j.facts = sb_facts(&arena, f);
  bool fused = false;
  for (uint32_t ji = 0; ji < f->blocks.len && !fused; ji++) {
    if (mir_preds_count(&j.preds, ji) != 2 || mir_pred(&j.preds, ji, 0) == ji ||
      mir_pred(&j.preds, ji, 1) == ji) {
      continue;
    }
    j.ji = ji;
    SbPredPlan plan[2];
    if (!sb_join_probe(&j)) {
      continue;
    }
    sb_join_names(&j);
    if (sb_plan_join(&j, plan)) {
      sb_fuse(&j, plan);
      fused = true;
    }
  }
  ms_arena_free(&arena);
  return fused;
}

