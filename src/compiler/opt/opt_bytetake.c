/* The `bytetake` pass: a derived result of a value that dies at the call reuses its storage.
 *
 * `r = f(b, .., out); ...; drop b` copies `b` into a new allocation and then frees it. When `b` is owned, is only dropped
 * after the call and the call dominates those drops, and `f` has a sibling `f_take` (the `MR_TAKES_DYING` role, set from
 * the signatures), the call becomes the twin, which moves `b` in and builds the result in the same allocation, so the
 * drops disappear. A take of a dying value is a move, so nothing observable changes. */

#include "compiler/mir/mir_analysis.h"
#include "compiler/opt/opt_pass.h"
#include "base/safe.h"

/* A call that can become its take twin, and the drops of its receiver that go with it (every drop the call reaches). */
typedef struct TakeSite {
  MirBlock block;
  uint32_t call, ext;
  uint32_t first_drop, ndrops; /* a range of `TakeDrops::at` */
} TakeSite;

typedef struct DropAt {
  MirBlock block;
  uint32_t index;
} DropAt;

/* The twin of runtime function `ext`: the same signature with the first argument moved in, named
 * `<name>_take`. */
static uint32_t take_twin(MirModule *m, uint32_t ext) {
  MirExtern def = m->externs.ptr[ext];
  def.name = mir_name_suffixed(m, def.name, ms_span_of_text("_take"));
  MirParam *params = MS_ARENA_NEW_ARRAY(&m->arena, MirParam, def.nparams);
  __builtin_memcpy(params, def.params, sizeof(MirParam) * def.nparams);
  params[0].mode = MM_MOVE;
  def.params = params;
  def.role = MR_NONE;
  return mir_extern_intern(m, &def);
}

/* Marks the blocks reachable from the successors of `from` (`from` itself when it lies on a cycle). `stack` has a slot per
 * block. */
static void mark_reached(const MirFunc *f, MirBlock from, bool *reached, MirBlock *stack) {
  size_t top = 0;
  stack[top++] = from;
  while (top > 0) {
    const MirTerm *term = &f->blocks.ptr[stack[--top]].term;
    for (uint32_t k = 0; k < mir_term_ntargets(term); k++) {
      const MirBlock to = mir_term_target_const(term, k)->block;
      if (!reached[to]) {
        reached[to] = true;
        stack[top++] = to;
      }
    }
  }
}

typedef struct UseScan {
  MirValue value;
  bool found;
} UseScan;

static void note_use(void *context, MirValue value) {
  UseScan *scan = context;
  scan->found = scan->found || value == scan->value;
}

static bool uses_value(const MirInst *inst, MirValue v) {
  for (uint32_t k = 0; k < inst->nargs; k++) {
    if (inst->args[k] == v) {
      return true;
    }
  }
  return false;
}

/* Whether the call at `(block, index)` has run before the instruction at `(at_block, at_index)` on some path. */
static bool after_call(const bool *reached, MirBlock block, uint32_t index, MirBlock at_block, uint32_t at_index) {
  return reached[at_block] || (at_block == block && at_index > index);
}

/* Finds the takes of one function: a call of a runtime function with a `_take` twin whose receiver `v` is an owned value
 * that the call leaves dying. After the call `v` is only dropped, by drops that the call dominates, so every path that ran the
 * call frees `v` there and no other path does. Before it `v` is only read for a number or a flag, so nothing views it. The
 * twin takes `v` in, and those drops go. */
static uint32_t find_take_sites(MsArena *arena, const MirModule *m, const MirFunc *f, TakeSite **out, DropAt **drops_out) {
  const MirBits owned = mir_owned_values(arena, m, f, true);
  MirBlock *order = NULL;
  const uint32_t reachable = mir_rpo(arena, f, &order);
  const MirPreds preds = mir_preds(arena, f);
  const MirBlock *idom = mir_dominators(arena, f, order, reachable, &preds);
  const MirDomTree tree = mir_dom_tree(arena, f, order, reachable, idom);
  const uint32_t insts_total = mir_inst_count(f);
  TakeSite *sites = MS_ARENA_NEW_ARRAY(arena, TakeSite, insts_total + 1);
  DropAt *drops = MS_ARENA_NEW_ARRAY(arena, DropAt, insts_total + 1);
  bool *reached = MS_ARENA_NEW_ARRAY(arena, bool, f->blocks.len + 1);
  MirBlock *stack = MS_ARENA_NEW_ARRAY(arena, MirBlock, f->blocks.len + 1);
  uint32_t count = 0, ndrops = 0;
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    const MirInstList *insts = &f->blocks.ptr[b].insts;
    for (uint32_t i = 0; i < insts->len; i++) {
      const MirInst *call = &insts->ptr[i];
      if (call->op != MOP_CallRt || call->imm.tag != MI_EXT || call->nargs == 0 ||
          m->externs.ptr[call->imm.a].role != MR_TAKES_DYING || !mir_bits_test(&owned, call->args[0]) ||
          tree.idom[b] == MIR_NONE) {
        continue;
      }
      const MirValue v = call->args[0];
      bool again = false;
      for (uint32_t k = 1; k < call->nargs; k++) {
        again = again || call->args[k] == v;
      }
      for (uint32_t k = 0; k < f->blocks.len; k++) {
        reached[k] = false;
      }
      mark_reached(f, b, reached, stack);
      const uint32_t first = ndrops;
      bool ok = !again;
      for (uint32_t pb = 0; pb < f->blocks.len && ok; pb++) {
        const MirInstList *list = &f->blocks.ptr[pb].insts;
        for (uint32_t pi = 0; pi < list->len && ok; pi++) {
          const MirInst *use = &list->ptr[pi];
          if (!uses_value(use, v) || (pb == b && pi == i)) {
            continue;
          }
          const bool later = after_call(reached, b, i, pb, pi);
          if ((use->op == MOP_Drop && use->nargs == 1) || (use->op == MOP_DropIf && use->nargs == 2 && use->args[1] == v)) {
            if (later) {
              ok = pb == b ? pi > i : mir_tree_dominates(&tree, b, pb);
              drops[ndrops++] = (DropAt){pb, pi};
            }
          } else if (later) {
            ok = false;
          } else {
            ok = use->res == MIR_NONE || mir_is_scalar(m, f->values.ptr[use->res]);
          }
        }
        UseScan scan = {.value = v};
        mir_term_each_value(&f->blocks.ptr[pb].term, note_use, &scan);
        ok = ok && !scan.found;
      }
      if (!ok) {
        ndrops = first;
        continue;
      }
      sites[count++] = (TakeSite){b, i, call->imm.a, first, ndrops - first};
    }
  }
  *out = sites;
  *drops_out = drops;
  return count;
}

/* Removal wants ascending positions; sites arrive in scan order. */
static void sort_ascending(uint32_t *v, uint32_t n) {
  for (uint32_t i = 1; i < n; i++) {
    const uint32_t x = v[i];
    uint32_t k = i;
    for (; k > 0 && v[k - 1] > x; k--) {
      v[k] = v[k - 1];
    }
    v[k] = x;
  }
}

static void rewrite_takes(MirModule *m, MirFunc *f, MsArena *arena, const TakeSite *sites, uint32_t count,
                          const DropAt *drops) {
  for (uint32_t s = 0; s < count; s++) {
    const uint32_t twin = take_twin(m, sites[s].ext);
    MirImm *imm = &f->blocks.ptr[sites[s].block].insts.ptr[sites[s].call].imm;
    imm->a = twin;
  }
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    uint32_t *dead = MS_ARENA_NEW_ARRAY(arena, uint32_t, f->blocks.ptr[b].insts.len + 1);
    uint32_t ndead = 0;
    for (uint32_t s = 0; s < count; s++) {
      for (uint32_t d = sites[s].first_drop; d < sites[s].first_drop + sites[s].ndrops; d++) {
        if (drops[d].block == b) {
          dead[ndead++] = drops[d].index;
        }
      }
    }
    if (ndead == 0) {
      continue;
    }
    sort_ascending(dead, ndead);
    mir_block_remove(&f->blocks.ptr[b], dead, ndead);
  }
}

bool opt_bytetake(MirModule *m) {
  bool changed = false;
  for (uint32_t fi = 0; fi < m->funcs.len; fi++) {
    MsArena arena = ms_arena_new();
    TakeSite *sites = NULL;
    DropAt *drops = NULL;
    const uint32_t count = find_take_sites(&arena, m, &m->funcs.ptr[fi], &sites, &drops);
    if (count > 0) {
      rewrite_takes(m, &m->funcs.ptr[fi], &arena, sites, count, drops);
      changed = true;
    }
    ms_arena_free(&arena);
  }
  return changed;
}
