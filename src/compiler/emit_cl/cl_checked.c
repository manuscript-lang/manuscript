/* Owns the operations that can fault: checked arithmetic and division, narrowing, and the cold blocks they branch
 * to; also the raw pointer operations and the stack check. */
#include "compiler/emit_cl/cl_cx.h"

#include "abi/layout.h"
#include "compiler/mir/mir_analysis.h"

/* The block the fault of the instruction being lowered leaves by: the true edge of the `fault.site` test that follows
 * it, whose block is the exit that closes what is owned there. False when the instruction has no such site, or the
 * exit takes arguments (a fault block has none to give). */
static bool fault_exit(const ClCx *cx, uint32_t *exit) {
  const MirBlockData *block = &cx->func->blocks.ptr[cx->cur_block];
  if (cx->cur_index >= block->insts.len) {
    return false;
  }
  const MirValue result = block->insts.ptr[cx->cur_index].res;
  if (result == MIR_NONE || block->term.kind != MT_CONDBR || block->term.a.nargs != 0) {
    return false;
  }
  for (size_t at = cx->cur_index + 1; at < block->insts.len; at++) {
    const MirInst *test = &block->insts.ptr[at];
    if (test->op == MOP_FaultSite && test->args[0] == result && test->res == block->term.value) {
      *exit = block->term.a.block;
      return true;
    }
  }
  return false;
}

void cl_fault_if(ClCx *cx, ms_cl_val condition, ClPost post, const ms_cl_val *args, uint32_t nargs) {
  ms_cl_fn *f = cx->fb;
  uint32_t exit = 0;
  const bool leaves = fault_exit(cx, &exit);
  const ms_cl_block fault = ms_cl_block_new(f);
  const ms_cl_block next = ms_cl_block_new(f);
  ms_cl_cold(f, fault);
  ms_cl_br(f, condition, fault, next);
  ms_cl_enter(f, fault);
  ms_cl_call(f, cl_post_func(cx->mod, post), args, nargs, NULL);
  if (leaves) {
    ms_cl_jump0(f, cx->blocks[exit]);
  } else {
    /* No exit to leave by (a function that only unwinds): the posted fault ends the program. */
    ms_cl_call(f, cl_post_func(cx->mod, CL_POST_FAULT_POSTED), NULL, 0, NULL);
    ms_cl_trap(f, 1);
  }
  ms_cl_enter(f, next);
  cx->cur = next;
}

/* The operations that overflow-check: the result is the first member of the pair and the second says whether it
 * overflowed. Signed overflow faults as overflow, unsigned as out of range. */
typedef struct Overflow {
  MirOp op;
  ms_cl_ovfop cl;
  ClPost fault;
} Overflow;

static const Overflow overflows[] = {
    {MOP_IAddChk, MS_CL_SADD_OVF, CL_POST_INT_OVERFLOW}, {MOP_ISubChk, MS_CL_SSUB_OVF, CL_POST_INT_OVERFLOW},
    {MOP_IMulChk, MS_CL_SMUL_OVF, CL_POST_INT_OVERFLOW}, {MOP_INegChk, MS_CL_SSUB_OVF, CL_POST_INT_OVERFLOW},
    {MOP_UAddChk, MS_CL_UADD_OVF, CL_POST_INT_RANGE},    {MOP_USubChk, MS_CL_USUB_OVF, CL_POST_INT_RANGE},
    {MOP_UMulChk, MS_CL_UMUL_OVF, CL_POST_INT_RANGE},
};

static const Overflow *find_overflow(MirOp op) {
  for (size_t index = 0; index < MS_COUNT_OF(overflows); index++) {
    if (overflows[index].op == op) {
      return &overflows[index];
    }
  }
  return NULL;
}

static void checked_arith(ClCx *cx, const MirInst *inst, const Overflow *kind) {
  ms_cl_fn *f = cx->fb;
  ms_cl_val a = inst->op == MOP_INegChk ? cl_const(cx, 0) : cl_arg(cx, inst, 0);
  ms_cl_val b = inst->op == MOP_INegChk ? cl_arg(cx, inst, 0) : cl_arg(cx, inst, 1);
  ms_cl_ovf_result r = ms_cl_ovf(f, kind->cl, a, b);
  cl_set(cx, inst->res, 0, r.result);
  int64_t lo = 0;
  int64_t hi = 0;
  const bool sized = mir_sized_result_range(cx->module, cx->func, inst, &lo, &hi);
  cl_fault_if(cx, r.flag, sized ? CL_POST_INT_RANGE : kind->fault, NULL, 0);
}

/* A check's result is defined before its fault branch, so the exit it leaves by may be joined by code that uses the
 * result (an inlined callee's exit continues in its caller); on the fault path it is a harmless value. A zero
 * divisor, and the one overflowing quotient, are replaced by 1 for the division itself. */

/* `udiv.chk` and `urem.chk` fault on a zero divisor; the quotient and remainder of two unsigned values always fit. */
static void checked_unsigned_div(ClCx *cx, const MirInst *inst) {
  ms_cl_fn *f = cx->fb;
  const bool is_div = inst->op == MOP_UDivChk;
  ms_cl_val zero = ms_cl_icmp(f, MS_CL_EQ, cl_arg(cx, inst, 1), cl_const(cx, 0));
  ms_cl_val divisor = ms_cl_select(f, zero, cl_const(cx, 1), cl_arg(cx, inst, 1));
  cl_set(cx, inst->res, 0, is_div ? ms_cl_udiv(f, cl_arg(cx, inst, 0), divisor) : ms_cl_urem(f, cl_arg(cx, inst, 0), divisor));
  cl_fault_if(cx, zero, is_div ? CL_POST_DIV_ZERO : CL_POST_REM_ZERO, NULL, 0);
}

/* `sdiv.chk` faults on a zero divisor and on the one quotient that does not fit, `Int.min / -1`; `srem.chk`
 * faults on a zero divisor and answers 0 for a divisor of -1 (the remainder is defined there, but the
 * instruction is not). */
static void checked_div(ClCx *cx, const MirInst *inst) {
  ms_cl_fn *f = cx->fb;
  const bool is_div = inst->op == MOP_SDivChk;
  ms_cl_val a = cl_arg(cx, inst, 0);
  ms_cl_val b = cl_arg(cx, inst, 1);
  ms_cl_val zero = ms_cl_icmp(f, MS_CL_EQ, b, cl_const(cx, 0));
  ms_cl_val minus_one = ms_cl_icmp(f, MS_CL_EQ, b, cl_const(cx, -1));
  if (is_div) {
    ms_cl_val min = ms_cl_icmp(f, MS_CL_EQ, a, cl_const(cx, INT64_MIN));
    ms_cl_val overflow = ms_cl_band(f, minus_one, min);
    ms_cl_val bad = ms_cl_bor(f, zero, overflow);
    cl_set(cx, inst->res, 0, ms_cl_sdiv(f, a, ms_cl_select(f, bad, cl_const(cx, 1), b)));
    cl_fault_if(cx, zero, CL_POST_DIV_ZERO, NULL, 0);
    cl_fault_if(cx, overflow, CL_POST_DIV_OVERFLOW, (ms_cl_val[]){a, b}, 2);
    return;
  }
  ms_cl_val bad = ms_cl_bor(f, zero, minus_one);
  ms_cl_val rem = ms_cl_srem(f, a, ms_cl_select(f, bad, cl_const(cx, 1), b));
  cl_set(cx, inst->res, 0, ms_cl_select(f, minus_one, cl_const(cx, 0), rem));
  cl_fault_if(cx, zero, CL_POST_REM_ZERO, NULL, 0);
}

/* The width and signedness of the sized integer kinds `narrow.chk` checks against. */
typedef struct Narrow {
  MirTyKind kind;
  ms_cl_type type;
  bool is_signed;
} Narrow;

static const Narrow narrows[] = {
    {MK_INT8, MS_CL_I8, true},   {MK_INT16, MS_CL_I16, true},   {MK_INT32, MS_CL_I32, true},
    {MK_UINT8, MS_CL_I8, false}, {MK_UINT16, MS_CL_I16, false}, {MK_UINT32, MS_CL_I32, false},
};

/* `narrow.chk`: faults unless the value survives a round trip through the result's width. Other result types
 * hold every `Int`. */
static void narrow_chk(ClCx *cx, const MirInst *inst) {
  ms_cl_fn *f = cx->fb;
  const MirTyKind kind = (MirTyKind)mir_ty_data(cx->module, cl_value_type(cx, inst->res))->kind;
  for (size_t index = 0; index < MS_COUNT_OF(narrows); index++) {
    const Narrow *width = &narrows[index];
    if (width->kind != kind) {
      continue;
    }
    ms_cl_val a = cl_arg(cx, inst, 0);
    ms_cl_val narrow = ms_cl_cast(f, MS_CL_IREDUCE, width->type, a);
    ms_cl_val back = ms_cl_cast(f, width->is_signed ? MS_CL_SEXTEND : MS_CL_UEXTEND, MS_CL_I64, narrow);
    cl_copy_leaf(cx, inst->res, 0, inst->args[0], 0); /* defined before the fault branch, as every check's is */
    cl_fault_if(cx, ms_cl_icmp(f, MS_CL_NE, back, a), CL_POST_INT_RANGE, NULL, 0);
    return;
  }
  cl_copy_leaf(cx, inst->res, 0, inst->args[0], 0);
}

/* `iadd.overflow`, `imul.overflow`: whether the signed operation overflows. */
static void overflow_flag(ClCx *cx, const MirInst *inst) {
  ms_cl_ovf_result r = ms_cl_ovf(cx->fb, inst->op == MOP_IAddOverflow ? MS_CL_SADD_OVF : MS_CL_SMUL_OVF,
                                 cl_arg(cx, inst, 0), cl_arg(cx, inst, 1));
  cl_set(cx, inst->res, 0, r.flag);
}

/* `inarrow.opt`, `f2i.opt`: the optional is [fits, value]. The value leaf is the integer register itself (or
 * the saturating conversion of the float), which only means something when it fits. */
static void opt_convert(ClCx *cx, const MirInst *inst) {
  ms_cl_fn *f = cx->fb;
  const MirValue source = inst->args[0];
  ms_cl_val x = cl_get(cx, source, 0);
  if (inst->op == MOP_INarrowOpt) {
    int64_t lo = 0;
    int64_t hi = 0;
    const MirTy element = mir_ty_data(cx->module, cl_value_type(cx, inst->res))->elem;
    mir_narrow_range(cx->module, cl_value_type(cx, source), element, &lo, &hi);
    ms_cl_val fits = ms_cl_band(f, ms_cl_icmp(f, MS_CL_SGE, x, cl_const(cx, lo)), ms_cl_icmp(f, MS_CL_SLE, x, cl_const(cx, hi)));
    cl_set(cx, inst->res, 0, fits);
    cl_copy_leaf(cx, inst->res, 1, source, 0);
    return;
  }
  ms_cl_val ge = ms_cl_fcmp(f, MS_CL_FGE, x, ms_cl_f64const(f, -9223372036854775808.0));
  ms_cl_val lt = ms_cl_fcmp(f, MS_CL_FLT, x, ms_cl_f64const(f, 9223372036854775808.0));
  cl_set(cx, inst->res, 0, ms_cl_band(f, ge, lt));
  cl_set(cx, inst->res, 1, ms_cl_cast(f, MS_CL_FCVT_TO_SINT_SAT, MS_CL_I64, x));
}

/* `stack.low`, `stack.near`: whether the stack pointer is below the running segment's limit (plus the
 * headroom). The limit is the word at the end of the stack's region, which is aligned to its size, so one mask
 * of an address in the frame finds it. */
static void stack_check(ClCx *cx, const MirInst *inst) {
  ms_cl_fn *f = cx->fb;
  ms_cl_val sp = ms_cl_sp(f);
  ms_cl_val region = ms_cl_band(f, sp, cl_const(cx, -(int64_t)MS_STACK_REGION));
  ms_cl_val cell = ms_cl_iadd(f, region, cl_const(cx, (int64_t)(MS_STACK_REGION - MS_STACK_CELL_LIMIT)));
  ms_cl_val limit = ms_cl_load(f, MS_CL_I64, MS_CL_NOTRAP, cell, 0);
  if (inst->op == MOP_StackNear) {
    limit = ms_cl_iadd(f, limit, cl_const(cx, inst->imm.i));
  }
  cl_set(cx, inst->res, 0, ms_cl_icmp(f, MS_CL_ULT, sp, limit));
}

/* The memory type of an unsigned access `bytes` wide: `ptr.loadu` and `ptr.storeu` take 1, 2, 4 or 8, and any
 * other width is a word. */
static uint32_t access_bits(int64_t bytes) {
  return bytes == 1 || bytes == 2 || bytes == 4 ? (uint32_t)bytes * 8 : 64;
}

static void pointer_load(ClCx *cx, const MirInst *inst, uint32_t bits) {
  ms_cl_val base = cl_arg(cx, inst, 0);
  cl_set(cx, inst->res, 0,
         bits == 64 ? ms_cl_load(cx->fb, MS_CL_I64, MS_CL_NOTRAP, base, 0)
                    : ms_cl_load_ext(cx->fb, bits, 0, MS_CL_I64, MS_CL_NOTRAP, base, 0));
}

static void pointer_store(ClCx *cx, const MirInst *inst, uint32_t bits) {
  ms_cl_val base = cl_arg(cx, inst, 0);
  if (bits == 64) {
    ms_cl_store(cx->fb, MS_CL_NOTRAP, cl_arg(cx, inst, 1), base, 0);
    return;
  }
  ms_cl_store_trunc(cx->fb, bits, MS_CL_NOTRAP, cl_arg(cx, inst, 1), base, 0);
}

/* `ptr.null`, `ptr.is_null`, `ptr.add`, `ptr.loadu`, `ptr.storeu`, `free`; false when `inst` is none. */
static bool pointer_op(ClCx *cx, const MirInst *inst, bool *ok) {
  ms_cl_fn *f = cx->fb;
  const uint32_t bits = access_bits(inst->imm.tag == MI_INT ? inst->imm.i : 8);
  switch ((MirOp)inst->op) {
  case MOP_Free: {
    if (inst->imm.tag != MI_NONE) {
      cx->why = "free of a collection field";
      *ok = false;
      return true;
    }
    ms_cl_call(f, cl_runtime_func(cx->mod, "msrt_free", 1, false), (ms_cl_val[]){cl_arg(cx, inst, 0)}, 1, NULL);
    return true;
  }
  case MOP_PtrNull:
    cl_set(cx, inst->res, 0, cl_const(cx, 0));
    return true;
  case MOP_PtrIsNull:
    cl_set(cx, inst->res, 0, ms_cl_icmp(f, MS_CL_EQ, cl_arg(cx, inst, 0), cl_const(cx, 0)));
    return true;
  case MOP_PtrAdd:
    cl_set(cx, inst->res, 0, ms_cl_iadd(f, cl_arg(cx, inst, 0), cl_arg(cx, inst, 1)));
    return true;
  case MOP_PtrLoadU:
    pointer_load(cx, inst, bits);
    return true;
  case MOP_PtrStoreU:
    pointer_store(cx, inst, bits);
    return true;
  default:
    return false;
  }
}

bool cl_checked_op(ClCx *cx, const MirInst *inst, bool *handled) {
  *handled = true;
  const Overflow *overflow = find_overflow((MirOp)inst->op);
  if (overflow != NULL) {
    checked_arith(cx, inst, overflow);
    return true;
  }
  switch ((MirOp)inst->op) {
  case MOP_SDivChk:
  case MOP_SRemChk:
    checked_div(cx, inst);
    return true;
  case MOP_UDivChk:
  case MOP_URemChk:
    checked_unsigned_div(cx, inst);
    return true;
  case MOP_NarrowChk:
    narrow_chk(cx, inst);
    return true;
  case MOP_IAddOverflow:
  case MOP_IMulOverflow:
    overflow_flag(cx, inst);
    return true;
  case MOP_IntOverflowIf:
    cl_fault_if(cx, cl_arg(cx, inst, 0), CL_POST_INT_OVERFLOW, NULL, 0);
    return true;
  case MOP_FaultSite: /* the checked instruction before it reaches this block's exit by its cold path; this test is false */
    cl_set(cx, inst->res, 0, ms_cl_iconst(cx->fb, MS_CL_I8, 0));
    return true;
  case MOP_INarrowOpt:
  case MOP_F2IOpt:
    opt_convert(cx, inst);
    return true;
  case MOP_StackLow:
  case MOP_StackNear:
    stack_check(cx, inst);
    return true;
  default:
    break;
  }
  bool ok = true;
  if (pointer_op(cx, inst, &ok)) {
    return ok;
  }
  *handled = false;
  return true;
}
