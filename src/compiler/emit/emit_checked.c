/* Owns the operations that can fault: checked arithmetic and division, narrowing, and the pieces they split a
 * block into; also the raw pointer operations and the stack check. */
#include "compiler/emit/emit_cx.h"

#include "abi/layout.h"
#include "compiler/mir/mir_analysis.h"

uint32_t emit_pieces(const MirModule *module, const MirFunc *func, const MirInst *inst) {
  int64_t lo = 0;
  int64_t hi = 0;
  uint32_t sized = mir_sized_result_range(module, func, inst, &lo, &hi) ? 1 : 0;
  switch ((MirOp)inst->op) {
  case MOP_IAddChk:
  case MOP_ISubChk:
  case MOP_IMulChk:
  case MOP_INegChk:
  case MOP_UAddChk:
  case MOP_USubChk:
  case MOP_UMulChk:
  case MOP_SRemChk:
  case MOP_UDivChk:
  case MOP_URemChk:
  case MOP_NarrowChk:
  case MOP_IntOverflowIf:
  case MOP_Poll:
  case MOP_ListNew:
  case MOP_BytesPush:
    return sized + 1;
  case MOP_SDivChk:
    return sized + 2;
  default:
    return sized + emit_record_pieces(module, func, inst);
  }
}

void emit_fault_if(EmitCx *cx, const EmitSite *site, const char *condition, const char *fault,
                   const MirValue *args, uint32_t arg_count) {
  MsStrBuild *out = cx->out;
  uint32_t number = cx->next++;
  *site->part += 1;
  ms_strbuild_printf(out, "  br i1 %s, label %%f%u, label %%", condition, number);
  emit_label(out, site->block, *site->part);
  ms_strbuild_printf(out, "\nf%u:\n  call void @%s(", number, fault);
  for (uint32_t arg = 0; arg < arg_count; arg++) {
    ms_strbuild_printf(out, "%si64 %%v%u", arg == 0 ? "" : ", ", args[arg]);
  }
  ms_strbuild_append_text(out, ") nomerge\n  unreachable\n");
  emit_label(out, site->block, *site->part);
  ms_strbuild_append_text(out, ":\n");
}

/* The operations that are an `llvm.<prefix>.with.overflow` intrinsic: the result is the first member of the
 * pair and the second says whether it overflowed. Signed overflow faults as overflow, unsigned as out of
 * range. */
typedef struct Overflow {
  const char *intrinsic;
  const char *fault;
  MirOp op;
} Overflow;

static const Overflow overflows[] = {
    {"sadd", "msrt_fault_int_overflow", MOP_IAddChk}, {"ssub", "msrt_fault_int_overflow", MOP_ISubChk},
    {"smul", "msrt_fault_int_overflow", MOP_IMulChk}, {"ssub", "msrt_fault_int_overflow", MOP_INegChk},
    {"uadd", "msrt_fault_int_range", MOP_UAddChk},    {"usub", "msrt_fault_int_range", MOP_USubChk},
    {"umul", "msrt_fault_int_range", MOP_UMulChk},
};

static const Overflow *find_overflow(MirOp op) {
  for (size_t index = 0; index < MS_COUNT_OF(overflows); index++) {
    if (overflows[index].op == op) {
      return &overflows[index];
    }
  }
  return NULL;
}

static void checked_arith(EmitCx *cx, const MirInst *inst, const Overflow *kind, const EmitSite *site) {
  const MirValue *args = inst->args;
  uint32_t number = cx->next++;
  bool negate = inst->op == MOP_INegChk;
  ms_strbuild_printf(cx->out, "  %%x%u = call { i64, i1 } @llvm.%s.with.overflow.i64(i64 ", number, kind->intrinsic);
  if (negate) {
    ms_strbuild_printf(cx->out, "0, i64 %%v%u)\n", args[0]);
  } else {
    ms_strbuild_printf(cx->out, "%%v%u, i64 %%v%u)\n", args[0], args[1]);
  }
  ms_strbuild_printf(cx->out, "  %%v%u = extractvalue { i64, i1 } %%x%u, 0\n  %%o%u = extractvalue { i64, i1 } %%x%u, 1\n",
                     inst->res, number, number, number);
  char flag[24];
  emit_register_name(flag, sizeof flag, "o", number);
  int64_t lo = 0;
  int64_t hi = 0;
  bool sized = mir_sized_result_range(cx->module, cx->func, inst, &lo, &hi);
  emit_fault_if(cx, site, flag, sized ? "msrt_fault_int_range" : kind->fault, NULL, 0);
}

/* `udiv.chk` and `urem.chk` fault on a zero divisor; the quotient and remainder of two unsigned values always fit. */
static void checked_unsigned_div(EmitCx *cx, const MirInst *inst, const EmitSite *site) {
  const MirValue *args = inst->args;
  const bool is_div = inst->op == MOP_UDivChk;
  uint32_t number = cx->next++;
  char name[24];
  ms_strbuild_printf(cx->out, "  %%z%u = icmp eq i64 %%v%u, 0\n", number, args[1]);
  emit_register_name(name, sizeof name, "z", number);
  emit_fault_if(cx, site, name, is_div ? "msrt_fault_div_zero" : "msrt_fault_rem_zero", NULL, 0);
  ms_strbuild_printf(cx->out, "  %%v%u = %s i64 %%v%u, %%v%u\n", inst->res, is_div ? "udiv" : "urem", args[0], args[1]);
}

/* `sdiv.chk` faults on a zero divisor and on the one quotient that does not fit, `Int.min / -1`; `srem.chk`
 * faults on a zero divisor and answers 0 for a divisor of -1 (the remainder is defined there, but the
 * instruction is not). */
static void checked_div(EmitCx *cx, const MirInst *inst, const EmitSite *site) {
  MsStrBuild *out = cx->out;
  const MirValue *args = inst->args;
  bool is_div = inst->op == MOP_SDivChk;
  uint32_t number = cx->next++;
  char name[24];
  ms_strbuild_printf(out, "  %%z%u = icmp eq i64 %%v%u, 0\n", number, args[1]);
  emit_register_name(name, sizeof name, "z", number);
  emit_fault_if(cx, site, name, is_div ? "msrt_fault_div_zero" : "msrt_fault_rem_zero", NULL, 0);
  if (is_div) {
    ms_strbuild_printf(out, "  %%m%u = icmp eq i64 %%v%u, -1\n  %%n%u = icmp eq i64 %%v%u, %lld\n", number, args[1],
                       number, args[0], (long long)INT64_MIN);
    ms_strbuild_printf(out, "  %%ob%u = and i1 %%m%u, %%n%u\n", number, number, number);
    emit_register_name(name, sizeof name, "ob", number);
    emit_fault_if(cx, site, name, "msrt_fault_div_overflow", args, 2);
    ms_strbuild_printf(out, "  %%v%u = sdiv i64 %%v%u, %%v%u\n", inst->res, args[0], args[1]);
    return;
  }
  ms_strbuild_printf(out, "  %%m%u = icmp eq i64 %%v%u, -1\n  %%d%u = select i1 %%m%u, i64 1, i64 %%v%u\n", number,
                     args[1], number, number, args[1]);
  ms_strbuild_printf(out, "  %%r%u = srem i64 %%v%u, %%d%u\n  %%v%u = select i1 %%m%u, i64 0, i64 %%r%u\n", number,
                     args[0], number, inst->res, number, number);
}

/* The width and signedness of the sized integer kinds `narrow.chk` checks against. */
typedef struct Narrow {
  MirTyKind kind;
  uint8_t bits;
  bool is_signed;
} Narrow;

static const Narrow narrows[] = {
    {MK_INT8, 8, true},   {MK_INT16, 16, true},   {MK_INT32, 32, true},
    {MK_UINT8, 8, false}, {MK_UINT16, 16, false}, {MK_UINT32, 32, false},
};

/* `narrow.chk`: faults unless the value survives a round trip through the result's width. Other result types
 * hold every `Int`. */
static void narrow_chk(EmitCx *cx, const MirInst *inst, const EmitSite *site) {
  MirTyKind kind = (MirTyKind)mir_ty_data(cx->module, emit_value_type(cx, inst->res))->kind;
  for (size_t index = 0; index < MS_COUNT_OF(narrows); index++) {
    const Narrow *width = &narrows[index];
    if (width->kind != kind) {
      continue;
    }
    uint32_t number = cx->next++;
    ms_strbuild_printf(cx->out,
                       "  %%n%u = trunc i64 %%v%u to i%u\n  %%e%u = %s i%u %%n%u to i64\n"
                       "  %%z%u = icmp ne i64 %%e%u, %%v%u\n",
                       number, inst->args[0], width->bits, number, width->is_signed ? "sext" : "zext", width->bits,
                       number, number, number, inst->args[0]);
    char flag[24];
    emit_register_name(flag, sizeof flag, "z", number);
    emit_fault_if(cx, site, flag, "msrt_fault_int_range", NULL, 0);
    break;
  }
  emit_copy_leaf(cx, inst->res, 0, inst->args[0], 0);
}

/* `iadd.overflow`, `imul.overflow`: whether the signed operation overflows. */
static void overflow_flag(EmitCx *cx, const MirInst *inst) {
  uint32_t number = cx->next++;
  ms_strbuild_printf(cx->out,
                     "  %%x%u = call { i64, i1 } @llvm.%s.with.overflow.i64(i64 %%v%u, i64 %%v%u)\n"
                     "  %%v%u = extractvalue { i64, i1 } %%x%u, 1\n",
                     number, inst->op == MOP_IAddOverflow ? "sadd" : "smul", inst->args[0], inst->args[1],
                     inst->res, number);
}

/* `int_overflow.if`: faults when the flag holds. */
static void overflow_if(EmitCx *cx, const MirInst *inst, const EmitSite *site) {
  char flag[24];
  emit_register_name(flag, sizeof flag, "v", inst->args[0]);
  emit_fault_if(cx, site, flag, "msrt_fault_int_overflow", NULL, 0);
}

/* `inarrow.opt`, `f2i.opt`: the optional is [fits, value]. The value leaf is the integer register itself (or
 * the saturating conversion of the float), which only means something when it fits. */
static void opt_convert(EmitCx *cx, const MirInst *inst) {
  MsStrBuild *out = cx->out;
  uint32_t number = cx->next++;
  MirValue source = inst->args[0];
  if (inst->op == MOP_INarrowOpt) {
    int64_t lo = 0;
    int64_t hi = 0;
    MirTy element = mir_ty_data(cx->module, emit_value_type(cx, inst->res))->elem;
    mir_narrow_range(cx->module, emit_value_type(cx, source), element, &lo, &hi);
    ms_strbuild_printf(out,
                       "  %%o%ua = icmp sge i64 %%v%u, %lld\n  %%o%ub = icmp sle i64 %%v%u, %lld\n"
                       "  %%v%u = and i1 %%o%ua, %%o%ub\n",
                       number, source, (long long)lo, number, source, (long long)hi, inst->res, number, number);
    emit_copy_leaf(cx, inst->res, 1, source, 0);
    return;
  }
  ms_strbuild_printf(out,
                     "  %%o%ua = fcmp oge double %%v%u, -9223372036854775808.0\n"
                     "  %%o%ub = fcmp olt double %%v%u, 9223372036854775808.0\n"
                     "  %%v%u = and i1 %%o%ua, %%o%ub\n"
                     "  %%v%u.1 = call i64 @llvm.fptosi.sat.i64.f64(double %%v%u)\n",
                     number, source, number, source, inst->res, number, number, inst->res, source);
}

/* `stack.low`, `stack.near`: whether the stack pointer is below the running segment's limit (plus the
 * headroom). The limit is the word at the end of the stack's region, which is aligned to its size, so one mask
 * of the frame address finds it. */
static void stack_check(EmitCx *cx, const MirInst *inst) {
  MsStrBuild *out = cx->out;
  uint32_t number = cx->next++;
  ms_strbuild_printf(out, "  %%f%u = call ptr @llvm.frameaddress.p0(i32 0)\n  %%sp%u = ptrtoint ptr %%f%u to i64\n",
                     number, number, number);
  ms_strbuild_printf(out, "  %%sm%u = and i64 %%sp%u, %lld\n  %%c%u = add i64 %%sm%u, %lld\n", number, number,
                     -(long long)MS_STACK_REGION, number, number,
                     (long long)(MS_STACK_REGION - MS_STACK_CELL_LIMIT));
  ms_strbuild_printf(out, "  %%l%up = inttoptr i64 %%c%u to ptr\n  %%l%u = load i64, ptr %%l%up\n", number, number,
                     number, number);
  if (inst->op == MOP_StackNear) {
    ms_strbuild_printf(out, "  %%l%u2 = add i64 %%l%u, %lld\n  %%v%u = icmp ult i64 %%sp%u, %%l%u2\n", number,
                       number, (long long)inst->imm.i, inst->res, number, number);
    return;
  }
  ms_strbuild_printf(out, "  %%v%u = icmp ult i64 %%sp%u, %%l%u\n", inst->res, number, number);
}

/* The memory type of an unsigned access `bytes` wide: `ptr.loadu` and `ptr.storeu` take 1, 2, 4 or 8, and any
 * other width is a word. */
static const char *word_type(int64_t bytes) {
  switch (bytes) {
  case 1:
    return "i8";
  case 2:
    return "i16";
  case 4:
    return "i32";
  default:
    return "i64";
  }
}

static void pointer_load(EmitCx *cx, const MirInst *inst, const char *type, bool word) {
  char base[24];
  emit_pointer(cx, inst->args[0], base, sizeof base);
  uint32_t number = cx->next++;
  ms_strbuild_printf(cx->out, "  %%l%u = load %s, ptr %s\n", number, type, base);
  if (word) {
    ms_strbuild_printf(cx->out, "  %%v%u = or i64 %%l%u, 0\n", inst->res, number);
  } else {
    ms_strbuild_printf(cx->out, "  %%v%u = zext %s %%l%u to i64\n", inst->res, type, number);
  }
}

static void pointer_store(EmitCx *cx, const MirInst *inst, const char *type, bool word) {
  char base[24];
  emit_pointer(cx, inst->args[0], base, sizeof base);
  uint32_t number = cx->next++;
  if (word) {
    ms_strbuild_printf(cx->out, "  store i64 %%v%u, ptr %s\n", inst->args[1], base);
    return;
  }
  ms_strbuild_printf(cx->out, "  %%t%u = trunc i64 %%v%u to %s\n  store %s %%t%u, ptr %s\n", number, inst->args[1],
                     type, type, number, base);
}

static void emit_free(EmitCx *cx, const MirInst *inst) {
  char block[32];
  emit_pointer(cx, inst->args[0], block, sizeof block);
  ms_strbuild_printf(cx->out, "  call void @msrt_free(ptr %s)\n", block);
}

/* `ptr.null`, `ptr.is_null`, `ptr.add`, `ptr.loadu`, `ptr.storeu`, `free`; false when `inst` is none. */
static bool pointer_op(EmitCx *cx, const MirInst *inst, bool *ok) {
  MsStrBuild *out = cx->out;
  int64_t width = inst->imm.tag == MI_INT ? inst->imm.i : 8;
  const char *type = word_type(width);
  bool word = type[1] == '6';
  switch ((MirOp)inst->op) {
  case MOP_Free:
    if (inst->imm.tag != MI_NONE) {
      cx->why = "free of a collection field";
      *ok = false;
      return true;
    }
    emit_free(cx, inst);
    return true;
  case MOP_PtrNull:
    ms_strbuild_printf(out, "  %%v%u = add i64 0, 0\n", inst->res);
    return true;
  case MOP_PtrIsNull:
    ms_strbuild_printf(out, "  %%v%u = icmp eq i64 %%v%u, 0\n", inst->res, inst->args[0]);
    return true;
  case MOP_PtrAdd:
    ms_strbuild_printf(out, "  %%v%u = add i64 %%v%u, %%v%u\n", inst->res, inst->args[0], inst->args[1]);
    return true;
  case MOP_PtrLoadU:
    pointer_load(cx, inst, type, word);
    return true;
  case MOP_PtrStoreU:
    pointer_store(cx, inst, type, word);
    return true;
  default:
    return false;
  }
}

bool emit_checked_op(EmitCx *cx, const MirInst *inst, const EmitSite *site, bool *handled) {
  *handled = true;
  const Overflow *overflow = find_overflow((MirOp)inst->op);
  if (overflow != NULL) {
    checked_arith(cx, inst, overflow, site);
    return true;
  }
  switch ((MirOp)inst->op) {
  case MOP_SDivChk:
  case MOP_SRemChk:
    checked_div(cx, inst, site);
    return true;
  case MOP_UDivChk:
  case MOP_URemChk:
    checked_unsigned_div(cx, inst, site);
    return true;
  case MOP_NarrowChk:
    narrow_chk(cx, inst, site);
    return true;
  case MOP_IAddOverflow:
  case MOP_IMulOverflow:
    overflow_flag(cx, inst);
    return true;
  case MOP_IntOverflowIf:
    overflow_if(cx, inst, site);
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
