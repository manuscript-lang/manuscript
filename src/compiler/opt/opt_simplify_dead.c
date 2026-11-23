/* The `simplify` pass, dead owned values: an owned value that only a drop or another dead constructor
 * consumes is never observed, so its construction and the drops go. This subsumes the per-shape cases
 * (an `alt.new` only dropped, a `type.new` of a dropped record) and removes whole trees: the error arm of
 * `r = if c: error(Error("bad")) else: ok(x)` built before a test that proved the arm is not an error. */
#include "compiler/opt/opt_simplify.h"

enum { SD_MAX_ARGS = 64 };

/* An operation that only allocates and takes ownership of its owned operands: dropping its result undoes it. */
static bool sd_constructor(const MirModule *m, const MirFunc *f, const MirInst *i) {
  MirMode mode;
  if (i->res == MIR_NONE || !mir_result_mode(m, f, i, &mode) || mode != MM_MOVE || i->nargs > SD_MAX_ARGS) {
    return false;
  }
  switch (i->op) {
  case MOP_AltNew: case MOP_TypeNew: case MOP_Clone: case MOP_ListNew: case MOP_ListLit: case MOP_OptSome:
    return true;
  case MOP_CallRt: return i->imm.tag == MI_EXT && m->externs.ptr[i->imm.a].pure && m->externs.ptr[i->imm.a].fresh;
  default: return false;
  }
}

typedef struct SdCtx {
  const MirModule *m;
  const MirFunc *f;
  bool *cand;
  MirBits owned; /* values that hold something to drop */
  bool changed;
} SdCtx;

static void sd_term_use(void *context, MirValue v) {
  SdCtx *c = context;
  if (c->cand[v]) {
    c->cand[v] = false;
    c->changed = true;
  }
}

static void sd_clear(SdCtx *c, MirValue v) {
  if (c->cand[v]) {
    c->cand[v] = false;
    c->changed = true;
  }
}

/* One sweep that clears every candidate with a use that keeps it alive. */
static void sd_sweep(SdCtx *c) {
  const MirFunc *f = c->f;
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    const MirBlockData *b = &f->blocks.ptr[bi];
    for (uint32_t ii = 0; ii < b->insts.len; ii++) {
      const MirInst *i = &b->insts.ptr[ii];
      MirMode modes[SD_MAX_ARGS];
      if (i->nargs > SD_MAX_ARGS) {
        for (uint32_t k = 0; k < i->nargs; k++) {
          sd_clear(c, i->args[k]);
        }
        continue;
      }
      mir_arg_modes(c->m, f, i, modes);
      const bool self = i->res != MIR_NONE && c->cand[i->res];
      for (uint32_t k = 0; k < i->nargs; k++) {
        const MirValue v = i->args[k];
        if (i->op == MOP_Drop && c->cand[v]) {
          continue;
        }
        if (self && modes[k] == MM_MOVE) {
          /* The constructor stays dead only if everything it takes is dead too. */
          if (!c->cand[v] && mir_bits_test(&c->owned, v)) {
            sd_clear(c, i->res);
          }
        } else if (c->cand[v] && !self) {
          sd_clear(c, v);
        }
      }
    }
    mir_term_each_value(&b->term, sd_term_use, c);
  }
}

static bool sd_remove(const void *ctx, const MirInst *i) {
  const bool *cand = ctx;
  return (i->op == MOP_Drop && cand[i->args[0]]) || (i->res != MIR_NONE && cand[i->res]);
}

bool opt_simplify_dead_owned(MirModule *m, MirFunc *f) {
  MsArena arena = ms_arena_new();
  bool *cand = MS_ARENA_NEW_ARRAY(&arena, bool, (size_t)f->values.len + 1);
  __builtin_memset(cand, 0, (size_t)f->values.len + 1);
  bool any = false;
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    for (uint32_t ii = 0; ii < f->blocks.ptr[bi].insts.len; ii++) {
      const MirInst *i = &f->blocks.ptr[bi].insts.ptr[ii];
      if (sd_constructor(m, f, i)) {
        cand[i->res] = true;
        any = true;
      }
    }
  }
  if (!any) {
    ms_arena_free(&arena);
    return false;
  }
  SdCtx c = {.m = m, .f = f, .cand = cand, .owned = mir_owned_values(&arena, m, f, true)};
  do {
    c.changed = false;
    sd_sweep(&c);
  } while (c.changed);
  any = false;
  for (uint32_t v = 0; v < f->values.len && !any; v++) {
    any = cand[v];
  }
  if (any) {
    for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
      MirBlockData *b = &f->blocks.ptr[bi];
      uint32_t *list = MS_ARENA_NEW_ARRAY(&arena, uint32_t, (size_t)b->insts.len + 1);
      uint32_t n = 0;
      for (uint32_t ii = 0; ii < b->insts.len; ii++) {
        if (sd_remove(cand, &b->insts.ptr[ii])) {
          list[n++] = ii;
        }
      }
      if (n > 0) {
        mir_block_remove(b, list, n);
      }
    }
  }
  ms_arena_free(&arena);
  return any;
}
