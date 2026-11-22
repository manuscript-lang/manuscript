/* compiler/lower/lower_glue.c: the equality and hash functions of a descriptor. The runtime compares and hashes
 * values it knows only by address (list elements, map keys) through their descriptor; a record or an alternative
 * has no byte-wise answer (strings are pointers), so each one the program describes gets a pair of functions that
 * compare and hash it field by field, the way `==` does. */
#include "compiler/lower/lower_fn.h"
#include "compiler/lower/lower.h"
#include "compiler/mir/mir_analysis.h"

static bool has_glue(const Lower *cx, MirTy ty) {
  for (size_t index = 0; index < cx->glues.len; index++) {
    if (cx->glues.ptr[index].ty == ty) {
      return true;
    }
  }
  return false;
}

static uint32_t reserve(Lower *cx, const char *what, uint32_t nparams, MirTy ret) {
  MirParam *params = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirParam, (size_t)nparams + 1);
  for (uint32_t at = 0; at < nparams; at++) {
    params[at] = (MirParam){MIR_PTR, (uint8_t)MM_BORROW};
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_printf(&text, "%s.%zu", what, (size_t)cx->module->funcs.len);
  const MsName name = mir_name(cx->module, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  MirFunc func;
  mir_func_init(cx->module, &func, name, params, nparams, ret);
  func.linkage = ML_INTERNAL;
  return mir_add_func(cx->module, &func);
}

/* Gives `ty` its glue if it is a record or an alternative, and does the same for the types a descriptor of `ty`
 * reaches (elements, keys, values). True when something was added. */
static bool ensure(Lower *cx, MirTy ty) {
  const MirTyData *data = mir_ty_data(cx->module, ty);
  bool added = false;
  if (data->kind == MK_LIST) {
    return ensure(cx, data->elem);
  }
  if (data->kind == MK_OPT) {
    added = ensure(cx, data->elem);
    data = mir_ty_data(cx->module, ty);
  }
  if (data->kind == MK_OBJ) {
    for (uint32_t at = 0; at < data->nargs; at++) {
      added = ensure(cx, mir_ty_data(cx->module, ty)->args[at]) || added;
    }
    return added;
  }
  if ((data->kind != MK_TYPE && data->kind != MK_ALT && data->kind != MK_OPT) || has_glue(cx, ty)) {
    return added;
  }
  const uint32_t eq = reserve(cx, "eq", 2, MIR_BOOL);
  const uint32_t hash = reserve(cx, "hash", 1, MIR_INT);
  lower_glue_list_push(&cx->glues, (LowerGlue){ty, eq, hash, false});
  mir_add_desc_glue(cx->module, ty, eq, hash);
  return true;
}

static LowerFn begin(Lower *cx, const MirFunc *reserved) {
  LowerFn fn = {.cx = cx,
                .facts = &cx->program->modules.ptr[0].facts,
                .module_index = 0,
                .file = lower_file(cx, 0),
                .ret = reserved->ret};
  mir_b_init(&fn.b, cx->module, reserved->name, reserved->params, reserved->nparams, reserved->ret);
  fn.b.func.loc = (MirLoc){fn.file, 0, 0, 0};
  (void)fn_scope_begin(&fn);
  fn.nvars = 16;
  fn.vars = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirVar, (size_t)fn.nvars + 1);
  return fn;
}

static bool finish(Lower *cx, LowerFn *fn, uint32_t slot, MirValue result) {
  fn_scope_unwind(fn, 0);
  mir_b_ret(&fn->b, result);
  MirFunc built;
  if (!mir_b_into_func(&fn->b, &built) || fn->failed || result == MIR_NONE) {
    return !fn->failed ? lower_fail(cx, "a comparison or hash function could not be built") : false;
  }
  built.linkage = ML_INTERNAL;
  mir_func_release(&cx->module->funcs.ptr[slot]);
  cx->module->funcs.ptr[slot] = built;
  return true;
}

static MirValue load_at(LowerFn *fn, MirValue address, MirTy ty) {
  const MirImm of_type = {.tag = MI_TY, .a = ty};
  return mir_b_emit(&fn->b, MOP_Load, &address, 1, of_type, ty);
}

/* The hash of one value: the runtime hashes it by its descriptor from a slot that holds it. */
static MirValue hash_value(LowerFn *fn, MirValue value) {
  const MirTy ty = mir_b_ty(&fn->b, value);
  const MirImm of_type = {.tag = MI_TY, .a = ty};
  const MirValue desc = mir_b_emit(&fn->b, MOP_TypeDesc, NULL, 0, of_type, MIR_PTR);
  const MirValue slot = mir_b_emit(&fn->b, MOP_Slot, NULL, 0, of_type, MIR_PTR);
  const MirValue stored[2] = {slot, value};
  (void)mir_b_emit(&fn->b, MOP_Store, stored, 2, (MirImm){0}, MIR_NONE);
  const MirValue operands[2] = {desc, slot};
  return fn_runtime_call(fn, mir_name(fn->cx->module, ms_span_of_text("msrt_slot_hash")), operands, 2, MIR_INT);
}

static MirValue combine(LowerFn *fn, MirValue seed, MirValue next) {
  const MirValue operands[2] = {seed, next};
  return fn_runtime_call(fn, mir_name(fn->cx->module, ms_span_of_text("msrt_hash_combine")), operands, 2, MIR_INT);
}

static MirValue hash_record(LowerFn *fn, MirValue value, MirTy ty) {
  const uint32_t id = mir_ty_data(fn->cx->module, ty)->id;
  const MirTypeDef *def = &fn->cx->module->type_defs.ptr[id];
  MirValue hash = mir_b_iconst(&fn->b, 0);
  for (uint32_t field = 0; field < def->nfields; field++) {
    const MirImm imm = {.tag = MI_FIELD, .a = id, .b = field};
    const MirValue item = mir_b_emit(&fn->b, MOP_TypeGet, &value, 1, imm, def->fields[field].ty);
    hash = combine(fn, hash, hash_value(fn, item));
  }
  return hash;
}

/* Whether it holds a value, then that value. */
static MirValue hash_opt(LowerFn *fn, MirValue value, MirTy ty) {
  const MirTy payload = mir_ty_data(fn->cx->module, ty)->elem;
  const MirValue some = mir_b_emit(&fn->b, MOP_OptIsSome, &value, 1, (MirImm){0}, MIR_BOOL);
  const MirBlock join = mir_b_new_block(&fn->b);
  const MirValue result = mir_b_add_block_param(&fn->b, join, MIR_INT, MM_BORROW);
  const MirBlock present = mir_b_new_block(&fn->b);
  const MirBlock absent = mir_b_new_block(&fn->b);
  mir_b_br_if(&fn->b, some, present, NULL, 0, absent, NULL, 0);
  mir_b_seal_block(&fn->b, present);
  mir_b_seal_block(&fn->b, absent);
  mir_b_switch_to(&fn->b, present);
  const MirValue item = mir_b_emit(&fn->b, MOP_OptGet, &value, 1, (MirImm){0}, payload);
  const MirValue full = combine(fn, mir_b_iconst(&fn->b, 1), hash_value(fn, item));
  mir_b_br(&fn->b, join, &full, 1);
  mir_b_switch_to(&fn->b, absent);
  const MirValue none = mir_b_iconst(&fn->b, 0);
  mir_b_br(&fn->b, join, &none, 1);
  mir_b_seal_block(&fn->b, join);
  mir_b_switch_to(&fn->b, join);
  return result;
}

/* The case index, then the fields of that case. */
static MirValue hash_alt(LowerFn *fn, MirValue value, MirTy ty) {
  const uint32_t id = mir_ty_data(fn->cx->module, ty)->id;
  const MirAltDef *alt = &fn->cx->module->alts.ptr[id];
  const MirValue tag = mir_b_emit(&fn->b, MOP_AltTag, &value, 1, (MirImm){0}, MIR_INT);
  const MirBlock join = mir_b_new_block(&fn->b);
  const MirValue result = mir_b_add_block_param(&fn->b, join, MIR_INT, MM_BORROW);
  const MirValue start = hash_value(fn, tag);
  for (uint32_t kase = 0; kase < alt->ncases; kase++) {
    const MirBlock here = mir_b_new_block(&fn->b);
    const MirBlock next = mir_b_new_block(&fn->b);
    mir_b_br_if(&fn->b, mir_b_icmp(&fn->b, MCC_EQ, tag, mir_b_iconst(&fn->b, kase)), here, NULL, 0, next, NULL, 0);
    mir_b_seal_block(&fn->b, here);
    mir_b_seal_block(&fn->b, next);
    mir_b_switch_to(&fn->b, here);
    MirValue hash = start;
    for (uint32_t at = 0; at < alt->cases[kase].nfields; at++) {
      const MirTy field_ty = alt->cases[kase].fields[at].ty;
      if (field_ty == MIR_VOID) {
        continue;
      }
      const MirImm imm = {.tag = MI_ALTFIELD, .a = id, .b = kase, .c = at};
      const MirValue item = mir_b_emit(&fn->b, MOP_AltGet, &value, 1, imm, field_ty);
      hash = combine(fn, hash, hash_value(fn, item));
    }
    mir_b_br(&fn->b, join, &hash, 1);
    mir_b_switch_to(&fn->b, next);
  }
  mir_b_br(&fn->b, join, &start, 1);
  mir_b_seal_block(&fn->b, join);
  mir_b_switch_to(&fn->b, join);
  return result;
}

static bool lower_glue(Lower *cx, uint32_t index) {
  const LowerGlue glue = cx->glues.ptr[index];
  const MirFunc eq_reserved = cx->module->funcs.ptr[glue.eq];
  LowerFn eq = begin(cx, &eq_reserved);
  MirValue args[2];
  mir_b_params(&eq.b, args, 2);
  const MirValue same = fn_compare_values(&eq, MS_B_EQ, load_at(&eq, args[0], glue.ty), load_at(&eq, args[1], glue.ty));
  if (!finish(cx, &eq, glue.eq, same)) {
    return false;
  }
  const MirFunc hash_reserved = cx->module->funcs.ptr[glue.hash];
  LowerFn hash = begin(cx, &hash_reserved);
  MirValue slot[1];
  mir_b_params(&hash.b, slot, 1);
  const MirValue value = load_at(&hash, slot[0], glue.ty);
  const uint8_t kind = mir_ty_data(cx->module, glue.ty)->kind;
  const MirValue result = kind == MK_ALT   ? hash_alt(&hash, value, glue.ty)
                          : kind == MK_OPT ? hash_opt(&hash, value, glue.ty)
                                           : hash_record(&hash, value, glue.ty);
  cx->glues.ptr[index].lowered = true;
  return finish(cx, &hash, glue.hash, result);
}

bool lower_glue_bodies(Lower *cx, bool *progressed) {
  /* Every descriptor the program makes: its record and alternative types need glue before the data is built. */
  for (size_t fi = 0; fi < cx->module->funcs.len; fi++) {
    /* Adding glue appends functions: only the block lists, which stay where they are, are held across it. */
    const MirBlockData *blocks = cx->module->funcs.ptr[fi].blocks.ptr;
    const size_t nblocks = cx->module->funcs.ptr[fi].blocks.len;
    for (size_t bi = 0; bi < nblocks; bi++) {
      const MirBlockData *block = &blocks[bi];
      for (size_t ii = 0; ii < block->insts.len; ii++) {
        const MirInst *inst = &block->insts.ptr[ii];
        if (inst->op == MOP_TypeDesc && inst->imm.tag == MI_TY && ensure(cx, inst->imm.a)) {
          *progressed = true;
        }
      }
    }
  }
  for (size_t index = 0; index < cx->glues.len; index++) {
    if (!cx->glues.ptr[index].lowered) {
      *progressed = true;
      if (!lower_glue(cx, (uint32_t)index)) {
        return lower_fail(cx, "  while building the comparison of a type used through its descriptor");
      }
    }
  }
  return true;
}
