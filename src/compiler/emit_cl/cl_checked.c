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

void clx_fault_if(ClCx *cx, cl_val condition, ClPost post, const cl_val *args, uint32_t nargs) {
  cl_fn *f = cx->fb;
  uint32_t exit = 0;
  const bool leaves = fault_exit(cx, &exit);
  const cl_block fault = cl_block_new(f);
  const cl_block next = cl_block_new(f);
  cl_cold(f, fault);
  cl_br(f, condition, fault, next);
  cl_enter(f, fault);
  cl_call(f, clx_post_func(cx->mod, post), args, nargs, NULL);
  if (leaves) {
    cl_jump0(f, cx->blocks[exit]);
  } else {
    /* No exit to leave by (a function that only unwinds): the posted fault ends the program. */
    cl_call(f, clx_post_func(cx->mod, CLX_POST_FAULT_POSTED), NULL, 0, NULL);
    cl_trap(f, 1);
  }
  cl_enter(f, next);
  cx->cur = next;
}

/* The operations that overflow-check: the result is the first member of the pair and the second says whether it
 * overflowed. Signed overflow faults as overflow, unsigned as out of range. */
typedef struct Overflow {
  MirOp op;
  cl_ovfop cl;
  ClPost fault;
} Overflow;

static const Overflow overflows[] = {
    {MOP_IAddChk, CL_SADD_OVF, CLX_POST_INT_OVERFLOW}, {MOP_ISubChk, CL_SSUB_OVF, CLX_POST_INT_OVERFLOW},
    {MOP_IMulChk, CL_SMUL_OVF, CLX_POST_INT_OVERFLOW}, {MOP_INegChk, CL_SSUB_OVF, CLX_POST_INT_OVERFLOW},
    {MOP_UAddChk, CL_UADD_OVF, CLX_POST_INT_RANGE},    {MOP_USubChk, CL_USUB_OVF, CLX_POST_INT_RANGE},
    {MOP_UMulChk, CL_UMUL_OVF, CLX_POST_INT_RANGE},
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
  cl_fn *f = cx->fb;
  cl_val a = inst->op == MOP_INegChk ? clx_const(cx, 0) : clx_arg(cx, inst, 0);
  cl_val b = inst->op == MOP_INegChk ? clx_arg(cx, inst, 0) : clx_arg(cx, inst, 1);
  cl_ovf_result r = cl_ovf(f, kind->cl, a, b);
  clx_set(cx, inst->res, 0, r.result);
  int64_t lo = 0;
  int64_t hi = 0;
  const bool sized = mir_sized_result_range(cx->module, cx->func, inst, &lo, &hi);
  clx_fault_if(cx, r.flag, sized ? CLX_POST_INT_RANGE : kind->fault, NULL, 0);
}

/* A check's result is defined before its fault branch, so the exit it leaves by may be joined by code that uses the
 * result (an inlined callee's exit continues in its caller); on the fault path it is a harmless value. A zero
 * divisor, and the one overflowing quotient, are replaced by 1 for the division itself. */

/* `udiv.chk` and `urem.chk` fault on a zero divisor; the quotient and remainder of two unsigned values always fit. */
static void checked_unsigned_div(ClCx *cx, const MirInst *inst) {
  cl_fn *f = cx->fb;
  const bool is_div = inst->op == MOP_UDivChk;
  cl_val zero = cl_icmp(f, CL_EQ, clx_arg(cx, inst, 1), clx_const(cx, 0));
  cl_val divisor = cl_select(f, zero, clx_const(cx, 1), clx_arg(cx, inst, 1));
  clx_set(cx, inst->res, 0, is_div ? cl_udiv(f, clx_arg(cx, inst, 0), divisor) : cl_urem(f, clx_arg(cx, inst, 0), divisor));
  clx_fault_if(cx, zero, is_div ? CLX_POST_DIV_ZERO : CLX_POST_REM_ZERO, NULL, 0);
}

/* `sdiv.chk` faults on a zero divisor and on the one quotient that does not fit, `Int.min / -1`; `srem.chk`
 * faults on a zero divisor and answers 0 for a divisor of -1 (the remainder is defined there, but the
 * instruction is not). */
static void checked_div(ClCx *cx, const MirInst *inst) {
  cl_fn *f = cx->fb;
  const bool is_div = inst->op == MOP_SDivChk;
  cl_val a = clx_arg(cx, inst, 0);
  cl_val b = clx_arg(cx, inst, 1);
  cl_val zero = cl_icmp(f, CL_EQ, b, clx_const(cx, 0));
  cl_val minus_one = cl_icmp(f, CL_EQ, b, clx_const(cx, -1));
  if (is_div) {
    cl_val min = cl_icmp(f, CL_EQ, a, clx_const(cx, INT64_MIN));
    cl_val overflow = cl_band(f, minus_one, min);
    cl_val bad = cl_bor(f, zero, overflow);
    clx_set(cx, inst->res, 0, cl_sdiv(f, a, cl_select(f, bad, clx_const(cx, 1), b)));
    clx_fault_if(cx, zero, CLX_POST_DIV_ZERO, NULL, 0);
    clx_fault_if(cx, overflow, CLX_POST_DIV_OVERFLOW, (cl_val[]){a, b}, 2);
    return;
  }
  cl_val bad = cl_bor(f, zero, minus_one);
  cl_val rem = cl_srem(f, a, cl_select(f, bad, clx_const(cx, 1), b));
  clx_set(cx, inst->res, 0, cl_select(f, minus_one, clx_const(cx, 0), rem));
  clx_fault_if(cx, zero, CLX_POST_REM_ZERO, NULL, 0);
}

/* The width and signedness of the sized integer kinds `narrow.chk` checks against. */
typedef struct Narrow {
  MirTyKind kind;
  cl_type type;
  bool is_signed;
} Narrow;

static const Narrow narrows[] = {
    {MK_INT8, CL_I8, true},   {MK_INT16, CL_I16, true},   {MK_INT32, CL_I32, true},
    {MK_UINT8, CL_I8, false}, {MK_UINT16, CL_I16, false}, {MK_UINT32, CL_I32, false},
};

/* `narrow.chk`: faults unless the value survives a round trip through the result's width. Other result types
 * hold every `Int`. */
static void narrow_chk(ClCx *cx, const MirInst *inst) {
  cl_fn *f = cx->fb;
  const MirTyKind kind = (MirTyKind)mir_ty_data(cx->module, clx_value_type(cx, inst->res))->kind;
  for (size_t index = 0; index < MS_COUNT_OF(narrows); index++) {
    const Narrow *width = &narrows[index];
    if (width->kind != kind) {
      continue;
    }
    cl_val a = clx_arg(cx, inst, 0);
    cl_val narrow = cl_cast(f, CL_IREDUCE, width->type, a);
    cl_val back = cl_cast(f, width->is_signed ? CL_SEXTEND : CL_UEXTEND, CL_I64, narrow);
    clx_copy_leaf(cx, inst->res, 0, inst->args[0], 0); /* defined before the fault branch, as every check's is */
    clx_fault_if(cx, cl_icmp(f, CL_NE, back, a), CLX_POST_INT_RANGE, NULL, 0);
    return;
  }
  clx_copy_leaf(cx, inst->res, 0, inst->args[0], 0);
}

/* `iadd.overflow`, `imul.overflow`: whether the signed operation overflows. */
static void overflow_flag(ClCx *cx, const MirInst *inst) {
  cl_ovf_result r = cl_ovf(cx->fb, inst->op == MOP_IAddOverflow ? CL_SADD_OVF : CL_SMUL_OVF,
                                 clx_arg(cx, inst, 0), clx_arg(cx, inst, 1));
  clx_set(cx, inst->res, 0, r.flag);
}

/* `inarrow.opt`, `f2i.opt`: the optional is [fits, value]. The value leaf is the integer register itself (or
 * the saturating conversion of the float), which only means something when it fits. */
static void opt_convert(ClCx *cx, const MirInst *inst) {
  cl_fn *f = cx->fb;
  const MirValue source = inst->args[0];
  cl_val x = clx_get(cx, source, 0);
  if (inst->op == MOP_INarrowOpt) {
    int64_t lo = 0;
    int64_t hi = 0;
    const MirTy element = mir_ty_data(cx->module, clx_value_type(cx, inst->res))->elem;
    mir_narrow_range(cx->module, clx_value_type(cx, source), element, &lo, &hi);
    cl_val fits = cl_band(f, cl_icmp(f, CL_SGE, x, clx_const(cx, lo)), cl_icmp(f, CL_SLE, x, clx_const(cx, hi)));
    clx_set(cx, inst->res, 0, fits);
    clx_copy_leaf(cx, inst->res, 1, source, 0);
    return;
  }
  cl_val ge = cl_fcmp(f, CL_FGE, x, cl_f64const(f, -9223372036854775808.0));
  cl_val lt = cl_fcmp(f, CL_FLT, x, cl_f64const(f, 9223372036854775808.0));
  clx_set(cx, inst->res, 0, cl_band(f, ge, lt));
  clx_set(cx, inst->res, 1, cl_cast(f, CL_FCVT_TO_SINT_SAT, CL_I64, x));
}

/* `stack.low`, `stack.near`: whether the stack pointer is below the running segment's limit (plus the
 * headroom). The limit is the word at the end of the stack's region, which is aligned to its size, so one mask
 * of an address in the frame finds it. */
static void stack_check(ClCx *cx, const MirInst *inst) {
  cl_fn *f = cx->fb;
  cl_val sp = cl_sp(f);
  cl_val region = cl_band(f, sp, clx_const(cx, -(int64_t)MS_STACK_REGION));
  cl_val cell = cl_iadd(f, region, clx_const(cx, (int64_t)(MS_STACK_REGION - MS_STACK_CELL_LIMIT)));
  cl_val limit = cl_load(f, CL_I64, CL_NOTRAP, cell, 0);
  if (inst->op == MOP_StackNear) {
    limit = cl_iadd(f, limit, clx_const(cx, inst->imm.i));
  }
  clx_set(cx, inst->res, 0, cl_icmp(f, CL_ULT, sp, limit));
}

/* The memory type of an unsigned access `bytes` wide: `ptr.loadu` and `ptr.storeu` take 1, 2, 4 or 8, and any
 * other width is a word. */
static uint32_t access_bits(int64_t bytes) {
  return bytes == 1 || bytes == 2 || bytes == 4 ? (uint32_t)bytes * 8 : 64;
}

static void pointer_load(ClCx *cx, const MirInst *inst, uint32_t bits) {
  cl_val base = clx_arg(cx, inst, 0);
  clx_set(cx, inst->res, 0,
         bits == 64 ? cl_load(cx->fb, CL_I64, CL_NOTRAP, base, 0)
                    : cl_load_ext(cx->fb, bits, 0, CL_I64, CL_NOTRAP, base, 0));
}

static void pointer_store(ClCx *cx, const MirInst *inst, uint32_t bits) {
  cl_val base = clx_arg(cx, inst, 0);
  if (bits == 64) {
    cl_store(cx->fb, CL_NOTRAP, clx_arg(cx, inst, 1), base, 0);
    return;
  }
  cl_store_trunc(cx->fb, bits, CL_NOTRAP, clx_arg(cx, inst, 1), base, 0);
}

/* `ptr.null`, `ptr.is_null`, `ptr.add`, `ptr.loadu`, `ptr.storeu`, `free`; false when `inst` is none. */
static bool pointer_op(ClCx *cx, const MirInst *inst) {
  cl_fn *f = cx->fb;
  const uint32_t bits = access_bits(inst->imm.tag == MI_INT ? inst->imm.i : 8);
  switch ((MirOp)inst->op) {
  case MOP_Free: {
    if (inst->imm.tag != MI_NONE) {
      return false; /* a collection field: clx_record_op */
    }
    cl_call(f, clx_runtime_func(cx->mod, "msrt_free", 1, false), (cl_val[]){clx_arg(cx, inst, 0)}, 1, NULL);
    return true;
  }
  case MOP_PtrNull:
    clx_set(cx, inst->res, 0, clx_const(cx, 0));
    return true;
  case MOP_PtrIsNull:
    clx_set(cx, inst->res, 0, cl_icmp(f, CL_EQ, clx_arg(cx, inst, 0), clx_const(cx, 0)));
    return true;
  case MOP_PtrAdd:
    clx_set(cx, inst->res, 0, cl_iadd(f, clx_arg(cx, inst, 0), clx_arg(cx, inst, 1)));
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

bool clx_checked_op(ClCx *cx, const MirInst *inst, bool *handled) {
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
    clx_fault_if(cx, clx_arg(cx, inst, 0), CLX_POST_INT_OVERFLOW, NULL, 0);
    return true;
  case MOP_FaultSite: /* the checked instruction before it reaches this block's exit by its cold path; this test is false */
    clx_set(cx, inst->res, 0, cl_iconst(cx->fb, CL_I8, 0));
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
  if (pointer_op(cx, inst)) {
    return true;
  }
  *handled = false;
  return true;
}
