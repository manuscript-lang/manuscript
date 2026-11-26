/* Owns how a block ends: the edges and their phis, returns, switches and faults. */
#include "compiler/emit/emit_func.h"
#include "compiler/mir/mir_analysis.h"

/* `ret`: nothing, the one leaf, or the leaves written through the hidden result pointer. */
static void emit_return(EmitCx *cx, MirValue value) {
  uint32_t leaves = value == MIR_NONE ? 0 : (uint32_t)emit_value_leaves(cx, value).len;
  if (leaves == 0) {
    ms_strbuild_append_text(cx->out, "  ret void\n");
    return;
  }
  if (leaves == 1) {
    ms_strbuild_printf(cx->out, "  ret %s %%v%u\n", emit_value_register_type(cx, value), value);
    return;
  }
  if (!emit_wide_return(cx, value)) {
    emit_leaves_at(cx, value, "%sret", false);
  }
  ms_strbuild_append_text(cx->out, "  ret void\n");
}

/* The runtime function a `fault` terminator calls, and how many zero words it takes. */
typedef struct FaultCall {
  const char *name;
  uint32_t words;
  MirFault kind;
} FaultCall;

static const FaultCall fault_calls[] = {
    {"msrt_fault_posted", 0, MF_POSTED},
};

/* Whether `b` emits nothing: no parameters, only `forget`s (and undefined values only they read), and a branch without arguments to a block with no
 * parameters (so no phi names it as a predecessor). */
static bool writes_nothing(const MirFunc *f, const uint32_t *uses, uint32_t block) {
  const MirBlockData *b = &f->blocks.ptr[block];
  if (block == 0 || b->params.len != 0 || b->term.kind != MT_BR || b->term.a.nargs != 0 || b->term.a.block == block ||
      f->blocks.ptr[b->term.a.block].params.len != 0) {
    return false;
  }
  for (uint32_t k = 0; k < b->insts.len; k++) {
    const MirInst *inst = &b->insts.ptr[k];
    if (inst->op == MOP_Forget) {
      continue;
    }
    if (inst->op != MOP_Undef || inst->res == MIR_NONE) {
      return false;
    }
    /* An undefined value only the `forget`s of this block read is never written. */
    uint32_t forgets = 0;
    for (uint32_t q = k + 1; q < b->insts.len; q++) {
      forgets += b->insts.ptr[q].op == MOP_Forget && b->insts.ptr[q].args[0] == inst->res;
    }
    if (uses[inst->res] != forgets) {
      return false;
    }
  }
  return true;
}

void emit_plan_forwards(EmitCx *cx, MsArena *arena) {
  const MirFunc *f = cx->func;
  const uint32_t *uses = mir_use_counts(arena, f);
  MirBlock *forward = MS_ARENA_NEW_ARRAY(arena, MirBlock, f->blocks.len + 1);
  for (uint32_t block = 0; block < f->blocks.len; block++) {
    forward[block] = writes_nothing(f, uses, block) ? f->blocks.ptr[block].term.a.block : MIR_NONE;
  }
  cx->forward = forward;
}

uint32_t emit_block_target(const EmitCx *cx, uint32_t block) {
  /* A chain of such blocks is followed to its end; a cycle of them would never end, so the walk is bounded. */
  for (uint32_t steps = 0; cx->forward != NULL && cx->forward[block] != MIR_NONE && steps < cx->func->blocks.len; steps++) {
    block = cx->forward[block];
  }
  return block;
}

uint32_t emit_edge_count(const MirTerm *term) {
  switch ((MirTermKind)term->kind) {
  case MT_BR:
    return 1;
  case MT_CONDBR:
    return 2;
  case MT_SWITCH:
    return term->ncases + 1;
  default:
    return 0;
  }
}

const MirTarget *emit_edge(const MirTerm *term, uint32_t index) {
  if (term->kind == MT_SWITCH && index < term->ncases) {
    return &term->cases[index].target;
  }
  return index == 0 && term->kind != MT_SWITCH ? &term->a : &term->b;
}

/* Whether edge `index` goes to a block an earlier edge of `term` reaches. A phi needs one predecessor per
 * incoming value, so such an edge goes through a block of its own (`t<block>_<index>`) that branches on. */
static bool emit_edge_repeats(const MirTerm *term, uint32_t index) {
  for (uint32_t earlier = 0; earlier < index; earlier++) {
    if (emit_edge(term, earlier)->block == emit_edge(term, index)->block) {
      return true;
    }
  }
  return false;
}

/* Whether edge `index` goes through a block of its own (`t<block>_<index>`): it repeats a target, or it copies held
 * block parameters and must do so only when taken. */
static bool edge_split(const EmitCx *cx, const MirTerm *term, uint32_t index) {
  return emit_edge_repeats(term, index) || (term->kind != MT_BR && emit_wide_edge_copies(cx, term, index));
}

static void edge_label(const EmitCx *cx, MsStrBuild *out, const MirTerm *term, uint32_t from, uint32_t index) {
  if (edge_split(cx, term, index)) {
    ms_strbuild_printf(out, "%%t%u_%u", from, index);
  } else {
    ms_strbuild_printf(out, "%%b%u", emit_block_target(cx, emit_edge(term, index)->block));
  }
}

static void emit_switch(EmitCx *cx, const MirTerm *term, uint32_t from) {
  MsStrBuild *out = cx->out;
  ms_strbuild_printf(out, "  switch i64 %%v%u, label ", term->value);
  edge_label(cx, out, term, from, term->ncases);
  ms_strbuild_append_text(out, " [");
  for (uint32_t index = 0; index < term->ncases; index++) {
    ms_strbuild_printf(out, " i64 %lld, label ", (long long)term->cases[index].value);
    edge_label(cx, out, term, from, index);
  }
  ms_strbuild_append_text(out, " ]\n");
}

static bool emit_fault_term(EmitCx *cx, const MirTerm *term) {
  MsStrBuild *out = cx->out;
  if (term->fault == MF_UNREACHABLE) {
    ms_strbuild_append_text(out, "  unreachable\n");
    return true;
  }
  for (size_t index = 0; index < MS_COUNT_OF(fault_calls); index++) {
    if (fault_calls[index].kind != term->fault) {
      continue;
    }
    ms_strbuild_printf(out, "  call void @%s(", fault_calls[index].name);
    for (uint32_t word = 0; word < fault_calls[index].words; word++) {
      ms_strbuild_printf(out, "%si64 0", word == 0 ? "" : ", ");
    }
    ms_strbuild_append_text(out, ") nomerge\n  unreachable\n");
    return true;
  }
  cx->why = "fault with a message";
  return false;
}

bool emit_terminator(EmitCx *cx, const MirTerm *term, uint32_t from) {
  MsStrBuild *out = cx->out;
  switch ((MirTermKind)term->kind) {
  case MT_BR:
    if (emit_wide_edge_copies(cx, term, 0)) {
      emit_wide_copy_edge(cx, term, 0);
    }
    ms_strbuild_printf(out, "  br label %%b%u\n", emit_block_target(cx, term->a.block));
    return true;
  case MT_CONDBR:
    ms_strbuild_printf(out, "  br i1 %%v%u, label ", term->value);
    edge_label(cx, out, term, from, 0);
    ms_strbuild_append_text(out, ", label ");
    edge_label(cx, out, term, from, 1);
    {
      /* A branch to a block laid out of line (a grow, a cleanup) is unlikely, so LLVM places and allocates for the
       * other way. */
      const bool first_cold = cx->func->blocks.ptr[term->a.block].cold;
      const bool second_cold = cx->func->blocks.ptr[term->b.block].cold;
      if (first_cold != second_cold) {
        ms_strbuild_printf(out, ", !prof !%d", first_cold ? EMIT_PROF_FIRST_COLD : EMIT_PROF_SECOND_COLD);
      }
    }
    ms_strbuild_append_byte(out, '\n');
    return true;
  case MT_SWITCH:
    emit_switch(cx, term, from);
    return true;
  case MT_RET:
    emit_return(cx, term->value);
    return true;
  case MT_UNREACHABLE:
    ms_strbuild_append_text(out, "  unreachable\n");
    return true;
  case MT_FAULT:
    return emit_fault_term(cx, term);
  default:
    cx->why = "terminator";
    return false;
  }
}

/* The blocks that carry the repeated edges of `from`'s terminator. */
void emit_edge_blocks(EmitCx *cx, const MirTerm *term, uint32_t from) {
  for (uint32_t index = 0; index < emit_edge_count(term); index++) {
    if (edge_split(cx, term, index)) {
      ms_strbuild_printf(cx->out, "t%u_%u:\n", from, index);
      if (emit_wide_edge_copies(cx, term, index)) {
        emit_wide_copy_edge(cx, term, index);
      }
      ms_strbuild_printf(cx->out, "  br label %%b%u\n", emit_block_target(cx, emit_edge(term, index)->block));
    }
  }
}

/* One phi per leaf of block parameter `index` of block `block`, naming the last piece of each predecessor. */
static void phi_leaf(EmitCx *cx, uint32_t block, uint32_t index, uint32_t leaf, const uint32_t *last) {
  const MirFunc *func = cx->func;
  MsStrBuild *out = cx->out;
  MirValue param = func->blocks.ptr[block].params.ptr[index].value;
  const char *type = emit_leaf_type(emit_value_leaves(cx, param).ptr[leaf]);
  ms_strbuild_append_text(out, "  ");
  emit_name(out, param, leaf);
  ms_strbuild_printf(out, " = phi %s ", type);
  bool first = true;
  for (uint32_t at = cx->into_start[block]; at < cx->into_start[block + 1]; at++) {
    const uint32_t source = cx->into_from[at], edge = cx->into_edge[at];
    const MirTerm *term = &func->blocks.ptr[source].term;
    const MirTarget *target = emit_edge(term, edge);
    ms_strbuild_printf(out, "%s[ ", first ? "" : ", ");
    emit_name(out, target->args[index], leaf);
    ms_strbuild_append_text(out, ", %");
    if (edge_split(cx, term, edge)) {
      ms_strbuild_printf(out, "t%u_%u", source, edge);
    } else {
      emit_label(out, source, last[source]);
    }
    ms_strbuild_append_text(out, " ]");
    first = false;
  }
  ms_strbuild_append_byte(out, '\n');
}

void emit_phis(EmitCx *cx, uint32_t block, const uint32_t *last) {
  const MirBlockData *data = &cx->func->blocks.ptr[block];
  for (uint32_t index = 0; index < data->params.len; index++) {
    MirValue param = data->params.ptr[index].value;
    if (emit_wide_held(cx, param)) {
      continue; /* a cell, written on each edge */
    }
    uint32_t leaves = (uint32_t)emit_value_leaves(cx, param).len;
    for (uint32_t leaf = 0; leaf < leaves; leaf++) {
      phi_leaf(cx, block, index, leaf, last);
    }
  }
}

/* Hands LLVM the interval the range pass proved for each integer parameter of `block`. */
void emit_block_facts(EmitCx *cx, uint32_t block) {
  const MirFunc *func = cx->func;
  if (func->nfacts == 0) {
    return;
  }
  const MirBlockData *data = &func->blocks.ptr[block];
  for (uint32_t index = 0; index < data->params.len; index++) {
    const MirValue param = data->params.ptr[index].value;
    uint32_t lo = 0, hi = func->nfacts;
    while (lo < hi) {
      const uint32_t mid = (lo + hi) / 2;
      if (func->facts[mid].value < param) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo < func->nfacts && func->facts[lo].value == param) {
      emit_assume_range(cx, param, func->facts[lo].lo, func->facts[lo].hi);
    }
  }
}

void emit_index_edges(EmitCx *cx, MsArena *arena) {
  const MirFunc *func = cx->func;
  const uint32_t blocks = (uint32_t)func->blocks.len;
  uint32_t *start = MS_ARENA_NEW_ARRAY(arena, uint32_t, (size_t)blocks + 2);
  for (uint32_t source = 0; source < blocks; source++) {
    const MirTerm *term = &func->blocks.ptr[source].term;
    for (uint32_t edge = 0; edge < emit_edge_count(term); edge++) {
      start[emit_edge(term, edge)->block + 1]++;
    }
  }
  for (uint32_t block = 0; block < blocks; block++) {
    start[block + 1] += start[block];
  }
  uint32_t *fill = MS_ARENA_NEW_ARRAY(arena, uint32_t, (size_t)blocks + 1);
  uint32_t *from = MS_ARENA_NEW_ARRAY_UNINIT(arena, uint32_t, (size_t)start[blocks] + 1);
  uint32_t *which = MS_ARENA_NEW_ARRAY_UNINIT(arena, uint32_t, (size_t)start[blocks] + 1);
  for (uint32_t source = 0; source < blocks; source++) {
    const MirTerm *term = &func->blocks.ptr[source].term;
    for (uint32_t edge = 0; edge < emit_edge_count(term); edge++) {
      const uint32_t target = emit_edge(term, edge)->block;
      from[start[target] + fill[target]] = source;
      which[start[target] + fill[target]++] = edge;
    }
  }
  cx->into_start = start;
  cx->into_from = from;
  cx->into_edge = which;
}
