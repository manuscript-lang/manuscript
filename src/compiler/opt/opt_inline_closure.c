/* The closure half of the `inline` pass: a `call.ind` of a closure built in the same function
 * becomes a direct call and is inlined; a call that passes such a closure to a callee that calls
 * it gets a private specialised copy of the callee; a runtime sort whose comparator is a known
 * closure gets a copy of the generic comparison thunk that calls the closure's code directly. */

#include "compiler/opt/opt_inline_closure.h"

/* ---- the closures a function builds ---- */


static IcKnown ic_known_new(MsArena *arena, uint32_t nvalues) {
  IcKnown k = {.n = nvalues};
  k.code = MS_ARENA_NEW_ARRAY(arena, uint32_t, nvalues);
  __builtin_memset(k.code, 0xff, sizeof(uint32_t) * nvalues);
  k.caps = MS_ARENA_NEW_ARRAY(arena, const MirValue *, nvalues);
  k.ncaps = MS_ARENA_NEW_ARRAY(arena, uint32_t, nvalues);
  return k;
}

bool ic_known_has(const IcKnown *k, MirValue v) {
  return v < k->n && k->code[v] != MIR_NONE;
}

static void ic_known_set(IcKnown *k, MirValue v, uint32_t code, const MirValue *caps, uint32_t n) {
  k->count += k->code[v] == MIR_NONE ? 1u : 0u;
  k->code[v] = code;
  k->caps[v] = caps;
  k->ncaps[v] = n;
}

/* The closures built in `f` by `closure.new` whose captures are all plain data. */
IcKnown ic_known_closures(MsArena *arena, const MirModule *m, const MirFunc *f) {
  IcKnown known = ic_known_new(arena, (uint32_t)f->values.len);
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      const MirInst *in = &f->blocks.ptr[b].insts.ptr[i];
      if (in->op != MOP_ClosureNew || in->imm.tag != MI_FUNC || in->res == MIR_NONE ||
        m->funcs.ptr[in->imm.a].ncapture_closers != 0) {
        continue;
      }
      bool plain = true;
      for (uint32_t a = 0; a < in->nargs; a++) {
        plain = plain && !mir_needs_drop(m, mir_value_ty(f, in->args[a]));
      }
      if (plain) {
        ic_known_set(&known, in->res, in->imm.a, in->args, in->nargs);
      }
    }
  }
  return known;
}


static IcIncoming ic_incoming(MsArena *arena, const MirFunc *f) {
  IcIncoming in = {0};
  in.base = MS_ARENA_NEW_ARRAY(arena, uint32_t, (size_t)f->blocks.len + 1);
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    in.base[b + 1] = (uint32_t)(in.base[b] + f->blocks.ptr[b].params.len);
  }
  const uint32_t rows = in.base[f->blocks.len];
  in.off = MS_ARENA_NEW_ARRAY(arena, uint32_t, (size_t)rows + 2);
  for (uint32_t pass = 0; pass < 2; pass++) {
    uint32_t *cursor = MS_ARENA_NEW_ARRAY(arena, uint32_t, (size_t)rows + 1);
    for (uint32_t b = 0; b < f->blocks.len; b++) {
      for (uint32_t k = 0; k < mir_term_ntargets(&f->blocks.ptr[b].term); k++) {
        const MirTarget *t = mir_term_target_const(&f->blocks.ptr[b].term, k);
        for (uint32_t j = 0; j < t->nargs; j++) {
          const uint32_t row = in.base[t->block] + j;
          if (pass == 0) {
            in.off[row + 1]++;
          } else {
            in.args[in.off[row] + cursor[row]++] = t->args[j];
          }
        }
      }
    }
    if (pass == 0) {
      for (uint32_t r = 0; r < rows; r++) {
        in.off[r + 1] += in.off[r];
      }
      in.args = MS_ARENA_NEW_ARRAY(arena, MirValue, in.off[rows]);
    }
  }
  return in;
}

/* Whether every incoming argument of parameter `p` is `p` itself or an alias of one root; the
 * root is stored in `*root` (MIR_NONE when no argument names one). */
static bool ic_param_class(const IcIncoming *in, uint32_t row, MirValue p, const MirValue *alias,
             uint32_t *root) {
  if (in->off[row] == in->off[row + 1]) {
    return false;
  }
  *root = MIR_NONE;
  for (uint32_t a = in->off[row]; a < in->off[row + 1]; a++) {
    const MirValue v = in->args[a];
    if (v == p) {
      continue;
    }
    if (alias[v] == MIR_NONE || (*root != MIR_NONE && *root != alias[v])) {
      return false;
    }
    *root = alias[v];
  }
  return *root != MIR_NONE;
}

/* One sweep over the copies and block parameters; whether an alias was added. */
static bool ic_alias_sweep(const MirFunc *f, const IcIncoming *in, MirValue *alias) {
  bool grew = false;
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      const MirInst *inst = &f->blocks.ptr[b].insts.ptr[i];
      if (inst->op == MOP_Clone && inst->res != MIR_NONE && alias[inst->res] == MIR_NONE &&
        alias[inst->args[0]] != MIR_NONE) {
        alias[inst->res] = alias[inst->args[0]];
        grew = true;
      }
    }
  }
  for (uint32_t b = 1; b < f->blocks.len; b++) {
    for (uint32_t j = 0; j < f->blocks.ptr[b].params.len; j++) {
      const MirValue p = f->blocks.ptr[b].params.ptr[j].value;
      uint32_t root = MIR_NONE;
      if (alias[p] == MIR_NONE && ic_param_class(in, in->base[b] + j, p, alias, &root)) {
        alias[p] = root;
        grew = true;
      }
    }
  }
  return grew;
}

/* Maps every value that always holds the same known closure to that closure's `closure.new`
 * result: the result itself, `copy` of such a value, and a block parameter each of whose incoming
 * arguments is such a value (or the parameter itself, on a loop back edge). */
static MirValue *ic_aliases(MsArena *arena, const MirFunc *f, const IcKnown *roots) {
  MirValue *alias = MS_ARENA_NEW_ARRAY(arena, MirValue, f->values.len);
  __builtin_memset(alias, 0xff, sizeof(MirValue) * f->values.len);
  for (uint32_t v = 0; v < f->values.len; v++) {
    alias[v] = ic_known_has(roots, v) ? v : MIR_NONE;
  }
  const IcIncoming in = ic_incoming(arena, f);
  while (ic_alias_sweep(f, &in, alias)) {
  }
  return alias;
}

/* ---- deleting closures nothing calls ---- */


static void ic_note(const IcDelete *d, MirValue v) {
  if (d->alias[v] != MIR_NONE) {
    d->live[d->alias[v]] = true;
  }
}

static bool ic_dead(const IcDelete *d, MirValue v) {
  return d->alias[v] != MIR_NONE && !d->live[d->alias[v]];
}

static void ic_note_block(const IcDelete *d, const MirFunc *f, const MirBlockData *b) {
  for (uint32_t i = 0; i < b->insts.len; i++) {
    const MirInst *in = &b->insts.ptr[i];
    const bool class_only = in->op == MOP_Drop || (in->op == MOP_Clone && in->res != MIR_NONE &&
                           d->alias[in->res] != MIR_NONE);
    for (uint32_t a = 0; a < in->nargs && !class_only; a++) {
      ic_note(d, in->args[a]);
    }
  }
  if (b->term.kind == MT_CONDBR || b->term.kind == MT_SWITCH ||
    (b->term.kind == MT_RET && b->term.value != MIR_NONE)) {
    ic_note(d, b->term.value);
  }
  /* An argument into a block parameter outside the class keeps the closure alive. */
  for (uint32_t k = 0; k < mir_term_ntargets(&b->term); k++) {
    const MirTarget *t = mir_term_target_const(&b->term, k);
    for (uint32_t j = 0; j < t->nargs; j++) {
      if (d->alias[f->blocks.ptr[t->block].params.ptr[j].value] == MIR_NONE) {
        ic_note(d, t->args[j]);
      }
    }
  }
}

static bool ic_sweep_insts(const IcDelete *d, MirBlockData *b) {
  uint32_t kept = 0;
  for (uint32_t i = 0; i < b->insts.len; i++) {
    const MirInst *in = &b->insts.ptr[i];
    const bool gone = ((in->op == MOP_ClosureNew || in->op == MOP_Clone) && in->res != MIR_NONE &&
             ic_dead(d, in->res)) ||
             (in->op == MOP_Drop && ic_dead(d, in->args[0]));
    if (!gone) {
      b->insts.ptr[kept++] = *in;
    }
  }
  const bool changed = kept != b->insts.len;
  b->insts.len = kept;
  return changed;
}

static void ic_sweep_target(MirModule *m, const IcDelete *d, MirTarget *t) {
  uint32_t kept = 0;
  MirValue *args = NULL;
  for (uint32_t j = 0; j < t->nargs; j++) {
    if (d->dead_param[d->base[t->block] + j]) {
      continue;
    }
    if (args == NULL) {
      args = MS_ARENA_NEW_ARRAY(&m->arena, MirValue, (size_t)t->nargs + 1);
    }
    args[kept++] = t->args[j];
  }
  if (kept != t->nargs) {
    t->args = args != NULL ? args : MS_ARENA_NEW_ARRAY(&m->arena, MirValue, 1);
    t->nargs = kept;
  }
}

static void ic_sweep_params(const IcDelete *d, MirBlockData *b, uint32_t bi) {
  uint32_t kept = 0;
  for (uint32_t j = 0; j < b->params.len; j++) {
    if (!d->dead_param[d->base[bi] + j]) {
      b->params.ptr[kept++] = b->params.ptr[j];
    }
  }
  b->params.len = kept;
}

static bool ic_delete_dead(MirModule *m, MirFunc *f, IcDelete *d) {
  bool changed = false;
  for (uint32_t b = 1; b < f->blocks.len; b++) {
    for (uint32_t j = 0; j < f->blocks.ptr[b].params.len; j++) {
      const bool dead = ic_dead(d, f->blocks.ptr[b].params.ptr[j].value);
      d->dead_param[d->base[b] + j] = dead;
      changed |= dead;
    }
  }
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    changed |= ic_sweep_insts(d, &f->blocks.ptr[b]);
    for (uint32_t k = 0; k < mir_term_ntargets(&f->blocks.ptr[b].term); k++) {
      ic_sweep_target(m, d, mir_term_target(&f->blocks.ptr[b].term, k));
    }
  }
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    ic_sweep_params(d, &f->blocks.ptr[b], b);
  }
  return changed;
}

/* Deletes each known closure whose aliases are only copied, dropped and carried through block
 * parameters, together with those copies, drops and parameters (and the arguments feeding them). A
 * plain-data environment owns nothing, so ownership stays linear. Returns whether anything was
 * deleted. */
bool ic_delete_unused(MirModule *m, uint32_t fi) {
  MsArena arena = ms_arena_new();
  MirFunc *f = &m->funcs.ptr[fi];
  const IcKnown roots = ic_known_closures(&arena, m, f);
  if (roots.count == 0) {
    ms_arena_free(&arena);
    return false;
  }
  const IcIncoming in = ic_incoming(&arena, f);
  IcDelete d = {.alias = ic_aliases(&arena, f, &roots), .base = in.base};
  d.live = MS_ARENA_NEW_ARRAY(&arena, bool, f->values.len);
  d.dead_param = MS_ARENA_NEW_ARRAY(&arena, bool, in.base[f->blocks.len]);
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    ic_note_block(&d, f, &f->blocks.ptr[b]);
  }
  const bool changed = ic_delete_dead(m, f, &d);
  ms_arena_free(&arena);
  return changed;
}

/* ---- closure code as a plain function ---- */


static void ic_env_term(void *ctx, MirValue v) {
  IcEnvUse *u = ctx;
  u->used = u->used || v == u->env;
}

/* Whether the closure's environment is used in any way besides `closure.cap`. */
static bool ic_env_escapes(const MirFunc *f, MirValue env) {
  IcEnvUse u = {.env = env};
  for (uint32_t b = 0; b < f->blocks.len && !u.used; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      const MirInst *in = &f->blocks.ptr[b].insts.ptr[i];
      const bool cap = in->op == MOP_ClosureCap && in->imm.tag == MI_IDX && in->res != MIR_NONE;
      for (uint32_t a = 0; a < in->nargs && !cap; a++) {
        u.used = u.used || in->args[a] == env;
      }
    }
    mir_term_each_value(&f->blocks.ptr[b].term, ic_env_term, &u);
  }
  return u.used;
}

bool ic_closure_usable(const MirFunc *f) {
  return f->kind == MFK_CLOSURE && f->blocks.len > 0 && !ic_env_escapes(f, f->blocks.ptr[0].params.ptr[0].value);
}

static MirValue ic_sub(const MirValue *sub, MirValue v) {
  return sub[v] == MIR_NONE ? v : sub[v];
}

static void ic_subst_term(void *ctx, MirValue *v) {
  *v = ic_sub(ctx, *v);
}

/* A copy of closure code `f` as a plain function taking the captures before the arguments, or
 * false when the environment is used in any way besides `closure.cap`. */
static bool ic_closure_body(MirModule *m, const MirFunc *f, MirFunc *out) {
  if (!ic_closure_usable(f)) {
    return false;
  }
  opt_func_deep_clone(m, f, out);
  MsArena arena = ms_arena_new();
  MirValue *sub = MS_ARENA_NEW_ARRAY(&arena, MirValue, f->values.len);
  __builtin_memset(sub, 0xff, sizeof(MirValue) * f->values.len);
  MirValue *cap = MS_ARENA_NEW_ARRAY(&arena, MirValue, (size_t)f->ncaptures + 1);
  for (uint32_t k = 0; k < f->ncaptures; k++) {
    cap[k] = mir_new_value(out, f->captures[k]);
  }
  for (uint32_t b = 0; b < out->blocks.len; b++) {
    MirBlockData *blk = &out->blocks.ptr[b];
    uint32_t kept = 0;
    for (uint32_t i = 0; i < blk->insts.len; i++) {
      const MirInst *in = &blk->insts.ptr[i];
      if (in->op == MOP_ClosureCap && in->imm.tag == MI_IDX && in->res != MIR_NONE) {
        sub[in->res] = cap[in->imm.a];
      } else {
        blk->insts.ptr[kept++] = *in;
      }
    }
    blk->insts.len = kept;
  }
  for (uint32_t b = 0; b < out->blocks.len; b++) {
    for (uint32_t i = 0; i < out->blocks.ptr[b].insts.len; i++) {
      MirInst *in = &out->blocks.ptr[b].insts.ptr[i];
      for (uint32_t a = 0; a < in->nargs; a++) {
        in->args[a] = ic_sub(sub, in->args[a]);
      }
    }
    mir_term_each_use(&out->blocks.ptr[b].term, ic_subst_term, sub);
  }
  MirBlockData *entry = &out->blocks.ptr[0];
  MirBlockParam *params = MS_ARENA_NEW_ARRAY(&m->arena, MirBlockParam, (size_t)entry->params.len + f->ncaptures);
  for (uint32_t k = 0; k < f->ncaptures; k++) {
    params[k] = (MirBlockParam){cap[k], MM_BORROW};
  }
  for (uint32_t j = 1; j < entry->params.len; j++) {
    params[f->ncaptures + j - 1] = entry->params.ptr[j];
  }
  opt_block_set_params(entry, params, (uint32_t)(entry->params.len - 1 + f->ncaptures));
  ms_arena_free(&arena);
  return true;
}

/* ---- constant closure fields ---- */


static uint32_t ic_field_slot(const IcFields *t, uint32_t type, uint32_t field) {
  uint32_t h = (type * 0x9e3779b1u) ^ (field * 0x85ebca6bu);
  h ^= h >> 15;
  uint32_t s = h & t->mask;
  while (t->used[s] && (t->type[s] != type || t->field[s] != field)) {
    s = (s + 1) & t->mask;
  }
  return s;
}

static IcFields ic_fields_new(MsArena *arena, uint32_t bound) {
  uint32_t cap = 16;
  while (cap < bound * 2) {
    cap *= 2;
  }
  IcFields t = {.mask = cap - 1};
  t.used = MS_ARENA_NEW_ARRAY(arena, bool, cap);
  t.type = MS_ARENA_NEW_ARRAY(arena, uint32_t, cap);
  t.field = MS_ARENA_NEW_ARRAY(arena, uint32_t, cap);
  t.code = MS_ARENA_NEW_ARRAY(arena, uint32_t, cap);
  return t;
}

/* `code` is the new fact about the field; `overwrite` replaces what is known (a write). */
static void ic_fields_note(IcFields *t, uint32_t type, uint32_t field, uint32_t code, bool overwrite) {
  const uint32_t s = ic_field_slot(t, type, field);
  if (!t->used[s]) {
    t->used[s] = true;
    t->type[s] = type;
    t->field[s] = field;
    t->code[s] = code;
  } else if (overwrite || t->code[s] != code) {
    t->code[s] = MIR_NONE;
  }
}

static uint32_t ic_fields_bound(const MirModule *m) {
  uint32_t n = 0;
  for (uint32_t fi = 0; fi < m->funcs.len; fi++) {
    for (uint32_t b = 0; b < m->funcs.ptr[fi].blocks.len; b++) {
      for (uint32_t i = 0; i < m->funcs.ptr[fi].blocks.ptr[b].insts.len; i++) {
        n += m->funcs.ptr[fi].blocks.ptr[b].insts.ptr[i].nargs + 1;
      }
    }
  }
  return n;
}

/* The closure code `v` always is: through copies to a `closure.new` with no captures. */
static uint32_t ic_capture_free_code(const MirInst *const *defs, MirValue v) {
  while (defs[v] != NULL && defs[v]->op == MOP_Clone) {
    v = defs[v]->args[0];
  }
  const MirInst *d = defs[v];
  if (d != NULL && d->op == MOP_ClosureNew && d->imm.tag == MI_FUNC && d->nargs == 0) {
    return d->imm.a;
  }
  return MIR_NONE;
}

static void ic_fields_scan(IcFields *t, MsArena *arena, const MirModule *m, const MirFunc *f) {
  const MirInst **defs = MS_ARENA_NEW_ARRAY(arena, const MirInst *, f->values.len);
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      const MirInst *in = &f->blocks.ptr[b].insts.ptr[i];
      if (in->res != MIR_NONE) {
        defs[in->res] = in;
      }
    }
  }
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      const MirInst *in = &f->blocks.ptr[b].insts.ptr[i];
      if ((in->op == MOP_TypeSet || in->op == MOP_TypeFill || in->op == MOP_PtrField) &&
        in->imm.tag == MI_FIELD) {
        ic_fields_note(t, in->imm.a, in->imm.b, MIR_NONE, true);
      }
      if (in->op != MOP_TypeNew || in->imm.tag != MI_TYPE) {
        continue;
      }
      for (uint32_t k = 0; k < in->nargs; k++) {
        if (mir_ty_data(m, mir_value_ty(f, in->args[k]))->kind == MK_FN) {
          ic_fields_note(t, in->imm.a, k, ic_capture_free_code(defs, in->args[k]), false);
        }
      }
    }
  }
}

/* ---- inlining the known calls ---- */


static void ic_work_push(IcInline *w, uint32_t bi) {
  if (w->nwork == w->cwork) {
    const uint32_t cap = w->cwork == 0 ? 16 : w->cwork * 2;
    uint32_t *grown = MS_ARENA_NEW_ARRAY(&w->m->arena, uint32_t, cap);
    if (w->nwork > 0) {
      __builtin_memcpy(grown, w->work, sizeof(uint32_t) * w->nwork);
    }
    w->work = grown;
    w->cwork = cap;
  }
  w->work[w->nwork++] = bi;
}

/* The closures of `f` as `known` sees them: every alias of a root, and every read of a constant
 * closure field. */
IcKnown ic_known_aliased(MsArena *arena, const MirModule *m, const MirFunc *f) {
  const IcKnown roots = ic_known_closures(arena, m, f);
  IcKnown known = ic_known_new(arena, (uint32_t)f->values.len);
  const MirValue *alias = ic_aliases(arena, f, &roots);
  for (uint32_t v = 0; v < f->values.len; v++) {
    if (alias[v] != MIR_NONE) {
      ic_known_set(&known, v, roots.code[alias[v]], roots.caps[alias[v]], roots.ncaps[alias[v]]);
    }
  }
  return known;
}

static IcKnown ic_known_with_fields(MsArena *arena, const MirModule *m, const MirFunc *f,
                  const IcFields *fields) {
  IcKnown known = ic_known_aliased(arena, m, f);
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      const MirInst *in = &f->blocks.ptr[b].insts.ptr[i];
      if (in->op != MOP_TypeGet || in->imm.tag != MI_FIELD || in->res == MIR_NONE) {
        continue;
      }
      const uint32_t s = ic_field_slot(fields, in->imm.a, in->imm.b);
      if (fields->used[s] && fields->code[s] != MIR_NONE) {
        ic_known_set(&known, in->res, fields->code[s], NULL, 0);
      }
    }
  }
  return known;
}

/* Makes the `call.ind` at (`bi`, `ii`) a direct call of `g` over `caps` and inlines it; false when
 * the callee is not eligible. */
static bool ic_inline_call(IcInline *w, const IcKnown *known, uint32_t bi, uint32_t ii) {
  MirModule *m = w->m;
  MirFunc *f = &m->funcs.ptr[w->fi];
  MirInst *call = &f->blocks.ptr[bi].insts.ptr[ii];
  const MirValue callee_value = call->args[0];
  if (!ic_known_has(known, callee_value)) {
    return false;
  }
  const uint32_t gi = known->code[callee_value];
  const MirFunc *callee = &m->funcs.ptr[gi];
  const uint32_t size = mir_inst_count(callee);
  /* A closure too big to inline here still becomes a direct call of a plain copy of its code, which the backend
   * can inline: an indirect call hides it from every optimiser. */
  const bool big = size > OPT_INLINE_BASE_THRESHOLD;
  if (gi == w->fi || callee->inline_hint == MINL_NEVER || size > OPT_INLINE_SPECIALIZE_MAX_SIZE ||
    opt_inline_cancel_mismatch(f, callee) || w->grown + size > w->budget) {
    return false;
  }
  MirFunc body;
  if (!ic_closure_body(m, callee, &body)) {
    return false;
  }
  w->grown += size;
  const uint32_t ncaps = known->ncaps[callee_value];
  MirValue *args = MS_ARENA_NEW_ARRAY(&m->arena, MirValue, (size_t)ncaps + call->nargs);
  if (ncaps > 0) {
    __builtin_memcpy(args, known->caps[callee_value], sizeof(MirValue) * ncaps);
  }
  __builtin_memcpy(args + ncaps, call->args + 1, sizeof(MirValue) * (call->nargs - 1));
  call->op = MOP_Call;
  call->imm = (MirImm){.tag = MI_FUNC, .a = gi};
  call->args = args;
  call->nargs = ncaps + call->nargs - 1;
  if (big) {
    body.kind = MFK_NORMAL;
    const uint32_t plain = mir_add_func(m, &body);
    m->funcs.ptr[w->fi].blocks.ptr[bi].insts.ptr[ii].imm.a = plain;
    return true;
  }
  const bool ret_own = mir_needs_drop(m, body.ret);
  ic_work_push(w, opt_inline_at(m, f, bi, ii, &body, ret_own));
  return true;
}

static bool ic_inline_block(IcInline *w, const IcKnown *known, uint32_t bi) {
  const MirFunc *f = &w->m->funcs.ptr[w->fi];
  for (uint32_t ii = 0; ii < f->blocks.ptr[bi].insts.len; ii++) {
    if (f->blocks.ptr[bi].insts.ptr[ii].op == MOP_CallInd && ic_inline_call(w, known, bi, ii)) {
      return true;
    }
  }
  return false;
}

static bool ic_inline_closures_in(MirModule *m, uint32_t fi, const IcFields *fields) {
  MsArena arena = ms_arena_new();
  IcInline w = {.m = m, .fi = fi, .fields = fields};
  w.budget = mir_inst_count(&m->funcs.ptr[fi]) * OPT_INLINE_GROWTH_FACTOR + OPT_INLINE_GROWTH_SLACK;
  for (uint32_t b = 0; b < m->funcs.ptr[fi].blocks.len; b++) {
    ic_work_push(&w, b);
  }
  const IcKnown known = ic_known_with_fields(&arena, m, &m->funcs.ptr[fi], fields);
  bool changed = false;
  if (known.count > 0) {
    while (w.nwork > 0) {
      changed |= ic_inline_block(&w, &known, w.work[--w.nwork]);
    }
    changed |= ic_delete_unused(m, fi);
  }
  ms_arena_free(&arena);
  return changed;
}

bool opt_inline_closures(MirModule *m) {
  MsArena arena = ms_arena_new();
  IcFields fields = ic_fields_new(&arena, ic_fields_bound(m));
  for (uint32_t fi = 0; fi < m->funcs.len; fi++) {
    ic_fields_scan(&fields, &arena, m, &m->funcs.ptr[fi]);
  }
  bool changed = false;
  for (uint32_t fi = 0; fi < m->funcs.len; fi++) {
    changed |= ic_inline_closures_in(m, fi, &fields);
  }
  ms_arena_free(&arena);
  return changed;
}
