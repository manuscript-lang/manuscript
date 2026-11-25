/* The `entry_ranges` step: what every caller of a function (or every construction of a closure) passes in an
 * integer parameter or capture, joined into an interval the range pass starts from. A function some other
 * reference names (a table, an export, an address) keeps every parameter unknown.
 *
 * The tables only grow: they start empty ("never reached"), a caller's analysis joins its arguments in, and a
 * function whose table changed is analysed again. A slot that changed four times goes to unknown, so the
 * iteration ends. */
#include "compiler/opt/opt_inline.h"
#include "compiler/opt/opt_range.h"

enum { EN_CHANGES_MAX = 4, EN_ROUNDS_MAX = 64 };

typedef struct EntryCx {
  MirModule *m;
  bool *unsafe;    /* named by something other than a call or a closure construction */
  bool *dirty;     /* its arguments must be read again */
  bool *reached;   /* some call or construction has joined into its table */
  int64_t **tab;   /* lo, hi per slot, once reached */
  uint8_t **moves; /* per slot: how often it changed */
} EntryCx;

static uint32_t slot_count(const MirFunc *f) {
  return f->nparams + f->ncaptures;
}

static MirTy slot_type(const MirFunc *f, uint32_t slot) {
  return slot < f->nparams ? f->params[slot].ty : f->captures[slot - f->nparams];
}

static bool slot_tracked(const MirFunc *f, uint32_t slot) {
  if (f->kind == MFK_CLOSURE && slot < f->nparams) {
    return false; /* the environment and the arguments the caller of a closure supplies */
  }
  const MirTy ty = slot_type(f, slot);
  return ty == MIR_INT || ty == MIR_BOOL;
}

static RgItv slot_top(const MirFunc *f, uint32_t slot) {
  return slot_type(f, slot) == MIR_BOOL ? RG_BOOL : RG_TOP;
}

/* Marks the functions an instruction or a table names in a way a call site does not account for. */
static void mark_unsafe(EntryCx *cx) {
  const MirModule *m = cx->m;
  opt_external_roots(m, cx->unsafe);
  for (uint32_t i = 0; i < m->funcs.len; i++) {
    const MirFunc *f = &m->funcs.ptr[i];
    for (uint32_t k = 0; k < f->ncapture_closers; k++) {
      cx->unsafe[f->capture_closers[k].func] = true;
    }
    if (f->has_slot_result) {
      cx->unsafe[f->slot_result] = true;
    }
    if (f->has_close_exit) {
      cx->unsafe[f->close_exit[0]] = true;
      cx->unsafe[f->close_exit[1]] = true;
    }
    for (uint32_t b = 0; b < f->blocks.len; b++) {
      for (uint32_t k = 0; k < f->blocks.ptr[b].insts.len; k++) {
        const MirInst *in = &f->blocks.ptr[b].insts.ptr[k];
        if (in->imm.tag != MI_FUNC) {
          continue;
        }
        const bool closure = m->funcs.ptr[in->imm.a].kind == MFK_CLOSURE;
        const bool plain = in->op == MOP_Call && !closure;
        const bool made = in->op == MOP_ClosureNew && closure;
        if (!plain && !made) {
          cx->unsafe[in->imm.a] = true;
        }
      }
    }
  }
}

/* Joins `x` into slot `slot` of `callee`; true when the table changed. */
static bool join_slot(EntryCx *cx, uint32_t callee, uint32_t slot, RgItv x) {
  const MirFunc *g = &cx->m->funcs.ptr[callee];
  int64_t *t = cx->tab[callee];
  if (t[2 * slot] > t[2 * slot + 1]) { /* still empty */
    t[2 * slot] = x.lo;
    t[2 * slot + 1] = x.hi;
    return true;
  }
  const RgItv old = {t[2 * slot], t[2 * slot + 1]};
  RgItv now = rg_join(old, x);
  if (rg_itv_eq(now, old)) {
    return false;
  }
  if (++cx->moves[callee][slot] > EN_CHANGES_MAX) {
    now = slot_top(g, slot);
  }
  t[2 * slot] = now.lo;
  t[2 * slot + 1] = now.hi;
  return true;
}

/* Reads the arguments of every call and closure construction in function `fi`. */
static bool read_function(EntryCx *cx, uint32_t fi) {
  MirModule *m = cx->m;
  MirFunc *f = &m->funcs.ptr[fi];
  RgFa fa;
  rg_fa_init(&fa, m, f);
  bool changed = false;
  const bool solved = rg_fa_solve(&fa);
  {
    for (uint32_t b = 0; b < f->blocks.len; b++) {
      const MirBlockData *blk = &f->blocks.ptr[b];
      for (uint32_t k = 0; k < blk->insts.len; k++) {
        const MirInst *in = &blk->insts.ptr[k];
        if (in->imm.tag != MI_FUNC || (in->op != MOP_Call && in->op != MOP_ClosureNew)) {
          continue;
        }
        const uint32_t g = in->imm.a;
        if (cx->unsafe[g]) {
          continue;
        }
        const MirFunc *callee = &m->funcs.ptr[g];
        const uint32_t base = in->op == MOP_Call ? 0 : callee->nparams;
        cx->reached[g] = true;
        for (uint32_t a = 0; a < in->nargs && base + a < slot_count(callee); a++) {
          if (!slot_tracked(callee, base + a)) {
            continue;
          }
          RgItv x = RG_TOP;
          if (!solved || !rg_get(&fa, in->args[a], &fa.envs[b], &x)) {
            x = slot_top(callee, base + a);
          }
          if (join_slot(cx, g, base + a, x)) {
            cx->dirty[g] = true;
            changed = true;
          }
        }
      }
    }
  }
  rg_fa_free(&fa);
  return changed;
}

bool opt_entry_ranges(MirModule *m) {
  const size_t n = m->funcs.len;
  MsArena arena = ms_arena_new();
  EntryCx cx = {.m = m};
  cx.unsafe = MS_ARENA_NEW_ARRAY(&arena, bool, n + 1);
  cx.dirty = MS_ARENA_NEW_ARRAY(&arena, bool, n + 1);
  cx.reached = MS_ARENA_NEW_ARRAY(&arena, bool, n + 1);
  cx.tab = MS_ARENA_NEW_ARRAY(&arena, int64_t *, n + 1);
  cx.moves = MS_ARENA_NEW_ARRAY(&arena, uint8_t *, n + 1);
  for (size_t i = 0; i < n; i++) {
    const uint32_t slots = slot_count(&m->funcs.ptr[i]);
    cx.unsafe[i] = cx.reached[i] = false;
    cx.dirty[i] = true;
    cx.tab[i] = MS_ARENA_NEW_ARRAY(&arena, int64_t, 2 * (size_t)slots + 2);
    cx.moves[i] = MS_ARENA_NEW_ARRAY(&arena, uint8_t, (size_t)slots + 1);
    __builtin_memset(cx.moves[i], 0, (size_t)slots + 1);
    for (uint32_t s = 0; s < slots; s++) {
      cx.tab[i][2 * s] = 1; /* empty: lo above hi */
      cx.tab[i][2 * s + 1] = 0;
    }
  }
  mark_unsafe(&cx);
  /* A function is read once something has reached it (or nothing can: it has no integer slot, or a table names
   * it); reading it earlier would join "unknown" into what it passes on. */
  bool progress = true;
  for (int round = 0; round < EN_ROUNDS_MAX && progress; round++) {
    progress = false;
    for (uint32_t fi = 0; fi < n; fi++) {
      MirFunc *f = &m->funcs.ptr[fi];
      const uint32_t slots = slot_count(f);
      bool tracked = false;
      for (uint32_t s = 0; s < slots; s++) {
        tracked = tracked || slot_tracked(f, s);
      }
      if (!cx.dirty[fi] || (tracked && !cx.unsafe[fi] && !cx.reached[fi])) {
        continue;
      }
      cx.dirty[fi] = false;
      progress = true;
      int64_t *seed = MS_ARENA_NEW_ARRAY(&arena, int64_t, 2 * (size_t)slots + 2);
      for (uint32_t s = 0; s < slots; s++) {
        const bool known = !cx.unsafe[fi] && cx.tab[fi][2 * s] <= cx.tab[fi][2 * s + 1];
        const RgItv x = known ? (RgItv){cx.tab[fi][2 * s], cx.tab[fi][2 * s + 1]} : slot_top(f, s);
        seed[2 * s] = x.lo;
        seed[2 * s + 1] = x.hi;
      }
      f->entry = seed;
      f->nentry = slots;
      (void)read_function(&cx, fi);
      f->entry = NULL;
      f->nentry = 0;
    }
  }
  const bool settled = !progress;
  bool any = false;
  for (uint32_t fi = 0; settled && fi < n; fi++) {
    MirFunc *f = &m->funcs.ptr[fi];
    const uint32_t slots = slot_count(f);
    if (cx.unsafe[fi] || !cx.reached[fi] || slots == 0) {
      continue;
    }
    int64_t *out = MS_ARENA_NEW_ARRAY(&m->arena, int64_t, 2 * (size_t)slots);
    bool narrowed = false;
    for (uint32_t s = 0; s < slots; s++) {
      const RgItv top = slot_top(f, s);
      RgItv x = {cx.tab[fi][2 * s], cx.tab[fi][2 * s + 1]};
      if (!slot_tracked(f, s) || x.lo > x.hi) {
        x = top;
      }
      narrowed = narrowed || !rg_itv_eq(x, top);
      out[2 * s] = x.lo;
      out[2 * s + 1] = x.hi;
    }
    if (narrowed) {
      f->entry = out;
      f->nentry = slots;
      any = true;
    }
  }
  ms_arena_free(&arena);
  return any;
}
