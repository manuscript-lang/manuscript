/* compiler/mir/mir_lower_ops.c: the lower-ops pass: the driver and the per-instruction rewrites. */
#include "compiler/mir/mir_lower_ops_internal.h"

#include "base/strbuild.h"

typedef enum LowerKind { LK_PLAIN, LK_STR, LK_OBJ, LK_GLUE } LowerKind;

uint32_t mirlo_rt(LowerCx *cx, uint32_t *cache, const char *name, const MirTy *params, uint32_t count, MirTy ret) {
  if (*cache != MIR_NONE) {
    return *cache;
  }
  MirExtern def = {.name = mir_name(cx->module, ms_span_of_text(name)),
                   .params = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirParam, count),
                   .nparams = count,
                   .ret = ret,
                   .fresh = ret != MIR_VOID,
                   .leaf = true,
                   .role = MR_NONE};
  for (uint32_t index = 0; index < count; index++) {
    def.params[index] = (MirParam){params[index], MM_BORROW};
  }
  *cache = mir_extern_intern(cx->module, &def);
  return *cache;
}

void mirlo_to_call_rt(MirInst *inst, uint32_t external) {
  inst->op = MOP_CallRt;
  inst->imm = mir_imm_ext(external);
}

void mirlo_to_call(MirInst *inst, uint32_t func) {
  inst->op = MOP_Call;
  inst->imm = (MirImm){.tag = MI_FUNC, .a = func};
}

/* A value that is one pointer to a runtime object: a function (closure), an object other than a map or set, or
 * an optional of one that is null when absent. */
static bool is_obj_like(LowerCx *cx, MirTy ty) {
  const MirTyData *data = mir_ty_data(cx->module, ty);
  switch ((MirTyKind)data->kind) {
  case MK_FN: return true;
  case MK_OBJ: return data->obj_class != MIR_OBJ_COLLECTION;
  case MK_OPT:
    return mir_opt_is_nullable(&cx->layouts, data->elem) && !mir_layouts_opt_boxed(&cx->layouts, data->elem);
  default: return false;
  }
}

static LowerKind kind_of(LowerCx *cx, MirTy ty) {
  if (!mir_needs_drop(cx->module, ty)) {
    return LK_PLAIN;
  }
  if (mir_is_str_like(&cx->layouts, ty)) {
    return LK_STR;
  }
  return is_obj_like(cx, ty) ? LK_OBJ : LK_GLUE;
}

/* `clone v` of the type of `inst`'s operand: renamed away, a runtime call, or a call of the clone glue.
 * Returns true when the instruction is to be removed. */
static bool lower_clone(LowerCx *cx, MirFunc *func, MirInst *inst) {
  const MirTy ty = mir_value_ty(func, inst->args[0]);
  const LowerKind kind = kind_of(cx, ty);
  if (kind == LK_PLAIN) {
    mir_func_replace_uses(func, inst->res, inst->args[0]);
    return true;
  }
  if (kind == LK_STR) {
    const MirTy str = MIR_STR;
    mirlo_to_call_rt(inst, mirlo_rt(cx, &cx->string_clone, "msrt_string_clone", &str, 1, MIR_STR));
  } else if (kind == LK_OBJ) {
    const MirTy ptr = MIR_PTR;
    mirlo_to_call_rt(inst, mirlo_rt(cx, &cx->obj_clone, "msrt_obj_clone", &ptr, 1, MIR_PTR));
  } else {
    const uint32_t glue = mir_glue_find(cx->glue, MG_CLONE, ty, 0, 0);
    if (glue != MIR_NONE) {
      mirlo_to_call(inst, glue);
    }
  }
  return false;
}

static bool lower_drop(LowerCx *cx, MirFunc *func, MirInst *inst) {
  const MirTy ty = mir_value_ty(func, inst->args[0]);
  const LowerKind kind = kind_of(cx, ty);
  if (kind == LK_PLAIN) {
    return true;
  }
  if (kind == LK_STR) {
    const MirTy str = MIR_STR;
    mirlo_to_call_rt(inst, mirlo_rt(cx, &cx->string_free, "msrt_string_free", &str, 1, MIR_VOID));
  } else if (kind == LK_OBJ) {
    const MirTy ptr = MIR_PTR;
    mirlo_to_call_rt(inst, mirlo_rt(cx, &cx->obj_drop, "msrt_obj_drop", &ptr, 1, MIR_VOID));
  } else {
    const uint32_t glue = mir_glue_find(cx->glue, MG_DROP, ty, 0, 0);
    if (glue != MIR_NONE) {
      mirlo_to_call(inst, glue);
    }
  }
  return false;
}

/* `list.release l, from` calls the function made for the type of `l`. */
static void lower_list_release(const LowerCx *cx, const MirFunc *func, MirInst *inst) {
  const MirTy ty = mir_value_ty(func, inst->args[0]);
  for (size_t index = 0; index < cx->release_tys.len; index++) {
    if (cx->release_tys.ptr[index] == ty) {
      mirlo_to_call(inst, cx->release_fns.ptr[index]);
      return;
    }
  }
}

/* Rewrites `inst` in place, or returns true when it is to be removed. */
static bool lower_inst(LowerCx *cx, MirFunc *func, MirInst *inst) {
  switch ((MirOp)inst->op) {
  case MOP_MoveOut:
    mir_func_replace_uses(func, inst->res, inst->args[0]);
    return true;
  case MOP_Forget: return true;
  case MOP_OptNoneOwned: /* an ownership-only distinction (the optimizer reads it); emitters see opt.none */
    inst->op = MOP_OptNone;
    return false;
  case MOP_Clone: return lower_clone(cx, func, inst);
  case MOP_Drop: return lower_drop(cx, func, inst);
  case MOP_ListRelease: lower_list_release(cx, func, inst); return false;
  case MOP_StrLen: {
    const MirTy str = MIR_STR;
    mirlo_to_call_rt(inst, mirlo_rt(cx, &cx->string_length, "msrt_string_scalar_length", &str, 1, MIR_INT));
    return false;
  }
  default: return false;
  }
}

/* ---- thunks and release functions, made before any function is rewritten ---- */

/* The function `cleanup.thunk` the runtime calls with the address of a spilled value: it loads the value and
 * calls closer `closer`. */
static void make_thunk(LowerCx *cx, uint32_t closer) {
  if (cx->thunks.ptr[closer] != MIR_NONE) {
    return;
  }
  MirModule *module = cx->module;
  const MirTy ty = module->funcs.ptr[closer].params[0].ty;
  const MirParam param = {MIR_PTR, MM_BORROW};
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_printf(&text, "cleanup.thunk.%u", closer);
  MirBuilder b;
  mir_b_init(&b, module, mir_name(module, ms_strbuild_span(&text)), &param, 1, MIR_VOID);
  ms_strbuild_free(&text);
  mir_b_func(&b)->linkage = ML_INTERNAL;
  MirValue pointer = 0;
  mir_b_params(&b, &pointer, 1);
  const MirValue value = mir_b_emit(&b, MOP_Load, &pointer, 1, (MirImm){.tag = MI_TY, .a = ty}, ty);
  (void)mir_b_call(&b, closer, &value, 1);
  mir_b_ret(&b, mir_b_unit(&b));
  uint32_t id = MIR_NONE;
  if (mir_b_finish(&b, &id)) {
    cx->thunks.ptr[closer] = id;
  }
}

/* The thunk of every closer a `cleanup.push` registers. Adding one may move the function table, so the
 * function is fetched again after each. */
static void make_thunks(LowerCx *cx, size_t nfuncs) {
  for (size_t fi = 0; fi < nfuncs; fi++) {
    for (size_t bi = 0; bi < cx->module->funcs.ptr[fi].blocks.len; bi++) {
      for (size_t ii = 0; ii < cx->module->funcs.ptr[fi].blocks.ptr[bi].insts.len; ii++) {
        const MirInst inst = cx->module->funcs.ptr[fi].blocks.ptr[bi].insts.ptr[ii];
        if (inst.op == MOP_CleanupPush) {
          make_thunk(cx, inst.imm.a);
        }
      }
    }
  }
}

static bool release_known(const LowerCx *cx, MirTy ty) {
  for (size_t index = 0; index < cx->release_tys.len; index++) {
    if (cx->release_tys.ptr[index] == ty) {
      return true;
    }
  }
  return false;
}

/* The function behind `list.release` of every list type that has one. */
static void make_releases(LowerCx *cx, size_t nfuncs) {
  for (size_t fi = 0; fi < nfuncs; fi++) {
    const MirFunc *func = &cx->module->funcs.ptr[fi];
    for (size_t bi = 0; bi < func->blocks.len; bi++) {
      for (size_t ii = 0; ii < func->blocks.ptr[bi].insts.len; ii++) {
        const MirInst *inst = &func->blocks.ptr[bi].insts.ptr[ii];
        const MirTy ty = inst->op == MOP_ListRelease ? mir_value_ty(func, inst->args[0]) : MIR_NONE;
        if (ty == MIR_NONE || release_known(cx, ty)) {
          continue;
        }
        const uint32_t release = mir_glue_list_release(cx->module, ty);
        func = &cx->module->funcs.ptr[fi];
        inst = &func->blocks.ptr[bi].insts.ptr[ii];
        mir_tylist_push(&cx->release_tys, ty);
        mir_idlist_push(&cx->release_fns, release);
      }
    }
  }
}

static void lower_function(LowerCx *cx, MirFunc *func) {
  mirlo_list_drops(cx, func);
  mirlo_str_eq_lits(cx, func);
  mirlo_block_clones(cx, func);
  mirlo_expand_sets(cx, func);
  mirlo_split_drop_ifs(cx->module, func);
  mirlo_expand_cleanups(cx, func);
  mirlo_fault_messages(cx, func);
  for (size_t bi = 0; bi < func->blocks.len; bi++) {
    MirInstList *insts = &func->blocks.ptr[bi].insts;
    size_t kept = 0;
    for (size_t ii = 0; ii < insts->len; ii++) {
      if (!lower_inst(cx, func, &insts->ptr[ii])) {
        insts->ptr[kept++] = insts->ptr[ii];
      }
    }
    insts->len = kept;
  }
}

void mir_lower_ops(MirModule *module, const MirGlue *glue) {
  LowerCx cx = {.module = module, .glue = glue, .string_clone = MIR_NONE, .string_free = MIR_NONE,
                .obj_clone = MIR_NONE, .obj_drop = MIR_NONE, .string_length = MIR_NONE,
                .cleanup_push = MIR_NONE, .cleanup_run = MIR_NONE, .fault_string = MIR_NONE,
                .string_eq = MIR_NONE};
  const size_t nfuncs = module->funcs.len;
  for (size_t index = 0; index < nfuncs; index++) {
    mir_idlist_push(&cx.thunks, MIR_NONE);
  }
  make_thunks(&cx, nfuncs);
  make_releases(&cx, nfuncs);
  mir_layouts_init(&cx.layouts, module);
  for (size_t index = 0; index < nfuncs; index++) {
    lower_function(&cx, &module->funcs.ptr[index]);
  }
  for (size_t index = 0; index < cx.release_fns.len; index++) {
    lower_function(&cx, &module->funcs.ptr[cx.release_fns.ptr[index]]);
  }
  mir_layouts_free(&cx.layouts);
  mir_idlist_free(&cx.thunks);
  mir_tylist_free(&cx.release_tys);
  mir_idlist_free(&cx.release_fns);
}
