/* compiler/mir/mir_elab_emit.c: drop elaboration, emission helpers: instructions and terminators, cleanup
 * entries, drop flags, and slot refill. */
#include "compiler/mir/mir_elab.h"

/* ---- instruction and terminator helpers ---- */

MirBlock em_new_block(ElEm *em) {
  const MirBlock block = mir_new_block(em->f);
  em->f->blocks.ptr[block].term_loc = MIR_LOC_NONE;
  return block;
}

MirImm em_imm_func(uint32_t id) {
  return (MirImm){.tag = MI_FUNC, .a = id};
}

MirImm em_imm_case(uint32_t alt, uint32_t cs) {
  return (MirImm){.tag = MI_CASE, .a = alt, .b = cs};
}

MirValue em_push(ElEm *em, uint32_t at, MirOp op, const MirValue *args, uint32_t nargs, MirImm imm, MirTy ty) {
  const MirValue res = ty == EM_NO_RESULT ? MIR_NONE : mir_new_value(em->f, ty);
  const MirInst inst = mir_inst(op, imm, res, MIR_LOC_NONE, mir_args_copy(em->m, args, nargs), nargs);
  mir_inst_list_push(&em->f->blocks.ptr[at].insts, inst);
  return res;
}

MirValue em_bconst(ElEm *em, uint32_t at, bool value) {
  return em_push(em, at, MOP_BConst, NULL, 0, (MirImm){.tag = MI_BOOL, .a = value ? 1 : 0}, MIR_BOOL);
}

MirValue em_iconst(ElEm *em, uint32_t at, int64_t value) {
  return em_push(em, at, MOP_IConst, NULL, 0, mir_imm_int(value), MIR_INT);
}

void em_br(ElEm *em, uint32_t at, MirBlock to, const MirValue *args, uint32_t nargs) {
  MirTerm *term = &em->f->blocks.ptr[at].term;
  *term = (MirTerm){.kind = MT_BR};
  term->a = (MirTarget){to, mir_args_copy(em->m, args, nargs), nargs};
}

void em_condbr(ElEm *em, uint32_t at, MirValue cond, MirBlock then, MirBlock otherwise) {
  MirTerm *term = &em->f->blocks.ptr[at].term;
  *term = (MirTerm){.kind = MT_CONDBR, .value = cond};
  term->a = (MirTarget){then, NULL, 0};
  term->b = (MirTarget){otherwise, NULL, 0};
}

MirValue em_block_param(ElEm *em, MirBlock block, MirTy ty, MirMode mode) {
  const MirValue value = mir_new_value(em->f, ty);
  mir_block_param_list_push(&em->f->blocks.ptr[block].params, (MirBlockParam){value, (uint8_t)mode});
  return value;
}

bool em_flag_of(const MirHash *map, MirValue key, MirValue *out) {
  uint64_t value = 0;
  if (!mh_get(map, key, &value)) {
    return false;
  }
  *out = (MirValue)value;
  return true;
}

/* ---- cleanup entries ---- */

void em_discard(ElEm *em, uint32_t at, MirValue value) {
  MirValue handle = MIR_NONE;
  if (em_flag_of(&em->handles, value, &handle) && em->cx->discard != MIR_NONE) {
    em_push(em, at, MOP_CallRt, &handle, 1, mir_imm_ext(em->cx->discard), MIR_VOID);
  }
}

/* The function that closes `value`: the module's `close` for kind 1 (it returns the failure code), else the
 * owner's own function, `fn(borrow T) -> unit`, named by kind - 2. */
bool em_closer(ElEm *em, MirValue value, uint32_t *close) {
  const int64_t kind = em->cx->tag_kind[value];
  if (kind != 1) {
    *close = (uint32_t)(kind - 2);
    return true;
  }
  *close = em->cx->close;
  return *close != MIR_NONE || el_fail(em->cx, "a closing owner needs a `close` function");
}

bool em_register(ElEm *em, uint32_t at, MirValue value) {
  uint32_t close = 0;
  if (!em_closer(em, value, &close)) {
    return false;
  }
  const MirValue handle = em_push(em, at, MOP_CleanupPush, &value, 1, em_imm_func(close), MIR_INT);
  (void)mh_put(em->cx->ma, &em->handles, value, handle);
  return true;
}

/* Registers a new cleanup entry for the refilled slot owner `value`; returns its handle. */
bool em_reregister(ElEm *em, uint32_t at, MirValue value, MirValue key, MirValue *handle) {
  uint32_t close = 0;
  if (!em_closer(em, value, &close)) {
    return false;
  }
  *handle = em_push(em, at, MOP_CleanupPush, &value, 1, em_imm_func(close), MIR_INT);
  if (key != MIR_NONE) {
    (void)mh_put(em->cx->ma, &em->flags, key, *handle);
  }
  return true;
}

/* Cancels the cleanup entry of a slot owner whose value moved out, and clears its flag: newer entries stay,
 * and the scope end discards this one. */
void em_cancel(ElEm *em, uint32_t at, MirValue value) {
  MirValue handle = MIR_NONE, key = MIR_NONE;
  const bool live = (em_flag_of(&em->hkeys, value, &key) && em_flag_of(&em->flags, key, &handle)) ||
                    em_flag_of(&em->handles, value, &handle);
  if (live && em->cx->cancel != MIR_NONE) {
    em_push(em, at, MOP_CallRt, &handle, 1, mir_imm_ext(em->cx->cancel), MIR_VOID);
  }
  if (mh_has(&em->flagged, value)) {
    (void)mh_put(em->cx->ma, &em->flags, value, em_bconst(em, at, false));
  }
}

/* The refilled owner holds a value again. */
void em_set_held(ElEm *em, uint32_t at, MirValue value) {
  if (mh_has(&em->flagged, value)) {
    (void)mh_put(em->cx->ma, &em->flags, value, em_bconst(em, at, true));
  }
}

static bool is_block_param(const MirFunc *func, MirValue value) {
  for (size_t b = 0; b < func->blocks.len; b++) {
    const MirBlockParamList *params = &func->blocks.ptr[b].params;
    for (size_t i = 0; i < params->len; i++) {
      if (params->ptr[i].value == value) {
        return true;
      }
    }
  }
  return false;
}

/* Initializes the flag of a new flagged owner, and registers a closing owner that arrives as a block
 * parameter where it is defined. */
void em_birth(ElEm *em, uint32_t at, MirValue value) {
  if (mh_has(&em->flagged, value)) {
    (void)mh_put(em->cx->ma, &em->flags, value, em_bconst(em, at, true));
  }
  if (!el_tagged(em->cx, value) || em->cx->tag_kind[value] < 1 || mh_has(&em->handles, value)) {
    return;
  }
  if (is_block_param(em->f, value)) {
    (void)em_register(em, at, value); /* an error here surfaces at the scope end */
  }
}

/* The operand for a consuming position: a flagged owner stays live and its operand is a `move.out` of it;
 * the flag turns false. A closing owner retires its cleanup entry. */
MirValue em_move_arg(ElEm *em, uint32_t at, MirValue arg) {
  em_discard(em, at, arg);
  if (!mh_has(&em->flagged, arg)) {
    return arg;
  }
  const MirValue moved = em_push(em, at, MOP_MoveOut, &arg, 1, mir_imm_none(), mir_value_ty(em->f, arg));
  (void)mh_put(em->cx->ma, &em->flags, arg, em_bconst(em, at, false));
  return moved;
}

/* ---- slot refill ---- */

/* Closes what the slot owner `value` holds, shielded, and releases what the close leaves; its cleanup entry
 * stays for the value stored next. */
static bool close_replaced(ElEm *em, uint32_t at, MirValue value) {
  uint32_t close = 0;
  if (!em_closer(em, value, &close)) {
    return false;
  }
  const MirFunc *closer = &em->m->funcs.ptr[close];
  if (closer->has_slot_result) {
    MirValue result = MIR_NONE;
    if (!em_close_result(em, at, value, closer->slot_result, &result)) {
      return false;
    }
    em_drop_owned(em, at, result);
    return true;
  }
  if (em->cx->shield_enter == MIR_NONE) {
    return el_fail(em->cx, "a closing owner needs the shield calls");
  }
  em_push(em, at, MOP_CallRt, NULL, 0, mir_imm_ext(em->cx->shield_enter), MIR_VOID);
  em_push(em, at, MOP_Call, &value, 1, em_imm_func(close), MIR_VOID);
  em_push(em, at, MOP_CallRt, NULL, 0, mir_imm_ext(em->cx->shield_exit), MIR_VOID);
  if (closer->has_slot_close) {
    const MirValue left = em_push(em, at, MOP_Take, &value, 1, (MirImm){.tag = MI_TY, .a = closer->slot_close},
                                  closer->slot_close);
    em_push(em, at, MOP_Drop, &left, 1, mir_imm_none(), EM_NO_RESULT);
  }
  return true;
}

/* The slot owner may have moved out on some paths: the flag says which, and the join carries the new
 * cleanup entry's handle when the owner has a key for it. */
static bool refill_flagged(ElEm *em, uint32_t *at, MirValue value, MirValue flag, MirValue key) {
  if (flag == MIR_NONE) {
    return el_fail(em->cx, "a moved slot owner without a drop flag");
  }
  const MirBlock yes = em_new_block(em);
  const MirBlock no = em_new_block(em);
  const MirBlock join = em_new_block(em);
  em_condbr(em, *at, flag, yes, no);
  if (!close_replaced(em, yes, value)) {
    return false;
  }
  MirValue kept = MIR_NONE, handle = MIR_NONE;
  if (key != MIR_NONE) {
    (void)em_flag_of(&em->flags, key, &kept);
  }
  em_br(em, yes, join, &kept, kept != MIR_NONE ? 1 : 0);
  if (!em_reregister(em, no, value, key, &handle)) {
    return false;
  }
  const MirValue fresh = key != MIR_NONE ? handle : MIR_NONE;
  em_br(em, no, join, &fresh, fresh != MIR_NONE ? 1 : 0);
  if (key != MIR_NONE) {
    (void)mh_put(em->cx->ma, &em->flags, key, em_block_param(em, join, MIR_INT, MM_BORROW));
  }
  em_set_held(em, join, value);
  *at = join;
  return true;
}

/* The program is about to store a new value in the slot owner `value` (`scope.mark 2`): what it still holds
 * is closed shielded (the replaced value), and a slot whose value moved out registers a fresh cleanup entry
 * for the value stored next. `*at` becomes the block to continue in. */
bool em_refill(ElEm *em, uint32_t *at, MirValue value, bool has_state, ElSt was) {
  MirValue flag = MIR_NONE, key = MIR_NONE, handle = MIR_NONE;
  (void)em_flag_of(&em->flags, value, &flag);
  (void)em_flag_of(&em->hkeys, value, &key);
  if (has_state && was == EL_MOVED) {
    if (!em_reregister(em, *at, value, key, &handle)) {
      return false;
    }
    em_set_held(em, *at, value);
    return true;
  }
  if (!has_state || (was != EL_MAYBE && was != EL_CLOSED_OR_MOVED)) {
    return close_replaced(em, *at, value);
  }
  return refill_flagged(em, at, value, flag, key);
}
