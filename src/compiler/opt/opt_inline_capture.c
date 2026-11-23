/* A closure that captures a known closure and only calls it. See opt_inline_closure.h.
 *
 *   %c = closure.new @inner %x          the work a caller hands over
 *   %w = closure.new @outer %id, %c     a wrapper that calls it and does something with the result
 *
 * `%w` becomes `closure.new @outer.fused %id, %x`: a copy of `@outer` that holds the captures of `@inner` in place
 * of the closure and calls the code of `@inner` directly. One object is built instead of two, and the call is no
 * longer indirect, so the inline pass can open it. */

#include "compiler/opt/opt_inline_closure.h"

typedef struct CfUse {
  MirValue value;
  bool used;
} CfUse;

static void cf_term(void *ctx, MirValue v) {
  CfUse *u = ctx;
  u->used = u->used || v == u->value;
}

/* The value of capture `k` in closure code `w` when it is read once and used only as the callee of `call.ind`;
 * MIR_NONE otherwise. */
static MirValue cf_called_capture(const MirFunc *w, uint32_t k) {
  MirValue cap = MIR_NONE;
  for (uint32_t b = 0; b < w->blocks.len; b++) {
    for (uint32_t i = 0; i < w->blocks.ptr[b].insts.len; i++) {
      const MirInst *in = &w->blocks.ptr[b].insts.ptr[i];
      if (in->op == MOP_ClosureCap && in->imm.tag == MI_IDX && in->imm.a == k && in->res != MIR_NONE) {
        if (cap != MIR_NONE) {
          return MIR_NONE;
        }
        cap = in->res;
      }
    }
  }
  if (cap == MIR_NONE) {
    return MIR_NONE;
  }
  CfUse use = {.value = cap};
  for (uint32_t b = 0; b < w->blocks.len && !use.used; b++) {
    for (uint32_t i = 0; i < w->blocks.ptr[b].insts.len; i++) {
      const MirInst *in = &w->blocks.ptr[b].insts.ptr[i];
      for (uint32_t a = 0; a < in->nargs; a++) {
        use.used = use.used || (in->args[a] == cap && !(in->op == MOP_CallInd && a == 0));
      }
    }
    mir_term_each_value(&w->blocks.ptr[b].term, cf_term, &use);
  }
  return use.used ? MIR_NONE : cap;
}

/* Per function: whether anything but a `closure.new` names it. Such a use (a comparison thunk a sort was already
 * specialised with, a direct call an earlier round made) runs the code over the closure's environment, so the
 * closure must keep that code and its capture layout. */
static bool *cf_named_elsewhere(MsArena *arena, const MirModule *m) {
  bool *named = MS_ARENA_NEW_ARRAY(arena, bool, m->funcs.len + 1);
  __builtin_memset(named, 0, m->funcs.len + 1);
  for (uint32_t fi = 0; fi < m->funcs.len; fi++) {
    const MirFunc *f = &m->funcs.ptr[fi];
    for (uint32_t b = 0; b < f->blocks.len; b++) {
      for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
        const MirInst *in = &f->blocks.ptr[b].insts.ptr[i];
        if (in->imm.tag == MI_FUNC && in->op != MOP_ClosureNew && in->imm.a < m->funcs.len) {
          named[in->imm.a] = true;
        }
      }
    }
  }
  return named;
}

/* Whether closure code `w` can take the captures of closure code `c` in place of its capture `k`. The wrapper is
 * copied once per inner closure, so only a small one is. */
static bool cf_fusable(const MirFunc *w, const MirFunc *c, uint32_t k) {
  return w != c && w->kind == MFK_CLOSURE && c->kind == MFK_CLOSURE && k < w->ncaptures && w->ncapture_closers == 0 &&
         c->ncapture_closers == 0 && mir_inst_count(w) <= OPT_INLINE_SPECIALIZE_MAX_SIZE && ic_closure_usable(w) && !opt_inline_cancel_mismatch(w, c) &&
         cf_called_capture(w, k) != MIR_NONE;
}

/* The instructions of block `b` of the fused copy: captures after `k` move up by `grow`, the read of capture `k`
 * becomes reads of the inner captures into `inner`, and a call of `cap` becomes a call of `plain` over them. */
static void cf_rewrite_block(MirModule *m, MsArena *scratch, MirBlockData *b, uint32_t k, uint32_t n, MirValue cap,
                             const MirValue *inner, uint32_t plain) {
  OptInstVec out = {0};
  for (uint32_t i = 0; i < b->insts.len; i++) {
    MirInst in = b->insts.ptr[i];
    const bool reads = in.op == MOP_ClosureCap && in.imm.tag == MI_IDX && in.res != MIR_NONE;
    if (reads && in.imm.a == k) {
      for (uint32_t j = 0; j < n; j++) {
        const MirInst read = opt_inst_make(m, MOP_ClosureCap, in.args, 1, (MirImm){.tag = MI_IDX, .a = k + j}, inner[j], in.loc);
        opt_inst_vec_push(scratch, &out, &read);
      }
      continue;
    }
    if (reads && in.imm.a > k) {
      in.imm.a += n - 1;
    }
    if (in.op == MOP_CallInd && in.nargs > 0 && in.args[0] == cap) {
      MirValue *args = MS_ARENA_NEW_ARRAY(&m->arena, MirValue, (size_t)n + in.nargs);
      for (uint32_t j = 0; j < n; j++) {
        args[j] = inner[j];
      }
      for (uint32_t a = 1; a < in.nargs; a++) {
        args[n + a - 1] = in.args[a];
      }
      in.op = MOP_Call;
      in.imm = (MirImm){.tag = MI_FUNC, .a = plain};
      in.args = args;
      in.nargs = n + in.nargs - 1;
    }
    opt_inst_vec_push(scratch, &out, &in);
  }
  opt_block_set_insts(b, out.v, out.n);
}

/* Adds the copy of closure code `wi` fused with closure code `ci` at capture `k`; MIR_NONE when the inner code
 * cannot run as a plain function. */
static uint32_t cf_fuse(MirModule *m, uint32_t wi, uint32_t ci, uint32_t k) {
  MirFunc body;
  if (!ic_closure_body(m, &m->funcs.ptr[ci], &body)) {
    return MIR_NONE;
  }
  body.kind = MFK_NORMAL;
  const uint32_t plain = mir_add_func(m, &body);
  const MirFunc *w = &m->funcs.ptr[wi];
  const MirFunc *c = &m->funcs.ptr[ci];
  const uint32_t n = c->ncaptures;
  const MirValue cap = cf_called_capture(w, k);
  MirFunc out;
  opt_func_deep_clone(m, w, &out);
  MirTy *captures = MS_ARENA_NEW_ARRAY(&m->arena, MirTy, (size_t)w->ncaptures + n);
  for (uint32_t j = 0; j < k; j++) {
    captures[j] = w->captures[j];
  }
  for (uint32_t j = 0; j < n; j++) {
    captures[k + j] = c->captures[j];
  }
  for (uint32_t j = k + 1; j < w->ncaptures; j++) {
    captures[n + j - 1] = w->captures[j];
  }
  out.captures = captures;
  out.ncaptures = w->ncaptures - 1 + n;
  /* The copy keeps the wrapper's `scoped` flags: the inner captures are plain data, which no flag changes how to
   * pass or drop, and the wrapper is still the closure its maker hands on. */
  MsArena scratch = ms_arena_new();
  MirValue *inner = MS_ARENA_NEW_ARRAY(&scratch, MirValue, (size_t)n + 1);
  for (uint32_t j = 0; j < n; j++) {
    inner[j] = mir_new_value(&out, c->captures[j]);
  }
  for (uint32_t b = 0; b < out.blocks.len; b++) {
    cf_rewrite_block(m, &scratch, &out.blocks.ptr[b], k, n, cap, inner, plain);
  }
  ms_arena_free(&scratch);
  return mir_add_func(m, &out);
}

/* Fused copies already made: (outer, inner, capture) -> copy. */
typedef struct CfMade {
  uint32_t *outer, *inner, *capture, *copy;
  uint32_t n, cap;
  const bool *named; /* cf_named_elsewhere, for the functions the module had when the pass began */
  uint32_t nnamed;
} CfMade;

static uint32_t cf_copy(MirModule *m, MsArena *arena, CfMade *made, uint32_t wi, uint32_t ci, uint32_t k) {
  for (uint32_t i = 0; i < made->n; i++) {
    if (made->outer[i] == wi && made->inner[i] == ci && made->capture[i] == k) {
      return made->copy[i];
    }
  }
  const uint32_t copy = cf_fuse(m, wi, ci, k);
  if (made->n == made->cap) {
    uint32_t cap = made->cap;
    made->outer = opt_grow(arena, made->outer, made->n, &cap, sizeof(uint32_t));
    cap = made->cap;
    made->inner = opt_grow(arena, made->inner, made->n, &cap, sizeof(uint32_t));
    cap = made->cap;
    made->capture = opt_grow(arena, made->capture, made->n, &cap, sizeof(uint32_t));
    made->copy = opt_grow(arena, made->copy, made->n, &made->cap, sizeof(uint32_t));
  }
  made->outer[made->n] = wi;
  made->inner[made->n] = ci;
  made->capture[made->n] = k;
  made->copy[made->n++] = copy;
  return copy;
}

/* Fuses the first known closure the `closure.new` at (`bi`, `ii`) of function `fi` captures; false when none. */
static bool cf_fuse_at(MirModule *m, MsArena *arena, CfMade *made, const IcKnown *known, uint32_t fi, uint32_t bi,
                       uint32_t ii) {
  const MirInst *at = &m->funcs.ptr[fi].blocks.ptr[bi].insts.ptr[ii];
  const uint32_t wi = at->imm.a;
  for (uint32_t k = 0; k < at->nargs; k++) {
    const MirValue captured = at->args[k];
    if (!ic_known_has(known, captured)) {
      continue;
    }
    const uint32_t ci = known->code[captured];
    if (wi == fi || ci == fi || wi >= made->nnamed || made->named[wi] || !cf_fusable(&m->funcs.ptr[wi], &m->funcs.ptr[ci], k)) {
      continue;
    }
    const uint32_t copy = cf_copy(m, arena, made, wi, ci, k);
    if (copy == MIR_NONE) {
      continue;
    }
    MirInst *in = &m->funcs.ptr[fi].blocks.ptr[bi].insts.ptr[ii]; /* the function list may have moved */
    const uint32_t n = known->ncaps[captured];
    MirValue *args = MS_ARENA_NEW_ARRAY(&m->arena, MirValue, (size_t)in->nargs + n);
    for (uint32_t j = 0; j < k; j++) {
      args[j] = in->args[j];
    }
    for (uint32_t j = 0; j < n; j++) {
      args[k + j] = known->caps[captured][j];
    }
    for (uint32_t j = k + 1; j < in->nargs; j++) {
      args[n + j - 1] = in->args[j];
    }
    in->args = args;
    in->nargs = in->nargs - 1 + n;
    in->imm.a = copy;
    return true;
  }
  return false;
}

static bool cf_fuse_in(MirModule *m, MsArena *arena, CfMade *made, uint32_t fi) {
  const IcKnown known = ic_known_aliased(arena, m, &m->funcs.ptr[fi]);
  if (known.count == 0) {
    return false;
  }
  bool changed = false;
  for (uint32_t b = 0; b < m->funcs.ptr[fi].blocks.len; b++) {
    for (uint32_t i = 0; i < m->funcs.ptr[fi].blocks.ptr[b].insts.len; i++) {
      const MirInst *in = &m->funcs.ptr[fi].blocks.ptr[b].insts.ptr[i];
      /* Again after each fusion: the copy may capture another known closure. */
      while (in->op == MOP_ClosureNew && in->imm.tag == MI_FUNC && in->res != MIR_NONE &&
             cf_fuse_at(m, arena, made, &known, fi, b, i)) {
        changed = true;
        in = &m->funcs.ptr[fi].blocks.ptr[b].insts.ptr[i];
      }
    }
  }
  if (changed) {
    (void)ic_delete_unused(m, fi); /* the inner closures nothing else uses */
  }
  return changed;
}

bool opt_inline_fuse_captured(MirModule *m) {
  MsArena arena = ms_arena_new();
  CfMade made = {.named = cf_named_elsewhere(&arena, m), .nnamed = (uint32_t)m->funcs.len};
  bool changed = false;
  const uint32_t count = (uint32_t)m->funcs.len; /* the copies made here capture nothing known */
  for (uint32_t fi = 0; fi < count; fi++) {
    changed |= cf_fuse_in(m, &arena, &made, fi);
  }
  ms_arena_free(&arena);
  return changed;
}
