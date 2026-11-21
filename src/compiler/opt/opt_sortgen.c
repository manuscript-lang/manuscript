/* The `sortgen` pass: sorts of word lists by a known comparator, compiled with the program.
 *
 * The runtime sort calls its comparator through a pointer once per comparison, which keeps the
 * comparator from being inlined. When the comparator is a closure the module already knows, the
 * call to `msrt_list_sorted` is replaced by a copy of the list and a call to a generated
 * driftsort (opt_sortgen_drift.c) that calls the closure's code directly, so the backend can
 * inline it into the sort loops. A comparator that is plainly `a < b` or `b < a` on `Int`s becomes
 * the runtime's integer sort, and `a - b` the runtime's sort by difference.
 *
 * The generated sort is stable, like the runtime's, which is its whole contract: equal elements
 * keep their order. It calls a comparator with effects in a different order than the runtime sort
 * does. Slots move as bits and the scratch list owns nothing, so a comparator that exits early
 * never leaves an owner duplicated. */

#include "compiler/mir/mir_analysis.h"
#include "compiler/mir/mir_builder.h"
#include "compiler/opt/opt_pass.h"

/* ---- recognising a sort ---- */

/* Whether the sort through thunk `thunk` and comparator `g` is over plain-data values (words or
 * types that own nothing) and `g` has the shape `(env, elem, elem) -> int`; `*elem` is the
 * element type. */
static bool sg_word_elem(const MirModule *m, uint32_t thunk, uint32_t g, MirTy *elem) {
  const MirFunc *code = &m->funcs.ptr[g], *th = &m->funcs.ptr[thunk];
  bool found = false;
  for (uint32_t b = 0; b < th->blocks.len && !found; b++) {
    for (uint32_t i = 0; i < th->blocks.ptr[b].insts.len && !found; i++) {
      const MirInst *inst = &th->blocks.ptr[b].insts.ptr[i];
      if (inst->op == MOP_Load && inst->imm.tag == MI_TY) {
        *elem = inst->imm.a;
        found = true;
      }
    }
  }
  if (!found) {
    return false;
  }
  const MirTy t = *elem;
  const bool shaped = code->kind == MFK_CLOSURE && code->nparams == 3 &&
            code->params[0].ty == MIR_PTR && code->params[1].ty == t &&
            code->params[2].ty == t && code->ret == MIR_INT;
  const bool plain = t == MIR_INT || t == MIR_FLOAT || t == MIR_STR ||
           mir_ty_data(m, t)->kind == MK_TYPE;
  return shaped && plain;
}

/* The function that decides `g(env, a, b)`, and its two element parameters: a closure that only
 * forwards its two arguments to a named function is that function. */
static bool sg_comparator(const MirModule *m, uint32_t g, const MirFunc **out, MirValue *a,
             MirValue *b) {
  const MirFunc *closure = &m->funcs.ptr[g];
  if (closure->blocks.len == 0 || closure->blocks.ptr[0].params.len != 3) {
    return false;
  }
  const MirFunc *fn = closure;
  uint32_t skip = 1;
  if (closure->blocks.len != 1) {
    return false;
  }
  const MirBlockData *only = &closure->blocks.ptr[0];
  const MirValue p = only->params.ptr[1].value, q = only->params.ptr[2].value;
  if (only->insts.len == 1 && only->term.kind == MT_RET && only->term.value != MIR_NONE) {
    const MirInst *call = &only->insts.ptr[0];
    if (call->op == MOP_Call && call->res == only->term.value && call->nargs == 2 &&
      call->args[0] == p && call->args[1] == q) {
      if (call->imm.tag != MI_FUNC) {
        return false;
      }
      fn = &m->funcs.ptr[call->imm.a];
      skip = 0;
    }
  }
  if (fn->blocks.ptr[0].params.len != skip + 2) {
    return false;
  }
  *out = fn;
  *a = fn->blocks.ptr[0].params.ptr[skip].value;
  *b = fn->blocks.ptr[0].params.ptr[skip + 1].value;
  return true;
}

static bool sg_is_depth(const MirInst *inst) {
  return inst->op == MOP_DepthEnter || inst->op == MOP_DepthLeave;
}

/* Whether `g(env, a, b)` for `Int`s is exactly `a - b` (`*desc` false) or `b - a` (true), checked
 * for overflow: a single block that subtracts one argument from the other and returns the
 * difference. */
static bool sg_difference_order(const MirModule *m, uint32_t g, bool *desc) {
  const MirFunc *fn = NULL;
  MirValue a = MIR_NONE, b = MIR_NONE;
  if (!sg_comparator(m, g, &fn, &a, &b) || fn->blocks.len != 1) {
    return false;
  }
  const MirBlockData *only = &fn->blocks.ptr[0];
  const MirInst *sub = NULL;
  for (uint32_t i = 0; i < only->insts.len; i++) {
    if (sg_is_depth(&only->insts.ptr[i])) {
      continue;
    }
    if (sub != NULL) {
      return false;
    }
    sub = &only->insts.ptr[i];
  }
  if (sub == NULL || only->term.kind != MT_RET || only->term.value == MIR_NONE) {
    return false;
  }
  if (sub->op != MOP_ISubChk || sub->res != only->term.value || sub->nargs != 2) {
    return false;
  }
  if (sub->args[0] == a && sub->args[1] == b) {
    *desc = false;
    return true;
  }
  if (sub->args[0] == b && sub->args[1] == a) {
    *desc = true;
    return true;
  }
  return false;
}

/* ---- evaluating a comparator on three orderings ---- */

typedef enum SgKind { SGK_NONE, SGK_ARG, SGK_NUM, SGK_BOXED, SGK_PAYLOAD } SgKind;

/* What the interpreter knows of a value: an argument (by its number), a number, an argument boxed
 * into a `Comparable` value, or the pointer to that payload. */
typedef struct SgVal {
  uint8_t kind;
  int64_t n;
} SgVal;

typedef struct SgEnv {
  SgVal *vals; /* by value */
  uint32_t nvals;
  MsArena *arena;
} SgEnv;

static bool sg_get(const SgEnv *env, MirValue v, SgVal *out) {
  if (v >= env->nvals || env->vals[v].kind == SGK_NONE) {
    return false;
  }
  *out = env->vals[v];
  return true;
}

static bool sg_set(SgEnv *env, MirValue v, SgVal val) {
  if (v == MIR_NONE || v >= env->nvals) {
    return false;
  }
  env->vals[v] = val;
  return true;
}

static bool sg_compare(MirCc cc, int64_t l, int64_t r) {
  switch (cc) {
  case MCC_EQ: return l == r;
  case MCC_NE: return l != r;
  case MCC_LT: return l < r;
  case MCC_LE: return l <= r;
  case MCC_GT: return l > r;
  case MCC_GE: return l >= r;
  }
  return false;
}

/* Evaluates one instruction of a comparator; false when it is not one the evaluation allows. */
static bool sg_step(SgEnv *env, const MirInst *inst) {
  SgVal x = {0}, y = {0}, z = {0};
  switch ((MirOp)inst->op) {
  case MOP_IConst:
    return sg_set(env, inst->res, (SgVal){SGK_NUM, inst->imm.i});
  case MOP_Clone:
    return inst->nargs >= 1 && sg_get(env, inst->args[0], &x) && sg_set(env, inst->res, x);
  case MOP_ICmp:
    if (inst->imm.tag != MI_CC || inst->nargs < 2 || !sg_get(env, inst->args[0], &x) ||
      !sg_get(env, inst->args[1], &y) || x.kind != y.kind ||
      (x.kind != SGK_ARG && x.kind != SGK_NUM)) {
      return false;
    }
    return sg_set(env, inst->res,
           (SgVal){SGK_NUM, sg_compare((MirCc)inst->imm.a, x.n, y.n) ? 1 : 0});
  case MOP_Select:
    if (inst->nargs < 3 || !sg_get(env, inst->args[0], &x) || !sg_get(env, inst->args[1], &y) ||
      !sg_get(env, inst->args[2], &z) || x.kind != SGK_NUM || y.kind != SGK_NUM ||
      z.kind != SGK_NUM) {
      return false;
    }
    return sg_set(env, inst->res, x.n != 0 ? y : z);
  /* `a.compare(b)` on a generic element passes `b` as a boxed `Comparable`. */
  case MOP_IfaceNew:
    return inst->nargs >= 1 && sg_get(env, inst->args[0], &x) && x.kind == SGK_ARG &&
       sg_set(env, inst->res, (SgVal){SGK_BOXED, x.n});
  case MOP_IfaceData:
    return inst->nargs >= 1 && sg_get(env, inst->args[0], &x) && x.kind == SGK_BOXED &&
       sg_set(env, inst->res, (SgVal){SGK_PAYLOAD, x.n});
  case MOP_Load:
    return inst->nargs >= 1 && sg_get(env, inst->args[0], &x) && x.kind == SGK_PAYLOAD &&
       sg_set(env, inst->res, (SgVal){SGK_ARG, x.n});
  default:
    return false;
  }
}

/* Follows `target`: binds the destination's parameters to the arguments passed. */
static bool sg_enter(SgEnv *env, const MirFunc *g, const MirTarget *target) {
  const MirBlockData *dest = &g->blocks.ptr[target->block];
  if (dest->params.len != target->nargs) {
    return false;
  }
  SgVal *passed = MS_ARENA_NEW_ARRAY(env->arena, SgVal, (size_t)target->nargs + 1);
  for (uint32_t i = 0; i < target->nargs; i++) {
    if (!sg_get(env, target->args[i], &passed[i])) {
      return false;
    }
  }
  for (uint32_t i = 0; i < target->nargs; i++) {
    if (!sg_set(env, dest->params.ptr[i].value, passed[i])) {
      return false;
    }
  }
  return true;
}

/* Runs the comparator on arguments `x` and `y`; `*negative` is whether the result is below 0. The
 * body may only compare the two arguments with each other, branch or select on those comparisons
 * and return constants. */
static bool sg_negative(MsArena *arena, const MirFunc *g, MirValue a, MirValue b, int64_t x,
            int64_t y, bool *negative) {
  SgEnv env = {MS_ARENA_NEW_ARRAY(arena, SgVal, g->values.len + 1), (uint32_t)g->values.len, arena};
  __builtin_memset(env.vals, 0, sizeof(SgVal) * ((size_t)g->values.len + 1));
  (void)sg_set(&env, a, (SgVal){SGK_ARG, x});
  (void)sg_set(&env, b, (SgVal){SGK_ARG, y});
  uint32_t block = 0;
  for (uint32_t step = 0; step < 64; step++) {
    const MirBlockData *bd = &g->blocks.ptr[block];
    for (uint32_t i = 0; i < bd->insts.len; i++) {
      const MirInst *inst = &bd->insts.ptr[i];
      if (sg_is_depth(inst) || inst->op == MOP_Drop) {
        continue;
      }
      if (!sg_step(&env, inst)) {
        return false;
      }
    }
    const MirTarget *target = NULL;
    SgVal c = {0};
    switch ((MirTermKind)bd->term.kind) {
    case MT_RET:
      if (bd->term.value == MIR_NONE || !sg_get(&env, bd->term.value, &c) ||
        c.kind != SGK_NUM) {
        return false;
      }
      *negative = c.n < 0;
      return true;
    case MT_BR:
      target = &bd->term.a;
      break;
    case MT_CONDBR:
      if (!sg_get(&env, bd->term.value, &c) || c.kind != SGK_NUM) {
        return false;
      }
      target = c.n != 0 ? &bd->term.a : &bd->term.b;
      break;
    case MT_SWITCH: case MT_FAULT: case MT_UNREACHABLE:
      return false;
    }
    if (!sg_enter(&env, g, target)) {
      return false;
    }
    block = target->block;
  }
  return false;
}

/* Whether `g(env, a, b)` for `Int`s is exactly "a before b" (`*desc` false) or "b before a"
 * (true), where "before" means a negative result. Its result may depend on nothing but the
 * ordering of `a` and `b`, so trying the three orderings decides every input. */
static bool sg_plain_int_order(MsArena *arena, const MirModule *m, uint32_t g, bool *desc) {
  const MirFunc *fn = NULL;
  MirValue a = MIR_NONE, b = MIR_NONE;
  if (!sg_comparator(m, g, &fn, &a, &b)) {
    return false;
  }
  bool lt = false, eq = false, gt = false;
  if (!sg_negative(arena, fn, a, b, 0, 1, &lt) || !sg_negative(arena, fn, a, b, 1, 1, &eq) ||
    !sg_negative(arena, fn, a, b, 1, 0, &gt)) {
    return false;
  }
  if (lt && !eq && !gt) {
    *desc = false;
    return true;
  }
  if (!lt && !eq && gt) {
    *desc = true;
    return true;
  }
  return false;
}

/* ---- rewriting a call ---- */

static MirInst sg_inst(MirOp op, const MirValue *args, uint32_t nargs, MirImm imm, MirValue res,
           MirLoc loc, MirModule *m) {
  MirInst inst = {0};
  inst.op = (uint8_t)op;
  inst.imm = imm;
  inst.res = res;
  inst.loc = loc;
  if (nargs > 0) {
    inst.args = MS_ARENA_NEW_ARRAY(&m->arena, MirValue, nargs);
    __builtin_memcpy(inst.args, args, sizeof(MirValue) * nargs);
  }
  inst.nargs = nargs;
  return inst;
}

/* Replaces the instruction at `at` by `n` instructions. */
static void sg_splice(MirBlockData *block, uint32_t at, const MirInst *insts,
           uint32_t n) {
  block->insts.ptr[at] = insts[0];
  for (uint32_t k = 1; k < n; k++) {
    mir_block_insert(block, at + k, &insts[k]);
  }
}

static MirImm sg_ext(uint32_t ext) { return (MirImm){.tag = MI_EXT, .a = ext}; }
static MirImm sg_int_imm(int64_t v) { return (MirImm){.tag = MI_INT, .i = v}; }

/* Rewrites the runtime sort at `blocks[bi].insts.ptr[ii]` into a copy and an in-place integer sort. */
static void sg_rewrite_plain(MirModule *m, MirFunc *f, uint32_t bi, uint32_t ii, uint32_t ext,
              bool desc) {
  const MirInst call = f->blocks.ptr[bi].insts.ptr[ii];
  const MirValue out = call.res;
  const MirValue list_arg[1] = {call.args[0]};
  const MirInst copy_out = sg_inst(MOP_Clone, list_arg, 1, (MirImm){0}, out, call.loc, m);
  const MirValue flag = mir_new_value(f, MIR_INT);
  const MirInst flag_inst = sg_inst(MOP_IConst, NULL, 0, sg_int_imm(desc ? 1 : 0), flag, call.loc, m);
  const MirValue unit = mir_new_value(f, MIR_VOID);
  const MirValue run_args[2] = {out, flag};
  const MirInst run = sg_inst(MOP_CallRt, run_args, 2, sg_ext(ext), unit, call.loc, m);
  const MirInst replacement[3] = {copy_out, flag_inst, run};
  sg_splice(&f->blocks.ptr[bi], ii, replacement, 3);
}

/* The runtime functions that copy a list's slots bitwise and free that copy, declared from the sort
 * call's extern `sort_ext`. */
static void sg_shadow_externs(MirModule *m, uint32_t sort_ext, uint32_t *shadow, uint32_t *free) {
  MirExtern def = m->externs.ptr[sort_ext];
  def.name = mir_name(m, ms_span_of_text("msrt_list_shadow"));
  def.role = MR_RAW_SLOTS;
  def.nparams = 2;
  def.leaf = true;
  const MirTy list = def.params[0].ty;
  MirParam moved = {list, MM_MOVE};
  /* The runtime releases the scratch buffer, so the call consumes the owned list value. */
  MirExtern release = {0};
  release.name = mir_name(m, ms_span_of_text("msrt_list_free_raw"));
  release.params = &moved;
  release.nparams = 1;
  release.ret = MIR_VOID;
  release.role = MR_RAW_FREE;
  release.leaf = true;
  *shadow = mir_extern_intern(m, &def);
  *free = mir_extern_intern(m, &release);
  /* A declaration the program already had keeps its role otherwise. */
  m->externs.ptr[*shadow].role = MR_RAW_SLOTS;
  m->externs.ptr[*free].role = MR_RAW_FREE;
}

/* The instructions replacing a call, built in order; `sg_push` makes a result of `ty` (none for
 * MIR_NONE) when the instruction is added */
typedef struct SgEmit {
  MirModule *m;
  MirFunc *f;
  MirInst *insts;
  uint32_t n, cap;
  MirLoc loc;
} SgEmit;

static MirValue sg_push_to(SgEmit *s, MirOp op, const MirValue *args, uint32_t nargs, MirImm imm,
             MirValue res) {
  const MirInst inst = sg_inst(op, args, nargs, imm, res, s->loc, s->m);
  OPT_PUSH(&s->m->arena, s->insts, s->n, s->cap, MirInst, inst);
  return res;
}

static MirValue sg_push(SgEmit *s, MirOp op, const MirValue *args, uint32_t nargs, MirImm imm,
            MirTy ty) {
  const MirValue res = ty == MIR_NONE ? MIR_NONE : mir_new_value(s->f, ty);
  return sg_push_to(s, op, args, nargs, imm, res);
}

/* The environment pointer a generated sort passes to its comparator: a scratch slot for a
 * comparator that captures nothing, and the closure's own environment for one that does (the
 * closure value is that pointer; it is stored to a slot and read back as a `ptr`). */
static MirValue sg_comparator_env(SgEmit *s, MirValue closure, MirTy elem, bool captures) {
  if (!captures) {
    return sg_push(s, MOP_Slot, NULL, 0, (MirImm){.tag = MI_TY, .a = elem}, MIR_PTR);
  }
  const MirTy closure_ty = mir_value_ty(s->f, closure);
  const MirValue slot =
    sg_push(s, MOP_Slot, NULL, 0, (MirImm){.tag = MI_TY, .a = closure_ty}, MIR_PTR);
  const MirValue store_args[2] = {slot, closure};
  (void)sg_push(s, MOP_Store, store_args, 2, (MirImm){0}, MIR_NONE);
  return sg_push(s, MOP_Load, &slot, 1, (MirImm){.tag = MI_TY, .a = MIR_PTR}, MIR_PTR);
}

/* Rewrites the runtime sort of owning elements. The sort permutes bitwise copies of the slots
 * (two scratch buffers that own nothing) and only then clones the sorted slots into the result, so
 * a comparator that exits early never leaves a list with duplicated owners. */
static void sg_rewrite_owned(MirModule *m, MirFunc *f, uint32_t bi, uint32_t ii, uint32_t sort,
              MirTy elem, bool captures, uint32_t shadow, uint32_t free) {
  const MirInst call = f->blocks.ptr[bi].insts.ptr[ii];
  const MirValue list = call.args[0], desc = call.args[1], out = call.res;
  const MirTy list_ty = mir_value_ty(f, out);
  SgEmit s = {m, f, NULL, 0, 0, call.loc};
  const MirValue env = sg_comparator_env(&s, call.args[3], elem, captures);
  const MirValue shadow_args[2] = {list, desc};
  const MirValue items = sg_push(&s, MOP_CallRt, shadow_args, 2, sg_ext(shadow), list_ty);
  const MirValue buf = sg_push(&s, MOP_CallRt, shadow_args, 2, sg_ext(shadow), list_ty);
  const MirValue len = sg_push(&s, MOP_ListLen, &items, 1, (MirImm){0}, MIR_INT);
  const MirValue zero = sg_push(&s, MOP_IConst, NULL, 0, sg_int_imm(0), MIR_INT);
  const MirValue sort_args[5] = {buf, items, zero, len, env};
  (void)sg_push(&s, MOP_Call, sort_args, 5, (MirImm){.tag = MI_FUNC, .a = sort}, MIR_VOID);
  /* The merge buffer is dead once the sort returns: freeing it before the clone lets the result
   * reuse its block instead of the sort holding a third and fourth copy of the list. */
  (void)sg_push(&s, MOP_CallRt, &buf, 1, sg_ext(free), MIR_VOID);
  (void)sg_push_to(&s, MOP_Clone, &items, 1, (MirImm){0}, out);
  (void)sg_push(&s, MOP_CallRt, &items, 1, sg_ext(free), MIR_VOID);
  sg_splice(&f->blocks.ptr[bi], ii, s.insts, s.n);
}

/* Rewrites the runtime sort at `blocks[bi].insts.ptr[ii]` into a copy, a buffer copy and a call. */
static void sg_rewrite(MirModule *m, MirFunc *f, uint32_t bi, uint32_t ii, uint32_t sort,
           MirTy elem, bool captures) {
  const MirInst call = f->blocks.ptr[bi].insts.ptr[ii];
  const MirValue list = call.args[0], out = call.res;
  const MirTy list_ty = mir_value_ty(f, out);
  SgEmit head = {m, f, NULL, 0, 0, call.loc};
  (void)sg_push_to(&head, MOP_Clone, &list, 1, (MirImm){0}, out);
  const MirValue buf = sg_push(&head, MOP_Clone, &out, 1, (MirImm){0}, list_ty);
  const MirValue len = sg_push(&head, MOP_ListLen, &out, 1, (MirImm){0}, MIR_INT);
  const MirValue zero = sg_push(&head, MOP_IConst, NULL, 0, sg_int_imm(0), MIR_INT);
  SgEmit tail = {m, f, NULL, 0, 0, call.loc};
  const MirValue env = sg_comparator_env(&tail, call.args[3], elem, captures);
  const MirValue run_args[5] = {buf, out, zero, len, env};
  (void)sg_push(&tail, MOP_Call, run_args, 5, (MirImm){.tag = MI_FUNC, .a = sort}, MIR_VOID);
  (void)sg_push(&tail, MOP_Drop, &buf, 1, (MirImm){0}, MIR_NONE);
  sg_splice(&f->blocks.ptr[bi], ii, head.insts, head.n);
  for (uint32_t k = 0; k < tail.n; k++) {
    mir_block_insert(&f->blocks.ptr[bi], ii + head.n + k, &tail.insts[k]);
  }
}

/* ---- the pass ---- */

/* A sort call to rewrite: where it is, its comparator closure code `g`, and its element type. */
typedef struct SgSite {
  uint32_t block, index, g;
  MirTy elem;
  bool captures;
} SgSite;

/* What a function's values stand for: closures the module knows and specialised sort thunks. */
typedef struct SgKnown {
  uint32_t *closure; /* by value: closure code, or MIR_NONE */
  bool *captures;
  uint32_t *thunk; /* by value: the thunk, or MIR_NONE */
  uint32_t nclosures, nthunks;
} SgKnown;

static SgKnown sg_scan(MsArena *arena, const MirModule *m, const MirFunc *f) {
  SgKnown k = {0};
  const uint32_t n = (uint32_t)(f->values.len + 1);
  k.closure = MS_ARENA_NEW_ARRAY(arena, uint32_t, n);
  k.captures = MS_ARENA_NEW_ARRAY(arena, bool, n);
  k.thunk = MS_ARENA_NEW_ARRAY(arena, uint32_t, n);
  for (uint32_t v = 0; v < n; v++) {
    k.closure[v] = MIR_NONE;
    k.captures[v] = false;
    k.thunk[v] = MIR_NONE;
  }
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      const MirInst *inst = &f->blocks.ptr[b].insts.ptr[i];
      if (inst->res == MIR_NONE || inst->imm.tag != MI_FUNC) {
        continue;
      }
      if (inst->op == MOP_ClosureNew) {
        k.nclosures += k.closure[inst->res] == MIR_NONE ? 1u : 0u;
        k.closure[inst->res] = inst->imm.a;
        k.captures[inst->res] = inst->nargs > 0;
      } else if (inst->op == MOP_FuncAddr && m->funcs.ptr[inst->imm.a].sort == MSORT_SPECIALIZED) {
        k.nthunks += k.thunk[inst->res] == MIR_NONE ? 1u : 0u;
        k.thunk[inst->res] = inst->imm.a;
      }
    }
  }
  return k;
}

/* The sort calls of `f` with a known comparator over plain words, in program order. */
static uint32_t sg_find_sites(MsArena *arena, const MirModule *m, const MirFunc *f,
               const SgKnown *known, SgSite **out) {
  SgSite *sites = NULL;
  uint32_t n = 0, cap = 0;
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      const MirInst *inst = &f->blocks.ptr[b].insts.ptr[i];
      if (inst->op != MOP_CallRt || inst->nargs != 4 || inst->imm.tag != MI_EXT ||
        m->externs.ptr[inst->imm.a].role != MR_LIST_SORTED) {
        continue;
      }
      const uint32_t t = known->thunk[inst->args[2]], g = known->closure[inst->args[3]];
      MirTy elem = MIR_VOID;
      if (t == MIR_NONE || g == MIR_NONE || !sg_word_elem(m, t, g, &elem)) {
        continue;
      }
      if (n == cap) {
        const uint32_t next = cap ? cap * 2 : 8;
        SgSite *grown = MS_ARENA_NEW_ARRAY(arena, SgSite, next);
        if (n > 0) {
          __builtin_memcpy(grown, sites, sizeof(SgSite) * n);
        }
        sites = grown;
        cap = next;
      }
      sites[n++] = (SgSite){b, i, g, elem, known->captures[inst->args[3]]};
    }
  }
  *out = sites;
  return n;
}

/* Replaces the sort with the runtime's in-place integer sort. */
static void sg_use_int_sort(MirModule *m, uint32_t fi, const SgSite *s, bool desc) {
  const MirInst *call = &m->funcs.ptr[fi].blocks.ptr[s->block].insts.ptr[s->index];
  MirParam params[2] = {{mir_value_ty(&m->funcs.ptr[fi], call->args[0]), MM_BORROW}, {MIR_INT, MM_BORROW}};
  MirExtern def = {0};
  def.name = mir_name(m, ms_span_of_text("msrt_list_sort_ints"));
  def.params = params;
  def.nparams = 2;
  def.ret = MIR_VOID;
  def.role = MR_LIST_SORT_INTS;
  def.leaf = true;
  const uint32_t ext = mir_extern_intern(m, &def);
  sg_rewrite_plain(m, &m->funcs.ptr[fi], s->block, s->index, ext, desc);
}

/* Replaces the sort with the runtime's sort by difference, which takes the direction as a flag. */
static void sg_use_difference_sort(MirModule *m, uint32_t fi, const SgSite *s, bool desc) {
  MirFunc *f = &m->funcs.ptr[fi];
  MirInst *call = &f->blocks.ptr[s->block].insts.ptr[s->index];
  MirExtern def = m->externs.ptr[call->imm.a];
  def.name = mir_name(m, ms_span_of_text("msrt_list_sorted_by_difference"));
  def.role = MR_LIST_SORTED_BY_DIFFERENCE;
  MirParam *params = MS_ARENA_NEW_ARRAY(&m->arena, MirParam, (size_t)def.nparams + 1);
  __builtin_memcpy(params, def.params, sizeof(MirParam) * def.nparams);
  params[def.nparams++] = (MirParam){MIR_INT, MM_BORROW};
  def.params = params;
  const uint32_t ext = mir_extern_intern(m, &def);
  const MirValue flag = mir_new_value(f, MIR_INT);
  const MirLoc loc = call->loc;
  call->imm = sg_ext(ext);
  MirValue *args = MS_ARENA_NEW_ARRAY(&m->arena, MirValue, (size_t)call->nargs + 1);
  __builtin_memcpy(args, call->args, sizeof(MirValue) * call->nargs);
  args[call->nargs] = flag;
  call->args = args;
  call->nargs++;
  const MirInst konst = sg_inst(MOP_IConst, NULL, 0, sg_int_imm(desc ? 1 : 0), flag, loc, m);
  mir_block_insert(&f->blocks.ptr[s->block], s->index, &konst);
}

/* The generated sort of comparator `g`, built once per comparator. */
typedef struct SgMade {
  uint32_t *g, *sort;
  uint32_t n, cap;
} SgMade;

static uint32_t sg_drift_for(MsArena *arena, SgMade *made, MirModule *m, uint32_t g, MirTy elem) {
  for (uint32_t i = 0; i < made->n; i++) {
    if (made->g[i] == g) {
      return made->sort[i];
    }
  }
  const uint32_t sort = opt_sortgen_drift(m, g, elem);
  if (made->n == made->cap) {
    const uint32_t next = made->cap ? made->cap * 2 : 8;
    uint32_t *gs = MS_ARENA_NEW_ARRAY(arena, uint32_t, next), *sorts = MS_ARENA_NEW_ARRAY(arena, uint32_t, next);
    if (made->n > 0) {
      __builtin_memcpy(gs, made->g, sizeof(uint32_t) * made->n);
      __builtin_memcpy(sorts, made->sort, sizeof(uint32_t) * made->n);
    }
    made->g = gs;
    made->sort = sorts;
    made->cap = next;
  }
  made->g[made->n] = g;
  made->sort[made->n++] = sort;
  return sort;
}

/* Rewrites one site; the plain and difference orders of `Int`s use the runtime's sorts. */
static void sg_rewrite_site(MsArena *arena, SgMade *made, MirModule *m, uint32_t fi,
              const SgSite *s) {
  bool desc = false;
  if (s->elem == MIR_INT && sg_plain_int_order(arena, m, s->g, &desc)) {
    sg_use_int_sort(m, fi, s, desc);
    return;
  }
  if (s->elem == MIR_INT && sg_difference_order(m, s->g, &desc)) {
    sg_use_difference_sort(m, fi, s, desc);
    return;
  }
  const uint32_t sort = sg_drift_for(arena, made, m, s->g, s->elem);
  if (mir_needs_drop(m, s->elem)) {
    uint32_t shadow = 0, free = 0;
    sg_shadow_externs(m, m->funcs.ptr[fi].blocks.ptr[s->block].insts.ptr[s->index].imm.a, &shadow, &free);
    sg_rewrite_owned(m, &m->funcs.ptr[fi], s->block, s->index, sort, s->elem, s->captures, shadow,
            free);
    return;
  }
  sg_rewrite(m, &m->funcs.ptr[fi], s->block, s->index, sort, s->elem, s->captures);
}

bool opt_sortgen(MirModule *m) {
  bool changed = false;
  MsArena arena = ms_arena_new();
  SgMade made = {0};
  const uint32_t nfuncs = (uint32_t)m->funcs.len; /* the sorts it generates are not scanned */
  for (uint32_t fi = 0; fi < nfuncs; fi++) {
    const SgKnown known = sg_scan(&arena, m, &m->funcs.ptr[fi]);
    if (known.nclosures == 0 || known.nthunks == 0) {
      continue;
    }
    SgSite *sites = NULL;
    const uint32_t n = sg_find_sites(&arena, m, &m->funcs.ptr[fi], &known, &sites);
    /* Last first, so each rewrite leaves the earlier indices valid. */
    for (uint32_t k = n; k > 0; k--) {
      sg_rewrite_site(&arena, &made, m, fi, &sites[k - 1]);
      changed = true;
    }
  }
  ms_arena_free(&arena);
  return changed;
}
