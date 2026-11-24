/* Owns how a block ends: the edges and their phis, returns, switches and faults. */
#include "compiler/emit/emit_func.h"

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
bool emit_edge_repeats(const MirTerm *term, uint32_t index) {
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
    ms_strbuild_printf(out, "%%b%u", emit_edge(term, index)->block);
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
    ms_strbuild_printf(out, "  br label %%b%u\n", term->a.block);
    return true;
  case MT_CONDBR:
    ms_strbuild_printf(out, "  br i1 %%v%u, label ", term->value);
    edge_label(cx, out, term, from, 0);
    ms_strbuild_append_text(out, ", label ");
    edge_label(cx, out, term, from, 1);
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
      ms_strbuild_printf(cx->out, "  br label %%b%u\n", emit_edge(term, index)->block);
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
  for (uint32_t source = 0; source < func->blocks.len; source++) {
    const MirTerm *term = &func->blocks.ptr[source].term;
    for (uint32_t edge = 0; edge < emit_edge_count(term); edge++) {
      const MirTarget *target = emit_edge(term, edge);
      if (target->block != block) {
        continue;
      }
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
