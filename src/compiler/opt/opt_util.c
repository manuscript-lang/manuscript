/* Helpers shared by the optimiser's passes. */
#include <stdatomic.h>

#include "base/fatal.h"
#include "base/parallel.h"
#include "compiler/opt/opt_util.h"

/* Removes the instructions flagged in `dead[block][index]` from every block. */
void opt_sweep_dead(MirFunc *f, bool *const *dead, MsArena *arena) {
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    MirBlockData *b = &f->blocks.ptr[bi];
    uint32_t *list = MS_ARENA_NEW_ARRAY(arena, uint32_t, (size_t)b->insts.len + 1);
    uint32_t n = 0;
    for (uint32_t ii = 0; ii < b->insts.len; ii++) {
      if (dead[bi][ii]) {
        list[n++] = ii;
      }
    }
    if (n > 0) {
      mir_block_remove(b, list, n);
    }
  }
}

/* One cleared flag per instruction of each block, for opt_sweep_dead. */
bool **opt_dead_flags(MsArena *arena, const MirFunc *f) {
  bool **dead = MS_ARENA_NEW_ARRAY(arena, bool *, (size_t)f->blocks.len + 1);
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    dead[bi] = MS_ARENA_NEW_ARRAY(arena, bool, f->blocks.ptr[bi].insts.len);
  }
  return dead;
}

OptSubst opt_subst_new(MsArena *arena, uint32_t nvalues) {
  OptSubst s = {MS_ARENA_NEW_ARRAY_UNINIT(arena, MirValue, nvalues), nvalues, 0}; /* set below */
  for (uint32_t v = 0; v < nvalues; v++) {
    s.to[v] = MIR_NONE;
  }
  return s;
}

void opt_subst_set(OptSubst *s, MirValue from, MirValue to) {
  if (s->to[from] == MIR_NONE) {
    s->count++;
  }
  s->to[from] = to;
}

static void apply_use(void *ctx, MirValue *v) {
  *v = opt_subst_resolve(ctx, *v);
}

void opt_subst_apply(MirFunc *f, OptSubst *s) {
  if (s->count == 0) {
    return;
  }
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    MirBlockData *b = &f->blocks.ptr[bi];
    for (uint32_t ii = 0; ii < b->insts.len; ii++) {
      for (uint32_t k = 0; k < b->insts.ptr[ii].nargs; k++) {
        b->insts.ptr[ii].args[k] = opt_subst_resolve(s, b->insts.ptr[ii].args[k]);
      }
    }
    mir_term_each_use(&b->term, apply_use, s);
  }
  /* A debugger name follows its value to what replaced it. */
  for (uint32_t k = 0; k < f->names.len; k++) {
    f->names.ptr[k].value = opt_subst_resolve(s, f->names.ptr[k].value);
  }
}

void opt_inst_vec_push(MsArena *arena, OptInstVec *vec, const MirInst *inst) {
  if (vec->n == vec->cap) {
    const uint32_t cap = vec->cap ? vec->cap * 2 : 8;
    MirInst *grown = MS_ARENA_NEW_ARRAY_UNINIT(arena, MirInst, cap); /* [0, n) is copied, the rest written by push */
    if (vec->n > 0) {
      __builtin_memcpy(grown, vec->v, sizeof(MirInst) * vec->n);
    }
    vec->v = grown;
    vec->cap = cap;
  }
  vec->v[vec->n++] = *inst;
}

void opt_block_set_insts(MirBlockData *b, const MirInst *src, uint32_t n) {
  MirInstList list = {0};
  mir_inst_list_reserve(&list, n);
  for (uint32_t i = 0; i < n; i++) {
    mir_inst_list_push(&list, src[i]);
  }
  mir_block_set_insts(b, &list);
}

void opt_block_set_params(MirBlockData *b, const MirBlockParam *src, uint32_t n) {
  MirBlockParamList list = {0};
  mir_block_param_list_reserve(&list, n);
  for (uint32_t i = 0; i < n; i++) {
    mir_block_param_list_push(&list, src[i]);
  }
  mir_block_param_list_free(&b->params);
  b->params = list;
}

void opt_block_append(MirBlockData *b, const MirInst *src, uint32_t n) {
  for (uint32_t i = 0; i < n; i++) {
    mir_inst_list_push(&b->insts, src[i]);
  }
}

bool opt_imm_eq(const MirImm *a, const MirImm *b) {
  return a->tag == b->tag && a->a == b->a && a->b == b->b && a->c == b->c && a->i == b->i;
}

bool opt_op_commutative(uint8_t op, const MirImm *imm) {
  switch ((MirOp)op) {
  case MOP_IAdd: case MOP_IMul: case MOP_IAddChk: case MOP_IMulChk: case MOP_IAddOverflow:
  case MOP_IMulOverflow: case MOP_And: case MOP_Or: case MOP_Xor:
    return true;
  case MOP_ICmp:
    return imm->tag == MI_CC && (imm->a == MCC_EQ || imm->a == MCC_NE);
  default:
    return false;
  }
}

MirTarget opt_target_clone(MirModule *m, const MirTarget *t) {
  MirTarget c = *t;
  c.args = MS_ARENA_NEW_ARRAY(&m->arena, MirValue, t->nargs + 1);
  if (t->nargs > 0) {
    __builtin_memcpy(c.args, t->args, sizeof(MirValue) * t->nargs);
  }
  return c;
}

bool opt_target_eq(const MirTarget *a, const MirTarget *b) {
  return a->block == b->block && a->nargs == b->nargs &&
         (a->nargs == 0 || __builtin_memcmp(a->args, b->args, sizeof(MirValue) * a->nargs) == 0);
}

void opt_term_set_br(MirTerm *t, MirTarget target) {
  *t = (MirTerm){0};
  t->kind = MT_BR;
  t->value = MIR_NONE;
  t->a = target;
}

MirInst opt_inst_make(MirModule *m, MirOp op, const MirValue *args, uint32_t nargs, MirImm imm, MirValue res,
                      MirLoc loc) {
  MirInst inst = {.op = (uint8_t)op, .imm = imm, .res = res, .loc = loc, .nargs = nargs};
  inst.args = MS_ARENA_NEW_ARRAY(&m->arena, MirValue, nargs + 1);
  if (nargs > 0) {
    __builtin_memcpy(inst.args, args, sizeof(MirValue) * nargs);
  }
  return inst;
}

static void clone_args(MirModule *m, MirValue **args, uint32_t n) {
  MirValue *copy = MS_ARENA_NEW_ARRAY(&m->arena, MirValue, n + 1);
  if (n > 0) {
    __builtin_memcpy(copy, *args, sizeof(MirValue) * n);
  }
  *args = copy;
}

static void clone_term(MirModule *m, MirTerm *t) {
  clone_args(m, &t->a.args, t->a.nargs);
  clone_args(m, &t->b.args, t->b.nargs);
  MirCase *cases = MS_ARENA_NEW_ARRAY(&m->arena, MirCase, t->ncases + 1);
  for (uint32_t i = 0; i < t->ncases; i++) {
    cases[i] = t->cases[i];
    clone_args(m, &cases[i].target.args, cases[i].target.nargs);
  }
  t->cases = cases;
}

void opt_func_deep_clone(MirModule *m, const MirFunc *f, MirFunc *out) {
  mir_func_clone(f, out);
  for (uint32_t bi = 0; bi < out->blocks.len; bi++) {
    MirBlockData *b = &out->blocks.ptr[bi];
    for (uint32_t ii = 0; ii < b->insts.len; ii++) {
      clone_args(m, &b->insts.ptr[ii].args, b->insts.ptr[ii].nargs);
    }
    clone_term(m, &b->term);
  }
}

void opt_id_push(MsArena *a, OptIdList *l, uint32_t x) {
  if (l->n == l->cap) {
    const uint32_t cap = l->cap ? l->cap * 2 : 4;
    uint32_t *grown = MS_ARENA_NEW_ARRAY_UNINIT(a, uint32_t, cap);
    if (l->n > 0) {
      __builtin_memcpy(grown, l->v, sizeof(uint32_t) * l->n);
    }
    l->v = grown;
    l->cap = cap;
  }
  l->v[l->n++] = x;
}

void *opt_grow(MsArena *a, void *arr, uint32_t n, uint32_t *cap, size_t elem) {
  const uint32_t ncap = *cap != 0 ? *cap * 2 : 8;
  void *p = ms_arena_alloc_array_uninit(a, elem, 16, ncap); /* callers write an element before reading it */
  if (n != 0) {
    __builtin_memcpy(p, arr, (size_t)n * elem);
  }
  *cap = ncap;
  return p;
}

typedef struct FuncLoop {
  MirModule *module;
  void (*step)(void *context, MirModule *view, uint32_t fi);
  void *context;
  MirModule views[MS_PARALLEL_MAX_WORKERS];
  bool started[MS_PARALLEL_MAX_WORKERS];
} FuncLoop;

static void func_loop_step(void *context, size_t worker, size_t fi) {
  FuncLoop *loop = context;
  MirModule *view = &loop->views[worker];
  if (!loop->started[worker]) {
    *view = *loop->module;
    view->arena = ms_arena_new();
    loop->started[worker] = true;
  }
  loop->step(loop->context, view, (uint32_t)fi);
}

void opt_parallel_funcs(MirModule *m, size_t grain, void (*step)(void *context, MirModule *view, uint32_t fi), void *context) {
  MsArena scratch = ms_arena_new();
  FuncLoop *loop = MS_ARENA_NEW(&scratch, FuncLoop);
  loop->module = m;
  loop->step = step;
  loop->context = context;
  (void)ms_parallel_for(m->funcs.len, grain, func_loop_step, loop);
  for (size_t worker = 0; worker < MS_PARALLEL_MAX_WORKERS; worker++) {
    if (!loop->started[worker]) {
      continue;
    }
    MirModule *view = &loop->views[worker];
    ms_arena_absorb(&m->arena, &view->arena);
    MirModule expected = *m;
    expected.arena = view->arena;
    if (!ms_span_equal(ms_span_of((const uint8_t *)&expected, sizeof expected), ms_span_of((const uint8_t *)view, sizeof *view))) {
      ms_fatal(MS_FATAL_INVARIANT, "a per-function pass changed the module");
    }
  }
  ms_arena_free(&scratch);
}

typedef struct EachFunc {
  bool (*pass)(MirModule *view, MirFunc *f, void *context);
  void *context;
  MirModule *module;
  atomic_bool changed;
} EachFunc;

static void each_func_step(void *context, MirModule *view, uint32_t fi) {
  EachFunc *each = context;
  if (each->pass(view, &each->module->funcs.ptr[fi], each->context)) {
    atomic_store(&each->changed, true);
  }
}

bool opt_for_each_func(MirModule *m, bool (*pass)(MirModule *view, MirFunc *f, void *context), void *context) {
  EachFunc each = {.pass = pass, .context = context, .module = m};
  atomic_init(&each.changed, false);
  opt_parallel_funcs(m, 16, each_func_step, &each);
  return atomic_load(&each.changed);
}
