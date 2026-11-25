/* opt_unwind_sites: a test of the `unwinding` byte is always clear when no call that can park ran since the last test.
 *
 * A cancel is delivered only inside a park (`ms_cancel_deliver`), so the byte test is needed only when a call that can
 * reach a cancellation point ran since the previous test, on some path to it. Elsewhere the test becomes the constant
 * zero, and the simplifier removes the branch and the exit it guarded. Inlining leaves such tests behind: the call
 * they guarded became an operation (`list.push`) or a body with no parking call. */
#include "compiler/mir/mir_pass.h"
#include "compiler/opt/opt_pass.h"

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
