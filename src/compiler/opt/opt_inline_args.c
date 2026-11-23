/* opt_inline_args.c: see opt_inline_closure.h. */
#include "compiler/opt/opt_inline_closure.h"

/* ---- closure arguments ---- */


static uint32_t ic_made_find(const IcMade *t, uint32_t a, uint32_t b, uint32_t c) {
  for (uint32_t i = 0; i < t->n; i++) {
    if (t->callee[i] == a && t->code[i] == b && t->param[i] == c) {
      return t->copy[i];
    }
  }
  return MIR_NONE;
}

static void ic_made_add(MsArena *arena, IcMade *t, uint32_t a, uint32_t b, uint32_t c, uint32_t copy) {
  if (t->n == t->cap) {
    const uint32_t cap = t->cap == 0 ? 16 : t->cap * 2;
    uint32_t **cols[4] = {&t->callee, &t->code, &t->param, &t->copy};
    for (uint32_t k = 0; k < 4; k++) {
      uint32_t *grown = MS_ARENA_NEW_ARRAY(arena, uint32_t, cap);
      if (t->n > 0) {
        __builtin_memcpy(grown, *cols[k], sizeof(uint32_t) * t->n);
      }
      *cols[k] = grown;
    }
    t->cap = cap;
  }
  t->callee[t->n] = a;
  t->code[t->n] = b;
  t->param[t->n] = c;
  t->copy[t->n++] = copy;
}


static void ic_rename_term(void *ctx, MirValue *v) {
  const IcRename *r = ctx;
  *v = *v == r->from ? r->to : *v;
}

static void ic_rename_uses(MirFunc *f, MirValue from, MirValue to) {
  IcRename r = {from, to};
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      MirInst *in = &f->blocks.ptr[b].insts.ptr[i];
      for (uint32_t a = 0; a < in->nargs; a++) {
        in->args[a] = in->args[a] == from ? to : in->args[a];
      }
    }
    mir_term_each_use(&f->blocks.ptr[b].term, ic_rename_term, &r);
  }
}

/* Replaces parameter `i` of `f` by one parameter per capture of closure code `g`. */
static MirValue *ic_split_param(MirModule *m, MirFunc *f, const MirFunc *g, uint32_t i) {
  const uint32_t nc = g->ncaptures;
  MirParam *params = MS_ARENA_NEW_ARRAY(&m->arena, MirParam, (size_t)f->nparams + nc);
  MirBlockData *entry = &f->blocks.ptr[0];
  MirBlockParam *bparams = MS_ARENA_NEW_ARRAY(&m->arena, MirBlockParam, (size_t)entry->params.len + nc);
  MirValue *caps = MS_ARENA_NEW_ARRAY(&m->arena, MirValue, (size_t)nc + 1);
  for (uint32_t k = 0; k < nc; k++) {
    caps[k] = mir_new_value(f, g->captures[k]);
  }
  uint32_t n = 0;
  for (uint32_t j = 0; j < f->nparams; j++) {
    if (j == i) {
      for (uint32_t k = 0; k < nc; k++) {
        params[n] = (MirParam){g->captures[k], MM_BORROW};
        bparams[n++] = (MirBlockParam){caps[k], MM_BORROW};
      }
      continue;
    }
    params[n] = f->params[j];
    bparams[n++] = entry->params.ptr[j];
  }
  /* Parameters after the split one move by the captures that replace it. */
  uint32_t kept = 0;
  for (uint32_t k = 0; k < f->nnoalias; k++) {
    if (f->noalias[k] != i) {
      f->noalias[kept++] = f->noalias[k] > i ? f->noalias[k] - 1 + nc : f->noalias[k];
    }
  }
  f->nnoalias = kept;
  f->params = params;
  f->nparams = n;
  opt_block_set_params(entry, bparams, n);
  return caps;
}

/* `callee` with parameter `i` (a borrowed closure) replaced by the captures of closure code `g`
 * and a `closure.new` of `g` over them at the top of the entry block, dropped before every `ret`.
 * The copy keeps the callee's name: a fault trace names the function the program wrote. */
static void ic_specialized_callee(MirModule *m, uint32_t callee, uint32_t g, uint32_t i, MirFunc *f) {
  opt_func_deep_clone(m, &m->funcs.ptr[callee], f);
  const MirFunc *code = &m->funcs.ptr[g];
  const MirValue old = f->blocks.ptr[0].params.ptr[i].value;
  const MirTy ty = mir_value_ty(f, old);
  const MirLoc loc = f->loc;
  MirValue *caps = ic_split_param(m, f, code, i);
  const MirValue k = mir_new_value(f, ty);
  ic_rename_uses(f, old, k);
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    if (f->blocks.ptr[b].term.kind == MT_RET) {
      const MirInst drop = opt_inst_make(m, MOP_Drop, &k, 1, (MirImm){0}, MIR_NONE, f->blocks.ptr[b].term_loc);
      mir_block_insert(&f->blocks.ptr[b], (uint32_t)f->blocks.ptr[b].insts.len, &drop);
    }
  }
  const MirInst make = opt_inst_make(m, MOP_ClosureNew, caps, code->ncaptures,
                   (MirImm){.tag = MI_FUNC, .a = g}, k, loc);
  mir_block_insert(&f->blocks.ptr[0], mir_entry_insert_at(f), &make);
}

/* The argument of the call that a specialisation applies to: a known closure passed in a borrowed
 * parameter whose code is small and takes its environment only through `closure.cap`. */
static bool ic_pick_arg(const MirModule *m, const IcKnown *known, const MirInst *call,
            const MirFunc *callee, uint32_t *index) {
  for (uint32_t i = 0; i < call->nargs; i++) {
    if (!ic_known_has(known, call->args[i])) {
      continue;
    }
    const MirFunc *code = &m->funcs.ptr[known->code[call->args[i]]];
    if (callee->params[i].mode == MM_BORROW && code->inline_hint != MINL_NEVER &&
      mir_inst_count(code) <= OPT_INLINE_SPECIALIZE_MAX_SIZE && ic_closure_usable(code)) {
      *index = i;
      return true;
    }
  }
  return false;
}

static bool ic_has_call_ind(const MirFunc *f) {
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      if (f->blocks.ptr[b].insts.ptr[i].op == MOP_CallInd) {
        return true;
      }
    }
  }
  return false;
}


/* Whether the call to `ci` from `fi` is worth a private copy: a plain, acyclic, small callee that
 * calls a closure indirectly. */
static bool ic_specializable(const IcSpecialize *s, uint32_t fi, uint32_t ci) {
  const MirFunc *callee = &s->m->funcs.ptr[ci];
  const bool cyclic = ci < s->ncyc && s->cyc[ci];
  return ci != fi && !cyclic && callee->kind == MFK_NORMAL && callee->inline_hint != MINL_NEVER &&
     mir_inst_count(callee) <= OPT_INLINE_SPECIALIZE_MAX_SIZE && ic_has_call_ind(callee);
}

/* The copy of `c` specialised for closure code `g` in parameter `i`, made on first use; MIR_NONE
 * when the budget is spent. */
static uint32_t ic_specialized(IcSpecialize *s, uint32_t c, uint32_t g, uint32_t i) {
  const uint32_t have = ic_made_find(&s->made, c, g, i);
  if (have != MIR_NONE) {
    return have;
  }
  MirFunc copy;
  ic_specialized_callee(s->m, c, g, i, &copy);
  const uint32_t size = mir_inst_count(&copy);
  if (s->spent + size > OPT_INLINE_SPECIALIZE_BUDGET) {
    return MIR_NONE;
  }
  s->spent += size;
  const uint32_t id = mir_add_func(s->m, &copy);
  ic_made_add(s->arena, &s->made, c, g, i, id);
  return id;
}

/* Calls `spec` instead, passing the captures in place of argument `i`. */
static void ic_redirect(MirModule *m, MirInst *call, uint32_t spec, uint32_t i, const MirValue *caps,
            uint32_t ncaps) {
  MirValue *args = MS_ARENA_NEW_ARRAY(&m->arena, MirValue, (size_t)call->nargs + ncaps);
  __builtin_memcpy(args, call->args, sizeof(MirValue) * i);
  if (ncaps > 0) {
    __builtin_memcpy(args + i, caps, sizeof(MirValue) * ncaps);
  }
  __builtin_memcpy(args + i + ncaps, call->args + i + 1, sizeof(MirValue) * (call->nargs - i - 1));
  call->imm.a = spec;
  call->nargs = call->nargs - 1 + ncaps;
  call->args = args;
}

static bool ic_specialize_in(IcSpecialize *s, uint32_t fi) {
  MirModule *m = s->m;
  MsArena arena = ms_arena_new();
  const IcKnown known = ic_known_aliased(&arena, m, &m->funcs.ptr[fi]);
  bool changed = false;
  for (uint32_t bi = 0; known.count > 0 && bi < m->funcs.ptr[fi].blocks.len; bi++) {
    for (uint32_t ii = 0; ii < m->funcs.ptr[fi].blocks.ptr[bi].insts.len; ii++) {
      const MirInst *inst = &m->funcs.ptr[fi].blocks.ptr[bi].insts.ptr[ii];
      uint32_t i = 0;
      if (inst->op != MOP_Call || inst->imm.tag != MI_FUNC ||
        !ic_specializable(s, fi, inst->imm.a) ||
        !ic_pick_arg(m, &known, inst, &m->funcs.ptr[inst->imm.a], &i)) {
        continue;
      }
      const MirValue arg = inst->args[i];
      const uint32_t spec = ic_specialized(s, inst->imm.a, known.code[arg], i);
      if (spec == MIR_NONE) {
        continue;
      }
      ic_redirect(m, &m->funcs.ptr[fi].blocks.ptr[bi].insts.ptr[ii], spec, i, known.caps[arg], known.ncaps[arg]);
      changed = true;
    }
  }
  if (changed) {
    (void)ic_delete_unused(m, fi);
  }
  ms_arena_free(&arena);
  return changed;
}


/* Gives each call that passes a closure built in the caller (plain-data captures, borrowed
 * parameter) a private copy of the callee in which that parameter is replaced by a `closure.new`
 * of the same code over captures taken as parameters. The closure inliner then resolves the
 * callee's indirect calls and deletes the closure. */
bool opt_inline_specialize_closure_args(MirModule *m) {
  MsArena arena = ms_arena_new();
  IcSpecialize s = {.m = m, .arena = &arena};
  bool changed = false;
  for (uint32_t round = 0; round < IC_SPECIALIZE_ROUNDS; round++) {
    const OptInlineGraph g = opt_inline_direct_graph(&arena, m);
    s.cyc = opt_inline_cyclic(&arena, &g);
    s.ncyc = g.n;
    bool any = false;
    const uint32_t nfuncs = (uint32_t)m->funcs.len;
    for (uint32_t fi = 0; fi < nfuncs; fi++) {
      any |= ic_specialize_in(&s, fi);
    }
    changed |= any;
    if (!any) {
      break;
    }
  }
  ms_arena_free(&arena);
  return changed;
}

/* ---- runtime sort comparators ---- */

/* `thunk` with its closure parameter replaced by the raw environment pointer and the indirect call
 * replaced by a direct call (inlined when small) of closure code `g`; false when `g` is not
 * eligible. */
static bool ic_specialized_thunk(MirModule *m, uint32_t thunk, uint32_t g, MirFunc *t) {
  const MirFunc *code = &m->funcs.ptr[g];
  if (code->kind != MFK_CLOSURE || code->inline_hint == MINL_NEVER) {
    return false;
  }
  opt_func_deep_clone(m, &m->funcs.ptr[thunk], t);
  if (opt_inline_cancel_mismatch(t, code)) {
    return false;
  }
  const MsSpan name = ms_names_span(&m->names, code->name);
  MsStrBuild full = ms_strbuild_new();
  ms_strbuild_append_text(&full, "sort.cmp.");
  ms_strbuild_append(&full, name);
  t->name = mir_name(m, ms_strbuild_span(&full));
  ms_strbuild_free(&full);
  t->sort = MSORT_SPECIALIZED;
  MirParam *params = MS_ARENA_NEW_ARRAY(&m->arena, MirParam, (size_t)t->nparams + 1);
  __builtin_memcpy(params, t->params, sizeof(MirParam) * t->nparams);
  params[0].ty = MIR_PTR;
  t->params = params;
  const MirValue env = t->blocks.ptr[0].params.ptr[0].value;
  t->values.ptr[env] = MIR_PTR;
  for (uint32_t bi = 0; bi < t->blocks.len; bi++) {
    for (uint32_t ii = 0; ii < t->blocks.ptr[bi].insts.len; ii++) {
      MirInst *call = &t->blocks.ptr[bi].insts.ptr[ii];
      if (call->op != MOP_CallInd || call->args[0] != env) {
        continue;
      }
      call->op = MOP_Call;
      call->imm = (MirImm){.tag = MI_FUNC, .a = g};
      /* A `closure.cap` reads the environment through the function's own capture layout,
       * which the thunk does not have: code that captures is called, not inlined. */
      if (mir_inst_count(code) <= OPT_INLINE_BASE_THRESHOLD && code->ncaptures == 0) {
        (void)opt_inline_at(m, t, bi, ii, code, mir_needs_drop(m, code->ret));
      }
      return true;
    }
  }
  return false;
}


/* The `func.addr` of a generic sort thunk and the `closure.new` code, by value, of one function. */
static bool ic_sort_scan(MsArena *arena, const MirModule *m, const MirFunc *f, uint32_t **thunks,
            uint32_t **codes) {
  *thunks = MS_ARENA_NEW_ARRAY(arena, uint32_t, f->values.len);
  *codes = MS_ARENA_NEW_ARRAY(arena, uint32_t, f->values.len);
  __builtin_memset(*thunks, 0xff, sizeof(uint32_t) * f->values.len);
  __builtin_memset(*codes, 0xff, sizeof(uint32_t) * f->values.len);
  bool any_thunk = false, any_code = false;
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      const MirInst *in = &f->blocks.ptr[b].insts.ptr[i];
      if (in->res == MIR_NONE || in->imm.tag != MI_FUNC) {
        continue;
      }
      if (in->op == MOP_ClosureNew) {
        (*codes)[in->res] = in->imm.a;
        any_code = true;
      } else if (in->op == MOP_FuncAddr && m->funcs.ptr[in->imm.a].sort == MSORT_GENERIC) {
        (*thunks)[in->res] = in->imm.a;
        any_thunk = true;
      }
    }
  }
  return any_thunk && any_code;
}

static uint32_t ic_sort_edits(MsArena *arena, const MirFunc *f, const uint32_t *thunks,
               const uint32_t *codes, IcSortEdit **out) {
  uint32_t n = 0, bound = 0;
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      bound += f->blocks.ptr[b].insts.ptr[i].nargs;
    }
  }
  *out = MS_ARENA_NEW_ARRAY(arena, IcSortEdit, (size_t)bound + 1);
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      const MirInst *in = &f->blocks.ptr[b].insts.ptr[i];
      for (uint32_t w = 0; in->op == MOP_CallRt && w + 1 < in->nargs; w++) {
        if (thunks[in->args[w]] != MIR_NONE && codes[in->args[w + 1]] != MIR_NONE) {
          (*out)[n++] = (IcSortEdit){in->args[w], thunks[in->args[w]], codes[in->args[w + 1]]};
        }
      }
    }
  }
  return n;
}

/* Points every `func.addr` defining `addr` at `spec`; whether any did. */
static bool ic_sort_retarget(MirFunc *f, MirValue addr, uint32_t spec) {
  bool changed = false;
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      MirInst *in = &f->blocks.ptr[b].insts.ptr[i];
      if (in->res == addr) {
        in->imm.a = spec;
        changed = true;
      }
    }
  }
  return changed;
}

/* Gives each runtime sort whose comparator is a known closure a private copy of the generic
 * `sort.cmp` thunk that calls the closure's code directly (and inlines it). The runtime then makes
 * one indirect call per comparison instead of three. */
bool opt_inline_specialize_sort_thunks(MirModule *m) {
  MsArena arena = ms_arena_new();
  IcMade made = {0};
  bool changed = false;
  const uint32_t nfuncs = (uint32_t)m->funcs.len;
  for (uint32_t fi = 0; fi < nfuncs; fi++) {
    uint32_t *thunks = NULL, *codes = NULL;
    if (!ic_sort_scan(&arena, m, &m->funcs.ptr[fi], &thunks, &codes)) {
      continue;
    }
    IcSortEdit *edits = NULL;
    const uint32_t n = ic_sort_edits(&arena, &m->funcs.ptr[fi], thunks, codes, &edits);
    for (uint32_t e = 0; e < n; e++) {
      uint32_t spec = ic_made_find(&made, edits[e].thunk, edits[e].code, 0);
      MirFunc thunk;
      if (spec == MIR_NONE && !ic_specialized_thunk(m, edits[e].thunk, edits[e].code, &thunk)) {
        continue;
      }
      if (spec == MIR_NONE) {
        spec = mir_add_func(m, &thunk);
        ic_made_add(&arena, &made, edits[e].thunk, edits[e].code, 0, spec);
      }
      changed |= ic_sort_retarget(&m->funcs.ptr[fi], edits[e].addr, spec);
    }
  }
  ms_arena_free(&arena);
  return changed;
}
