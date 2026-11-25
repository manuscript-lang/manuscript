/* compiler/mir/mir_expand_owned.c: the ownership shorthands as plain loads, drops and frees.
 *
 * Lowering and the optimizer use ops that bundle a layout decision with a release or a copy: `alt.own`,
 * `alt.unbox`, `alt.release`, `type.release`, `opt.unbox`, `opt.unwrap`. After the last pass that reads them
 * (`unwind`), each becomes `alt.get`/`type.get`/`opt.get` reads, `drop`s of the fields that stay, and one
 * `free` of the heap block when the value lives behind one. */
#include "compiler/mir/mir_expand.h"

#include "compiler/mir/mir_layout.h"
#include "compiler/mir/mir_pass.h"

static bool expands(MirOp op) {
  return op == MOP_AltOwn || op == MOP_AltUnbox || op == MOP_AltRelease || op == MOP_TypeRelease ||
         op == MOP_OptUnbox || op == MOP_OptUnwrap;
}

static bool func_has_shorthand(const MirFunc *func) {
  for (size_t bi = 0; bi < func->blocks.len; bi++) {
    for (size_t ii = 0; ii < func->blocks.ptr[bi].insts.len; ii++) {
      if (expands((MirOp)func->blocks.ptr[bi].insts.ptr[ii].op)) {
        return true;
      }
    }
  }
  return false;
}

/* The ownership shorthands (`alt.own`, `alt.unbox`, `alt.release`, `type.release`, `opt.unbox`, `opt.unwrap`)
 * as plain reads, drops and frees; run after the last pass that reads them. */
static bool mir_expand_owned_needed(const MirModule *module) {
  for (size_t index = 0; index < module->funcs.len; index++) {
    if (func_has_shorthand(&module->funcs.ptr[index])) {
      return true;
    }
  }
  return false;
}

typedef struct OwnedCx {
  MirModule *module;
  MirLayouts *layouts;
  MirFunc *func;
  MirBlockData *out; /* the block being rebuilt */
  MirLoc loc;
} OwnedCx;

static MirValue push(OwnedCx *cx, MirOp op, const MirValue *args, uint32_t nargs, MirImm imm, MirTy ty) {
  return mir_block_emit(cx->module, cx->func, cx->out, op, args, nargs, imm, ty, cx->loc);
}

/* Like push, for an instruction that defines the existing value `res`. */
static void push_into(OwnedCx *cx, MirOp op, const MirValue *args, uint32_t nargs, MirImm imm, MirValue res) {
  (void)push(cx, op, args, nargs, imm, MIR_NONE);
  cx->out->insts.ptr[cx->out->insts.len - 1].res = res;
}

/* Bit `k` of a mask, 0 past the width of the mask. */
static bool bit(uint32_t mask, uint32_t k) {
  return k < 32 && (mask >> k & 1) != 0;
}

static void drop_value(OwnedCx *cx, MirValue value) {
  (void)push(cx, MOP_Drop, &value, 1, mir_imm_none(), MIR_NONE);
}

/* Drops every payload field of case `case_index` of `value` that is not in `skip` (`alt.release` passes the
 * moved fields, `alt.unbox` every field but the one it returns), then frees the box. */
static void release_alt_fields(OwnedCx *cx, MirValue value, uint32_t alt, uint32_t case_index, uint32_t skip) {
  const MirCaseDef *def = &cx->module->alts.ptr[alt].cases[case_index];
  for (uint32_t field = 0; field < def->nfields; field++) {
    const MirTy ty = def->fields[field].ty;
    if (bit(skip, field) || !mir_needs_drop(cx->module, ty)) {
      continue;
    }
    const MirImm imm = {.tag = MI_ALTFIELD, .a = alt, .b = case_index, .c = field};
    drop_value(cx, push(cx, MOP_AltGet, &value, 1, imm, ty));
  }
  /* A case without payload is one shared static block: nothing to free. */
  if (mir_layouts_alt_boxed(cx->layouts, alt) && def->nfields > 0) {
    (void)push(cx, MOP_Free, &value, 1, mir_imm_none(), MIR_NONE);
  }
}

/* An indirect type is one pointer to a heap block whose map and set fields sit behind their own nullable
 * boxes: each box is freed, kept field or not, then the block. */
static void release_type(OwnedCx *cx, MirValue value, uint32_t type, uint32_t mask) {
  const MirTypeDef *def = &cx->module->type_defs.ptr[type];
  for (uint32_t field = 0; field < def->nfields; field++) {
    const MirTy ty = def->fields[field].ty;
    const MirImm imm = {.tag = MI_FIELD, .a = type, .b = field};
    if (!bit(mask, field) && !def->fields[field].borrowed && mir_needs_drop(cx->module, ty)) {
      drop_value(cx, push(cx, MOP_TypeGet, &value, 1, imm, ty));
    }
    if (def->indirect && mir_type_field_boxed(cx->layouts, ty)) {
      (void)push(cx, MOP_Free, &value, 1, imm, MIR_NONE);
    }
  }
  if (def->indirect) {
    (void)push(cx, MOP_Free, &value, 1, mir_imm_none(), MIR_NONE);
  }
}

/* `alt.own` and `opt.unwrap` read the payload and clone it: a copy of the borrowing variant read as its
 * ordinary alternative, or the owned payload of an optional known to be some. */
static void clone_of(OwnedCx *cx, MirOp read, MirValue value, MirValue res) {
  const MirValue plain = push(cx, read, &value, 1, mir_imm_none(), mir_value_ty(cx->func, res));
  push_into(cx, MOP_Clone, &plain, 1, mir_imm_none(), res);
}

/* The payload leaves the box; the box is freed, the payload lives on. */
static void unbox_opt(OwnedCx *cx, MirValue value, MirValue res) {
  push_into(cx, MOP_OptGet, &value, 1, mir_imm_none(), res);
  const MirTy inner = mir_ty_data(cx->module, mir_value_ty(cx->func, value))->elem;
  if (mir_layouts_opt_boxed(cx->layouts, inner)) {
    (void)push(cx, MOP_Free, &value, 1, mir_imm_none(), MIR_NONE);
  }
}

static void expand_inst(OwnedCx *cx, const MirInst *inst) {
  cx->loc = inst->loc;
  const MirValue value = inst->args[0];
  switch ((MirOp)inst->op) {
  case MOP_AltOwn: clone_of(cx, MOP_AltPlain, value, inst->res); break;
  case MOP_OptUnwrap: clone_of(cx, MOP_OptGet, value, inst->res); break;
  case MOP_OptUnbox: unbox_opt(cx, value, inst->res); break;
  case MOP_AltUnbox:
    push_into(cx, MOP_AltGet, &value, 1, inst->imm, inst->res);
    release_alt_fields(cx, value, inst->imm.a, inst->imm.b, inst->imm.c < 32 ? 1u << inst->imm.c : 0);
    break;
  case MOP_AltRelease: release_alt_fields(cx, value, inst->imm.a, inst->imm.b, inst->imm.c); break;
  default: release_type(cx, value, inst->imm.a, inst->imm.b); break; /* MOP_TypeRelease */
  }
}

static void expand_func(MirModule *module, MirLayouts *layouts, MirFunc *func) {
  for (size_t bi = 0; bi < func->blocks.len; bi++) {
    MirBlockData *block = &func->blocks.ptr[bi];
    MirBlockData rebuilt = {0};
    OwnedCx cx = {.module = module, .layouts = layouts, .func = func, .out = &rebuilt};
    for (size_t ii = 0; ii < block->insts.len; ii++) {
      const MirInst *inst = &block->insts.ptr[ii];
      if (expands((MirOp)inst->op)) {
        expand_inst(&cx, inst);
      } else {
        mir_inst_list_push(&rebuilt.insts, *inst);
      }
    }
    mir_block_set_insts(block, &rebuilt.insts);
  }
}

bool mir_expand_owned(MirModule *module) {
  if (!mir_expand_owned_needed(module)) {
    return false;
  }
  MirLayouts layouts;
  mir_layouts_init(&layouts, module);
  for (size_t index = 0; index < module->funcs.len; index++) {
    if (func_has_shorthand(&module->funcs.ptr[index])) {
      expand_func(module, &layouts, &module->funcs.ptr[index]);
    }
  }
  mir_layouts_free(&layouts);
  return true;
}
