/* Owns calls: the stack slots a call needs, and the calls of MIR functions and runtime functions. */
#include "compiler/emit/emit_cx.h"


static MirTy value_type(const EmitCx *cx, MirValue value) {
  return cx->func->values.ptr[value];
}

/* `%<prefix><a>_<b>_<c>` (or `%<prefix><a>_<b>` when `c` is not a number) into `out`. */
static size_t put_number(char *out, size_t at, uint32_t number) {
  char digits[10];
  size_t count = 0;
  do {
    digits[count++] = (char)('0' + number % 10);
    number /= 10;
  } while (number != 0);
  while (count > 0) {
    out[at++] = digits[--count];
  }
  return at;
}

static void slot_name(char out[static 48], char prefix, uint32_t block, uint32_t index, uint32_t arg) {
  size_t at = 0;
  out[at++] = '%';
  out[at++] = prefix;
  at = put_number(out, at, block);
  out[at++] = '_';
  at = put_number(out, at, index);
  if (arg != MIR_NONE) {
    out[at++] = '_';
    at = put_number(out, at, arg);
  }
  out[at] = 0;
}

bool emit_rt_direct(EmitCx *cx, MirTy type) {
  return mir_rt_direct(cx->module, cx->layouts, type);
}

/* The frame slots one runtime call needs: a copy of each argument that does not pass directly, and the result
 * area when the result does not. */
static void frame_rt_call(EmitCx *cx, const MirInst *inst, uint32_t block, uint32_t index) {
  const MirExtern *def = &cx->module->externs.ptr[inst->imm.a];
  for (uint32_t arg = 0; arg < inst->nargs; arg++) {
    if (!emit_rt_direct(cx, def->params[arg].ty)) {
      ms_strbuild_printf(cx->out, "  %%p%u_%u_%u = alloca [%u x i8], align 8\n", block, index, arg,
                         emit_slot_bytes(cx, def->params[arg].ty));
    }
  }
  if (!emit_rt_direct(cx, def->ret)) {
    ms_strbuild_printf(cx->out, "  %%r%u_%u = alloca [%u x i8], align 8\n", block, index,
                       emit_slot_bytes(cx, def->ret));
  }
}

/* The frame slots a call of a MIR function needs: the result area when the result has several leaves, and a
 * copy of each argument that passes by address. */
static void frame_call(EmitCx *cx, const MirInst *inst, uint32_t block, uint32_t index) {
  if (inst->res != MIR_NONE && emit_value_leaves(cx, inst->res).len > 1) {
    ms_strbuild_printf(cx->out, "  %%r%u_%u = alloca [%u x i8], align 8\n", block, index,
                       emit_slot_bytes(cx, value_type(cx, inst->res)));
  }
  for (uint32_t arg = 0; arg < inst->nargs; arg++) {
    MirTy type = value_type(cx, inst->args[arg]);
    if (emit_is_indirect(cx, type)) {
      ms_strbuild_printf(cx->out, "  %%x%u_%u_%u = alloca [%u x i8], align 8\n", block, index, arg,
                         emit_slot_bytes(cx, type));
    }
  }
}

void emit_frame_slots(EmitCx *cx) {
  const MirFunc *func = cx->func;
  for (uint32_t block = 0; block < func->blocks.len; block++) {
    const MirBlockData *data = &func->blocks.ptr[block];
    for (uint32_t index = 0; index < data->insts.len; index++) {
      const MirInst *inst = &data->insts.ptr[index];
      switch ((MirOp)inst->op) {
      case MOP_Slot:
        ms_strbuild_printf(cx->out,
                           "  %%s%u = alloca [%u x i8], align 8\n  %%v%u = ptrtoint ptr %%s%u to i64\n", inst->res,
                           emit_slot_bytes(cx, inst->imm.a), inst->res, inst->res);
        break;
      case MOP_Call:
      case MOP_CallInd:
      case MOP_CallMethod:
        frame_call(cx, inst, block, index);
        break;
      case MOP_ClosureNew:
        if (cx->framed != NULL && cx->framed[inst->res]) {
          ms_strbuild_printf(cx->out, "  %%o%u_%u = alloca [%u x i8], align 16\n", block, index,
                             mir_closure_layout(cx->layouts, &cx->module->funcs.ptr[inst->imm.a]).size);
        }
        break;
      case MOP_IfaceBorrow:
        if (cx->borrowed != NULL && cx->borrowed[inst->res]) {
          ms_strbuild_printf(cx->out, "  %%i%u_%u = alloca [%u x i8], align 8\n", block, index,
                             emit_slot_bytes(cx, value_type(cx, inst->args[0])));
        }
        break;
      case MOP_StrByte:
        ms_strbuild_printf(cx->out, "  %%y%u_%u = alloca [16 x i8], align 8\n", block, index);
        break;
      case MOP_CallRt:
        frame_rt_call(cx, inst, block, index);
        break;
      default:
        break;
      }
    }
  }
}

/* Every leaf of every argument, in order, after the hidden result pointer when there is one. */
static void call_arguments(EmitCx *cx, const MirInst *inst, const char *result_area, const char *lead,
                           uint32_t block, uint32_t index) {
  MsStrBuild *out = cx->out;
  bool first = true;
  if (result_area != NULL) {
    ms_strbuild_printf(out, "ptr %s", result_area);
    first = false;
  }
  if (lead != NULL) {
    ms_strbuild_printf(out, "%s%s", first ? "" : ", ", lead);
    first = false;
  }
  for (uint32_t arg = lead != NULL ? 1 : 0; arg < inst->nargs; arg++) {
    MirTy type = value_type(cx, inst->args[arg]);
    if (emit_is_indirect(cx, type)) {
      ms_strbuild_printf(out, "%sptr %%x%u_%u_%u", first ? "" : ", ", block, index, arg);
      first = false;
      continue;
    }
    MsSpan leaves = emit_leaves(cx, type);
    for (uint32_t leaf = 0; leaf < leaves.len; leaf++) {
      ms_strbuild_printf(out, "%s%s ", first ? "" : ", ", emit_leaf_type(leaves.ptr[leaf]));
      emit_name(out, inst->args[arg], leaf);
      first = false;
    }
  }
}

/* Writes each argument that passes by address into its frame slot, before the call. */
static void spill_arguments(EmitCx *cx, const MirInst *inst, uint32_t block, uint32_t index) {
  char slot[48];
  for (uint32_t arg = 0; arg < inst->nargs; arg++) {
    if (emit_is_indirect(cx, value_type(cx, inst->args[arg]))) {
      slot_name(slot, 'x', block, index, arg);
      emit_leaves_at(cx, inst->args[arg], slot, false);
    }
  }
}

/* A call of `callee` (the register holding a code pointer), or of the MIR function the instruction names when it
 * is NULL; `lead`, when given, is the first argument in place of operand 0. A result of several leaves comes
 * back through a stack area that the call is given and that is read leaf by leaf afterwards. */
void emit_call_to(EmitCx *cx, const MirInst *inst, const EmitSite *site, const char *callee, const char *lead) {
  uint32_t block = site->block;
  uint32_t index = site->index;
  MsStrBuild *out = cx->out;
  spill_arguments(cx, inst, block, index);
  uint32_t result_leaves = inst->res == MIR_NONE ? 0 : (uint32_t)emit_value_leaves(cx, inst->res).len;
  char area[48];
  slot_name(area, 'r', block, index, MIR_NONE);
  if (result_leaves == 1) {
    ms_strbuild_printf(out, "  %%v%u = call %s ", inst->res, emit_value_register_type(cx, inst->res));
  } else {
    ms_strbuild_append_text(out, "  call void ");
  }
  if (callee != NULL) {
    ms_strbuild_append_text(out, callee);
  } else {
    emit_function_symbol(cx, inst->imm.a);
  }
  ms_strbuild_append_byte(out, '(');
  call_arguments(cx, inst, result_leaves > 1 ? area : NULL, lead, block, index);
  ms_strbuild_append_text(out, ")\n");
  if (result_leaves > 1) {
    emit_leaves_at(cx, inst->res, area, true);
  }
}

/* Whether extern `def` is a function of a C library: the runtime's own (`msrt_`, `msstd_`) take a Float32 as
 * a double. */
bool emit_extern_is_c(const EmitCx *cx, const MirExtern *def) {
  MsSpan name = ms_names_span(&cx->module->names, def->name);
  return !ms_span_starts_with(name, ms_span_of_text("msrt_")) &&
         !ms_span_starts_with(name, ms_span_of_text("msstd_"));
}

/* Appends one argument of a runtime call to `args`: the leaves of `value` when `type` passes directly, else
 * the address of a stack copy that is written first. */
static void rt_argument(EmitCx *cx, MsStrBuild *args, MirTy type, MirValue value, const char *area,
                        bool c_float) {
  const char *separator = ms_strbuild_length(args) > 0 ? ", " : "";
  if (!emit_rt_direct(cx, type)) {
    emit_leaves_at(cx, value, area, false);
    ms_strbuild_printf(args, "%sptr %s", separator, area);
    return;
  }
  if (type == MIR_PTR) {
    char address[32];
    emit_pointer(cx, value, address, sizeof address);
    ms_strbuild_printf(args, "%sptr %s", separator, address);
    return;
  }
  MsSpan leaves = emit_leaves(cx, type);
  for (uint32_t leaf = 0; leaf < leaves.len; leaf++) {
    separator = ms_strbuild_length(args) > 0 ? ", " : "";
    const char *register_type = emit_leaf_type(leaves.ptr[leaf]);
    if (leaves.ptr[leaf] == MIR_LEAF_F32 && c_float) {
      /* A Float32 is a double in registers; a C library function takes a float (the runtime takes a double). */
      uint32_t number = cx->next++;
      ms_strbuild_printf(cx->out, "  %%fa%u = fptrunc double ", number);
      emit_name(cx->out, value, leaf);
      ms_strbuild_append_text(cx->out, " to float\n");
      ms_strbuild_printf(args, "%sfloat %%fa%u", separator, number);
      continue;
    }
    /* C expects a `bool` argument zero-extended to a byte; LLVM leaves the upper bits of an i1 undefined. */
    bool is_bool = register_type[0] == 'i' && register_type[1] == '1' && register_type[2] == 0;
    ms_strbuild_printf(args, "%s%s%s ", separator, register_type, is_bool ? " zeroext" : "");
    emit_name(args, value, leaf);
  }
}

static const char *widen_op(EmitWiden widen) {
  switch (widen) {
  case EMIT_SEXT:
    return "sext";
  case EMIT_FPEXT:
    return "fpext";
  default:
    return "zext";
  }
}

/* The result of a runtime call that returns a narrow type: the C function leaves the bits above it as they
 * are (the AAPCS64 does not make a callee extend its result), so the call carries no extension attribute and
 * the extension after it reads the low bits only. */
static void widen_rt_result(EmitCx *cx, MirValue res, const EmitLeafKind *kind) {
  if (kind->widen == EMIT_BOOL) {
    ms_strbuild_printf(cx->out, "  %%v%u = trunc i8 %%v%ur to i1\n", res, res);
    return;
  }
  ms_strbuild_printf(cx->out, "  %%v%u = %s %s %%v%ur to %s\n", res, widen_op(kind->widen), kind->mem, res,
                     kind->reg);
}

/* A call of a runtime function, which follows the C ABI of the runtime: scalars by value, everything else by
 * the address of a copy, and a result that is not a scalar through a trailing output pointer. */
static bool call_runtime(EmitCx *cx, const MirInst *inst, uint32_t block, uint32_t index) {
  const MirExtern *def = &cx->module->externs.ptr[inst->imm.a];
  MsStrBuild args = ms_strbuild_new();
  char area[48];
  bool is_c = emit_extern_is_c(cx, def);
  for (uint32_t arg = 0; arg < inst->nargs; arg++) {
    slot_name(area, 'p', block, index, arg);
    rt_argument(cx, &args, def->params[arg].ty, inst->args[arg], area, is_c);
  }
  MsSpan result = emit_leaves(cx, def->ret);
  bool direct = emit_rt_direct(cx, def->ret);
  if (direct && result.len > 1) {
    cx->why = "runtime result of several scalars";
    ms_strbuild_free(&args);
    return false;
  }
  slot_name(area, 'r', block, index, MIR_NONE);
  if (!direct) {
    ms_strbuild_printf(&args, "%sptr %s", ms_strbuild_length(&args) > 0 ? ", " : "", area);
  }
  const EmitLeafKind *kind = direct && result.len == 1 ? emit_leaf_kind(result.ptr[0]) : NULL;
  bool runtime_float = kind != NULL && kind->widen == EMIT_FPEXT && !is_c; /* a double */
  bool narrow = kind != NULL && !ms_span_equal(ms_span_of_text(kind->reg), ms_span_of_text(kind->mem)) &&
                !runtime_float;
  if (narrow) {
    ms_strbuild_printf(cx->out, "  %%v%ur = call %s ", inst->res, kind->mem);
  } else if (kind != NULL) {
    ms_strbuild_printf(cx->out, "  %%v%u = call %s ", inst->res, kind->reg);
  } else {
    ms_strbuild_append_text(cx->out, "  call void ");
  }
  emit_symbol(cx->out, ms_names_span(&cx->module->names, def->name));
  ms_strbuild_append_byte(cx->out, '(');
  ms_strbuild_append(cx->out, ms_strbuild_span(&args));
  ms_strbuild_append_text(cx->out, ")\n");
  if (narrow) {
    widen_rt_result(cx, inst->res, kind);
  }
  if (!direct && inst->res != MIR_NONE) {
    emit_leaves_at(cx, inst->res, area, true);
  }
  ms_strbuild_free(&args);
  return true;
}

bool emit_call_op(EmitCx *cx, const MirInst *inst, const EmitSite *site, bool *handled) {
  *handled = true;
  switch ((MirOp)inst->op) {
  case MOP_Call:
    emit_call_to(cx, inst, site, NULL, NULL);
    return true;
  case MOP_CallRt:
    return call_runtime(cx, inst, site->block, site->index);
  default:
    *handled = false;
    return true;
  }
}
