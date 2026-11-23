/* compiler/mir/mir_analysis.c: ownership modes of operands and results, terminator walks, predecessors,
 * reverse post-order, dominators, value sets and ranges. Owns nothing: results live in the arena the caller
 * passes. */
#include "compiler/mir/mir_analysis.h"

#include "base/fatal.h"

static uint32_t block_count(const MirFunc *func) {
  return (uint32_t)func->blocks.len;
}

/* ---- ownership modes ---- */

static bool result_is_borrow(const MirModule *module, const MirFunc *func, const MirInst *inst) {
  switch ((MirOp)inst->op) {
  case MOP_TypeGet: case MOP_AltGet: case MOP_ListGet: case MOP_ListGetNn: case MOP_ListGetU:
  case MOP_OptGet: case MOP_ClosureCap: case MOP_GlobalGet: case MOP_Load: case MOP_StrLit:
  case MOP_BytesLit: case MOP_ListConstView: case MOP_StrAscii: case MOP_OptView: case MOP_OptViewAt:
  case MOP_AltPlain: case MOP_OptNone:
    return true;
  case MOP_Undef:
    return inst->imm.tag == MI_INT && inst->imm.i == 1;
  case MOP_IfaceNew: /* a view of a value its binding keeps */
    return inst->imm.tag == MI_VTABLE && inst->imm.b != 0;
  case MOP_AltView: {
    const MirTyData *data = mir_ty_data(module, mir_value_ty(func, inst->res));
    return !(data->kind == MK_ALT && module->alts.ptr[data->id].borrowed != 0);
  }
  case MOP_Call:
    return inst->imm.tag == MI_FUNC && module->funcs.ptr[inst->imm.a].ret_borrowed;
  default:
    return false;
  }
}

bool mir_result_mode(const MirModule *module, const MirFunc *func, const MirInst *inst, MirMode *mode) {
  if (inst->res == MIR_NONE || !mir_needs_drop(module, mir_value_ty(func, inst->res))) {
    return false;
  }
  *mode = result_is_borrow(module, func, inst) ? MM_BORROW : MM_MOVE;
  return true;
}

bool mir_result_borrowed(const MirModule *module, const MirFunc *func, const MirInst *inst) {
  return result_is_borrow(module, func, inst);
}

static bool mir_method_consumes(const MirModule *module, const MirInst *inst) {
  if (inst->op != MOP_CallMethod || inst->imm.tag != MI_METHOD || inst->imm.a >= module->ifaces.len) {
    return false;
  }
  const MirIfaceDef *iface = &module->ifaces.ptr[inst->imm.a];
  return inst->imm.b < iface->nmethods && iface->methods[inst->imm.b].consumes;
}

uint64_t mir_indirect_owned(const MirModule *module, const MirFunc *func, const MirInst *inst) {
  if (inst->op == MOP_CallMethod && inst->imm.tag == MI_METHOD) {
    if (inst->imm.a >= module->ifaces.len) {
      return 0;
    }
    const MirIfaceDef *iface = &module->ifaces.ptr[inst->imm.a];
    return inst->imm.b < iface->nmethods ? iface->methods[inst->imm.b].owned : 0;
  }
  if (inst->op == MOP_CallInd && inst->nargs > 0) {
    const MirTyData *data = mir_ty_data(module, mir_value_ty(func, inst->args[0]));
    return data->kind == MK_FN ? data->owned : 0;
  }
  return 0;
}

static void fill_modes(MirMode *out, uint32_t count, MirMode mode) {
  for (uint32_t index = 0; index < count; index++) {
    out[index] = mode;
  }
}

static void one_moved(MirMode *out, uint32_t count, uint32_t index) {
  fill_modes(out, count, MM_BORROW);
  if (index < count) {
    out[index] = MM_MOVE;
  }
}

/* Parameter modes of a callee, padded with borrows when the call passes more arguments. */
static void param_modes(const MirParam *params, uint32_t nparams, MirMode *out, uint32_t count) {
  fill_modes(out, count, MM_BORROW);
  for (uint32_t index = 0; index < count && index < nparams; index++) {
    out[index] = (MirMode)params[index].mode;
  }
}

static void indirect_modes(const MirModule *module, const MirFunc *func, const MirInst *inst, MirMode *out) {
  /* Operand 0 (the closure or interface value) is borrowed unless the operation consumes it; argument `i` is
   * operand `i + 1`. */
  const uint64_t owned = mir_indirect_owned(module, func, inst);
  fill_modes(out, inst->nargs, MM_BORROW);
  if (inst->nargs > 0 && mir_method_consumes(module, inst)) {
    out[0] = MM_MOVE;
  }
  for (uint32_t index = 1; index < inst->nargs; index++) {
    out[index] = mir_owns(owned, index - 1) ? MM_MOVE : MM_BORROW;
  }
}

void mir_arg_modes(const MirModule *module, const MirFunc *func, const MirInst *inst, MirMode *out) {
  const uint32_t count = inst->nargs;
  switch ((MirOp)inst->op) {
  case MOP_ClosureNew: /* a closure into its maker's frame only reads the captures where they live */
    fill_modes(out, count, inst->imm.tag == MI_FUNC && module->funcs.ptr[inst->imm.a].scoped ? MM_BORROW : MM_MOVE);
    return;
  case MOP_TypeNew: case MOP_AltNew: case MOP_ListLit: case MOP_TypeSet:
  case MOP_TypeFill: case MOP_ListPush: case MOP_ListDropLast: case MOP_ListSet: case MOP_ListSetNn:
  case MOP_ListSetU: case MOP_ListFill: case MOP_ListFillU: case MOP_ListPushU:
    fill_modes(out, count, MM_MOVE);
    return;
  case MOP_IfaceNew:
    if (inst->imm.tag == MI_VTABLE && inst->imm.b != 0) { /* a view of a binding that keeps its value */
      fill_modes(out, count, MM_BORROW);
      return;
    }
    one_moved(out, count, 0);
    return;
  case MOP_OptSome: case MOP_Drop: case MOP_Forget: case MOP_ListRelease:
  case MOP_GlobalSet: case MOP_AltUnbox: case MOP_AltRelease: case MOP_TypeRelease: case MOP_OptUnbox:
  case MOP_ListGrow:
    one_moved(out, count, 0);
    return;
  case MOP_Put: case MOP_DropIf:
    one_moved(out, count, 1);
    return;
  case MOP_Call:
    if (inst->imm.tag == MI_FUNC) {
      const MirFunc *callee = &module->funcs.ptr[inst->imm.a];
      param_modes(callee->params, callee->nparams, out, count);
      return;
    }
    fill_modes(out, count, MM_BORROW);
    return;
  case MOP_CallRt:
    if (inst->imm.tag == MI_EXT) {
      const MirExtern *callee = &module->externs.ptr[inst->imm.a];
      param_modes(callee->params, callee->nparams, out, count);
      return;
    }
    fill_modes(out, count, MM_BORROW);
    return;
  case MOP_CallInd: case MOP_CallMethod:
    indirect_modes(module, func, inst, out);
    return;
  default:
    fill_modes(out, count, MM_BORROW);
    return;
  }
}

bool mir_result_views(const MirModule *module, const MirFunc *func, const MirInst *inst) {
  switch ((MirOp)inst->op) {
  case MOP_IfaceBorrow: case MOP_IfaceView:
    return true;
  case MOP_Call:
    if (inst->imm.tag == MI_FUNC && module->funcs.ptr[inst->imm.a].ret_view) {
      return true;
    }
    break;
  case MOP_CallRt:
    if (inst->imm.tag == MI_EXT && module->externs.ptr[inst->imm.a].role == MR_VIEW_RESULT) {
      return true;
    }
    break;
  case MOP_AltView: case MOP_CallInd: case MOP_CallMethod:
    break;
  default:
    return false;
  }
  /* A borrowing variant points into the arguments its borrowed cases came from. */
  if (inst->res == MIR_NONE) {
    return false;
  }
  const MirTyData *data = mir_ty_data(module, mir_value_ty(func, inst->res));
  return data->kind == MK_ALT && module->alts.ptr[data->id].borrowed != 0;
}

/* ---- terminators ---- */

const MirTarget *mir_term_target_const(const MirTerm *term, uint32_t index) {
  if (term->kind == MT_SWITCH && index < term->ncases) {
    return &term->cases[index].target;
  }
  if (term->kind == MT_SWITCH) {
    return &term->b; /* a switch keeps its default in `b`, even when it has no cases */
  }
  return index == 0 ? &term->a : &term->b;
}

static bool term_has_value(const MirTerm *term) {
  return (term->kind == MT_CONDBR || term->kind == MT_SWITCH || term->kind == MT_RET) && term->value != MIR_NONE;
}

void mir_term_each_use(MirTerm *term, MirUseFn visit, void *context) {
  if (term_has_value(term)) {
    visit(context, &term->value);
  }
  const uint32_t ntargets = mir_term_ntargets(term);
  for (uint32_t index = 0; index < ntargets; index++) {
    MirTarget *target = mir_term_target(term, index);
    for (uint32_t arg = 0; arg < target->nargs; arg++) {
      visit(context, &target->args[arg]);
    }
  }
}

void mir_term_each_value(const MirTerm *term, MirValueFn visit, void *context) {
  if (term_has_value(term)) {
    visit(context, term->value);
  }
  const uint32_t ntargets = mir_term_ntargets(term);
  for (uint32_t index = 0; index < ntargets; index++) {
    const MirTarget *target = mir_term_target_const(term, index);
    for (uint32_t arg = 0; arg < target->nargs; arg++) {
      visit(context, target->args[arg]);
    }
  }
}

/* ---- control flow ---- */

/* Calls `visit(context, from, to)` once per distinct edge, in block order. Edges out of one block arrive
 * together, so a repeat of the previous source is the only duplicate. */
typedef void (*EdgeFn)(void *context, MirBlock from, MirBlock to);

static void each_edge(const MirFunc *func, MirBlock *last, EdgeFn visit, void *context) {
  const uint32_t count = block_count(func);
  for (uint32_t index = 0; index < count; index++) {
    last[index] = MIR_NONE;
  }
  for (uint32_t from = 0; from < count; from++) {
    const MirTerm *term = &func->blocks.ptr[from].term;
    for (uint32_t index = 0; index < mir_term_ntargets(term); index++) {
      const MirBlock to = mir_term_target_const(term, index)->block;
      if (last[to] != from) {
        last[to] = from;
        visit(context, from, to);
      }
    }
  }
}

typedef struct PredFill {
  uint32_t *start;
  uint32_t *fill;
  MirBlock *list;
} PredFill;

static void count_edge(void *context, MirBlock from, MirBlock to) {
  (void)from;
  ((PredFill *)context)->start[to + 1]++;
}

static void store_edge(void *context, MirBlock from, MirBlock to) {
  PredFill *fill = context;
  fill->list[fill->fill[to]++] = from;
}

MirPreds mir_preds(MsArena *arena, const MirFunc *func) {
  const uint32_t count = block_count(func);
  PredFill fill = {MS_ARENA_NEW_ARRAY(arena, uint32_t, (size_t)count + 1),
                   MS_ARENA_NEW_ARRAY(arena, uint32_t, (size_t)count + 1), NULL};
  MirBlock *last = MS_ARENA_NEW_ARRAY(arena, MirBlock, (size_t)count + 1);
  each_edge(func, last, count_edge, &fill);
  for (uint32_t index = 0; index < count; index++) {
    fill.start[index + 1] += fill.start[index];
  }
  __builtin_memcpy(fill.fill, fill.start, sizeof(uint32_t) * ((size_t)count + 1));
  fill.list = MS_ARENA_NEW_ARRAY(arena, MirBlock, (size_t)fill.start[count] + 1);
  each_edge(func, last, store_edge, &fill);
  return (MirPreds){fill.start, fill.list};
}

/* The most entries the post-order walk's stack can hold: every edge pushes once, plus the entry and a closing
 * entry per block. */
static size_t rpo_stack_bound(const MirFunc *func) {
  size_t bound = 1;
  for (uint32_t block = 0; block < block_count(func); block++) {
    size_t sum = 0;
    if (!ms_size_add(bound, (size_t)mir_term_ntargets(&func->blocks.ptr[block].term) + 1, &sum)) {
      ms_fatal(MS_FATAL_OVERFLOW, "mir_rpo: stack bound overflows");
    }
    bound = sum;
  }
  return bound;
}

static void reverse_blocks(MirBlock *post, size_t count) {
  for (size_t index = 0; index < count / 2; index++) {
    const MirBlock swap = post[index];
    post[index] = post[count - 1 - index];
    post[count - 1 - index] = swap;
  }
}

uint32_t mir_rpo(MsArena *arena, const MirFunc *func, MirBlock **order) {
  const uint32_t blocks = block_count(func);
  bool *seen = MS_ARENA_NEW_ARRAY(arena, bool, (size_t)blocks + 1);
  MirBlock *post = MS_ARENA_NEW_ARRAY(arena, MirBlock, (size_t)blocks + 1);
  /* One flat stack of entries; the high bit marks a block being closed rather than opened. */
  uint32_t *stack = MS_ARENA_NEW_ARRAY(arena, uint32_t, rpo_stack_bound(func) + 1);
  size_t top = 0;
  size_t count = 0;
  stack[top++] = 0;
  while (top > 0) {
    const uint32_t entry = stack[--top];
    const MirBlock block = entry & INT32_MAX;
    if ((entry >> 31) != 0) {
      post[count++] = block;
      continue;
    }
    if (seen[block]) {
      continue;
    }
    seen[block] = true;
    stack[top++] = block | (UINT32_C(1) << 31);
    const MirTerm *term = &func->blocks.ptr[block].term;
    for (uint32_t index = 0; index < mir_term_ntargets(term); index++) {
      stack[top++] = mir_term_target_const(term, index)->block;
    }
  }
  reverse_blocks(post, count);
  *order = post;
  return (uint32_t)count;
}

/* The nearest common dominator of `a` and `b` by walking up the dominator tree. */
static MirBlock intersect(const MirBlock *idom, const uint32_t *rank, MirBlock a, MirBlock b) {
  while (a != b) {
    while (rank[a] > rank[b]) {
      a = idom[a];
    }
    while (rank[b] > rank[a]) {
      b = idom[b];
    }
  }
  return a;
}

MirBlock *mir_dominators(MsArena *arena, const MirFunc *func, const MirBlock *order, uint32_t count,
                         const MirPreds *preds) {
  const uint32_t blocks = block_count(func);
  uint32_t *rank = MS_ARENA_NEW_ARRAY(arena, uint32_t, (size_t)blocks + 1);
  MirBlock *idom = MS_ARENA_NEW_ARRAY(arena, MirBlock, (size_t)blocks + 1);
  for (uint32_t index = 0; index < blocks; index++) {
    rank[index] = MIR_NONE;
    idom[index] = MIR_NONE;
  }
  for (uint32_t index = 0; index < count; index++) {
    rank[order[index]] = index;
  }
  if (blocks == 0) {
    return idom;
  }
  idom[0] = 0;
  for (bool changed = true; changed;) {
    changed = false;
    for (uint32_t index = 1; index < count; index++) {
      const MirBlock block = order[index];
      MirBlock best = MIR_NONE;
      for (uint32_t k = 0; k < mir_preds_count(preds, block); k++) {
        const MirBlock pred = mir_pred(preds, block, k);
        if (idom[pred] == MIR_NONE || rank[pred] == MIR_NONE) {
          continue;
        }
        best = best == MIR_NONE ? pred : intersect(idom, rank, pred, best);
      }
      if (best != idom[block]) {
        idom[block] = best;
        changed = true;
      }
    }
  }
  return idom;
}

uint32_t mir_inst_count(const MirFunc *func) {
  uint32_t count = 0;
  for (size_t block = 0; block < func->blocks.len; block++) {
    count += (uint32_t)func->blocks.ptr[block].insts.len;
  }
  return count;
}

static void count_use(void *context, MirValue value) {
  ((uint32_t *)context)[value]++;
}

uint32_t *mir_use_counts(MsArena *arena, const MirFunc *func) {
  uint32_t *uses = MS_ARENA_NEW_ARRAY(arena, uint32_t, func->values.len + 1);
  for (size_t block = 0; block < func->blocks.len; block++) {
    const MirBlockData *data = &func->blocks.ptr[block];
    for (size_t inst = 0; inst < data->insts.len; inst++) {
      for (uint32_t arg = 0; arg < data->insts.ptr[inst].nargs; arg++) {
        uses[data->insts.ptr[inst].args[arg]]++;
      }
    }
    mir_term_each_value(&data->term, count_use, uses);
  }
  return uses;
}

bool mir_is_scalar(const MirModule *module, MirTy ty) {
  switch ((MirTyKind)mir_ty_data(module, ty)->kind) {
  case MK_BOOL: case MK_INT: case MK_INT8: case MK_INT16: case MK_INT32: case MK_UINT8: case MK_UINT16:
  case MK_UINT32: case MK_UINT64: case MK_FLOAT: case MK_FLOAT32:
    return true;
  case MK_VOID: case MK_STR: case MK_BYTES: case MK_PTR: case MK_TYPE: case MK_ALT: case MK_LIST:
  case MK_OPT: case MK_OBJ: case MK_FN: case MK_IFACE:
    return false;
  }
  return false;
}

/* ---- value sets ---- */

MirBits mir_bits_new(MsArena *arena, uint32_t nbits) {
  const size_t nwords = ((size_t)nbits + 63) / 64;
  return (MirBits){MS_ARENA_NEW_ARRAY(arena, uint64_t, nwords + 1), nbits};
}

MirBits mir_owned_values(MsArena *arena, const MirModule *module, const MirFunc *func, bool entry_params) {
  MirBits owned = mir_bits_new(arena, (uint32_t)func->values.len);
  for (size_t block = entry_params ? 0 : 1; block < func->blocks.len; block++) {
    const MirBlockParamList *params = &func->blocks.ptr[block].params;
    for (size_t index = 0; index < params->len; index++) {
      if (params->ptr[index].mode == MM_MOVE) {
        mir_bits_set(&owned, params->ptr[index].value);
      }
    }
  }
  for (size_t block = 0; block < func->blocks.len; block++) {
    const MirInstList *insts = &func->blocks.ptr[block].insts;
    for (size_t index = 0; index < insts->len; index++) {
      MirMode mode = MM_BORROW;
      if (mir_result_mode(module, func, &insts->ptr[index], &mode) && mode == MM_MOVE) {
        mir_bits_set(&owned, insts->ptr[index].res);
      }
    }
  }
  return owned;
}

/* ---- ranges ---- */

void mir_narrow_range(const MirModule *module, MirTy from, MirTy to, int64_t *lo, int64_t *hi) {
  *lo = INT64_MIN;
  *hi = INT64_MAX;
  switch ((MirTyKind)mir_ty_data(module, to)->kind) {
  case MK_INT8: *lo = INT8_MIN; *hi = INT8_MAX; break;
  case MK_INT16: *lo = INT16_MIN; *hi = INT16_MAX; break;
  case MK_INT32: *lo = INT32_MIN; *hi = INT32_MAX; break;
  case MK_UINT8: *lo = 0; *hi = UINT8_MAX; break;
  case MK_UINT16: *lo = 0; *hi = UINT16_MAX; break;
  case MK_UINT32: *lo = 0; *hi = UINT32_MAX; break;
  case MK_UINT64: *lo = 0; break;
  default: break;
  }
  if (mir_ty_data(module, from)->kind == MK_UINT64 && *lo < 0) {
    *lo = 0;
  }
}

static bool is_checked_integer_op(MirOp op) {
  switch (op) {
  case MOP_IAddChk: case MOP_ISubChk: case MOP_IMulChk: case MOP_INegChk: case MOP_UAddChk:
  case MOP_USubChk: case MOP_UMulChk: case MOP_SDivChk: case MOP_SRemChk: case MOP_UDivChk: case MOP_URemChk:
    return true;
  default:
    return false;
  }
}

bool mir_sized_result_range(const MirModule *module, const MirFunc *func, const MirInst *inst, int64_t *lo,
                            int64_t *hi) {
  if (!is_checked_integer_op((MirOp)inst->op) || inst->res == MIR_NONE) {
    return false;
  }
  const MirTy result = func->values.ptr[inst->res];
  switch ((MirTyKind)mir_ty_data(module, result)->kind) {
  case MK_INT8: case MK_INT16: case MK_INT32: case MK_UINT8: case MK_UINT16: case MK_UINT32:
    mir_narrow_range(module, MIR_INT, result, lo, hi);
    return true;
  default:
    return false;
  }
}
