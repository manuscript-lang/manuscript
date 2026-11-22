/* compiler/mir/mir_desc_glue.c: the equality and hash functions a descriptor of an aggregate points to. A value
 * with no equality of its own (a record, an alternative or an optional that holds a string, a list...) compares and
 * hashes through its shape table in the runtime: each function here is `msstd_value_equals` or `msstd_value_hash`
 * of the type's shape. Runs before the data tables, over every type a `typedesc` asks for and the element and key
 * types a collection descriptor names. */
#include "compiler/mir/mir_desc_glue.h"

#include "compiler/mir/mir_builder.h"
#include "compiler/mir/mir_analysis.h"
#include "compiler/mir/mir_layout.h"

typedef struct GlueCx {
  MirModule *module;
  MirLayouts layouts;
  MirTyList seen;
  uint32_t equals_extern, hash_extern;
} GlueCx;

static bool seen(const GlueCx *cx, MirTy ty) {
  for (size_t index = 0; index < cx->seen.len; index++) {
    if (cx->seen.ptr[index] == ty) {
      return true;
    }
  }
  return false;
}

static uint32_t declare(GlueCx *cx, const char *name, uint32_t nparams, MirTy ret) {
  MirParam *params = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirParam, nparams);
  for (uint32_t index = 0; index < nparams; index++) {
    params[index] = (MirParam){MIR_PTR, MM_BORROW};
  }
  const MirExtern external = {.name = mir_name(cx->module, ms_span_of_text(name)),
                              .params = params,
                              .nparams = nparams,
                              .ret = ret,
                              .leaf = true,
                              .pure = true,
                              .reads = true};
  return mir_extern_intern(cx->module, &external);
}

/* `fn(a, b) -> bool` or `fn(a) -> int` over the shape of `ty`. */
static uint32_t make_function(GlueCx *cx, MirTy ty, bool equality) {
  MirParam params[2] = {{MIR_PTR, MM_BORROW}, {MIR_PTR, MM_BORROW}};
  const MirTy ret = equality ? MIR_BOOL : MIR_INT;
  MirBuilder b;
  mir_b_init(&b, cx->module, mir_name(cx->module, ms_span_of_text(equality ? "desc.eq" : "desc.hash")), params,
             equality ? 2 : 1, ret);
  MirValue args[2];
  mir_b_params(&b, args, equality ? 2 : 1);
  const MirImm of_type = {.tag = MI_TY, .a = ty};
  const MirValue table = mir_b_emit(&b, MOP_Shape, NULL, 0, of_type, MIR_PTR);
  const MirValue call_args[3] = {table, args[0], equality ? args[1] : MIR_NONE};
  const MirValue result = mir_b_call_rt(&b, equality ? cx->equals_extern : cx->hash_extern, call_args,
                                        equality ? 3 : 2);
  mir_b_ret(&b, result);
  MirFunc built;
  if (!mir_b_into_func(&b, &built)) {
    return MIR_NONE;
  }
  built.linkage = ML_INTERNAL;
  return mir_add_func(cx->module, &built);
}

static void visit_type(GlueCx *cx, MirTy key);

/* Whether the descriptor of `ty` is the opaque kind: it needs functions to compare and hash. */
static bool is_custom(GlueCx *cx, MirTy ty) {
  const MirTyData *data = mir_ty_data(cx->module, ty);
  if (data->kind == MK_LIST || data->kind == MK_OBJ || data->kind == MK_FN) {
    return false;
  }
  if (data->kind == MK_OPT && mir_opt_is_nullable(&cx->layouts, data->elem)) {
    return false;
  }
  return mir_needs_drop(cx->module, ty);
}

static bool has_glue(const GlueCx *cx, MirTy ty) {
  for (size_t index = 0; index < cx->module->desc_glue.len; index++) {
    if (cx->module->desc_glue.ptr[index].ty == ty) {
      return true;
    }
  }
  return false;
}

static void visit_type(GlueCx *cx, MirTy key) {
  const MirTy ty = mir_ty_unscoped(key);
  if (ty == MIR_NONE || seen(cx, ty)) {
    return;
  }
  mir_tylist_push(&cx->seen, ty);
  const MirTyData *data = mir_ty_data(cx->module, ty);
  if (data->kind == MK_LIST) {
    visit_type(cx, data->elem);
  } else if (data->kind == MK_OBJ && data->obj_class == MIR_OBJ_COLLECTION) {
    for (uint32_t index = 0; index < data->nargs && index < 2; index++) {
      visit_type(cx, data->args[index]);
    }
  } else if (is_custom(cx, ty) && !has_glue(cx, ty)) {
    const uint32_t eq = make_function(cx, ty, true);
    const uint32_t hash = make_function(cx, ty, false);
    if (eq != MIR_NONE && hash != MIR_NONE) {
      mir_add_desc_glue(cx->module, ty, eq, hash);
    }
  }
}

void mir_desc_glue(MirModule *module) {
  GlueCx cx = {.module = module};
  mir_layouts_init(&cx.layouts, module);
  cx.equals_extern = declare(&cx, "msstd_value_equals", 3, MIR_BOOL);
  cx.hash_extern = declare(&cx, "msstd_value_hash", 2, MIR_INT);
  const size_t count = module->funcs.len; /* the functions made here have no typedesc */
  for (size_t f = 0; f < count; f++) {
    /* Visiting a type adds functions, which may move the function table: read this function's blocks first. */
    const MirBlockList blocks = module->funcs.ptr[f].blocks;
    for (uint32_t b = 0; b < blocks.len; b++) {
      const MirBlockData *block = &blocks.ptr[b];
      for (uint32_t i = 0; i < block->insts.len; i++) {
        const MirInst *inst = &block->insts.ptr[i];
        if (inst->op == MOP_TypeDesc && inst->imm.tag == MI_TY) {
          visit_type(&cx, inst->imm.a);
        }
      }
    }
  }
  mir_tylist_free(&cx.seen);
  mir_layouts_free(&cx.layouts);
}
