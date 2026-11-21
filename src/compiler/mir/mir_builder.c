/* compiler/mir/mir_builder.c: appends instructions to a function under construction and turns mutable
 * variables into block parameters (Braun et al.), removing the trivial parameters again.
 *
 * Scratch state (variables, definitions, predecessors, forwards) lives in base lists and a map that
 * mir_b_into_func frees; operand arrays are copied into the module arena, where the function stays. */
#include "compiler/mir/mir_builder.h"

/* A variable read recurses once per block on a path, so this many nested reads means a cycle of sealed
 * single-predecessor blocks no read can resolve: the build fails instead of overflowing the stack. */
enum { MAX_READ_DEPTH = 100000 };

/* ---- scratch tables ---- */

static MirBlockLinks *links_of(MirBuilder *builder, MirBlock block) {
  while (builder->links.len <= block) {
    mir_block_links_list_push(&builder->links, (MirBlockLinks){0});
  }
  return &builder->links.ptr[block];
}

static void set_forward(MirBuilder *builder, MirValue from, MirValue to) {
  while (builder->forward.len <= from) {
    mir_idlist_push(&builder->forward, MIR_NONE);
  }
  builder->forward.ptr[from] = to;
}

/* The value `value` stands for once removed trivial parameters are followed. */
static MirValue resolve(MirBuilder *builder, MirValue value) {
  MirValue end = value;
  while (end < builder->forward.len && builder->forward.ptr[end] != MIR_NONE) {
    end = builder->forward.ptr[end];
  }
  if (end != value) {
    builder->forward.ptr[value] = end;
  }
  return end;
}

static MirValue *copy_values(MirBuilder *builder, const MirValue *values, uint32_t count) {
  if (count == 0) {
    return NULL;
  }
  MirValue *copy = MS_ARENA_NEW_ARRAY(&builder->module->arena, MirValue, count);
  __builtin_memcpy(copy, values, sizeof(MirValue) * count);
  return copy;
}

/* ---- construction ---- */

void mir_b_init(MirBuilder *builder, MirModule *module, MsName name, const MirParam *params, uint32_t count,
                MirTy ret) {
  *builder = (MirBuilder){.module = module, .loc = MIR_LOC_NONE};
  mir_func_init(module, &builder->func, name, params, count, ret);
  links_of(builder, 0)->sealed = true;
}

void mir_b_init_fast_path(MirBuilder *builder, MirModule *module, MsName name, const MirParam *params,
                          uint32_t count, MirTy ret) {
  mir_b_init(builder, module, name, params, count, ret);
  builder->func.linkage = ML_INTERNAL;
  builder->func.inline_hint = MINL_ALWAYS;
}

void mir_b_params(const MirBuilder *builder, MirValue *out, uint32_t count) {
  const MirBlockParamList *entry = &builder->func.blocks.ptr[0].params;
  for (uint32_t index = 0; index < count; index++) {
    out[index] = index < entry->len ? entry->ptr[index].value : MIR_NONE;
  }
}

MirBlock mir_b_new_block(MirBuilder *builder) {
  const MirBlock block = mir_new_block(&builder->func);
  links_of(builder, block)->sealed = false;
  return block;
}

MirValue mir_b_add_block_param(MirBuilder *builder, MirBlock block, MirTy ty, MirMode mode) {
  const MirValue value = mir_new_value(&builder->func, ty);
  mir_block_param_list_push(&builder->func.blocks.ptr[block].params,
                            (MirBlockParam){value, (uint8_t)mode});
  return value;
}

MirValue mir_b_emit(MirBuilder *builder, MirOp op, const MirValue *args, uint32_t nargs, MirImm imm,
                    MirTy res_ty) {
  MirInst inst = {0};
  inst.op = (uint8_t)op;
  inst.imm = imm;
  inst.res = res_ty == MIR_NONE ? MIR_NONE : mir_new_value(&builder->func, res_ty);
  inst.loc = builder->loc;
  inst.args = copy_values(builder, args, nargs);
  inst.nargs = nargs;
  mir_inst_list_push(&builder->func.blocks.ptr[builder->cur].insts, inst);
  return inst.res;
}

MirValue mir_b_iconst(MirBuilder *builder, int64_t value) {
  return mir_b_emit(builder, MOP_IConst, NULL, 0, (MirImm){.tag = MI_INT, .i = value}, MIR_INT);
}

MirValue mir_b_bconst(MirBuilder *builder, bool value) {
  return mir_b_emit(builder, MOP_BConst, NULL, 0, (MirImm){.tag = MI_BOOL, .a = value ? 1u : 0u}, MIR_BOOL);
}

MirValue mir_b_unit(MirBuilder *builder) {
  return mir_b_emit(builder, MOP_VoidConst, NULL, 0, (MirImm){0}, MIR_VOID);
}

MirValue mir_b_binop(MirBuilder *builder, MirOp op, MirValue left, MirValue right) {
  const MirValue args[2] = {left, right};
  return mir_b_emit(builder, op, args, 2, (MirImm){0}, mir_b_ty(builder, left));
}

MirValue mir_b_icmp(MirBuilder *builder, MirCc cc, MirValue left, MirValue right) {
  const MirValue args[2] = {left, right};
  const MirImm imm = {.tag = MI_CC, .a = (uint32_t)cc};
  const bool unsigned_order = mir_b_ty(builder, left) == MIR_UINT64 && cc != MCC_EQ && cc != MCC_NE;
  return mir_b_emit(builder, unsigned_order ? MOP_UICmp : MOP_ICmp, args, 2, imm, MIR_BOOL);
}

MirValue mir_b_select(MirBuilder *builder, MirValue cond, MirValue then, MirValue otherwise) {
  const MirValue args[3] = {cond, then, otherwise};
  return mir_b_emit(builder, MOP_Select, args, 3, (MirImm){0}, mir_b_ty(builder, then));
}

MirValue mir_b_list_new(MirBuilder *builder, MirTy elem, MirValue capacity) {
  return mir_b_emit(builder, MOP_ListNew, &capacity, 1, (MirImm){0}, mir_ty_list(builder->module, elem));
}

MirValue mir_b_call_rt(MirBuilder *builder, uint32_t external, const MirValue *args, uint32_t nargs) {
  return mir_b_emit(builder, MOP_CallRt, args, nargs, (MirImm){.tag = MI_EXT, .a = external},
                    builder->module->externs.ptr[external].ret);
}

static bool same_fields(const MirField *left, const MirField *right, uint32_t count) {
  for (uint32_t index = 0; index < count; index++) {
    if (left[index].name != right[index].name || left[index].ty != right[index].ty) {
      return false;
    }
  }
  return true;
}

static bool same_cases(const MirAltDef *have, const MirAltDef *want) {
  for (uint32_t index = 0; index < have->ncases; index++) {
    const MirCaseDef *left = &have->cases[index];
    const MirCaseDef *right = &want->cases[index];
    if (left->name != right->name || left->nfields != right->nfields ||
        !same_fields(left->fields, right->fields, left->nfields)) {
      return false;
    }
  }
  return true;
}

/* Whether `have` is a borrowing variant of the ordinary alternative `want`. */
static bool is_variant_of(const MirModule *module, MirTy have, MirTy want) {
  const MirTyData *have_data = mir_ty_data(module, have);
  const MirTyData *want_data = mir_ty_data(module, want);
  if (have_data->kind != MK_ALT || want_data->kind != MK_ALT) {
    return false;
  }
  const MirAltDef *have_def = &module->alts.ptr[have_data->id];
  const MirAltDef *want_def = &module->alts.ptr[want_data->id];
  return have_def->borrowed != 0 && want_def->borrowed == 0 && have_def->name == want_def->name &&
         have_def->ncases == want_def->ncases && same_cases(have_def, want_def);
}

MirValue mir_b_call(MirBuilder *builder, uint32_t func, const MirValue *args, uint32_t nargs) {
  const MirFunc *callee = &builder->module->funcs.ptr[func];
  MirIdList plain = {0};
  for (uint32_t index = 0; index < nargs; index++) {
    MirValue arg = args[index];
    const bool borrowed = index < callee->nparams && callee->params[index].mode == MM_BORROW;
    if (borrowed && is_variant_of(builder->module, mir_b_ty(builder, arg), callee->params[index].ty)) {
      arg = mir_b_emit(builder, MOP_AltPlain, &args[index], 1, (MirImm){0}, callee->params[index].ty);
    }
    mir_idlist_push(&plain, arg);
  }
  const MirValue result = mir_b_emit(builder, MOP_Call, plain.ptr, nargs,
                                     (MirImm){.tag = MI_FUNC, .a = func}, callee->ret);
  mir_idlist_free(&plain);
  return result;
}

/* ---- terminators ---- */

/* Records the edges of the terminator just stored in the current block. */
static void end_block(MirBuilder *builder) {
  MirBlockData *block = &builder->func.blocks.ptr[builder->cur];
  block->term_loc = builder->loc;
  for (uint32_t index = 0; index < mir_term_ntargets(&block->term); index++) {
    const MirBlock to = mir_term_target(&block->term, index)->block;
    mir_idlist_push(&links_of(builder, to)->preds, builder->cur);
  }
}

static MirTerm *start_term(MirBuilder *builder, MirTermKind kind) {
  MirTerm *term = &builder->func.blocks.ptr[builder->cur].term;
  *term = (MirTerm){.kind = (uint8_t)kind, .value = MIR_NONE};
  return term;
}

void mir_b_br(MirBuilder *builder, MirBlock to, const MirValue *args, uint32_t nargs) {
  MirTerm *term = start_term(builder, MT_BR);
  term->a = (MirTarget){to, copy_values(builder, args, nargs), nargs};
  end_block(builder);
}

void mir_b_br_if(MirBuilder *builder, MirValue cond, MirBlock then, const MirValue *then_args, uint32_t nthen,
                 MirBlock otherwise, const MirValue *else_args, uint32_t nelse) {
  MirTerm *term = start_term(builder, MT_CONDBR);
  term->value = cond;
  term->a = (MirTarget){then, copy_values(builder, then_args, nthen), nthen};
  term->b = (MirTarget){otherwise, copy_values(builder, else_args, nelse), nelse};
  end_block(builder);
}

void mir_b_switch(MirBuilder *builder, MirValue value, const MirCase *cases, uint32_t ncases,
                  MirBlock fallback) {
  MirTerm *term = start_term(builder, MT_SWITCH);
  term->value = value;
  term->cases = MS_ARENA_NEW_ARRAY(&builder->module->arena, MirCase, (size_t)ncases + 1);
  for (uint32_t index = 0; index < ncases; index++) {
    term->cases[index] = (MirCase){cases[index].value, {cases[index].target.block, NULL, 0}};
  }
  term->ncases = ncases;
  term->b = (MirTarget){fallback, NULL, 0};
  end_block(builder);
}

void mir_b_ret(MirBuilder *builder, MirValue value) {
  start_term(builder, MT_RET)->value = value;
  end_block(builder);
}

void mir_b_fault(MirBuilder *builder, MirFault kind) {
  start_term(builder, MT_FAULT)->fault = (uint8_t)kind;
  end_block(builder);
}

void mir_b_unreachable(MirBuilder *builder) {
  (void)start_term(builder, MT_UNREACHABLE);
  end_block(builder);
}

/* ---- variables ---- */

static MirVar declare(MirBuilder *builder, MirTy ty, MirMode mode, bool single) {
  mir_var_info_list_push(&builder->vars, (MirVarInfo){ty, (uint8_t)mode, single, MIR_NONE});
  return (MirVar)(builder->vars.len - 1);
}

MirVar mir_b_declare_var(MirBuilder *builder, MirTy ty, MirMode mode) {
  return declare(builder, ty, mode, false);
}

MirVar mir_b_declare_single(MirBuilder *builder, MirTy ty, MirMode mode) {
  return declare(builder, ty, mode, true);
}

static void set_def(MirBuilder *builder, MirVar var, MirBlock block, MirValue value) {
  mir_def_map_put(&builder->defs, (MirVarBlock){var, block}, value);
}

void mir_b_def_var(MirBuilder *builder, MirVar var, MirValue value) {
  MirVarInfo *info = &builder->vars.ptr[var];
  if (info->single) {
    info->only_def = value;
    return;
  }
  set_def(builder, var, builder->cur, value);
}

static uint32_t param_index(const MirBuilder *builder, MirBlock block, MirValue param) {
  const MirBlockParamList *params = &builder->func.blocks.ptr[block].params;
  for (uint32_t index = 0; index < params->len; index++) {
    if (params->ptr[index].value == param) {
      return index;
    }
  }
  return (uint32_t)params->len; /* unreachable: every caller just added the parameter */
}

static MirValue read_var(MirBuilder *builder, MirVar var, MirBlock block);

/* Gives `target` the operand `value` at parameter position `index`. */
static void set_target_arg(MirBuilder *builder, MirTarget *target, uint32_t index, MirValue value) {
  while (target->nargs <= index) {
    MirValue *grown = MS_ARENA_NEW_ARRAY(&builder->module->arena, MirValue, (size_t)target->nargs + 1);
    if (target->nargs != 0) {
      __builtin_memcpy(grown, target->args, sizeof(MirValue) * target->nargs);
    }
    grown[target->nargs] = value;
    target->args = grown;
    target->nargs++;
  }
}

static bool pred_seen_before(const MirIdList *preds, size_t count) {
  for (size_t index = 0; index < count; index++) {
    if (preds->ptr[index] == preds->ptr[count]) {
      return true;
    }
  }
  return false;
}

/* Fills in the operand every distinct predecessor passes for `param`, reading the variable there. */
static void add_phi_operands(MirBuilder *builder, MirVar var, MirBlock block, MirValue param) {
  const uint32_t index = param_index(builder, block, param);
  const size_t npreds = links_of(builder, block)->preds.len;
  for (size_t k = 0; k < npreds; k++) {
    if (pred_seen_before(&links_of(builder, block)->preds, k)) {
      continue;
    }
    const MirBlock pred = links_of(builder, block)->preds.ptr[k];
    const MirValue value = read_var(builder, var, pred);
    MirTerm *term = &builder->func.blocks.ptr[pred].term;
    for (uint32_t t = 0; t < mir_term_ntargets(term); t++) {
      MirTarget *target = mir_term_target(term, t);
      if (target->block == block) {
        set_target_arg(builder, target, index, value);
      }
    }
  }
}

/* Whether every edge into `block` passes the same value for parameter `index`; the value is written to
 * `same`. Edges passing the parameter itself change nothing. */
static bool uniform_operand(MirBuilder *builder, MirBlock block, uint32_t index, MirValue param,
                            MirValue *same) {
  uint32_t edges = 0;
  *same = MIR_NONE;
  const size_t npreds = links_of(builder, block)->preds.len;
  for (size_t k = 0; k < npreds; k++) {
    MirTerm *term = &builder->func.blocks.ptr[links_of(builder, block)->preds.ptr[k]].term;
    for (uint32_t t = 0; t < mir_term_ntargets(term); t++) {
      const MirTarget *target = mir_term_target(term, t);
      if (target->block != block) {
        continue;
      }
      edges++;
      if (index >= target->nargs) {
        return false;
      }
      const MirValue operand = resolve(builder, target->args[index]);
      if (operand == param) {
        continue;
      }
      if (*same != MIR_NONE && *same != operand) {
        return false;
      }
      *same = operand;
    }
  }
  return edges > 0 && *same != MIR_NONE;
}

static void remove_edge_operand(MirTarget *target, uint32_t index) {
  for (uint32_t arg = index + 1; arg < target->nargs; arg++) {
    target->args[arg - 1] = target->args[arg];
  }
  target->nargs--;
}

static void remove_param_operands(MirBuilder *builder, MirBlock block, uint32_t index) {
  const size_t npreds = links_of(builder, block)->preds.len;
  for (size_t k = 0; k < npreds; k++) {
    MirTerm *term = &builder->func.blocks.ptr[links_of(builder, block)->preds.ptr[k]].term;
    for (uint32_t t = 0; t < mir_term_ntargets(term); t++) {
      MirTarget *target = mir_term_target(term, t);
      if (target->block == block && target->nargs > index) {
        remove_edge_operand(target, index);
      }
    }
  }
}

/* Removes `param` of the sealed block when every predecessor passes the same value, so that value stays live
 * across the join instead of being handed through an edge. */
static MirValue without_trivial_param(MirBuilder *builder, MirVar var, MirBlock block, MirValue param) {
  const uint32_t index = param_index(builder, block, param);
  MirValue same = MIR_NONE;
  if (!uniform_operand(builder, block, index, param, &same)) {
    return param;
  }
  remove_param_operands(builder, block, index);
  MirBlockParamList *params = &builder->func.blocks.ptr[block].params;
  for (size_t at = (size_t)index + 1; at < params->len; at++) {
    params->ptr[at - 1] = params->ptr[at];
  }
  params->len--;
  set_def(builder, var, block, same);
  set_forward(builder, param, same);
  return same;
}

/* A read in an unsealed block: a parameter that waits for the block to be sealed. */
static MirValue read_unsealed(MirBuilder *builder, MirVar var, MirBlock block) {
  const MirVarInfo info = builder->vars.ptr[var];
  const MirValue value = mir_b_add_block_param(builder, block, info.ty, (MirMode)info.mode);
  MirBlockLinks *links = links_of(builder, block);
  mir_var_list_push(&links->waiting_var, var);
  mir_idlist_push(&links->waiting_param, value);
  return value;
}

static MirValue read_join(MirBuilder *builder, MirVar var, MirBlock block) {
  const MirVarInfo info = builder->vars.ptr[var];
  const MirValue param = mir_b_add_block_param(builder, block, info.ty, (MirMode)info.mode);
  set_def(builder, var, block, param);
  add_phi_operands(builder, var, block, param);
  return without_trivial_param(builder, var, block, param);
}

static MirValue read_var_slow(MirBuilder *builder, MirVar var, MirBlock block) {
  const MirBlockLinks *links = links_of(builder, block);
  if (!links->sealed) {
    return read_unsealed(builder, var, block);
  }
  if (links->preds.len == 1) {
    return read_var(builder, var, links->preds.ptr[0]);
  }
  if (links->preds.len == 0) {
    builder->failed = true; /* read before any path defines it */
    return mir_b_iconst(builder, 0);
  }
  return read_join(builder, var, block);
}

static MirValue read_var(MirBuilder *builder, MirVar var, MirBlock block) {
  const MirVarInfo info = builder->vars.ptr[var];
  if (info.single) {
    return resolve(builder, info.only_def);
  }
  const MirValue *known = mir_def_map_get(&builder->defs, (MirVarBlock){var, block});
  if (known != NULL) {
    return resolve(builder, *known);
  }
  if (++builder->depth > MAX_READ_DEPTH) {
    builder->failed = true;
    builder->depth--;
    return info.only_def;
  }
  const MirValue value = read_var_slow(builder, var, block);
  set_def(builder, var, block, value);
  builder->depth--;
  return value;
}

MirValue mir_b_use_var(MirBuilder *builder, MirVar var) {
  return read_var(builder, var, builder->cur);
}

void mir_b_seal_block(MirBuilder *builder, MirBlock block) {
  if (links_of(builder, block)->sealed) {
    return;
  }
  links_of(builder, block)->sealed = true;
  const size_t count = links_of(builder, block)->waiting_var.len;
  for (size_t index = 0; index < count; index++) {
    const MirBlockLinks *links = links_of(builder, block);
    add_phi_operands(builder, links->waiting_var.ptr[index], block, links->waiting_param.ptr[index]);
  }
}

/* ---- finishing ---- */

static void resolve_edges(MirBuilder *builder) {
  for (size_t block = 0; block < builder->func.blocks.len; block++) {
    MirTerm *term = &builder->func.blocks.ptr[block].term;
    for (uint32_t t = 0; t < mir_term_ntargets(term); t++) {
      MirTarget *target = mir_term_target(term, t);
      for (uint32_t arg = 0; arg < target->nargs; arg++) {
        target->args[arg] = resolve(builder, target->args[arg]);
      }
    }
  }
}

static void free_scratch(MirBuilder *builder) {
  for (size_t index = 0; index < builder->links.len; index++) {
    mir_idlist_free(&builder->links.ptr[index].preds);
    mir_var_list_free(&builder->links.ptr[index].waiting_var);
    mir_idlist_free(&builder->links.ptr[index].waiting_param);
  }
  mir_block_links_list_free(&builder->links);
  mir_var_info_list_free(&builder->vars);
  mir_def_map_free(&builder->defs);
  mir_idlist_free(&builder->forward);
}

bool mir_b_into_func(MirBuilder *builder, MirFunc *out) {
  if (builder->forward.len != 0) {
    resolve_edges(builder);
  }
  for (size_t index = 0; index < builder->func.names.len; index++) {
    MirNamedValue *named = &builder->func.names.ptr[index];
    named->value = resolve(builder, named->value);
  }
  const bool ok = !builder->failed;
  *out = builder->func;
  free_scratch(builder);
  return ok;
}

bool mir_b_finish(MirBuilder *builder, uint32_t *id) {
  MirFunc func = {0};
  MirModule *module = builder->module;
  if (!mir_b_into_func(builder, &func)) {
    return false;
  }
  *id = mir_add_func(module, &func);
  return true;
}

uint32_t mir_b_open_scope(MirBuilder *builder, MsName name, uint32_t file, uint32_t call_line) {
  const uint32_t outer = builder->loc.scope;
  mir_scope_list_push(&builder->func.scopes,
                      (MirScope){.name = name, .file = file, .parent = outer, .call_line = call_line});
  builder->loc.scope = (uint32_t)builder->func.scopes.len;
  return outer;
}

void mir_b_close_scope(MirBuilder *builder, uint32_t outer) {
  builder->loc.scope = outer;
}
