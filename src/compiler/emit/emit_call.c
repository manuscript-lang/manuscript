/* Owns calls: the stack slots a call needs, and the calls of MIR functions and runtime functions. */
#include "compiler/emit/emit_cx.h"
#include "compiler/mir/mir_analysis.h"
#include "abi/layout.h"
#include "base/alloc.h"
#include "compiler/mir/mir_pass.h"


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

/* An argument copy is dead once its call returns unless the result can point into it (a short string's view
 * does), so a call whose result is void or a number shares one copy slot per argument position, as large as
 * the largest copy; any other call keeps a slot of its own. Positions past SHARED_ARGS keep one per site. */
#define SHARED_ARGS 32u

static bool temps_shared(const EmitCx *cx, const MirInst *inst) {
  MirTy result = MIR_NONE;
  if ((MirOp)inst->op == MOP_CallRt) {
    const MirExtern *external = &cx->module->externs.ptr[inst->imm.a];
    /* A runtime call that neither returns a view nor keeps an argument leaves nothing pointing into the copies. */
    if (!mir_extern_pins_argument(external)) {
      return true;
    }
    result = external->ret;
  } else if (inst->res != MIR_NONE) {
    result = value_type(cx, inst->res);
    /* A function whose result is not a view of an argument leaves nothing pointing into the copies. */
    if ((MirOp)inst->op == MOP_Call && inst->imm.tag == MI_FUNC && inst->imm.a < cx->module->funcs.len &&
        !cx->module->funcs.ptr[inst->imm.a].ret_borrowed) {
      return true;
    }
  } else {
    return true;
  }
  return mir_ty_data(cx->module, result)->kind == MK_VOID || mir_is_scalar(cx->module, result);
}

static void arg_slot_name(const EmitCx *cx, const MirInst *inst, char out[static 48], char prefix, uint32_t block,
                          uint32_t index, uint32_t arg) {
  const bool shared = arg < SHARED_ARGS && temps_shared(cx, inst);
  slot_name(out, prefix, shared ? 0 : block, shared ? 0 : index, arg);
  if (shared) {
    out[1] = (char)(prefix - 'a' + 'A');
  }
}

bool emit_rt_direct(EmitCx *cx, MirTy type) {
  return mir_rt_direct(cx->module, cx->layouts, type);
}

/* An `opt<scalar>` the runtime returns as a C `u8` flag with the payload through a trailing output pointer. */
bool emit_rt_scalar_option(EmitCx *cx, MirTy type) {
  return mir_ty_data(cx->module, type)->kind == MK_OPT && emit_rt_direct(cx, type) && emit_leaves(cx, type).len == 2;
}

/* A call's result area is written by the callee and read leaf by leaf right after the call, so every call shares one
 * area, as large as the largest. */
static void note_result_area(uint32_t *area, uint32_t bytes) {
  *area = bytes > *area ? bytes : *area;
}

/* The frame slots one runtime call needs: a copy of each argument that does not pass directly, and the result
 * area when the result does not. */
static void frame_rt_call(EmitCx *cx, const MirInst *inst, uint32_t block, uint32_t index, uint32_t *shared, uint32_t *area) {
  const MirExtern *def = &cx->module->externs.ptr[inst->imm.a];
  const bool share = temps_shared(cx, inst);
  for (uint32_t arg = 0; arg < inst->nargs; arg++) {
    if (emit_rt_direct(cx, def->params[arg].ty) || emit_wide_held(cx, inst->args[arg])) {
      continue;
    }
    const uint32_t bytes = emit_slot_bytes(cx, def->params[arg].ty);
    if (share && arg < SHARED_ARGS) {
      shared[arg] = bytes > shared[arg] ? bytes : shared[arg];
    } else {
      ms_strbuild_printf(cx->out, "  %%p%u_%u_%u = alloca [%u x i8], align 8\n", block, index, arg, bytes);
    }
  }
  if (!emit_rt_direct(cx, def->ret)) {
    if (inst->res == MIR_NONE || !emit_wide_held(cx, inst->res)) {
      note_result_area(area, emit_slot_bytes(cx, def->ret));
    }
  } else if (emit_rt_scalar_option(cx, def->ret)) {
    note_result_area(area, 8);
  }
}

/* The frame slots a call of a MIR function needs: the result area when the result has several leaves, and a
 * copy of each argument that passes by address. */
static void frame_call(EmitCx *cx, const MirInst *inst, uint32_t block, uint32_t index, uint32_t *shared, uint32_t *area) {
  const bool share = temps_shared(cx, inst);
  if (inst->res != MIR_NONE && emit_value_leaves(cx, inst->res).len > 1 && !emit_wide_held(cx, inst->res)) {
    note_result_area(area, emit_slot_bytes(cx, value_type(cx, inst->res)));
  }
  for (uint32_t arg = 0; arg < inst->nargs; arg++) {
    MirTy type = value_type(cx, inst->args[arg]);
    if (!emit_is_indirect(cx, type) || emit_wide_held(cx, inst->args[arg])) {
      continue;
    }
    const uint32_t bytes = emit_slot_bytes(cx, type);
    if (share && arg < SHARED_ARGS) {
      shared[arg] = bytes > shared[arg] ? bytes : shared[arg];
    } else {
      ms_strbuild_printf(cx->out, "  %%x%u_%u_%u = alloca [%u x i8], align 8\n", block, index, arg, bytes);
    }
  }
}

/* Slots and held values that are never live together share one `%cell` alloca: the biggest go first, each into the
 * first cell none of whose occupants it conflicts with. A function whose conflicts cannot be analysed gives each
 * held value a cell of its own and its slots their own allocas. */
const uint32_t *emit_slot_pool(MsArena *arena, EmitCx *cx, const bool *held) {
  const MirFunc *func = cx->func;
  cx->ncells = 0;
  cx->cell_bytes = NULL;
  cx->cell_escape = NULL;
  const size_t count = func->values.len + 1;
  uint32_t *pool = MS_ARENA_NEW_ARRAY(arena, uint32_t, count);
  for (size_t value = 0; value < count; value++) {
    pool[value] = UINT32_MAX;
  }
  MirCellMap map;
  cx->poison = NULL;
  cx->npoison = 0;
  if (!mir_cell_conflicts(arena, cx->module, func, held, cx->poison_slots, &map)) {
    if (held == NULL) {
      return NULL;
    }
    uint32_t *sizes = MS_ARENA_NEW_ARRAY(arena, uint32_t, count);
    bool *escape = MS_ARENA_NEW_ARRAY(arena, bool, count);
    uint32_t ncells = 0;
    for (uint32_t value = 0; value < func->values.len; value++) {
      if (held[value]) {
        pool[value] = ncells;
        sizes[ncells] = emit_slot_bytes(cx, func->values.ptr[value]);
        escape[ncells++] = true;
      }
    }
    cx->cell_bytes = sizes;
    cx->cell_escape = escape;
    cx->ncells = ncells;
    return ncells != 0 ? pool : NULL;
  }
  /* The type of each slot: its instruction names it. */
  uint32_t *bytes = MS_ARENA_NEW_ARRAY(arena, uint32_t, (size_t)map.nobjects + 1);
  for (uint32_t object = 0; object < map.nobjects; object++) {
    bytes[object] = 0;
    if (held != NULL && held[map.value[object]]) {
      bytes[object] = emit_slot_bytes(cx, func->values.ptr[map.value[object]]);
    }
  }
  for (uint32_t block = 0; block < func->blocks.len; block++) {
    const MirInstList *insts = &func->blocks.ptr[block].insts;
    for (uint32_t index = 0; index < insts->len; index++) {
      const MirInst *inst = &insts->ptr[index];
      if (inst->op == MOP_Slot && map.ordinal[inst->res] != MIR_NONE) {
        bytes[map.ordinal[inst->res]] = emit_slot_bytes(cx, inst->imm.a);
      } else if (inst->op == MOP_StrData && map.ordinal[inst->res] != MIR_NONE) {
        bytes[map.ordinal[inst->res]] = STR_DATA_BYTES;
      }
    }
  }
  uint32_t *order = MS_ARENA_NEW_ARRAY(arena, uint32_t, (size_t)map.nobjects + 1);
  uint32_t norder = 0;
  for (uint32_t object = 0; object < map.nobjects; object++) {
    if (map.shareable[object] && bytes[object] != 0) {
      uint32_t at = norder++;
      while (at > 0 && bytes[order[at - 1]] < bytes[object]) { /* insertion, biggest first, stable */
        order[at] = order[at - 1];
        at--;
      }
      order[at] = object;
    }
  }
  uint32_t *cell_bytes = NULL;
  bool *cell_escape = NULL;
  uint64_t *cell_rows = NULL; /* by cell: the objects some occupant conflicts with */
  uint32_t ncells = 0;
  for (uint32_t at = 0; at < norder; at++) {
    const uint32_t object = order[at];
    uint32_t chosen = UINT32_MAX;
    for (uint32_t cell = 0; cell < ncells && chosen == UINT32_MAX; cell++) {
      const uint64_t *row = cell_rows + (size_t)cell * map.words;
      if ((row[object / 64] >> (object % 64) & 1) == 0) {
        chosen = cell;
      }
    }
    if (chosen == UINT32_MAX) {
      cell_bytes = ms_realloc(cell_bytes, (ncells + 1) * sizeof(uint32_t));
      cell_escape = ms_realloc(cell_escape, (ncells + 1) * sizeof(bool));
      cell_rows = ms_realloc(cell_rows, ((size_t)ncells + 1) * map.words * sizeof(uint64_t));
      for (uint32_t word = 0; word < map.words; word++) {
        cell_rows[(size_t)ncells * map.words + word] = 0;
      }
      cell_bytes[ncells] = 0;
      cell_escape[ncells] = false;
      chosen = ncells++;
    }
    const uint64_t *conflict = map.conflict + (size_t)object * map.words;
    for (uint32_t word = 0; word < map.words; word++) {
      cell_rows[(size_t)chosen * map.words + word] |= conflict[word];
    }
    cell_bytes[chosen] = bytes[object] > cell_bytes[chosen] ? bytes[object] : cell_bytes[chosen];
    cell_escape[chosen] = cell_escape[chosen] || (held != NULL && held[map.value[object]]);
    pool[map.value[object]] = chosen;
  }
  uint32_t *sizes = MS_ARENA_NEW_ARRAY(arena, uint32_t, (size_t)ncells + 1);
  bool *escape = MS_ARENA_NEW_ARRAY(arena, bool, (size_t)ncells + 1);
  for (uint32_t cell = 0; cell < ncells; cell++) {
    sizes[cell] = cell_bytes[cell];
    escape[cell] = cell_escape[cell];
  }
  ms_free(cell_bytes);
  ms_free(cell_escape);
  ms_free(cell_rows);
  if (cx->poison_slots && map.ndeaths != 0) {
    EmitPoison *fills = MS_ARENA_NEW_ARRAY(arena, EmitPoison, (size_t)map.ndeaths + 1);
    uint32_t nfills = 0;
    for (uint32_t at = 0; at < map.ndeaths; at++) {
      const uint32_t object = map.deaths[at].object;
      const uint32_t cell = pool[map.value[object]];
      const MirInst *at_inst = &func->blocks.ptr[map.deaths[at].block].insts.ptr[map.deaths[at].index];
      /* An operation that is not a call may write its result over an operand's cell; that result lives there now. */
      const bool replaced = at_inst->res != MIR_NONE && pool[at_inst->res] == cell;
      if (map.shareable[object] && cell != UINT32_MAX && bytes[object] != 0 && !replaced) {
        fills[nfills++] = (EmitPoison){map.deaths[at].block, map.deaths[at].index, cell, bytes[object]};
      }
    }
    cx->poison = fills;
    cx->npoison = nfills;
  }
  cx->cell_bytes = sizes;
  cx->cell_escape = escape;
  cx->ncells = ncells;
  return ncells != 0 ? pool : NULL;
}

void emit_frame_slots(EmitCx *cx) {
  const MirFunc *func = cx->func;
  uint32_t shared_x[SHARED_ARGS] = {0};
  uint32_t shared_p[SHARED_ARGS] = {0};
  uint32_t result_area = 0;
  for (uint32_t block = 0; block < func->blocks.len; block++) {
    const MirBlockData *data = &func->blocks.ptr[block];
    for (uint32_t index = 0; index < data->insts.len; index++) {
      const MirInst *inst = &data->insts.ptr[index];
      switch ((MirOp)inst->op) {
      case MOP_Slot:
        if (cx->pool != NULL && cx->pool[inst->res] != UINT32_MAX) {
          break; /* in a shared cell */
        }
        /* Zeroed where the instruction is, after the stack check: a frame this big may already reach the guard page. */
        ms_strbuild_printf(cx->out, "  %%s%u = alloca [%u x i8], align 8\n", inst->res, emit_slot_bytes(cx, inst->imm.a));
        break;
      case MOP_Call:
      case MOP_CallInd:
      case MOP_CallMethod:
        frame_call(cx, inst, block, index, shared_x, &result_area);
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
      case MOP_StrData:
        if (cx->pool != NULL && cx->pool[inst->res] != UINT32_MAX) {
          break; /* in a shared cell */
        }
        ms_strbuild_printf(cx->out, "  %%y%u_%u = alloca [%u x i8], align 8\n", block, index, STR_DATA_BYTES);
        break;
      case MOP_StrByte:
        ms_strbuild_printf(cx->out, "  %%y%u_%u = alloca [%u x i8], align 8\n", block, index, STR_DATA_BYTES);
        break;
      case MOP_CallRt:
        frame_rt_call(cx, inst, block, index, shared_p, &result_area);
        break;
      default:
        break;
      }
    }
  }
  for (uint32_t cell = 0; cell < cx->ncells; cell++) {
    if (emit_wide_is_ret_cell(cx, cell)) {
      ms_strbuild_printf(cx->out, "  %%cell%u = getelementptr i8, ptr %%sret, i64 0\n", cell);
    } else {
      ms_strbuild_printf(cx->out, "  %%cell%u = alloca [%u x i8], align 8\n", cell, cx->cell_bytes[cell]);
    }
    if (cx->cell_escape[cell] && cx->wide_hide) {
      /* An empty `asm` takes the address, so LLVM keeps the cell in memory instead of promoting it to registers. */
      ms_strbuild_printf(cx->out, "  call void asm sideeffect \"\", \"r,~{memory}\"(ptr %%cell%u)\n", cell);
    }
  }
  emit_wide_alias_cells(cx);
  if (result_area != 0) {
    ms_strbuild_printf(cx->out, "  %%R = alloca [%u x i8], align 8\n", result_area);
  }
  for (uint32_t arg = 0; arg < SHARED_ARGS; arg++) {
    if (shared_x[arg] != 0) {
      ms_strbuild_printf(cx->out, "  %%X0_0_%u = alloca [%u x i8], align 8\n", arg, shared_x[arg]);
    }
    if (shared_p[arg] != 0) {
      ms_strbuild_printf(cx->out, "  %%P0_0_%u = alloca [%u x i8], align 8\n", arg, shared_p[arg]);
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
      char slot[48];
      if (!emit_wide_address(cx, inst->args[arg], slot, sizeof slot)) {
        arg_slot_name(cx, inst, slot, 'x', block, index, arg);
      }
      ms_strbuild_printf(out, "%sptr %s", first ? "" : ", ", slot);
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
    if (emit_is_indirect(cx, value_type(cx, inst->args[arg])) && !emit_wide_held(cx, inst->args[arg])) {
      arg_slot_name(cx, inst, slot, 'x', block, index, arg);
      emit_store_value(cx, inst->args[arg], slot);
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
  char held_area[24];
  const char *area = "%R";
  bool held = false; /* the result stays in its cell: the instructions that read it load what they need */
  if (result_leaves > 1 && emit_wide_result(cx, inst->res, held_area, sizeof held_area)) {
    area = held_area;
    held = true;
  }
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
  if (result_leaves > 1 && !held) {
    emit_leaves_at(cx, inst->res, area, true);
  }
}

/* Whether extern `def` is a function of a C library: the runtime's own (`msrt_`, `msstd_`) take a Float32 as
 * a double. */
bool emit_extern_is_c(const EmitCx *cx, const MirExtern *def) {
  MsSpan name = ms_names_span(&cx->module->names, def->name);
  return !ms_span_starts_with_text(name, "msrt_") &&
         !ms_span_starts_with_text(name, "msstd_");
}

/* Appends one argument of a runtime call to `args`: the leaves of `value` when `type` passes directly, else
 * the address of a stack copy that is written first. */
static void rt_argument(EmitCx *cx, MsStrBuild *args, MirTy type, MirValue value, const char *area,
                        bool c_float) {
  const char *separator = ms_strbuild_length(args) > 0 ? ", " : "";
  if (!emit_rt_direct(cx, type)) {
    char held[24];
    if (emit_wide_address(cx, value, held, sizeof held)) {
      ms_strbuild_printf(args, "%sptr %s", separator, held);
      return;
    }
    emit_store_value(cx, value, area);
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

/* A runtime function returning `opt<scalar>`: the C function returns the flag as a `u8` and stores the payload
 * through the trailing pointer `area`, which is then loaded as the payload leaf. */
static bool call_runtime_option(EmitCx *cx, const MirInst *inst, const MirExtern *def, MsStrBuild *args,
                                const char *area) {
  const uint32_t flag = cx->next++;
  ms_strbuild_printf(cx->out, "  %%l%u = call i8 ", flag);
  emit_symbol(cx->out, ms_names_span(&cx->module->names, def->name));
  ms_strbuild_printf(cx->out, "(%.*s)\n", (int)ms_strbuild_length(args), (const char *)ms_strbuild_span(args).ptr);
  if (inst->res != MIR_NONE) {
    ms_strbuild_append_text(cx->out, "  ");
    emit_name(cx->out, inst->res, 0);
    ms_strbuild_printf(cx->out, " = trunc i8 %%l%u to i1\n", flag);
    const MsSpan leaves = emit_value_leaves(cx, inst->res);
    emit_load_leaf(cx, leaves.ptr[1], inst->res, 1, emit_address(cx, area, 0));
  }
  ms_strbuild_free(args);
  return true;
}

/* The address of the running task's `unwinding` byte, into `%ubp`: the region's cell holds the header pointer, and the
 * byte sits at a fixed offset (read in line, as the depth check reads its limit). The frame, hence its region and the
 * cell, stay the same while the function runs, so the entry block makes it once and every test is one load. */
void emit_unwinding_address(EmitCx *cx) {
  MsStrBuild *out = cx->out;
  ms_strbuild_printf(out, "  %%ubf = call ptr @llvm.frameaddress.p0(i32 0)\n  %%ubs = ptrtoint ptr %%ubf to i64\n");
  /* The frame address goes through an empty asm so the compiler cannot assume its low bits are zero: on Windows x64 a
   * leaf function's frame pointer is only 8-aligned, and the folded mask then read the cell's limit word. */
  ms_strbuild_printf(out, "  %%ubo = call i64 asm \"\", \"=r,0\"(i64 %%ubs)\n");
  ms_strbuild_printf(out, "  %%ubm = and i64 %%ubo, %lld\n  %%ubc = add i64 %%ubm, %lld\n", -(long long)MS_STACK_REGION,
                     (long long)(MS_STACK_REGION - MS_STACK_CELL_HDR));
  /* The header pointer of the cell does not change while this activation runs, so loads of it merge. */
  ms_strbuild_printf(out, "  %%ubhp = inttoptr i64 %%ubc to ptr\n  %%ubh = load ptr, ptr %%ubhp, !invariant.load !%d\n",
                     EMIT_METADATA_EMPTY);
  ms_strbuild_printf(out, "  %%ubp = getelementptr i8, ptr %%ubh, i64 %d\n", MS_HDR_UNWINDING);
}

/* `unwinding`: whether the running task is leaving for a posted fault or a delivered cancel. */
static void unwinding_test(EmitCx *cx, const MirInst *inst) {
  const uint32_t number = cx->next++;
  ms_strbuild_printf(cx->out, "  %%u%u = load i8, ptr %%ubp\n  %%v%u = icmp ne i8 %%u%u, 0\n", number, inst->res, number);
}

/* A call of a runtime function, which follows the C ABI of the runtime: scalars by value, everything else by
 * the address of a copy, and a result that is not a scalar through a trailing output pointer. */
static bool call_runtime(EmitCx *cx, const MirInst *inst, uint32_t block, uint32_t index) {
  const MirExtern *def = &cx->module->externs.ptr[inst->imm.a];
  if (def->role == MR_UNWINDING && inst->res != MIR_NONE) {
    unwinding_test(cx, inst);
    return true;
  }
  MsStrBuild args = ms_strbuild_new();
  char area[48];
  bool is_c = emit_extern_is_c(cx, def);
  for (uint32_t arg = 0; arg < inst->nargs; arg++) {
    arg_slot_name(cx, inst, area, 'p', block, index, arg);
    rt_argument(cx, &args, def->params[arg].ty, inst->args[arg], area, is_c);
  }
  MsSpan result = emit_leaves(cx, def->ret);
  bool direct = emit_rt_direct(cx, def->ret);
  const bool option = direct && emit_rt_scalar_option(cx, def->ret);
  if (direct && result.len > 1 && !option) {
    cx->why = "runtime result of several scalars";
    ms_strbuild_free(&args);
    return false;
  }
  area[0] = '%';
  area[1] = 'R';
  area[2] = 0; /* the area every call shares */
  bool held = false;
  if (!direct && inst->res != MIR_NONE) {
    held = emit_wide_result(cx, inst->res, area, sizeof area); /* a held result goes straight to its cell */
  }
  if (!direct || option) {
    ms_strbuild_printf(&args, "%sptr %s", ms_strbuild_length(&args) > 0 ? ", " : "", area);
  }
  if (option) {
    return call_runtime_option(cx, inst, def, &args, area);
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
  /* A call that ends its block in `unreachable`, or that posts a fault, keeps its own location: LLVM would
   * merge two such blocks that differ only in the line, and the trace would name the first. */
  const MirBlockData *home = &cx->func->blocks.ptr[block];
  const bool ends_block = (index + 1 == home->insts.len && home->term.kind == MT_UNREACHABLE) ||
                          def->role == MR_POSTS_FAULT;
  ms_strbuild_append_text(cx->out, ends_block ? ") nomerge\n" : ")\n");
  if (narrow) {
    widen_rt_result(cx, inst->res, kind);
  }
  if (!direct && inst->res != MIR_NONE && !held) {
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
