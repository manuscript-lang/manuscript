/* opt_unwind_sites: a test of the `unwinding` byte is always clear when no call that can park ran since the last test.
 *
 * A cancel is delivered only inside a park (`ms_cancel_deliver`), so the byte test is needed only when a call that can
 * reach a cancellation point ran since the previous test, on some path to it. Elsewhere the test becomes the constant
 * zero, and the simplifier removes the branch and the exit it guarded. Inlining leaves such tests behind: the call
 * they guarded became an operation (`list.push`) or a body with no parking call. */
#include "compiler/mir/mir_pass.h"
#include "compiler/opt/opt_pass.h"
#include "compiler/opt/opt_util.h"
#include <stdlib.h>

/* Whether `inst` is the byte test of an unwind site. */
static bool is_site_test(const MirModule *m, const MirInst *inst) {
  return inst->op == MOP_CallRt && inst->imm.tag == MI_EXT && m->externs.ptr[inst->imm.a].role == MR_UNWINDING;
}

/* Whether `inst` may reach a cancellation point and then continue, so that the byte can be set after it. A fault site
 * leaves by its exit as a cancel does, so it counts only on that edge (`pending_after`). */
static bool parks_and_continues(const MirModule *m, const bool *parks, const MirInst *inst) {
  return inst->op != MOP_FaultSite && mir_inst_parks(m, parks, inst);
}

/* The state at the end of block `b` that flows along its edges: whether a call that can park ran since the last test of
 * the byte. `fault` is the state along the edge a fault site takes, `normal` along the other edge. */
typedef struct SiteState {
  bool normal, fault;
} SiteState;

static SiteState walk_block(const MirModule *m, const bool *parks, MirFunc *f, size_t bi, bool entry, bool rewrite,
                            bool *changed) {
  MirInstList *insts = &f->blocks.ptr[bi].insts;
  bool pending = entry;
  bool faulted = false;
  MirValue site = MIR_NONE;
  for (size_t k = 0; k < insts->len; k++) {
    MirInst *inst = &insts->ptr[k];
    if (is_site_test(m, inst)) {
      if (rewrite && !pending && !faulted) {
        inst->op = MOP_BConst;
        inst->imm = (MirImm){.tag = MI_BOOL, .a = 0};
        *changed = true;
      }
      pending = false;
      faulted = false;
      site = MIR_NONE;
    } else if (inst->op == MOP_FaultSite) {
      faulted = true;
      site = inst->res;
    } else if (parks_and_continues(m, parks, inst)) {
      pending = true;
    }
  }
  const MirTerm *term = &f->blocks.ptr[bi].term;
  const bool on_fault_site = term->kind == MT_CONDBR && site != MIR_NONE && term->value == site;
  return (SiteState){.normal = pending || (faulted && !on_fault_site), .fault = pending || faulted};
}

bool opt_unwind_sites(MirModule *m) {
  MsArena arena = ms_arena_new();
  const bool *parks = mir_parking_funcs(&arena, m);
  bool changed = false;
  for (size_t fi = 0; fi < m->funcs.len; fi++) {
    MirFunc *f = &m->funcs.ptr[fi];
    bool *entry = MS_ARENA_NEW_ARRAY(&arena, bool, f->blocks.len + 1);
    for (size_t at = 0; at < f->blocks.len; at++) {
      entry[at] = false;
    }
    for (bool moved = true; moved;) { /* the states flow along edges until nothing changes */
      moved = false;
      for (size_t bi = 0; bi < f->blocks.len; bi++) {
        const SiteState out = walk_block(m, parks, f, bi, entry[bi], false, &changed);
        const MirTerm *term = &f->blocks.ptr[bi].term;
        for (uint32_t k = 0; k < mir_term_ntargets(term); k++) {
          const MirBlock to = mir_term_target_const(term, k)->block;
          const bool pending = term->kind == MT_CONDBR && k == 1 ? out.normal : out.fault;
          if (pending && !entry[to]) {
            entry[to] = true;
            moved = true;
          }
        }
      }
    }
    for (size_t bi = 0; bi < f->blocks.len; bi++) {
      (void)walk_block(m, parks, f, bi, entry[bi], true, &changed);
    }
  }
  ms_arena_free(&arena);
  return changed;
}

/* Whether `inst` is the call of the runtime function named `name`, as the interned `want` (MS_NAME_EMPTY when the
 * module has none). */
static bool calls_named(const MirModule *m, const MirInst *inst, MsName want) {
  return want != MS_NAME_EMPTY && inst->op == MOP_CallRt && inst->imm.tag == MI_EXT && m->externs.ptr[inst->imm.a].name == want;
}

/* Whether `b` is an exit that closes nothing: cold, no parameters, and only an undefined result to return. */
static bool bare_exit(const MirFunc *f, const MirBlockData *b) {
  if (!b->cold || b->params.len != 0 || b->term.kind != MT_RET || b->insts.len > 1) {
    return false;
  }
  if (b->insts.len == 0) {
    return b->term.value == MIR_NONE;
  }
  return b->insts.ptr[0].op == MOP_Undef && b->insts.ptr[0].res == b->term.value && f->ret != MIR_VOID;
}

/* The exits of a function that close nothing are one block: edges go to the first of them. One sweep over the
 * edges serves every exit; a sweep per exit made a function with many fallible calls quadratic. */
static bool share_exits(MirFunc *f) {
  MirBlock canonical = MIR_NONE;
  MsArena arena = ms_arena_new();
  bool *shared = MS_ARENA_NEW_ARRAY(&arena, bool, f->blocks.len);
  for (size_t bi = 0; bi < f->blocks.len; bi++) {
    if (!bare_exit(f, &f->blocks.ptr[bi])) {
      continue;
    }
    if (canonical == MIR_NONE) {
      canonical = (MirBlock)bi;
    } else {
      shared[bi] = true;
    }
  }
  bool changed = false;
  for (size_t pi = 0; canonical != MIR_NONE && pi < f->blocks.len; pi++) {
    MirTerm *term = &f->blocks.ptr[pi].term;
    for (uint32_t k = 0; k < mir_term_ntargets(term); k++) {
      MirTarget *edge = mir_term_target(term, k);
      if (shared[edge->block] && edge->nargs == 0 && pi != edge->block) {
        edge->block = canonical;
        changed = true;
      }
    }
  }
  ms_arena_free(&arena);
  return changed;
}

/* An exit's closing work: what its edges run before leaving, apart from bookkeeping that emits nothing. */
enum { TAIL_MAX_INSTS = 32 };

static bool is_closing(const MirModule *m, const MirInst *inst, MsName pause, MsName resume) {
  return inst->op == MOP_Drop || inst->op == MOP_DropIf || calls_named(m, inst, pause) || calls_named(m, inst, resume);
}

static bool is_bookkeeping(const MirInst *inst) {
  return inst->op == MOP_Forget || inst->op == MOP_Undef;
}

/* Whether `b` is an unwinding exit made of bookkeeping and closing work only, going on without arguments (the `pause`
 * marks it: nothing else sets the byte aside); fills `closing` with the indices of the closing instructions. A closing
 * operand defined in the block would not be the same value in another block, so such a block is not shareable. The
 * flag `cold` is not asked for: inlining and threading copy exits into blocks that lost it. */
static bool tail_exit(const MirModule *m, const MirBlockData *b, MsName pause, MsName resume, uint32_t *closing,
                      uint32_t *nclosing) {
  const bool leaves = (b->term.kind == MT_BR && b->term.a.nargs == 0) || (b->term.kind == MT_RET && b->term.value == MIR_NONE);
  if (b->params.len != 0 || !leaves || b->insts.len > TAIL_MAX_INSTS) {
    return false;
  }
  *nclosing = 0;
  bool paused = false;
  for (uint32_t k = 0; k < b->insts.len; k++) {
    const MirInst *inst = &b->insts.ptr[k];
    if (is_bookkeeping(inst)) {
      continue;
    }
    if (!is_closing(m, inst, pause, resume)) {
      return false;
    }
    paused = paused || calls_named(m, inst, pause);
    for (uint32_t a = 0; a < inst->nargs; a++) {
      for (uint32_t d = 0; d < k; d++) {
        if (b->insts.ptr[d].res == inst->args[a] && inst->args[a] != MIR_NONE) {
          return false;
        }
      }
    }
    closing[(*nclosing)++] = k;
  }
  return paused;
}

static uint64_t tail_hash(const MirBlockData *b, const uint32_t *closing, uint32_t nclosing) {
  uint64_t h = (uint64_t)b->term.kind * 0x9e3779b97f4a7c15ull + (b->term.kind == MT_BR ? b->term.a.block : 0);
  for (uint32_t c = 0; c < nclosing; c++) {
    const MirInst *inst = &b->insts.ptr[closing[c]];
    h = (h ^ inst->op) * 0x100000001b3ull;
    h = (h ^ inst->imm.a) * 0x100000001b3ull;
    for (uint32_t a = 0; a < inst->nargs; a++) {
      h = (h ^ inst->args[a]) * 0x100000001b3ull;
    }
  }
  return h;
}

static bool tail_same(const MirBlockData *x, const uint32_t *xc, uint32_t nx, const MirBlockData *y, const uint32_t *yc,
                      uint32_t ny) {
  if (nx != ny || x->term.kind != y->term.kind || (x->term.kind == MT_BR && x->term.a.block != y->term.a.block)) {
    return false;
  }
  for (uint32_t c = 0; c < nx; c++) {
    const MirInst *p = &x->insts.ptr[xc[c]], *q = &y->insts.ptr[yc[c]];
    if (p->op != q->op || p->nargs != q->nargs || p->imm.tag != q->imm.tag || p->imm.a != q->imm.a ||
        p->imm.b != q->imm.b || p->imm.c != q->imm.c || p->imm.i != q->imm.i) {
      return false;
    }
    for (uint32_t a = 0; a < p->nargs; a++) {
      if (p->args[a] != q->args[a]) {
        return false;
      }
    }
  }
  return true;
}

typedef struct TailClosing {
  uint32_t at[TAIL_MAX_INSTS];
} TailClosing;

typedef struct TailKey {
  uint64_t hash;
  uint32_t block;
} TailKey;

static int tail_key_cmp(const void *x, const void *y) {
  const TailKey *p = x, *q = y;
  if (p->hash != q->hash) {
    return p->hash < q->hash ? -1 : 1;
  }
  return p->block < q->block ? -1 : p->block > q->block;
}

/* Exits that close the same values the same way share the closing work: inlining copies a callee's exit into every
 * call site, and a function with n calls then holds n copies of the same drops, which LLVM's value numbering walks once
 * per copy. Each such exit keeps its bookkeeping and goes on to one block that runs the closing work. */
static bool share_tails(const MirModule *m, MirFunc *f, MsName pause, MsName resume) {
  MsArena arena = ms_arena_new();
  const size_t count = f->blocks.len;
  TailKey *keys = MS_ARENA_NEW_ARRAY(&arena, TailKey, count + 1);
  TailClosing *closing = MS_ARENA_NEW_ARRAY(&arena, TailClosing, count + 1);
  uint32_t *nclosing = MS_ARENA_NEW_ARRAY(&arena, uint32_t, count + 1);
  size_t nkeys = 0;
  for (size_t bi = 0; bi < count; bi++) {
    const MirBlockData *b = &f->blocks.ptr[bi];
    if (tail_exit(m, b, pause, resume, closing[bi].at, &nclosing[bi])) {
      keys[nkeys++] = (TailKey){tail_hash(b, closing[bi].at, nclosing[bi]), (uint32_t)bi};
    }
  }
  qsort(keys, nkeys, sizeof keys[0], tail_key_cmp);
  bool changed = false;
  for (size_t at = 0; at < nkeys;) {
    size_t end = at + 1;
    while (end < nkeys && keys[end].hash == keys[at].hash) {
      end++;
    }
    const uint32_t first = keys[at].block;
      MirBlock shared = MIR_NONE;
    for (size_t k = at + 1; k < end; k++) {
      const uint32_t other = keys[k].block;
      if (!tail_same(&f->blocks.ptr[first], closing[first].at, nclosing[first], &f->blocks.ptr[other], closing[other].at, nclosing[other])) {
        continue;
      }
      if (shared == MIR_NONE) {
        shared = mir_new_block(f);
        MirBlockData *s = &f->blocks.ptr[shared];
        const MirBlockData *head = &f->blocks.ptr[first];
        s->cold = true;
        s->term = head->term;
        s->term_loc = head->term_loc;
        for (uint32_t c = 0; c < nclosing[first]; c++) {
          mir_block_insert(s, (uint32_t)s->insts.len, &head->insts.ptr[closing[first].at[c]]);
        }
      }
      MirBlockData *b = &f->blocks.ptr[other];
      size_t out = 0;
      for (uint32_t k2 = 0; k2 < b->insts.len; k2++) {
        if (is_bookkeeping(&b->insts.ptr[k2])) {
          b->insts.ptr[out++] = b->insts.ptr[k2];
        }
      }
      b->insts.len = out;
      opt_term_set_br(&b->term, (MirTarget){shared, NULL, 0});
      changed = true;
    }
    if (shared != MIR_NONE) {
      MirBlockData *b = &f->blocks.ptr[first];
      size_t out = 0;
      for (uint32_t k2 = 0; k2 < b->insts.len; k2++) {
        if (is_bookkeeping(&b->insts.ptr[k2])) {
          b->insts.ptr[out++] = b->insts.ptr[k2];
        }
      }
      b->insts.len = out;
      opt_term_set_br(&b->term, (MirTarget){shared, NULL, 0});
    }
    at = end;
  }
  ms_arena_free(&arena);
  return changed;
}

bool opt_unwind_pairs(MirModule *m) {
  MsName pause = MS_NAME_EMPTY, resume = MS_NAME_EMPTY;
  if (!ms_names_find(&m->names, ms_span_of_text("msrt_unwinding_pause"), &pause) ||
    !ms_names_find(&m->names, ms_span_of_text("msrt_unwinding_resume"), &resume)) {
    return false;
  }
  bool changed = false;
  for (size_t fi = 0; fi < m->funcs.len; fi++) {
    MirFunc *f = &m->funcs.ptr[fi];
    for (size_t bi = 0; bi < f->blocks.len; bi++) {
      MirInstList *insts = &f->blocks.ptr[bi].insts;
      size_t out = 0;
      for (size_t k = 0; k < insts->len; k++) {
        if (k + 1 < insts->len && calls_named(m, &insts->ptr[k], pause) && calls_named(m, &insts->ptr[k + 1], resume)) {
          k++; /* nothing runs between them: the byte is set aside and put back untouched */
          changed = true;
          continue;
        }
        insts->ptr[out++] = insts->ptr[k];
      }
      insts->len = out;
    }
    changed = share_exits(f) || changed;
  }
  return changed;
}

bool opt_unwind_tails(MirModule *m) {
  MsName pause = MS_NAME_EMPTY, resume = MS_NAME_EMPTY;
  if (!ms_names_find(&m->names, ms_span_of_text("msrt_unwinding_pause"), &pause) ||
    !ms_names_find(&m->names, ms_span_of_text("msrt_unwinding_resume"), &resume)) {
    return false;
  }
  bool changed = false;
  for (size_t fi = 0; fi < m->funcs.len; fi++) {
    changed = share_tails(m, &m->funcs.ptr[fi], pause, resume) || changed;
  }
  return changed;
}
