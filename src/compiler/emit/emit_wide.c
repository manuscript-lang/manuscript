/* compiler/emit/emit_wide.c: values of many leaves live in stack cells, not in registers.
 *
 * A value of more than `wide_leaves` leaves that anything reads is written to a cell where it is made, and each
 * instruction that reads it loads the leaves it names just before itself, under names of its own (`%u7_3_41`: leaf 3
 * of value 7 for instruction 41), so no leaf of it is live across an instruction. A block parameter has a cell of
 * its own and no phi: each edge copies the argument's cell into it. A parameter that arrives as an address is read
 * from that address. Cells that are never live together share storage (emit_slot_pool). */
#include "compiler/emit/emit_cx.h"
#include "compiler/emit/emit_func.h"

#include "base/alloc.h"
#include "base/fatal.h"
#include "compiler/mir/mir_analysis.h"
#include "compiler/mir/mir_pass.h"

struct EmitWide {
  bool *held;           /* by value: lives in a cell */
  bool *incoming;       /* by value: a parameter of the function that arrived as an address */
  uint32_t *leaf_base;  /* by value: first bit of its leaves in `needed` */
  uint64_t *needed;     /* a bit per leaf of each held value: read by the instruction being written */
  uint32_t *touched;    /* the values with a bit set */
  uint32_t ntouched;
  uint32_t seq;         /* the instruction being written, for the names of its loads */
  MirValue defining;    /* the value it makes: its names are definitions, not reads */
  bool loading;         /* writing the loads: names are not requests */
  uint32_t capacity;    /* entries of `touched` */
  bool *stored;         /* by value: its cell was written by the call that made it */
  MirValue moved;       /* the value whose leaves [moved_first, +moved_count) were just copied cell to cell */
  uint32_t moved_first;
  uint32_t moved_count;
};

static EmitWide *active; /* the function being written; the emitter writes one function at a time */

static bool wide_type(EmitCx *cx, MirTy type) {
  return cx->wide_leaves != 0 && emit_leaves(cx, type).len > cx->wide_leaves;
}

/* Marks the values that live in cells. `values` receives, per value, whether it needs one (parameters that arrive
 * as an address do not). Returns false when nothing is held. */
const bool *emit_wide_plan(EmitCx *cx, MsArena *arena) {
  const MirFunc *func = cx->func;
  active = NULL;
  cx->wide = NULL;
  if (cx->wide_leaves == 0) {
    return NULL;
  }
  const size_t count = func->values.len + 1;
  bool *wide = MS_ARENA_NEW_ARRAY(arena, bool, count);
  bool any = false;
  for (size_t value = 0; value < count; value++) {
    wide[value] = value < func->values.len && wide_type(cx, func->values.ptr[value]);
    any = any || wide[value];
  }
  if (!any) {
    return NULL;
  }
  EmitWide *plan = MS_ARENA_NEW(arena, EmitWide);
  plan->held = MS_ARENA_NEW_ARRAY(arena, bool, count);
  plan->incoming = MS_ARENA_NEW_ARRAY(arena, bool, count);
  plan->stored = MS_ARENA_NEW_ARRAY(arena, bool, count);
  plan->leaf_base = MS_ARENA_NEW_ARRAY(arena, uint32_t, count);
  bool *cells = MS_ARENA_NEW_ARRAY(arena, bool, count);
  for (size_t value = 0; value < count; value++) {
    plan->held[value] = plan->incoming[value] = cells[value] = plan->stored[value] = false;
  }
  plan->moved = MIR_NONE;
  /* Every parameter, and every value anything reads, is held. */
  for (uint32_t block = 0; block < func->blocks.len; block++) {
    const MirBlockData *data = &func->blocks.ptr[block];
    for (uint32_t param = 0; param < data->params.len; param++) {
      const MirValue value = data->params.ptr[param].value;
      if (wide[value]) {
        plan->held[value] = true;
        plan->incoming[value] = block == 0;
        cells[value] = block != 0;
      }
    }
  }
  for (uint32_t block = 0; block < func->blocks.len; block++) {
    const MirBlockData *data = &func->blocks.ptr[block];
    for (uint32_t index = 0; index < data->insts.len; index++) {
      const MirInst *inst = &data->insts.ptr[index];
      for (uint32_t arg = 0; arg < inst->nargs; arg++) {
        const MirValue value = inst->args[arg];
        if (wide[value] && !plan->held[value]) {
          plan->held[value] = cells[value] = true;
        }
      }
    }
    const MirTerm *term = &data->term;
    if ((term->kind == MT_RET || term->kind == MT_CONDBR || term->kind == MT_SWITCH) && term->value != MIR_NONE &&
        wide[term->value] && !plan->held[term->value]) {
      plan->held[term->value] = cells[term->value] = true;
    }
    for (uint32_t target = 0; target < mir_term_ntargets(term); target++) {
      const MirTarget *edge = mir_term_target_const(term, target);
      for (uint32_t arg = 0; arg < edge->nargs; arg++) {
        const MirValue value = edge->args[arg];
        if (wide[value] && !plan->held[value]) {
          plan->held[value] = cells[value] = true;
        }
      }
    }
  }
  uint32_t bits = 0;
  for (size_t value = 0; value < func->values.len; value++) {
    plan->leaf_base[value] = bits;
    if (plan->held[value]) {
      bits += (uint32_t)emit_leaves(cx, func->values.ptr[value]).len;
    }
  }
  plan->needed = MS_ARENA_NEW_ARRAY(arena, uint64_t, bits / 64 + 1);
  for (uint32_t word = 0; word <= bits / 64; word++) {
    plan->needed[word] = 0;
  }
  plan->capacity = (uint32_t)func->values.len + 1;
  plan->touched = MS_ARENA_NEW_ARRAY(arena, uint32_t, plan->capacity);
  cx->wide = plan;
  active = plan;
  return cells;
}

void emit_wide_end(EmitCx *cx) {
  cx->wide = NULL;
  active = NULL;
}

bool emit_wide_held(const EmitCx *cx, MirValue value) {
  return cx->wide != NULL && cx->wide->held[value];
}

/* The name of a leaf of a held value the instruction being written reads: loaded just before it. False for any other
 * leaf, including those of the value the instruction makes. */
bool emit_wide_name(MsStrBuild *out, MirValue value, uint32_t leaf) {
  EmitWide *plan = active;
  if (plan == NULL || !plan->held[value] || plan->defining == value) {
    return false;
  }
  if (!plan->loading) {
    const uint32_t bit = plan->leaf_base[value] + leaf;
    if ((plan->needed[bit / 64] >> (bit % 64) & 1) == 0) {
      plan->needed[bit / 64] |= (uint64_t)1 << (bit % 64);
      bool seen = false;
      for (uint32_t index = 0; index < plan->ntouched && !seen; index++) {
        seen = plan->touched[index] == value;
      }
      if (!seen && plan->ntouched < plan->capacity) {
        plan->touched[plan->ntouched++] = value;
      }
    }
  }
  ms_strbuild_printf(out, "%%u%u_%u_%u", value, leaf, plan->seq);
  return true;
}

/* Starts the next instruction (or terminator, with `defining` MIR_NONE): its loads get names of their own. */
void emit_wide_start(EmitCx *cx, MirValue defining) {
  if (cx->wide != NULL) {
    cx->wide->seq++;
    cx->wide->defining = defining;
    cx->wide->ntouched = 0;
  }
}

/* The name of the cell of `value`: its cell, or the address it arrived as. */
static void cell_name(const EmitCx *cx, MirValue value, char *out, size_t capacity) {
  if (cx->wide->incoming[value]) {
    emit_register_name(out, capacity, "in", value);
  } else {
    emit_text_name(out, capacity, "cell", cx->pool[value], NULL, MIR_NONE);
  }
}

/* Writes the leaves of a value just made to its cell, except a run an instruction copied there already. */
void emit_wide_store(EmitCx *cx, MirValue value) {
  if (cx->wide == NULL || value == MIR_NONE || !cx->wide->held[value] || cx->wide->incoming[value] ||
      cx->wide->stored[value]) {
    return;
  }
  EmitWide *plan = cx->wide;
  char cell[24];
  cell_name(cx, value, cell, sizeof cell);
  if (plan->moved != value) {
    emit_leaves_at(cx, value, cell, false);
    return;
  }
  MsSpan leaves = emit_value_leaves(cx, value);
  uint32_t *offsets = ms_alloc_zeroed(((size_t)leaves.len + 1) * sizeof *offsets);
  (void)mir_mem_layout(leaves, offsets);
  for (uint32_t leaf = 0; leaf < leaves.len; leaf++) {
    if (leaf < plan->moved_first || leaf >= plan->moved_first + plan->moved_count) {
      emit_store_leaf(cx, leaves.ptr[leaf], value, leaf, emit_address(cx, cell, offsets[leaf]));
    }
  }
  ms_free(offsets);
  plan->moved = MIR_NONE;
}

/* A held value that may be any value (`undef`): its cell is zeroed by one memset and no leaf is stored after. False
 * when the value is not held here. */
bool emit_wide_zero(EmitCx *cx, MirValue value) {
  EmitWide *plan = cx->wide;
  if (plan == NULL || value == MIR_NONE || !plan->held[value] || plan->incoming[value] || plan->stored[value]) {
    return false;
  }
  char cell[24];
  cell_name(cx, value, cell, sizeof cell);
  ms_strbuild_printf(cx->out, "  call void @llvm.memset.p0.i64(ptr %s, i8 0, i64 %u, i1 false)\n", cell,
                     mir_mem_layout(emit_value_leaves(cx, value), NULL).size);
  plan->stored[value] = true;
  return true;
}

/* A held value made by loading its leaves from memory at `from`: its cell is that memory's layout, so one copy fills
 * it and nothing is stored after. False when the value is not held here. */
bool emit_wide_fill(EmitCx *cx, MirValue value, const char *from, const uint32_t *at) {
  EmitWide *plan = cx->wide;
  if (plan == NULL || value == MIR_NONE || !plan->held[value] || plan->incoming[value] || plan->stored[value]) {
    return false;
  }
  MsSpan leaves = emit_value_leaves(cx, value);
  if (leaves.len < 4) {
    return false;
  }
  uint32_t *layout = ms_alloc_zeroed(((size_t)leaves.len + 1) * sizeof *layout);
  const uint32_t size = mir_mem_layout(leaves, layout).size;
  bool same = true;
  for (uint32_t leaf = 0; at != NULL && leaf < leaves.len && same; leaf++) {
    same = at[leaf] - at[0] == layout[leaf];
  }
  ms_free(layout);
  if (!same) {
    return false;
  }
  char cell[24];
  cell_name(cx, value, cell, sizeof cell);
  const EmitAddr start = emit_address(cx, from, at == NULL ? 0 : at[0]);
  ms_strbuild_printf(cx->out, "  call void @llvm.memcpy.p0.p0.i64(ptr %s, ptr %s, i64 %u, i1 false)\n", cell,
                     start.text, size);
  plan->stored[value] = true;
  return true;
}

/* Copies `count` leaves of held `src`, from leaf `from`, over those of held `dst` from leaf `to` as one block, when
 * both have the same leaf types and byte distances. The caller skips those leaves; the rest of `dst` is stored by
 * emit_wide_store. False, with nothing written, when the leaves do not line up. */
bool emit_wide_move_leaves(EmitCx *cx, MirValue dst, uint32_t to, MirValue src, uint32_t from, uint32_t count) {
  EmitWide *plan = cx->wide;
  if (plan == NULL || count < 2 || !plan->held[dst] || !plan->held[src] || plan->incoming[dst] ||
      plan->stored[dst] || plan->moved != MIR_NONE) {
    return false;
  }
  MsSpan dleaves = emit_value_leaves(cx, dst);
  MsSpan sleaves = emit_value_leaves(cx, src);
  if (to + count > dleaves.len || from + count > sleaves.len) {
    return false;
  }
  uint32_t *doff = ms_alloc_zeroed(((size_t)dleaves.len + 1) * sizeof *doff);
  uint32_t *soff = ms_alloc_zeroed(((size_t)sleaves.len + 1) * sizeof *soff);
  doff[dleaves.len] = mir_mem_layout(dleaves, doff).size;
  soff[sleaves.len] = mir_mem_layout(sleaves, soff).size;
  bool same = true;
  for (uint32_t index = 0; index < count && same; index++) {
    same = dleaves.ptr[to + index] == sleaves.ptr[from + index] &&
           doff[to + index] - doff[to] == soff[from + index] - soff[from];
  }
  const uint32_t size = doff[to + count] - doff[to];
  same = same && size == soff[from + count] - soff[from];
  char dcell[24];
  char scell[24];
  cell_name(cx, dst, dcell, sizeof dcell);
  cell_name(cx, src, scell, sizeof scell);
  if (same) {
    const bool shared = !plan->incoming[src] && cx->pool[src] == cx->pool[dst];
    const EmitAddr target = emit_address(cx, dcell, doff[to]);
    const EmitAddr source = emit_address(cx, scell, soff[from]);
    ms_strbuild_printf(cx->out, "  call void @llvm.%s.p0.p0.i64(ptr %s, ptr %s, i64 %u, i1 false)\n",
                       shared ? "memmove" : "memcpy", target.text, source.text, size);
    plan->moved = dst;
    plan->moved_first = to;
    plan->moved_count = count;
  }
  ms_free(doff);
  ms_free(soff);
  return same;
}

/* The loads of every leaf the instruction just written asked for, then the bits are cleared for the next one. */
void emit_wide_loads(EmitCx *cx) {
  EmitWide *plan = cx->wide;
  if (plan == NULL) {
    return;
  }
  plan->loading = true;
  cx->volatile_loads = cx->wide_hide;
  for (uint32_t index = 0; index < plan->ntouched; index++) {
    const MirValue value = plan->touched[index];
    MsSpan leaves = emit_value_leaves(cx, value);
    size_t bytes = 0;
    if (!ms_size_mul(leaves.len + 1, sizeof(uint32_t), &bytes)) {
      ms_fatal(MS_FATAL_OVERFLOW, "leaf count");
    }
    uint32_t *offsets = ms_alloc_zeroed(bytes);
    (void)mir_mem_layout(leaves, offsets);
    char cell[24];
    cell_name(cx, value, cell, sizeof cell);
    for (uint32_t leaf = 0; leaf < leaves.len; leaf++) {
      const uint32_t bit = plan->leaf_base[value] + leaf;
      if ((plan->needed[bit / 64] >> (bit % 64) & 1) == 0) {
        continue;
      }
      plan->needed[bit / 64] &= ~((uint64_t)1 << (bit % 64));
      emit_load_leaf(cx, leaves.ptr[leaf], value, leaf, emit_address(cx, cell, offsets[leaf]));
    }
    ms_free(offsets);
  }
  plan->loading = false;
  cx->volatile_loads = false;
  plan->ntouched = 0;
}

/* Whether the edge `index` of `term` copies a held block parameter. */
static bool wide_params(const EmitCx *cx, const MirTerm *term, uint32_t index) {
  const MirTarget *edge = emit_edge(term, index);
  const MirBlockData *target = &cx->func->blocks.ptr[edge->block];
  for (uint32_t param = 0; cx->wide != NULL && param < edge->nargs; param++) {
    const MirValue value = target->params.ptr[param].value;
    if (cx->wide->held[value] && !cx->wide->incoming[value] && edge->args[param] != value) {
      return true;
    }
  }
  return false;
}

bool emit_wide_edge_copies(const EmitCx *cx, const MirTerm *term, uint32_t index) {
  return wide_params(cx, term, index);
}

/* Copies each held argument of the edge into the cell of its block parameter. An argument that is a parameter of
 * the target itself (a swap around a loop) is copied leaf by leaf through registers read at the block start, so
 * no copy overwrites a source. */
void emit_wide_copy_edge(EmitCx *cx, const MirTerm *term, uint32_t index) {
  const MirTarget *edge = emit_edge(term, index);
  const MirBlockData *target = &cx->func->blocks.ptr[edge->block];
  bool overlap = false;
  for (uint32_t param = 0; param < edge->nargs && !overlap; param++) {
    for (uint32_t other = 0; other < target->params.len && !overlap; other++) {
      overlap = cx->wide->held[edge->args[param]] && edge->args[param] == target->params.ptr[other].value &&
                other != param;
    }
  }
  for (uint32_t param = 0; param < edge->nargs; param++) {
    const MirValue dest = target->params.ptr[param].value;
    const MirValue source = edge->args[param];
    if (!cx->wide->held[dest] || cx->wide->incoming[dest] || source == dest) {
      continue;
    }
    char to[24];
    char from[24];
    cell_name(cx, dest, to, sizeof to);
    if (overlap) {
      emit_leaves_at(cx, source, to, false);
      continue;
    }
    cell_name(cx, source, from, sizeof from);
    if (!cx->wide->incoming[source] && cx->pool[source] == cx->pool[dest]) {
      continue; /* already where it goes */
    }
    ms_strbuild_printf(cx->out, "  call void @llvm.memcpy.p0.p0.i64(ptr %s, ptr %s, i64 %u, i1 false)\n", to, from,
                       emit_slot_bytes(cx, emit_value_type(cx, dest)));
  }
}

/* A return of a held value copies its cell into the result area. */
bool emit_wide_return(EmitCx *cx, MirValue value) {
  if (cx->wide == NULL || !cx->wide->held[value]) {
    return false;
  }
  char from[24];
  cell_name(cx, value, from, sizeof from);
  ms_strbuild_printf(cx->out, "  call void @llvm.memcpy.p0.p0.i64(ptr %%sret, ptr %s, i64 %u, i1 false)\n", from,
                     emit_slot_bytes(cx, emit_value_type(cx, value)));
  return true;
}

/* The cell of a held value, for a callee that reads it by address. NULL name when it has none. */
bool emit_wide_address(const EmitCx *cx, MirValue value, char *out, size_t capacity) {
  if (cx->wide == NULL || !cx->wide->held[value]) {
    return false;
  }
  cell_name(cx, value, out, capacity);
  return true;
}

/* Whether two held values share one cell (a value that arrived as an address has a cell of its own). */
bool emit_wide_same_cell(const EmitCx *cx, MirValue first, MirValue second) {
  return cx->wide != NULL && cx->wide->held[first] && cx->wide->held[second] && !cx->wide->incoming[first] &&
         !cx->wide->incoming[second] && cx->pool[first] == cx->pool[second];
}

/* A call that returns a held value writes it straight to its cell: the name of the area to pass; false when it has none. */
bool emit_wide_result(EmitCx *cx, MirValue value, char *out, size_t capacity) {
  if (cx->wide == NULL || value == MIR_NONE || !cx->wide->held[value] || cx->wide->incoming[value]) {
    return false;
  }
  cx->wide->stored[value] = true;
  cell_name(cx, value, out, capacity);
  return true;
}
