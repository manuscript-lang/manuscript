/* compiler/mir/mir_pass.c: helpers shared by the MIR passes: extern declaration, plain-memory
 * classification, instruction constructors and cancellation points. Everything is built in the module's
 * arena. */
#include "compiler/mir/mir_pass.h"

uint32_t mir_extern_get(MirModule *module, MsSpan name, const MirTy *params, uint32_t nparams, MirTy ret,
                        bool leaf, MirRole role) {
  const MsName symbol = mir_name(module, name);
  const uint32_t found = mir_extern_by_name(module, symbol);
  if (found != MIR_NONE) {
    return found;
  }
  MirExtern external = {.name = symbol,
                        .params = MS_ARENA_NEW_ARRAY(&module->arena, MirParam, nparams),
                        .nparams = nparams,
                        .ret = ret,
                        .leaf = leaf,
                        .role = (uint8_t)role};
  for (uint32_t index = 0; index < nparams; index++) {
    external.params[index] = (MirParam){params[index], MM_BORROW};
  }
  return mir_add_extern(module, &external);
}

/* ---- plain memory ---- */

static bool plain_in(const MirModule *module, MirTy ty, MirTyList *path);

static bool plain_all(const MirModule *module, MirTy ty, const MirTy *types, uint32_t count, MirTyList *path) {
  mir_tylist_push(path, ty);
  bool plain = true;
  for (uint32_t index = 0; index < count && plain; index++) {
    plain = plain_in(module, types[index], path);
  }
  mir_tylist_truncate(path, path->len - 1);
  return plain;
}

static bool plain_fields(const MirModule *module, MirTy ty, const MirField *fields, uint32_t count,
                         MirTyList *path) {
  mir_tylist_push(path, ty);
  bool plain = true;
  for (uint32_t index = 0; index < count && plain; index++) {
    plain = plain_in(module, fields[index].ty, path);
  }
  mir_tylist_truncate(path, path->len - 1);
  return plain;
}

static bool plain_alt(const MirModule *module, MirTy ty, const MirAltDef *def, MirTyList *path) {
  for (uint32_t index = 0; index < def->ncases; index++) {
    if (!plain_fields(module, ty, def->cases[index].fields, def->cases[index].nfields, path)) {
      return false;
    }
  }
  return true;
}

/* `path` is the types being examined, so a recursive type counts as plain on its second visit. */
static bool plain_in(const MirModule *module, MirTy ty, MirTyList *path) {
  for (size_t index = 0; index < path->len; index++) {
    if (path->ptr[index] == ty) {
      return true;
    }
  }
  const MirTyData *data = mir_ty_data(module, ty);
  switch ((MirTyKind)data->kind) {
  case MK_FN: case MK_IFACE:
    return false;
  case MK_OBJ:
    return data->obj_class != MIR_OBJ_HANDLE && plain_all(module, ty, data->args, data->nargs, path);
  case MK_LIST: case MK_OPT:
    return plain_all(module, ty, &data->elem, 1, path);
  case MK_TYPE:
    return plain_fields(module, ty, module->type_defs.ptr[data->id].fields,
                        module->type_defs.ptr[data->id].nfields, path);
  case MK_ALT:
    return plain_alt(module, ty, &module->alts.ptr[data->id], path);
  case MK_VOID: case MK_BOOL: case MK_INT: case MK_FLOAT: case MK_INT8: case MK_INT16: case MK_INT32:
  case MK_FLOAT32: case MK_UINT8: case MK_UINT16: case MK_UINT32: case MK_UINT64: case MK_STR:
  case MK_BYTES: case MK_PTR:
    return true;
  }
  return true;
}

bool mir_drops_plain_memory(const MirModule *module, MirTy ty) {
  MirTyList path = {0};
  const bool plain = plain_in(module, ty, &path);
  mir_tylist_free(&path);
  return plain;
}

/* ---- constructors ---- */

MirValue *mir_args_copy(MirModule *module, const MirValue *args, uint32_t count) {
  MirValue *copy = MS_ARENA_NEW_ARRAY(&module->arena, MirValue, count);
  if (count != 0) {
    __builtin_memcpy(copy, args, sizeof(MirValue) * count);
  }
  return copy;
}

MirInst mir_inst(MirOp op, MirImm imm, MirValue res, MirLoc loc, MirValue *args, uint32_t count) {
  return (MirInst){.op = (uint8_t)op, .imm = imm, .res = res, .loc = loc, .args = args, .nargs = count};
}

MirImm mir_imm_none(void) {
  return (MirImm){.tag = MI_NONE};
}

MirImm mir_imm_int(int64_t value) {
  return (MirImm){.tag = MI_INT, .i = value};
}

MirImm mir_imm_cc(MirCc cc) {
  return (MirImm){.tag = MI_CC, .a = (uint32_t)cc};
}

MirImm mir_imm_ext(uint32_t external) {
  return (MirImm){.tag = MI_EXT, .a = external};
}

MirFunc mir_func_stand_in(MirModule *module, const MirFunc *func) {
  MirFunc stand_in;
  mir_func_init(module, &stand_in, MS_NAME_EMPTY, func->params, func->nparams, func->ret);
  stand_in.ret_borrowed = func->ret_borrowed;
  stand_in.ret_view = func->ret_view;
  stand_in.noalias = func->noalias;
  stand_in.nnoalias = func->nnoalias;
  return stand_in;
}

/* ---- cancellation points ---- */

bool mir_starts_tasks(const MirModule *module) {
  for (size_t index = 0; index < module->externs.len; index++) {
    if (module->externs.ptr[index].role == MR_SPAWNS_TASK) {
      return true;
    }
  }
  return false;
}

static bool leaf_extern(const MirModule *module, uint32_t external) {
  return module->externs.ptr[external].noreturn || module->externs.ptr[external].leaf;
}

/* Whether `inst` reaches a cancellation point by itself, not through a callee. */
static bool parks_directly(const MirModule *module, const MirInst *inst) {
  switch ((MirOp)inst->op) {
  case MOP_Poll: case MOP_CallInd: case MOP_CallMethod:
    return true;
  case MOP_FaultSite: /* a check that faults leaves the function by its exit, as a cancel does */
    return true;
  case MOP_CallRt:
    return inst->imm.tag == MI_EXT && !leaf_extern(module, inst->imm.a);
  default:
    return false;
  }
}

bool mir_inst_parks(const MirModule *module, const bool *parks, const MirInst *inst) {
  if (parks_directly(module, inst)) {
    return true;
  }
  return inst->op == MOP_Call && inst->imm.tag == MI_FUNC && parks[inst->imm.a];
}

/* Whether any instruction of `func` satisfies the test: directly, or a call of a function already known. */
static bool func_parks(const MirModule *module, const MirFunc *func, const bool *known) {
  for (size_t block = 0; block < func->blocks.len; block++) {
    const MirInstList *insts = &func->blocks.ptr[block].insts;
    for (size_t index = 0; index < insts->len; index++) {
      const MirInst *inst = &insts->ptr[index];
      const bool through_callee = known != NULL && inst->op == MOP_Call && inst->imm.tag == MI_FUNC &&
                                  known[inst->imm.a];
      if (known != NULL ? through_callee : parks_directly(module, inst)) {
        return true;
      }
    }
  }
  return false;
}

bool *mir_parking_funcs(MsArena *arena, const MirModule *module) {
  bool *parks = MS_ARENA_NEW_ARRAY(arena, bool, module->funcs.len + 1);
  for (size_t func = 0; func < module->funcs.len; func++) {
    parks[func] = func_parks(module, &module->funcs.ptr[func], NULL);
  }
  for (bool changed = true; changed;) { /* propagate to callers until nothing changes */
    changed = false;
    for (size_t func = 0; func < module->funcs.len; func++) {
      if (!parks[func] && func_parks(module, &module->funcs.ptr[func], parks)) {
        parks[func] = true;
        changed = true;
      }
    }
  }
  return parks;
}

MirValue mir_block_emit(MirModule *module, MirFunc *func, MirBlockData *block, MirOp op, const MirValue *args,
                        uint32_t count, MirImm imm, MirTy ty, MirLoc loc) {
  const MirValue result = ty == MIR_NONE ? MIR_NONE : mir_new_value(func, ty);
  mir_inst_list_push(&block->insts, mir_inst(op, imm, result, loc, mir_args_copy(module, args, count), count));
  return result;
}

void mir_block_set_insts(MirBlockData *block, MirInstList *insts) {
  mir_inst_list_free(&block->insts);
  block->insts = *insts;
  *insts = (MirInstList){0};
}

static void replace_use(MirValue *use, MirValue from, MirValue to) {
  *use = *use == from ? to : *use;
}

static void replace_in_target(MirTarget *target, MirValue from, MirValue to) {
  for (uint32_t index = 0; index < target->nargs; index++) {
    replace_use(&target->args[index], from, to);
  }
}

void mir_func_replace_uses(MirFunc *func, MirValue from, MirValue to) {
  for (size_t bi = 0; bi < func->blocks.len; bi++) {
    MirBlockData *block = &func->blocks.ptr[bi];
    for (size_t ii = 0; ii < block->insts.len; ii++) {
      for (uint32_t arg = 0; arg < block->insts.ptr[ii].nargs; arg++) {
        replace_use(&block->insts.ptr[ii].args[arg], from, to);
      }
    }
    replace_use(&block->term.value, from, to);
    replace_in_target(&block->term.a, from, to);
    replace_in_target(&block->term.b, from, to);
    for (uint32_t index = 0; index < block->term.ncases; index++) {
      replace_in_target(&block->term.cases[index].target, from, to);
    }
  }
}
