/* Owns lowering one function: its blocks and their parameters, the instructions, source places and terminators. */
#include "compiler/emit_cl/cl_func.h"

#include "base/alloc.h"
#include "base/fatal.h"
#include "compiler/emit/emit_func.h"
#include "compiler/mir/mir_analysis.h"

/* ---- values and edges ---- */

/* The leaves of a block's parameters, as Cranelift block parameters. */
static void add_block_params(ClCx *cx, uint32_t block) {
  const MirBlockData *data = &cx->func->blocks.ptr[block];
  for (uint32_t index = 0; index < data->params.len; index++) {
    const MirValue param = data->params.ptr[index].value;
    MsSpan leaves = cl_value_leaves(cx, param);
    for (uint32_t leaf = 0; leaf < leaves.len; leaf++) {
      cl_set(cx, param, leaf, ms_cl_block_param_add(cx->fb, cx->blocks[block], cl_reg_type(leaves.ptr[leaf])));
    }
  }
}

/* Every leaf of every argument of an edge, in order. Returns a count; `*out` is the array (free with ms_free). */
static uint32_t edge_values(ClCx *cx, const MirTarget *target, ms_cl_val **out) {
  uint32_t count = 0;
  for (uint32_t arg = 0; arg < target->nargs; arg++) {
    count += (uint32_t)cl_value_leaves(cx, target->args[arg]).len;
  }
  ms_cl_val *values = ms_alloc((count + 1) * sizeof(ms_cl_val));
  uint32_t at = 0;
  for (uint32_t arg = 0; arg < target->nargs; arg++) {
    const uint32_t leaves = (uint32_t)cl_value_leaves(cx, target->args[arg]).len;
    for (uint32_t leaf = 0; leaf < leaves; leaf++) {
      values[at++] = cl_get(cx, target->args[arg], leaf);
    }
  }
  *out = values;
  return count;
}

static void jump_to(ClCx *cx, const MirTarget *target) {
  ms_cl_val *values = NULL;
  const uint32_t count = edge_values(cx, target, &values);
  ms_cl_jump(cx->fb, cx->blocks[target->block], values, count);
  ms_free(values);
}

/* ---- terminators ---- */

static bool lower_return(ClCx *cx, MirValue value) {
  const uint32_t leaves = value == MIR_NONE ? 0 : (uint32_t)cl_value_leaves(cx, value).len;
  if (leaves == 0) {
    ms_cl_ret0(cx->fb);
    return true;
  }
  if (leaves == 1) {
    ms_cl_ret1(cx->fb, cl_get(cx, value, 0));
    return true;
  }
  cl_leaves_at(cx, value, cx->result_area, false);
  ms_cl_ret0(cx->fb);
  return true;
}

/* A switch edge takes no arguments in Cranelift: one that carries some goes through a block of its own. */
static ms_cl_block switch_edge(ClCx *cx, const MirTarget *target) {
  uint32_t leaves = 0;
  for (uint32_t arg = 0; arg < target->nargs; arg++) {
    leaves += (uint32_t)cl_value_leaves(cx, target->args[arg]).len;
  }
  if (leaves == 0) {
    return cx->blocks[target->block];
  }
  const ms_cl_block trampoline = ms_cl_block_new(cx->fb);
  ms_cl_enter(cx->fb, trampoline);
  jump_to(cx, target);
  return trampoline;
}

static void lower_switch(ClCx *cx, const MirTerm *term) {
  uint64_t *keys = ms_alloc((term->ncases + 1) * sizeof(uint64_t));
  ms_cl_block *targets = ms_alloc((term->ncases + 1) * sizeof(ms_cl_block));
  for (uint32_t index = 0; index < term->ncases; index++) {
    keys[index] = (uint64_t)term->cases[index].value;
    targets[index] = switch_edge(cx, &term->cases[index].target);
  }
  const ms_cl_block fallback = switch_edge(cx, &term->b);
  ms_cl_enter(cx->fb, cx->cur); /* the trampolines were made in blocks of their own: resume where the block stands */
  ms_cl_switch(cx->fb, cl_get(cx, term->value, 0), fallback, keys, targets, term->ncases);
  ms_free(keys);
  ms_free(targets);
}

static bool lower_fault_term(ClCx *cx, const MirTerm *term) {
  if (term->fault == MF_POSTED) {
    ms_cl_call(cx->fb, cl_post_func(cx->mod, CL_POST_FAULT_POSTED), NULL, 0, NULL);
  }
  ms_cl_trap(cx->fb, 2);
  return true;
}

static bool lower_terminator(ClCx *cx, const MirTerm *term) {
  ms_cl_fn *f = cx->fb;
  switch ((MirTermKind)term->kind) {
  case MT_BR:
    jump_to(cx, &term->a);
    return true;
  case MT_CONDBR: {
    ms_cl_val *then_values = NULL;
    ms_cl_val *else_values = NULL;
    const uint32_t then_count = edge_values(cx, &term->a, &then_values);
    const uint32_t else_count = edge_values(cx, &term->b, &else_values);
    ms_cl_brif(f, cl_get(cx, term->value, 0), cx->blocks[term->a.block], then_values, then_count,
               cx->blocks[term->b.block], else_values, else_count);
    ms_free(then_values);
    ms_free(else_values);
    return true;
  }
  case MT_SWITCH:
    lower_switch(cx, term);
    return true;
  case MT_RET:
    return lower_return(cx, term->value);
  case MT_UNREACHABLE:
    ms_cl_trap(f, 2);
    return true;
  case MT_FAULT:
    return lower_fault_term(cx, term);
  default:
    cx->why = "terminator";
    return false;
  }
}

/* ---- source places ---- */

/* The line of the first instruction of the function that has one of its own (not an inlined callee's), or the
 * function's own line when none does. */
static uint32_t body_line(const ClCx *cx) {
  for (uint32_t block = 0; block < cx->func->blocks.len; block++) {
    const MirBlockData *data = &cx->func->blocks.ptr[block];
    for (uint32_t index = 0; index < data->insts.len; index++) {
      const MirLoc at = data->insts.ptr[index].loc;
      if (!mir_loc_none(at) && at.line != 0 && at.scope == 0) {
        return at.line;
      }
    }
  }
  return cx->func->loc.line;
}

/* The place the following instructions carry: the source line, the module file, and the module-wide scope number
 * (1 to the number of inlined-callee scopes the functions list, then one per function body). */
static void set_place(ClCx *cx, MirLoc loc, uint32_t body) {
  const bool known = !mir_loc_none(loc) && loc.line != 0;
  const uint32_t line = known ? loc.line : body;
  const uint32_t scope = known && loc.scope != 0 ? cx->scope_base + loc.scope : cx->body_scope;
  const uint32_t file = known && loc.file != MIR_NONE ? loc.file : cx->func->loc.file;
  ms_cl_srcloc(cx->fb, file, line, scope);
}

/* ---- instructions ---- */

static bool lower_instruction(ClCx *cx, const MirInst *inst) {
  bool handled = false;
  bool ok = cl_scalar_op(cx, inst, &handled);
  if (!handled) {
    ok = cl_checked_op(cx, inst, &handled);
  }
  if (!handled) {
    ok = cl_memory_op(cx, inst, &handled);
  }
  if (!handled) {
    ok = cl_call_op(cx, inst, &handled);
  }
  if (!handled) {
    cx->why = mir_op_info[inst->op].name;
    return false;
  }
  if (!ok) {
    return false;
  }
  int64_t lo = 0;
  int64_t hi = 0;
  if (!mir_sized_result_range(cx->module, cx->func, inst, &lo, &hi)) {
    return true;
  }
  /* A checked operation on a sized integer also faults when its result leaves the type's range. */
  ms_cl_fn *f = cx->fb;
  ms_cl_val result = cl_get(cx, inst->res, 0);
  ms_cl_val outside = ms_cl_bor(f, ms_cl_icmp(f, MS_CL_SLT, result, cl_const(cx, lo)),
                                ms_cl_icmp(f, MS_CL_SGT, result, cl_const(cx, hi)));
  cl_fault_if(cx, outside, CL_POST_INT_RANGE, NULL, 0);
  return true;
}

static bool lower_block(ClCx *cx, uint32_t block, uint32_t body) {
  const MirBlockData *data = &cx->func->blocks.ptr[block];
  cx->cur = cx->blocks[block];
  ms_cl_enter(cx->fb, cx->cur);
  for (uint32_t index = 0; index < data->insts.len; index++) {
    const MirInst *inst = &data->insts.ptr[index];
    cx->cur_block = block;
    cx->cur_index = index;
    if (cx->places) {
      set_place(cx, inst->loc, body);
    }
    if (!lower_instruction(cx, inst)) {
      return false;
    }
  }
  cx->cur_block = block;
  cx->cur_index = (uint32_t)data->insts.len;
  if (cx->places) {
    set_place(cx, data->term_loc, body);
  }
  return lower_terminator(cx, &data->term);
}

/* ---- the function ---- */

/* The blocks reachable from the entry, each before every block it dominates (reverse post-order), so a value is made
 * before the blocks that read it are lowered. */
static uint32_t order_blocks(ClCx *cx, uint32_t *order) {
  const MirFunc *func = cx->func;
  const uint32_t count = (uint32_t)func->blocks.len;
  uint8_t *state = ms_alloc_zeroed(count + 1);
  uint32_t *stack = ms_alloc((count + 1) * sizeof(uint32_t));
  uint32_t *next = ms_alloc_zeroed((count + 1) * sizeof(uint32_t));
  uint32_t depth = 0;
  uint32_t out = 0;
  stack[depth++] = 0;
  state[0] = 1;
  while (depth > 0) {
    const uint32_t block = stack[depth - 1];
    const MirTerm *term = &func->blocks.ptr[block].term;
    if (next[block] < emit_edge_count(term)) {
      const MirTarget *target = emit_edge(term, next[block]++);
      if (state[target->block] == 0) {
        state[target->block] = 1;
        stack[depth++] = target->block;
      }
      continue;
    }
    order[out++] = block; /* post-order */
    depth--;
  }
  for (uint32_t low = 0, high = out; low + 1 < high; low++, high--) { /* reverse */
    const uint32_t swap = order[low];
    order[low] = order[high - 1];
    order[high - 1] = swap;
  }
  ms_free(state);
  ms_free(stack);
  ms_free(next);
  return out;
}

/* Whether the function's boundary is one the lowering handles: layouts that did not fail, and an entry block that
 * nothing branches to (it cannot hold block parameters). */
static bool types_ok(ClCx *cx) {
  const MirFunc *func = cx->func;
  for (uint32_t value = 0; value < func->values.len; value++) {
    (void)cl_leaves(cx, func->values.ptr[value]);
  }
  if (cx->layouts->failed) {
    cx->why = "type layout";
    return false;
  }
  for (uint32_t block = 0; block < func->blocks.len; block++) {
    const MirTerm *term = &func->blocks.ptr[block].term;
    for (uint32_t edge = 0; edge < emit_edge_count(term); edge++) {
      if (emit_edge(term, edge)->block == 0) {
        cx->why = "entry block is a branch target";
        return false;
      }
    }
  }
  return true;
}

/* The entry block: its parameters are the function's, after the hidden result pointer when there is one; an
 * argument that arrived as an address has its leaves loaded from it. */
static void enter_function(ClCx *cx) {
  const MirFunc *func = cx->func;
  const ms_cl_block entry = ms_cl_entry(cx->fb);
  cx->blocks[0] = entry;
  uint32_t at = 0;
  MsSpan result = cl_leaves(cx, func->ret);
  if (result.len > 1) {
    cx->has_result_area = true;
    cx->result_area = ms_cl_block_param(cx->fb, entry, at++);
  }
  for (uint32_t param = 0; param < func->nparams; param++) {
    const MirValue value = func->blocks.ptr[0].params.ptr[param].value;
    if (cl_is_indirect(cx, func->params[param].ty)) {
      cl_leaves_at(cx, value, ms_cl_block_param(cx->fb, entry, at++), true);
      continue;
    }
    const uint32_t leaves = (uint32_t)cl_value_leaves(cx, value).len;
    for (uint32_t leaf = 0; leaf < leaves; leaf++) {
      cl_set(cx, value, leaf, ms_cl_block_param(cx->fb, entry, at++));
    }
  }
}

bool cl_lower_function(ClCx *cx) {
  const MirFunc *func = cx->func;
  if (!types_ok(cx)) {
    return false;
  }
  const uint32_t nvalues = (uint32_t)func->values.len;
  uint32_t *first = ms_alloc((nvalues + 1) * sizeof(uint32_t));
  uint32_t total = 0;
  for (uint32_t value = 0; value < nvalues; value++) {
    first[value] = total;
    total += (uint32_t)cl_value_leaves(cx, value).len;
  }
  cx->first = first;
  cx->regs = ms_alloc_zeroed((total + 1) * sizeof(ms_cl_val));
  const uint32_t nblocks = (uint32_t)func->blocks.len;
  cx->blocks = ms_alloc_zeroed((nblocks + 1) * sizeof(ms_cl_block));
  uint32_t *order = ms_alloc((nblocks + 1) * sizeof(uint32_t));
  const uint32_t reachable = order_blocks(cx, order);
  cx->has_result_area = false;
  cl_frame_areas(cx);
  ms_cl_fn_begin(cx->fb, cx->mod->funcs[cx->index]);
  enter_function(cx);
  for (uint32_t at = 1; at < reachable; at++) {
    cx->blocks[order[at]] = ms_cl_block_new(cx->fb);
    add_block_params(cx, order[at]);
    if (func->blocks.ptr[order[at]].cold) {
      ms_cl_cold(cx->fb, cx->blocks[order[at]]);
    }
  }
  const uint32_t body = body_line(cx);
  bool ok = true;
  for (uint32_t at = 0; ok && at < reachable; at++) {
    ok = lower_block(cx, order[at], body);
  }
  if (ok) {
    ms_cl_seal_all(cx->fb);
    if (ms_cl_fn_end(cx->fb) != 0) {
      cx->why = "Cranelift refused the function";
      ok = false;
    }
  }
  ms_free(order);
  ms_free(cx->blocks);
  ms_free(cx->regs);
  ms_free(first);
  cx->blocks = NULL;
  cx->regs = NULL;
  cx->first = NULL;
  return ok;
}
