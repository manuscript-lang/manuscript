/* compiler/mir/mir_expand.c: safety checks and list growth as explicit MIR, so the back ends only lower.
 *
 * Run once after `unwind`, on the module a back end is about to compile. A checked list access becomes the
 * arithmetic that counts a negative index from the end, a compare of the index against the length, a branch to
 * a block that reports the fault, and the unchecked access (`list.get.u`, `list.set.u`, `list.fill.u`,
 * `list.addr.u`). `opt.unwrap` gets a branch to the none fault ahead of it, and `list.push` becomes a test for a
 * full list, growth to the next capacity (4 when empty, else double) with `list.grow`, and `list.push.u`. With
 * `checks` off the branches are left out. Overflow and division checks stay with the back ends.
 *
 * Fault blocks and the block that grows a list are marked cold: a back end lays them out of line and treats the
 * branch to them as unlikely. */
#include "compiler/mir/mir_expand.h"

#include "compiler/mir/mir_pass.h"

static bool is_join(const MirModule *module, const MirInst *inst) {
  if (inst->op != MOP_CallRt || inst->imm.tag != MI_EXT) {
    return false;
  }
  const uint8_t role = module->externs.ptr[inst->imm.a].role;
  return role == MR_STRING_JOIN || role == MR_STRING_JOIN_GROW;
}

static bool expands(const MirModule *module, const MirInst *inst) {
  const MirOp op = (MirOp)inst->op;
  return is_join(module, inst) || op == MOP_ListGet || op == MOP_ListGetNn || op == MOP_ListSet || op == MOP_ListSetNn ||
         op == MOP_ListFill || op == MOP_ListAddr || op == MOP_ListPush || op == MOP_OptUnwrap;
}

/* How many blocks `op` adds after the one it is in, apart from fault blocks. */
static uint32_t continuations(MirOp op, bool checks) {
  if (op == MOP_ListPush) {
    return 2;
  }
  return (op == MOP_CallRt || !checks) ? 0 : (op == MOP_ListGet || op == MOP_ListGetNn || op == MOP_ListSet ||
                                              op == MOP_ListSetNn || op == MOP_ListFill || op == MOP_ListAddr ||
                                              op == MOP_OptUnwrap) ? 1 : 0;
}

/* Rewrites one function. Blocks keep their order: a block that is split is followed by its continuations, and
 * the fault blocks come last, so numbering is known before any block is built and a terminator only needs its
 * targets renumbered. */
typedef struct Expander {
  MirModule *module;
  MirFunc *func;
  bool checks;
  uint32_t index_fault;
  uint32_t join_open, join_extend, join_close, join_format; /* the string primitives, interned on first use */
  MirBlockList out;
  MirBlockList faults;
  uint32_t fault_base; /* the number of the first fault block: after every block built in order */
  uint32_t next;       /* the number of the next continuation block of the current block */
} Expander;

static MirValue emit(Expander *e, MirBlockData *block, MirOp op, const MirValue *args, uint32_t nargs,
                     MirImm imm, MirTy ty, MirLoc loc) {
  return mir_block_emit(e->module, e->func, block, op, args, nargs, imm, ty, loc);
}

static MirValue emit_int(Expander *e, MirBlockData *block, int64_t value, MirLoc loc) {
  return emit(e, block, MOP_IConst, NULL, 0, mir_imm_int(value), MIR_INT, loc);
}

static MirValue emit_cmp(Expander *e, MirBlockData *block, MirOp op, MirCc cc, MirValue x, MirValue y,
                         MirLoc loc) {
  const MirValue args[2] = {x, y};
  return emit(e, block, op, args, 2, mir_imm_cc(cc), MIR_BOOL, loc);
}

static MirValue emit_pure2(Expander *e, MirBlockData *block, MirOp op, MirValue x, MirValue y, MirLoc loc) {
  const MirValue args[2] = {x, y};
  return emit(e, block, op, args, 2, mir_imm_none(), MIR_INT, loc);
}

static MirValue emit_select(Expander *e, MirBlockData *block, MirValue cond, MirValue yes, MirValue no,
                            MirLoc loc) {
  const MirValue args[3] = {cond, yes, no};
  return emit(e, block, MOP_Select, args, 3, mir_imm_none(), MIR_INT, loc);
}

/* Ends `cur` with a branch on `ok` to the next block of the chain, or to a new fault block, and leaves in
 * `cur` the next block, ready for the rest of the instructions. */
static void guard(Expander *e, MirBlockData *cur, MirValue ok, MirBlockData fault) {
  const MirBlock to_fault = e->fault_base + (MirBlock)e->faults.len;
  fault.cold = true;
  mir_block_list_push(&e->faults, fault);
  const MirBlock cont = e->next++;
  cur->term = (MirTerm){.kind = MT_CONDBR, .value = ok, .a = {.block = cont}, .b = {.block = to_fault}};
  mir_block_list_push(&e->out, *cur);
  *cur = mir_block_empty();
}

static void expand_unwrap(Expander *e, const MirInst *inst, MirBlockData *cur) {
  if (e->checks) {
    const MirValue some = emit(e, cur, MOP_OptIsSome, inst->args, inst->nargs, mir_imm_none(), MIR_BOOL, inst->loc);
    MirBlockData fault = mir_block_empty();
    fault.term = (MirTerm){.kind = MT_FAULT, .value = MIR_NONE, .fault = MF_NONE_UNWRAP};
    fault.term_loc = inst->loc;
    guard(e, cur, some, fault);
  }
  mir_inst_list_push(&cur->insts, *inst);
}

/* The block that reports an index outside the list: `msrt_index_fault(index, length)`. */
static MirBlockData index_fault_block(Expander *e, MirValue index, MirValue len, MirLoc loc) {
  MirBlockData fault = mir_block_empty();
  const MirValue args[2] = {index, len};
  (void)emit(e, &fault, MOP_CallRt, args, 2, mir_imm_ext(e->index_fault), MIR_VOID, loc);
  fault.term_loc = loc;
  return fault;
}

static MirOp unchecked_op(MirOp op) {
  switch (op) {
  case MOP_ListGet:
  case MOP_ListGetNn: return MOP_ListGetU;
  case MOP_ListSet:
  case MOP_ListSetNn: return MOP_ListSetU;
  case MOP_ListFill: return MOP_ListFillU;
  default: return MOP_ListAddrU;
  }
}

/* A list access: `list.get`, `list.set`, `list.fill` and `list.addr` count a negative index from the end; the
 * `.nn` forms know it is not negative. */
static void expand_access(Expander *e, const MirInst *inst, MirBlockData *cur) {
  const MirOp op = (MirOp)inst->op;
  const MirLoc loc = inst->loc;
  const MirValue list = inst->args[0], index = inst->args[1];
  const bool wraps = op == MOP_ListGet || op == MOP_ListSet || op == MOP_ListFill || op == MOP_ListAddr;
  MirValue len = MIR_NONE;
  if (e->checks || wraps) {
    len = emit(e, cur, MOP_ListLen, &list, 1, mir_imm_none(), MIR_INT, loc);
  }
  MirValue wrapped_index = index;
  if (wraps) {
    const MirValue zero = emit_int(e, cur, 0, loc);
    const MirValue negative = emit_cmp(e, cur, MOP_ICmp, MCC_LT, index, zero, loc);
    const MirValue wrapped = emit_pure2(e, cur, MOP_IAdd, index, len, loc);
    wrapped_index = emit_select(e, cur, negative, wrapped, index, loc);
  }
  if (e->checks) {
    const MirValue ok = emit_cmp(e, cur, MOP_UICmp, MCC_LT, wrapped_index, len, loc);
    guard(e, cur, ok, index_fault_block(e, index, len, loc));
  }
  MirValue *args = mir_args_copy(e->module, inst->args, inst->nargs);
  args[1] = wrapped_index;
  mir_inst_list_push(&cur->insts, mir_inst(unchecked_op(op), inst->imm, inst->res, loc, args, inst->nargs));
}

/* The block that grows a full list: 4 elements if it is empty, twice its capacity otherwise. */
static MirBlockData grow_block(Expander *e, MirValue list, MirValue cap, MirBlock ready, MirLoc loc) {
  MirBlockData block = mir_block_empty();
  block.cold = true;
  block.term_loc = loc;
  const MirTy ty = mir_value_ty(e->func, list);
  const MirValue zero = emit_int(e, &block, 0, loc);
  const MirValue empty = emit_cmp(e, &block, MOP_ICmp, MCC_EQ, cap, zero, loc);
  const MirValue one = emit_int(e, &block, 1, loc);
  const MirValue doubled = emit_pure2(e, &block, MOP_Shl, cap, one, loc);
  const MirValue four = emit_int(e, &block, 4, loc);
  const MirValue new_cap = emit_select(e, &block, empty, four, doubled, loc);
  const MirValue grow_args[2] = {list, new_cap};
  const MirValue grown = emit(e, &block, MOP_ListGrow, grow_args, 2, mir_imm_none(), ty, loc);
  block.term = (MirTerm){.kind = MT_BR, .value = MIR_NONE,
                         .a = {.block = ready, .args = mir_args_copy(e->module, &grown, 1), .nargs = 1}};
  return block;
}

/* `list.push l, v`: when the list is full, grow it, then store the element after the last. */
static void expand_push(Expander *e, const MirInst *inst, MirBlockData *cur) {
  const MirLoc loc = inst->loc;
  const MirValue list = inst->args[0];
  const MirTy ty = mir_value_ty(e->func, list);
  const MirValue len = emit(e, cur, MOP_ListLen, &list, 1, mir_imm_none(), MIR_INT, loc);
  const MirValue cap = emit(e, cur, MOP_ListCap, &list, 1, mir_imm_none(), MIR_INT, loc);
  const MirValue full = emit_cmp(e, cur, MOP_ICmp, MCC_EQ, len, cap, loc);
  const MirBlock grow = e->next;
  const MirBlock ready = e->next + 1;
  e->next += 2;
  cur->term = (MirTerm){.kind = MT_CONDBR,
                        .value = full,
                        .a = {.block = grow},
                        .b = {.block = ready, .args = mir_args_copy(e->module, &list, 1), .nargs = 1}};
  mir_block_list_push(&e->out, *cur);
  mir_block_list_push(&e->out, grow_block(e, list, cap, ready, loc));
  const MirValue param = mir_new_value(e->func, ty);
  MirBlockData next = mir_block_empty();
  mir_block_param_list_push(&next.params, (MirBlockParam){param, MM_MOVE});
  const MirValue push_args[2] = {param, inst->args[1]};
  (void)mir_block_emit(e->module, e->func, &next, MOP_ListPushU, push_args, 2, mir_imm_none(), MIR_NONE, loc);
  next.insts.ptr[next.insts.len - 1].res = inst->res;
  *cur = next;
}

static uint32_t primitive(Expander *e, uint32_t *cached, const char *name, const MirTy *params, uint32_t count,
                          MirTy ret) {
  if (*cached == MIR_NONE) {
    *cached = mir_extern_get(e->module, ms_span_of_text(name), params, count, ret, true, MR_NONE);
  }
  return *cached;
}

static MirValue emit_call(Expander *e, MirBlockData *cur, uint32_t external, const MirValue *args, uint32_t count,
                          MirTy ret, MirLoc loc) {
  return emit(e, cur, MOP_CallRt, args, count, mir_imm_ext(external), ret, loc);
}

static MirValue emit_slot(Expander *e, MirBlockData *cur, MirTy ty, MirLoc loc) {
  return emit(e, cur, MOP_Slot, NULL, 0, (MirImm){.tag = MI_TY, .a = ty}, MIR_PTR, loc);
}

/* An f-string: the pieces are strings and Ints. The lengths are added up (an Int is written in decimal into a
 * 24-byte frame first), the string is made or grown once, and each piece is copied after the last. A join that
 * grows its first string works in a frame {text, block it left}: the block is released after the copies, so a piece
 * that was a view into the old text is still readable while they happen. */
static void expand_join(Expander *e, const MirInst *inst, MirBlockData *cur) {
  const MirLoc loc = inst->loc;
  const bool grow = e->module->externs.ptr[inst->imm.a].role == MR_STRING_JOIN_GROW;
  const uint32_t first = grow ? 1 : 0;
  const MirTy int_params[2] = {MIR_INT, MIR_PTR};
  const uint32_t format = primitive(e, &e->join_format, "msrt_int_format", int_params, 2, MIR_INT);
  MirValue *lens = MS_ARENA_NEW_ARRAY(&e->module->arena, MirValue, inst->nargs);
  MirValue *data = MS_ARENA_NEW_ARRAY(&e->module->arena, MirValue, inst->nargs);
  MirValue frame = MIR_NONE;
  if (grow) {
    frame = emit_slot(e, cur, MIR_BYTES, loc);
    const MirValue stored[2] = {frame, inst->args[0]};
    (void)emit(e, cur, MOP_Put, stored, 2, mir_imm_none(), MIR_NONE, loc);
  }
  MirValue total = MIR_NONE;
  for (uint32_t at = first; at < inst->nargs; at++) {
    const MirValue piece = inst->args[at];
    if (mir_value_ty(e->func, piece) == MIR_INT) {
      data[at] = emit_slot(e, cur, MIR_BYTES, loc);
      const MirValue written[2] = {piece, data[at]};
      lens[at] = emit_call(e, cur, format, written, 2, MIR_INT, loc);
    } else {
      lens[at] = emit(e, cur, MOP_StrBytes, &piece, 1, mir_imm_none(), MIR_INT, loc);
      data[at] = emit(e, cur, MOP_StrData, &piece, 1, mir_imm_none(), MIR_PTR, loc);
    }
    total = total == MIR_NONE ? lens[at] : emit_pure2(e, cur, MOP_IAdd, total, lens[at], loc);
  }
  MirValue text = frame;
  MirValue cursor = MIR_NONE;
  if (grow) {
    const MirTy params[2] = {MIR_PTR, MIR_INT};
    const MirValue args[2] = {frame, total};
    cursor = emit_call(e, cur, primitive(e, &e->join_extend, "msrt_string_extend", params, 2, MIR_PTR), args, 2,
                       MIR_PTR, loc);
  } else {
    const MirTy params[2] = {MIR_INT, MIR_PTR};
    text = emit_slot(e, cur, MIR_STR, loc);
    const MirValue args[2] = {total, text};
    cursor = emit_call(e, cur, primitive(e, &e->join_open, "msrt_string_open", params, 2, MIR_PTR), args, 2, MIR_PTR,
                       loc);
  }
  for (uint32_t at = first; at < inst->nargs; at++) {
    const MirValue copy[3] = {cursor, data[at], lens[at]};
    (void)emit(e, cur, MOP_MemCopy, copy, 3, mir_imm_none(), MIR_NONE, loc);
    if (at + 1 < inst->nargs) {
      const MirValue step[2] = {cursor, lens[at]};
      cursor = emit(e, cur, MOP_PtrAdd, step, 2, mir_imm_none(), MIR_PTR, loc);
    }
  }
  if (grow) {
    const MirTy params[1] = {MIR_PTR};
    (void)emit_call(e, cur, primitive(e, &e->join_close, "msrt_string_close", params, 1, MIR_VOID), &frame, 1,
                    MIR_VOID, loc);
  }
  MirValue *taken = mir_args_copy(e->module, &text, 1);
  mir_inst_list_push(&cur->insts, mir_inst(MOP_Take, (MirImm){.tag = MI_TY, .a = MIR_STR}, inst->res, loc, taken, 1));
}

static void expand_inst(Expander *e, const MirInst *inst, MirBlockData *cur) {
  if (is_join(e->module, inst)) {
    expand_join(e, inst, cur);
    return;
  }
  switch ((MirOp)inst->op) {
  case MOP_ListPush: expand_push(e, inst, cur); break;
  case MOP_OptUnwrap: expand_unwrap(e, inst, cur); break;
  default: expand_access(e, inst, cur); break;
  }
}

/* Points the targets of an original terminator at the new numbers of the blocks they name. */
static void renumber(MirModule *module, MirTerm *term, const uint32_t *start) {
  switch ((MirTermKind)term->kind) {
  case MT_BR: term->a.block = start[term->a.block]; break;
  case MT_CONDBR:
    term->a.block = start[term->a.block];
    term->b.block = start[term->b.block];
    break;
  case MT_SWITCH: {
    MirCase *cases = MS_ARENA_NEW_ARRAY(&module->arena, MirCase, term->ncases);
    for (uint32_t index = 0; index < term->ncases; index++) {
      cases[index] = term->cases[index];
      cases[index].target.block = start[cases[index].target.block];
    }
    term->cases = cases;
    term->b.block = start[term->b.block];
    break;
  }
  case MT_RET:
  case MT_FAULT:
  case MT_UNREACHABLE: break;
  }
}

static uint32_t block_continuations(const MirBlockData *block, bool checks) {
  uint32_t count = 0;
  for (size_t index = 0; index < block->insts.len; index++) {
    count += continuations((MirOp)block->insts.ptr[index].op, checks);
  }
  return count;
}

/* Rebuilds the instructions of block `old` into `cur` and any continuation blocks it needs. */
static void expand_block(Expander *e, MirBlockData *old, MirBlockData *cur) {
  for (size_t index = 0; index < old->insts.len; index++) {
    const MirInst *inst = &old->insts.ptr[index];
    if (expands(e->module, inst)) {
      expand_inst(e, inst, cur);
    } else {
      mir_inst_list_push(&cur->insts, *inst);
    }
  }
}

static void expand_func(Expander *e) {
  MirBlockList old = e->func->blocks;
  uint32_t *start = MS_ARENA_NEW_ARRAY(&e->module->arena, uint32_t, old.len);
  uint32_t total = 0;
  for (size_t index = 0; index < old.len; index++) {
    start[index] = total;
    total += 1 + block_continuations(&old.ptr[index], e->checks);
  }
  e->fault_base = total;
  mir_block_list_reserve(&e->out, total);
  for (size_t index = 0; index < old.len; index++) {
    e->next = start[index] + 1;
    MirBlockData cur = mir_block_empty();
    cur.params = old.ptr[index].params;
    expand_block(e, &old.ptr[index], &cur);
    cur.term_loc = old.ptr[index].term_loc;
    cur.cold = old.ptr[index].cold;
    cur.term = old.ptr[index].term;
    renumber(e->module, &cur.term, start);
    mir_block_list_push(&e->out, cur);
    mir_inst_list_free(&old.ptr[index].insts);
  }
  for (size_t index = 0; index < e->faults.len; index++) {
    mir_block_list_push(&e->out, e->faults.ptr[index]);
  }
  mir_block_list_free(&old);
  mir_block_list_free(&e->faults);
  e->func->blocks = e->out;
}

static bool func_expands(const MirModule *module, const MirFunc *func) {
  for (size_t bi = 0; bi < func->blocks.len; bi++) {
    for (size_t ii = 0; ii < func->blocks.ptr[bi].insts.len; ii++) {
      if (expands(module, &func->blocks.ptr[bi].insts.ptr[ii])) {
        return true;
      }
    }
  }
  return false;
}

static uint32_t add_index_fault(MirModule *module) {
  const MirTy ints[2] = {MIR_INT, MIR_INT};
  const uint32_t id = mir_extern_get(module, ms_span_of_text("msrt_index_fault"), ints, 2, MIR_VOID, true, MR_NONE);
  module->externs.ptr[id].noreturn = true;
  return id;
}

bool mir_expand(MirModule *module, bool checks) {
  uint32_t index_fault = MIR_NONE;
  bool changed = false;
  for (size_t index = 0; index < module->funcs.len; index++) {
    if (!func_expands(module, &module->funcs.ptr[index])) {
      continue;
    }
    if (index_fault == MIR_NONE) {
      index_fault = add_index_fault(module);
    }
    Expander e = {.module = module, .func = &module->funcs.ptr[index], .checks = checks, .index_fault = index_fault,
                  .join_open = MIR_NONE, .join_extend = MIR_NONE, .join_close = MIR_NONE, .join_format = MIR_NONE};
    expand_func(&e);
    changed = true;
  }
  return changed;
}
