/* opt_copyelim_local.c: see opt_copyelim.h. */
#include "compiler/opt/opt_copyelim.h"

/* ---- a copy that only lives next to its source ---- */

/* Where each value is defined, as (block, instruction) with `block == UINT32_MAX` for a parameter
 * or a value no instruction defines. */
static CpePos *cpe_defs(MsArena *arena, const MirFunc *f) {
  CpePos *defs = MS_ARENA_NEW_ARRAY(arena, CpePos, (size_t)f->values.len + 1);
  for (uint32_t v = 0; v <= f->values.len; v++) {
    defs[v] = (CpePos){UINT32_MAX, 0};
  }
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      if (f->blocks.ptr[b].insts.ptr[i].res != MIR_NONE) {
        defs[f->blocks.ptr[b].insts.ptr[i].res] = (CpePos){b, i};
      }
    }
  }
  return defs;
}

static const MirInst *cpe_def_inst(const MirFunc *f, const CpePos *defs, MirValue v) {
  return defs[v].block == UINT32_MAX ? NULL : &f->blocks.ptr[defs[v].block].insts.ptr[defs[v].index];
}

/* The owned value (or parameter) `v` is ultimately read out of, followed through every kind of
 * projection: field, list element, optional payload, alternative payload, and a map entry (`load`
 * of the pointer a map lookup returns). False when the chain reaches a borrow it cannot see
 * through (a call returning a reference, a global), so the caller keeps its copy. */
static bool cpe_projection_owner(const MirModule *m, const MirFunc *f, const CpePos *defs, MirValue v,
                MirValue *owner) {
  for (const MirInst *def = cpe_def_inst(f, defs, v); def != NULL; def = cpe_def_inst(f, defs, v)) {
    switch ((MirOp)def->op) {
    case MOP_TypeGet: case MOP_ListGet: case MOP_ListGetU: case MOP_ListGetNn:
    case MOP_OptGet: case MOP_AltGet:
      v = def->args[0];
      break;
    case MOP_Load: {
      const MirInst *ptr_def = cpe_def_inst(f, defs, def->args[0]);
      if (ptr_def == NULL || ptr_def->op != MOP_CallRt || ptr_def->nargs == 0) {
        return false;
      }
      v = ptr_def->args[0];
      break;
    }
    default: {
      MirMode mode = MM_BORROW;
      if (mir_result_mode(m, f, def, &mode) && mode == MM_MOVE) {
        *owner = v;
        return true;
      }
      return false;
    }
    }
  }
  *owner = v;
  return true;
}

/* What a string copy of `v` may borrow instead of copying: the owner (`*root`, MIR_NONE when `v`
 * is a parameter or a literal) of an element read out of a list, which stays valid while that owner
 * is only borrowed. False for any other source or when the owner cannot be traced. */
static bool cpe_str_source(const MirModule *m, const MirFunc *f, const CpePos *defs, MirValue v,
             MirValue *root) {
  *root = MIR_NONE;
  const MirInst *def = cpe_def_inst(f, defs, v);
  if (def == NULL || def->op == MOP_StrLit) {
    return true;
  }
  if (def->op == MOP_ListGet || def->op == MOP_ListGetU || def->op == MOP_ListGetNn) {
    return cpe_projection_owner(m, f, defs, def->args[0], root);
  }
  return false;
}

/* The owner at the end of the field projections that produced `v`, or MIR_NONE when `v` is not
 * a projection. */
static MirValue cpe_field_root(const MirFunc *f, const CpePos *defs, MirValue v) {
  MirValue root = MIR_NONE;
  for (const MirInst *def = cpe_def_inst(f, defs, v); def != NULL && def->op == MOP_TypeGet;
    def = cpe_def_inst(f, defs, v)) {
    v = def->args[0];
    root = v;
  }
  return root;
}


/* The number of the first `k` instructions of block `b` that write memory or touch reference
 * counts (other than `str.len` and `clone`), so a span is checked without a scan. */
static uint32_t cpe_unstable(const CpeLocal *l, uint32_t b, uint32_t k) {
  return l->unstable[l->unstable_base[b] + k];
}

static CpeLocal cpe_local(MsArena *arena, const MirModule *m, const MirFunc *f) {
  CpeLocal l = {m, f, cpe_operand_uses(arena, f), cpe_defs(arena, f), mir_use_counts(arena, f), NULL,
        MS_ARENA_NEW_ARRAY(arena, uint32_t, (size_t)f->blocks.len + 1), NULL};
  uint32_t total = 0, most = 0;
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    l.unstable_base[b] = total;
    total += f->blocks.ptr[b].insts.len + 1;
    most = f->blocks.ptr[b].insts.len > most ? (uint32_t)f->blocks.ptr[b].insts.len : most;
  }
  l.unstable = MS_ARENA_NEW_ARRAY(arena, uint32_t, (size_t)total + 1);
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    uint32_t n = 0;
    l.unstable[l.unstable_base[b]] = 0;
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      const MirInst *inst = &f->blocks.ptr[b].insts.ptr[i];
      const uint8_t e = mir_op_info[inst->op].effects;
      if (((e & MIR_E_WRITES) != 0 && inst->op != MOP_StrLen) ||
        ((e & MIR_E_OWNERSHIP) != 0 && inst->op != MOP_Clone)) {
        n++;
      }
      l.unstable[l.unstable_base[b] + i + 1] = n;
    }
  }
  uint32_t widest = 1;
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      widest = f->blocks.ptr[b].insts.ptr[i].nargs > widest ? f->blocks.ptr[b].insts.ptr[i].nargs : widest;
    }
  }
  l.modes = MS_ARENA_NEW_ARRAY(arena, MirMode, (size_t)widest + 1);
  (void)most;
  return l;
}

/* Whether an instruction of block `bi` strictly between `lo` and `hi` takes `x` other than by
 * borrow. */
static bool cpe_consumes(CpeLocal *l, MirValue x, uint32_t bi, uint32_t lo, uint32_t hi) {
  for (uint32_t u = 0; u < cpe_nuses(&l->at, x); u++) {
    const CpePos p = cpe_use(&l->at, x, u);
    if (p.block != bi || p.index <= lo || p.index >= hi) {
      continue;
    }
    const MirInst *n = &l->f->blocks.ptr[bi].insts.ptr[p.index];
    mir_arg_modes(l->m, l->f, n, l->modes);
    for (uint32_t a = 0; a < n->nargs; a++) {
      if (n->args[a] == x && l->modes[a] != MM_BORROW) {
        return true;
      }
    }
  }
  return false;
}

/* The first drop of `c` after instruction `i` of block `bi`; false when there is none. */
static bool cpe_first_drop(const CpeLocal *l, MirValue c, uint32_t bi, uint32_t i, uint32_t *j) {
  for (uint32_t u = 0; u < cpe_nuses(&l->at, c); u++) {
    const CpePos p = cpe_use(&l->at, c, u);
    if (p.block == bi && p.index > i && l->f->blocks.ptr[bi].insts.ptr[p.index].op == MOP_Drop) {
      *j = p.index;
      return true;
    }
  }
  return false;
}

static uint32_t cpe_uses_between(const CpeLocal *l, MirValue c, uint32_t bi, uint32_t i, uint32_t j) {
  uint32_t n = 0;
  for (uint32_t u = 0; u < cpe_nuses(&l->at, c); u++) {
    const CpePos p = cpe_use(&l->at, c, u);
    n += (p.block == bi && p.index > i && p.index < j) ? 1u : 0u;
  }
  return n;
}

/* Whether the copy `c = clone v` at `(bi, i)` dropped at `j` can be replaced by `v`. */
static bool cpe_local_copy_ok(CpeLocal *l, MirValue v, MirValue c, uint32_t bi, uint32_t i,
              uint32_t j) {
  const MirModule *m = l->m;
  const MirFunc *f = l->f;
  const uint8_t kind = mir_ty_data(m, mir_value_ty(f, v))->kind;
  const bool is_str = kind == MK_STR;
  const bool composite = kind == MK_TYPE || kind == MK_ALT || kind == MK_OPT || kind == MK_LIST ||
             kind == MK_BYTES;
  if (is_str) {
    /* Strings are immutable, so the copy can only differ from `v` once `v`'s owner releases or
     * replaces it. */
    MirValue root = MIR_NONE;
    if (!cpe_str_source(m, f, l->defs, v, &root) ||
      (root != MIR_NONE && cpe_consumes(l, root, bi, i, j))) {
      return false;
    }
  }
  if (composite && cpe_unstable(l, bi, j) > cpe_unstable(l, bi, i + 1)) {
    return false;
  }
  if (kind == MK_FN) {
    const MirValue root = cpe_field_root(f, l->defs, v);
    if (root != MIR_NONE && cpe_consumes(l, root, bi, i, j)) {
      return false; /* a closure read out of a type dies with the type */
    }
  }
  if (cpe_uses_between(l, c, bi, i, j) + 1 != l->uses[c]) {
    return false;
  }
  return !cpe_consumes(l, v, bi, i, j) && !cpe_consumes(l, c, bi, i, j);
}

/* Removes `c = clone v; ...; drop c` when the span only borrows the copy and its source stays
 * alive. Composite values additionally require a span without writes that could change or
 * release a projection's owner. String length may cache its result, but cannot release or
 * replace data. This includes read-only iteration over a list of types, which otherwise copies
 * every type on every visit. */
bool cpe_borrow_local_copies(MsArena *arena, const MirModule *m, MirFunc *f) {
  CpeLocal l = cpe_local(arena, m, f);
  MirValue *alias = cpe_new_values(arena, f, MIR_NONE);
  CpeDead dead = {0};
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    for (uint32_t i = 0; i < f->blocks.ptr[bi].insts.len; i++) {
      const MirInst *inst = &f->blocks.ptr[bi].insts.ptr[i];
      if (inst->op != MOP_Clone || inst->res == MIR_NONE) {
        continue;
      }
      const MirValue c = inst->res, v = inst->args[0];
      const uint8_t kind = mir_ty_data(m, mir_value_ty(f, v))->kind;
      const bool wanted = kind == MK_FN || kind == MK_STR || kind == MK_TYPE ||
                kind == MK_ALT || kind == MK_OPT || kind == MK_LIST ||
                kind == MK_BYTES;
      uint32_t j = 0;
      if (!wanted || alias[v] != MIR_NONE || !cpe_first_drop(&l, c, bi, i, &j) ||
        !cpe_local_copy_ok(&l, v, c, bi, i, j)) {
        continue;
      }
      alias[c] = v;
      cpe_dead_push(arena, &dead, bi, i);
      cpe_dead_push(arena, &dead, bi, j);
    }
  }
  if (dead.n == 0) {
    return false;
  }
  cpe_remove_insts(arena, f, &dead);
  cpe_apply_rename(f, alias, false);
  return true;
}

static bool *cpe_stable_values(MsArena *arena, const MirFunc *f);

/* The extern `<name>_view` of the copying native `external`, declared when the module has none: same operands, a result
 * that views the first operand. MIR_NONE when the twin is no view. */
static uint32_t cpe_view_twin(MirModule *m, uint32_t external) {
  const MirExtern *copying = &m->externs.ptr[external];
  const MsName name = mir_name_suffixed(m, copying->name, ms_span_of_text("_view"));
  const MirExtern def = {.name = name, .params = copying->params, .nparams = copying->nparams, .ret = copying->ret,
                         .leaf = copying->leaf, .role = (uint8_t)MR_VIEW_RESULT};
  return mir_extern_intern(m, &def);
}

/* Replaces `r = call.rt copy(v)` by `r = call.rt copy_view(v)` when the span only borrows `r` and `v`
 * stays alive, as for a copy of `v` itself: `s.trim().length()` then makes no string. Only a String result, which is
 * immutable, so the view differs from the copy only once the owner of `v` releases or replaces it. */
bool cpe_view_twins(MsArena *arena, MirModule *m, MirFunc *f) {
  CpeLocal l = cpe_local(arena, m, f);
  const bool *stable = cpe_stable_values(arena, f);
  bool changed = false;
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    for (uint32_t i = 0; i < f->blocks.ptr[bi].insts.len; i++) {
      MirInst *inst = &f->blocks.ptr[bi].insts.ptr[i];
      if (inst->op != MOP_CallRt || inst->imm.tag != MI_EXT || inst->res == MIR_NONE || inst->nargs != 1 ||
          m->externs.ptr[inst->imm.a].twin != MTW_VIEW || mir_value_ty(f, inst->res) != MIR_STR ||
          mir_value_ty(f, inst->args[0]) != MIR_STR) {
        continue;
      }
      uint32_t j = 0;
      if (!cpe_first_drop(&l, inst->res, bi, i, &j)) {
        continue;
      }
      /* A borrowed parameter (or a part of one) lives through the whole function, so only the result's own uses count. */
      const MirInst *def = cpe_def_inst(f, l.defs, inst->args[0]);
      /* A string a clone or a runtime call made is an owner of its own: only its release ends it. */
      const bool owned = def != NULL && (def->op == MOP_Clone || (def->op == MOP_CallRt && def->imm.tag == MI_EXT &&
                                                                    m->externs.ptr[def->imm.a].fresh));
      const bool kept = stable[inst->args[0]] || owned
                            ? cpe_uses_between(&l, inst->res, bi, i, j) + 1 == l.uses[inst->res] &&
                                  !cpe_consumes(&l, inst->res, bi, i, j) &&
                                  (stable[inst->args[0]] || !cpe_consumes(&l, inst->args[0], bi, i, j))
                            : cpe_local_copy_ok(&l, inst->args[0], inst->res, bi, i, j);
      if (!kept) {
        continue;
      }
      const uint32_t twin = cpe_view_twin(m, inst->imm.a);
      inst = &f->blocks.ptr[bi].insts.ptr[i];
      inst->imm = mir_imm_ext(twin);
      changed = true; /* the drop stays: a view is an owned value whose release frees nothing */
    }
  }
  return changed;
}

/* ---- a copy of a value that never changes ---- */

/* Values that stay valid and unchanged for the whole function: borrowed parameters and borrowed
 * projections of them. */
static bool *cpe_stable_values(MsArena *arena, const MirFunc *f) {
  bool *stable = cpe_new_flags(arena, f);
  for (uint32_t p = 0; p < f->blocks.ptr[0].params.len; p++) {
    stable[f->blocks.ptr[0].params.ptr[p].value] = f->blocks.ptr[0].params.ptr[p].mode == MM_BORROW;
  }
  MirBlock *order = NULL;
  const uint32_t n = mir_rpo(arena, f, &order);
  /* Definitions precede uses in reverse post-order, so one sweep suffices. */
  for (uint32_t k = 0; k < n; k++) {
    const MirBlockData *b = &f->blocks.ptr[order[k]];
    for (uint32_t i = 0; i < b->insts.len; i++) {
      const MirInst *inst = &b->insts.ptr[i];
      const bool projection = inst->op == MOP_TypeGet || inst->op == MOP_AltGet ||
                  inst->op == MOP_OptGet || inst->op == MOP_ListGet ||
                  inst->op == MOP_ListGetNn || inst->op == MOP_ListGetU;
      if (projection && inst->res != MIR_NONE && stable[inst->args[0]]) {
        stable[inst->res] = true;
      }
    }
  }
  return stable;
}

/* Keeps an alias only while every use of the copy is a read-only operand or one of its drops. */
static void cpe_prune_aliases(MsArena *arena, const MirModule *m, const MirFunc *f,
              MirValue *alias) {
  uint32_t widest = 1;
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      widest = f->blocks.ptr[b].insts.ptr[i].nargs > widest ? f->blocks.ptr[b].insts.ptr[i].nargs : widest;
    }
  }
  MirMode *modes = MS_ARENA_NEW_ARRAY(arena, MirMode, (size_t)widest + 1);
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      const MirInst *inst = &f->blocks.ptr[b].insts.ptr[i];
      mir_arg_modes(m, f, inst, modes);
      for (uint32_t k = 0; k < inst->nargs; k++) {
        if (alias[inst->args[k]] != MIR_NONE && modes[k] != MM_BORROW &&
          inst->op != MOP_Drop) {
          alias[inst->args[k]] = MIR_NONE;
        }
      }
      if (inst->op == MOP_DropIf && inst->nargs > 1) {
        alias[inst->args[1]] = MIR_NONE;
      }
    }
  }
}

static void cpe_clear_term(void *ctx, MirValue v) {
  ((MirValue *)ctx)[v] = MIR_NONE;
}

/* Replaces each copy of a stable value by its source and removes the copies and their drops. */
bool cpe_alias_stable(MsArena *arena, const MirModule *m, MirFunc *f) {
  const bool *stable = cpe_stable_values(arena, f);
  MirValue *alias = cpe_new_values(arena, f, MIR_NONE);
  bool any = false;
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      const MirInst *inst = &f->blocks.ptr[b].insts.ptr[i];
      if (inst->op == MOP_Clone && inst->res != MIR_NONE && stable[inst->args[0]]) {
        alias[inst->res] = inst->args[0];
        any = true;
      }
    }
  }
  if (!any) {
    return false;
  }
  cpe_prune_aliases(arena, m, f, alias);
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    mir_term_each_value(&f->blocks.ptr[b].term, cpe_clear_term, alias);
  }
  bool changed = false;
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    MirBlockData *blk = &f->blocks.ptr[b];
    uint32_t kept = 0;
    for (uint32_t i = 0; i < blk->insts.len; i++) {
      const MirInst *inst = &blk->insts.ptr[i];
      const bool gone = (inst->op == MOP_Clone && inst->res != MIR_NONE &&
               alias[inst->res] != MIR_NONE) ||
               (inst->op == MOP_Drop && alias[inst->args[0]] != MIR_NONE);
      changed |= gone;
      if (!gone) {
        blk->insts.ptr[kept++] = *inst;
      }
    }
    blk->insts.len = kept;
  }
  cpe_apply_rename(f, alias, false);
  return changed;
}
