/* compiler/mir/mir_print_func.c: one function in text form. Values are renumbered densely in definition
 * order (block parameters, then results), so the text does not depend on how passes numbered them. */
#include "compiler/mir/mir_print.h"

typedef struct PrintCx {
  const MirModule *module;
  const MirFunc *func;
  MirIdList numbers; /* value -> dense number, MIR_NONE when not defined */
  MsStrBuild *out;
} PrintCx;

static void put(PrintCx *cx, const char *text) {
  ms_strbuild_append_text(cx->out, text);
}

static void put_sep(PrintCx *cx, size_t index) {
  put(cx, index > 0 ? ", " : "");
}

static void put_uint(PrintCx *cx, uint64_t value) {
  ms_strbuild_append_u64(cx->out, value);
}

static void put_name(PrintCx *cx, MsName name) {
  ms_strbuild_append(cx->out, ms_names_span(&cx->module->names, name));
}

static void put_func_name(PrintCx *cx, uint32_t func) {
  put_name(cx, cx->module->funcs.ptr[func].name);
}

static void put_value(PrintCx *cx, MirValue value) {
  const uint32_t number = cx->numbers.ptr[value];
  put(cx, "%");
  put_uint(cx, number == MIR_NONE ? UINT64_MAX : number);
}

static void put_values(PrintCx *cx, const MirValue *values, uint32_t count) {
  for (uint32_t index = 0; index < count; index++) {
    put_sep(cx, index);
    put_value(cx, values[index]);
  }
}

static void put_mode(PrintCx *cx, uint8_t mode) {
  put(cx, mode == MM_MOVE ? "move " : "");
}

static void put_target(PrintCx *cx, const MirTarget *target) {
  put(cx, "b");
  put_uint(cx, target->block);
  put(cx, "(");
  put_values(cx, target->args, target->nargs);
  put(cx, ")");
}

static void put_fault(PrintCx *cx, const MirTerm *term) {
  static const char *const names[] = {"cancelled", "call_depth", "posted", "unreachable_code"};
  if (term->fault == MF_MESSAGE) {
    mir_print_quoted(cx->out, ms_names_span(&cx->module->strings, term->fault_str));
    return;
  }
  put(cx, names[term->fault]);
}

static void put_switch(PrintCx *cx, const MirTerm *term) {
  put(cx, "switch ");
  put_value(cx, term->value);
  put(cx, " [");
  for (uint32_t index = 0; index < term->ncases; index++) {
    put_sep(cx, index);
    ms_strbuild_append_i64(cx->out, term->cases[index].value);
    put(cx, ": ");
    put_target(cx, &term->cases[index].target);
  }
  put(cx, "] default ");
  put_target(cx, &term->b);
}

static void put_term(PrintCx *cx, const MirTerm *term) {
  switch ((MirTermKind)term->kind) {
  case MT_BR:
    put(cx, "br ");
    put_target(cx, &term->a);
    return;
  case MT_CONDBR:
    put(cx, "br_if ");
    put_value(cx, term->value);
    put(cx, ", ");
    put_target(cx, &term->a);
    put(cx, ", ");
    put_target(cx, &term->b);
    return;
  case MT_SWITCH:
    put_switch(cx, term);
    return;
  case MT_RET:
    put(cx, "ret");
    if (term->value != MIR_NONE) {
      put(cx, " ");
      put_value(cx, term->value);
    }
    return;
  case MT_FAULT:
    put(cx, "fault ");
    put_fault(cx, term);
    return;
  case MT_UNREACHABLE:
    put(cx, "unreachable");
    return;
  }
}

static void put_loc(PrintCx *cx, MirLoc loc) {
  if (mir_loc_none(loc)) {
    return;
  }
  put(cx, " !");
  put_uint(cx, loc.file);
  put(cx, ":");
  put_uint(cx, loc.line);
  put(cx, ":");
  put_uint(cx, loc.col);
  if (loc.scope != 0) {
    put(cx, ":");
    put_uint(cx, loc.scope);
  }
}

/* The fields of a case or type selected by `mask`, each after a dot. */
static void put_masked(PrintCx *cx, const MirField *fields, uint32_t count, uint32_t mask) {
  for (uint32_t index = 0; index < count && index < 32; index++) {
    if (((mask >> index) & 1) != 0) {
      put(cx, ".");
      put_name(cx, fields[index].name);
    }
  }
}

static void put_pair(PrintCx *cx, MsName first, MsName second) {
  put_name(cx, first);
  put(cx, ".");
  put_name(cx, second);
}

/* Immediates that name a declaration or a field of one. */
static void put_imm_declared(PrintCx *cx, const MirImm *imm) {
  const MirModule *module = cx->module;
  switch ((MirImmTag)imm->tag) {
  case MI_FUNC:
    put(cx, "@");
    put_func_name(cx, imm->a);
    return;
  case MI_EXT:
    put(cx, "@");
    put_name(cx, module->externs.ptr[imm->a].name);
    return;
  case MI_TYPE:
    put_name(cx, module->type_defs.ptr[imm->a].name);
    return;
  case MI_FIELD:
    put_pair(cx, module->type_defs.ptr[imm->a].name, module->type_defs.ptr[imm->a].fields[imm->b].name);
    return;
  case MI_CASE:
    put_pair(cx, module->alts.ptr[imm->a].name, module->alts.ptr[imm->a].cases[imm->b].name);
    return;
  case MI_ALTFIELD: {
    const MirCaseDef *def = &module->alts.ptr[imm->a].cases[imm->b];
    put_pair(cx, module->alts.ptr[imm->a].name, def->name);
    put(cx, ".");
    put_name(cx, def->fields[imm->c].name);
    return;
  }
  case MI_ALTMASK: {
    const MirCaseDef *def = &module->alts.ptr[imm->a].cases[imm->b];
    put_pair(cx, module->alts.ptr[imm->a].name, def->name);
    put_masked(cx, def->fields, def->nfields, imm->c);
    return;
  }
  case MI_TYPEMASK: {
    const MirTypeDef *def = &module->type_defs.ptr[imm->a];
    put_name(cx, def->name);
    put_masked(cx, def->fields, def->nfields, imm->b);
    return;
  }
  case MI_VTABLE:
    put(cx, "@");
    put_name(cx, module->vtables.ptr[imm->a].name);
    return;
  case MI_GLOBAL:
    put(cx, "@");
    put_name(cx, module->globals.ptr[imm->a].name);
    return;
  case MI_METHOD:
    put_pair(cx, module->ifaces.ptr[imm->a].name, module->ifaces.ptr[imm->a].methods[imm->b].name);
    return;
  default:
    return;
  }
}

static void put_float_imm(PrintCx *cx, const MirImm *imm) {
  const uint64_t bits = (uint64_t)imm->i;
  double value = 0;
  __builtin_memcpy(&value, &bits, sizeof value);
  if (__builtin_isfinite(value)) {
    mir_print_float(cx->out, value);
    return;
  }
  ms_strbuild_printf(cx->out, "0x%016llx", (unsigned long long)bits);
}

/* The text after the mnemonic (a comparison condition is part of the mnemonic). */
static void put_imm(PrintCx *cx, const MirImm *imm) {
  switch ((MirImmTag)imm->tag) {
  case MI_INT:
    ms_strbuild_append_i64(cx->out, imm->i);
    return;
  case MI_FLOAT:
    put_float_imm(cx, imm);
    return;
  case MI_BOOL:
    put(cx, imm->a != 0 ? "true" : "false");
    return;
  case MI_STR:
    mir_print_quoted(cx->out, ms_names_span(&cx->module->strings, imm->a));
    return;
  case MI_TY:
    mir_print_ty(cx->module, imm->a, cx->out);
    return;
  case MI_IDX:
    put_uint(cx, imm->a);
    return;
  case MI_SCOPE:
    put_uint(cx, imm->a);
    put(cx, " ");
    put_uint(cx, imm->b);
    return;
  case MI_NONE:
  case MI_CC:
    return;
  default:
    put_imm_declared(cx, imm);
    return;
  }
}

static void put_inst(PrintCx *cx, const MirInst *inst) {
  put(cx, mir_op_info[inst->op].name);
  if (inst->imm.tag == MI_CC) {
    put(cx, ".");
    ms_strbuild_append(cx->out, mir_cc_name((MirCc)inst->imm.a));
  } else if (inst->imm.tag != MI_NONE) {
    put(cx, " ");
    put_imm(cx, &inst->imm);
  }
  if (mir_op_is_call((MirOp)inst->op)) {
    put(cx, " (");
    put_values(cx, inst->args, inst->nargs);
    put(cx, ")");
  } else if (inst->nargs > 0) {
    put(cx, " ");
    put_values(cx, inst->args, inst->nargs);
  }
}

static void number_values(PrintCx *cx) {
  const MirFunc *func = cx->func;
  uint32_t next = 0;
  for (size_t b = 0; b < func->blocks.len; b++) {
    const MirBlockData *block = &func->blocks.ptr[b];
    for (size_t i = 0; i < block->params.len; i++) {
      uint32_t *number = &cx->numbers.ptr[block->params.ptr[i].value];
      if (*number == MIR_NONE) {
        *number = next++;
      }
    }
    for (size_t i = 0; i < block->insts.len; i++) {
      const MirValue result = block->insts.ptr[i].res;
      if (result != MIR_NONE && cx->numbers.ptr[result] == MIR_NONE) {
        cx->numbers.ptr[result] = next++;
      }
    }
  }
}

static void put_inline_hint(PrintCx *cx, const MirFunc *func) {
  put(cx, func->linkage == ML_EXPORT ? " export" : "");
  put(cx, func->inline_hint == MINL_ALWAYS ? " inline(always)" : "");
  put(cx, func->inline_hint == MINL_NEVER ? " inline(never)" : "");
}

static void put_kind(PrintCx *cx, const MirFunc *func) {
  put(cx, func->kind == MFK_METHOD ? " method" : "");
  if (func->kind == MFK_CLOSURE) {
    put(cx, " closure(");
    for (uint32_t i = 0; i < func->ncaptures; i++) {
      put_sep(cx, i);
      mir_print_ty(cx->module, func->captures[i], cx->out);
    }
    put(cx, ")");
  }
  put(cx, func->sort == MSORT_GENERIC ? " sort_cmp" : "");
  put(cx, func->sort == MSORT_SPECIALIZED ? " sort_cmp_for" : "");
  put(cx, func->explicit_cancel ? " explicit_cancel" : "");
}

static void put_list_attrs(PrintCx *cx, const MirFunc *func) {
  if (func->nnoalias > 0) {
    put(cx, " noalias(");
    for (uint32_t i = 0; i < func->nnoalias; i++) {
      put_sep(cx, i);
      put_uint(cx, func->noalias[i]);
    }
    put(cx, ")");
  }
  if (func->ncapture_closers > 0) {
    put(cx, " capture_closers(");
    for (uint32_t i = 0; i < func->ncapture_closers; i++) {
      put_sep(cx, i);
      put_uint(cx, func->capture_closers[i].capture);
      put(cx, " @");
      put_func_name(cx, func->capture_closers[i].func);
    }
    put(cx, ")");
  }
}

static void put_flag_attrs(PrintCx *cx, const MirFunc *func) {
  if (func->has_slot_result) {
    put(cx, " slot_result(@");
    put_func_name(cx, func->slot_result);
    put(cx, ")");
  }
  if (func->has_close_exit) {
    put(cx, " close_exit(@");
    put_func_name(cx, func->close_exit[0]);
    put(cx, ", @");
    put_func_name(cx, func->close_exit[1]);
    put(cx, ")");
  }
  put(cx, func->ret_borrowed ? " ret_borrowed" : "");
  put(cx, func->ret_view ? " ret_view" : "");
  put(cx, func->scoped ? " scoped" : "");
  put(cx, func->keeps_scoped ? " keeps_scoped" : "");
  put(cx, func->unwind_only ? " unwind_only" : "");
  put(cx, func->raw_scratch ? " raw_scratch" : "");
  if (func->has_slot_close) {
    put(cx, " slot_close(");
    mir_print_ty(cx->module, func->slot_close, cx->out);
    put(cx, ")");
  }
}

static void put_header(PrintCx *cx) {
  const MirFunc *func = cx->func;
  put(cx, "fn @");
  put_name(cx, func->name);
  put(cx, "(");
  for (uint32_t i = 0; i < func->nparams; i++) {
    put_sep(cx, i);
    put_value(cx, func->blocks.ptr[0].params.ptr[i].value);
    put(cx, ": ");
    put_mode(cx, func->params[i].mode);
    mir_print_ty(cx->module, func->params[i].ty, cx->out);
  }
  put(cx, ") -> ");
  mir_print_ty(cx->module, func->ret, cx->out);
  put_inline_hint(cx, func);
  put_kind(cx, func);
  put_list_attrs(cx, func);
  put_flag_attrs(cx, func);
  put_loc(cx, func->loc);
  put(cx, " {\n");
}

static void put_block_label(PrintCx *cx, size_t index) {
  const MirBlockData *block = &cx->func->blocks.ptr[index];
  if (index == 0) {
    put(cx, "b0:\n");
    return;
  }
  put(cx, "b");
  put_uint(cx, index);
  put(cx, "(");
  for (size_t i = 0; i < block->params.len; i++) {
    const MirBlockParam *param = &block->params.ptr[i];
    put_sep(cx, i);
    put_value(cx, param->value);
    put(cx, ": ");
    put_mode(cx, param->mode);
    mir_print_ty(cx->module, mir_value_ty(cx->func, param->value), cx->out);
  }
  put(cx, "):\n");
}

static void put_block(PrintCx *cx, size_t index) {
  const MirBlockData *block = &cx->func->blocks.ptr[index];
  put_block_label(cx, index);
  for (size_t i = 0; i < block->insts.len; i++) {
    const MirInst *inst = &block->insts.ptr[i];
    put(cx, "  ");
    if (inst->res != MIR_NONE) {
      put_value(cx, inst->res);
      put(cx, ": ");
      mir_print_ty(cx->module, mir_value_ty(cx->func, inst->res), cx->out);
      put(cx, " = ");
    }
    put_inst(cx, inst);
    put_loc(cx, inst->loc);
    put(cx, "\n");
  }
  put(cx, "  ");
  put_term(cx, &block->term);
  put_loc(cx, block->term_loc);
  put(cx, "\n");
}

static void put_scopes_and_names(PrintCx *cx) {
  const MirFunc *func = cx->func;
  for (size_t i = 0; i < func->scopes.len; i++) {
    const MirScope *scope = &func->scopes.ptr[i];
    put(cx, "  scope ");
    mir_print_quoted(cx->out, ms_names_span(&cx->module->names, scope->name));
    ms_strbuild_printf(cx->out, " %u %u %u\n", scope->file, scope->parent, scope->call_line);
  }
  for (size_t i = 0; i < func->names.len; i++) {
    const MirNamedValue *named = &func->names.ptr[i];
    if (named->value >= func->values.len || cx->numbers.ptr[named->value] == MIR_NONE) {
      continue; /* its value no longer exists */
    }
    ms_strbuild_printf(cx->out, "  name %%%u ", cx->numbers.ptr[named->value]);
    mir_print_quoted(cx->out, ms_names_span(&cx->module->names, named->name));
    ms_strbuild_printf(cx->out, " %s %u\n", named->param ? "param" : "local", named->scope);
  }
}

static bool is_exact(const MirFunc *func, uint32_t value) {
  return (value >> 6) < func->nexact && ((func->exact[value >> 6] >> (value & 63)) & 1) != 0;
}

/* The exact values in printed-number order, which is not the value order after a pass moved values. */
static void put_exact(PrintCx *cx) {
  const MirFunc *func = cx->func;
  MirIdList by_number = {0};
  mir_idlist_reserve(&by_number, func->values.len);
  for (size_t i = 0; i < func->values.len; i++) {
    mir_idlist_push(&by_number, MIR_NONE);
  }
  for (uint32_t value = 0; value < func->values.len; value++) {
    const uint32_t number = cx->numbers.ptr[value];
    if (number != MIR_NONE) {
      by_number.ptr[number] = value;
    }
  }
  for (uint32_t number = 0; number < by_number.len; number++) {
    const uint32_t value = by_number.ptr[number];
    if (value != MIR_NONE && is_exact(func, value)) {
      ms_strbuild_printf(cx->out, "  exact %%%u\n", number);
    }
  }
  mir_idlist_free(&by_number);
}

void mir_print_func(const MirModule *module, const MirFunc *func, MsStrBuild *out) {
  PrintCx cx = {module, func, {0}, out};
  mir_idlist_reserve(&cx.numbers, func->values.len);
  for (size_t i = 0; i < func->values.len; i++) {
    mir_idlist_push(&cx.numbers, MIR_NONE);
  }
  number_values(&cx);
  put_header(&cx);
  for (size_t i = 0; i < func->blocks.len; i++) {
    put_block(&cx, i);
  }
  put_scopes_and_names(&cx);
  if (func->nexact > 0) {
    put_exact(&cx);
  }
  put(&cx, "}\n");
  mir_idlist_free(&cx.numbers);
}
