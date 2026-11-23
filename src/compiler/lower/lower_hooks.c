/* compiler/lower/lower_hooks.c: the hooks of a shape. A generic native (text, JSON) walks a value by its shape and has
 * no way to call the program's code; a type that declares its own `to_string` or `to_json` gets a small function the
 * shape table points at, so the type shows and encodes the same wherever it is nested. */
#include "compiler/lower/lower_fn.h"
#include "compiler/lower/lower.h"
#include "compiler/mir/mir_analysis.h"
#include "compiler/mir/mir_json_tree.h"

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

/* A hook function taking two addresses: the slot that holds the value, and the text or writer it fills. */
static uint32_t reserve(Lower *cx, const char *what, MirTy ret) {
  MirParam *params = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirParam, 3);
  params[0] = (MirParam){MIR_PTR, (uint8_t)MM_BORROW};
  params[1] = (MirParam){MIR_PTR, (uint8_t)MM_BORROW};
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_printf(&text, "%s.%zu", what, (size_t)cx->module->funcs.len);
  const MsName name = mir_name(cx->module, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  MirFunc func;
  mir_func_init(cx->module, &func, name, params, 2, ret);
  func.linkage = ML_INTERNAL;
  return mir_add_func(cx->module, &func);
}

static uint32_t finish(Lower *cx, LowerFn *fn, uint32_t slot, MirValue result) {
  fn_scope_unwind(fn, 0);
  mir_b_ret(&fn->b, result);
  MirFunc built;
  if (!mir_b_into_func(&fn->b, &built) || fn->failed) {
    (void)lower_fail(cx, "a shape hook could not be built");
    return MIR_NONE;
  }
  built.linkage = ML_INTERNAL;
  mir_func_release(&cx->module->funcs.ptr[slot]);
  cx->module->funcs.ptr[slot] = built;
  return slot;
}

static MirValue receiver(LowerFn *fn, MirValue address, MirTy ty) {
  const MirImm of_type = {.tag = MI_TY, .a = ty};
  return mir_b_emit(&fn->b, MOP_Load, &address, 1, of_type, ty);
}

/* `fn(slot, out)`: the type's own text, moved into the string `out` addresses. */
static uint32_t text_hook(Lower *cx, MirTy ty, uint32_t method) {
  const uint32_t slot = reserve(cx, "shape.text", MIR_VOID);
  const MirFunc reserved = cx->module->funcs.ptr[slot];
  LowerFn fn = begin(cx, &reserved);
  MirValue args[2];
  mir_b_params(&fn.b, args, 2);
  MirValue self = receiver(&fn, args[0], ty);
  const MirValue text = mir_b_call(&fn.b, method, &self, 1);
  const MirValue stored[2] = {args[1], text};
  (void)mir_b_emit(&fn.b, MOP_Put, stored, 2, (MirImm){0}, MIR_NONE);
  return finish(cx, &fn, slot, MIR_NONE);
}

/* `fn(slot, writer) -> u8`: the `JsonValue` the type's own `to_json` returns, written by the runtime through the
 * shape of `JsonValue`; 0 when it was written. */
static uint32_t json_hook(Lower *cx, MirTy ty, MirTy tree_ty, uint32_t method) {
  const uint32_t slot = reserve(cx, "shape.json", MIR_UINT8);
  const MirFunc reserved = cx->module->funcs.ptr[slot];
  LowerFn fn = begin(cx, &reserved);
  MirValue args[2];
  mir_b_params(&fn.b, args, 2);
  MirValue self = receiver(&fn, args[0], ty);
  const MirValue tree = mir_b_call(&fn.b, method, &self, 1);
  const MirImm tree_imm = {.tag = MI_TY, .a = tree_ty};
  const MirValue holder = mir_b_emit(&fn.b, MOP_Slot, NULL, 0, tree_imm, MIR_PTR);
  const MirValue stored[2] = {holder, tree};
  (void)mir_b_emit(&fn.b, MOP_Put, stored, 2, (MirImm){0}, MIR_NONE);
  const MirValue table = mir_b_emit(&fn.b, MOP_Shape, NULL, 0, tree_imm, MIR_PTR);
  const MirValue operands[3] = {args[1], table, holder};
  const MirValue status = fn_runtime_call(&fn, mir_name(cx->module, ms_span_of_text("msstd_json_w_value")), operands, 3, MIR_UINT8);
  const MirValue back = mir_b_emit(&fn.b, MOP_Take, &holder, 1, tree_imm, tree_ty);
  (void)mir_b_emit(&fn.b, MOP_Drop, &back, 1, (MirImm){0}, MIR_NONE);
  return finish(cx, &fn, slot, status);
}

/* A method of `ty` the hook can call: one borrowed receiver, answering `ret`. */
static uint32_t own_method(Lower *cx, MirTy ty, const char *name, MirTy ret) {
  const MsTy checked = lower_source_type(cx, ty);
  if (checked == MS_TY_NONE) {
    return MIR_NONE;
  }
  const uint32_t method = lower_named_method(cx, checked, name);
  if (method == MIR_NONE) {
    return MIR_NONE;
  }
  const MirFunc *func = &cx->module->funcs.ptr[method];
  return func->nparams == 1 && func->ret == ret && func->params[0].mode != MM_MOVE ? method : MIR_NONE;
}

/* The `to_json` of `ty` when it answers the untyped JSON value; `tree` is that value's type. */
static uint32_t own_json_method(Lower *cx, MirTy ty, MirTy *tree) {
  const MsTy checked = lower_source_type(cx, ty);
  const uint32_t method = checked == MS_TY_NONE ? MIR_NONE : lower_named_method(cx, checked, "to_json");
  if (method == MIR_NONE) {
    return MIR_NONE;
  }
  const MirFunc *func = &cx->module->funcs.ptr[method];
  const MirTyData *ret = mir_ty_data(cx->module, func->ret);
  if (func->nparams != 1 || func->params[0].mode == MM_MOVE || ret->kind != MK_ALT ||
      cx->module->alts.ptr[ret->id].std != MSTD_JSON_VALUE) {
    return MIR_NONE;
  }
  *tree = func->ret;
  return method;
}

static bool visited(Lower *cx, MirTy ty) {
  for (size_t index = 0; index < cx->hooked.len; index++) {
    if (cx->hooked.ptr[index] == ty) {
      return true;
    }
  }
  mir_idlist_push(&cx->hooked, ty);
  return false;
}

static void walk(Lower *cx, MirTy ty);

/* A native object type that declares its own `to_string` or `to_json` shows and encodes through them. */
static void object_hooks(Lower *cx, MirTy ty) {
  if (mir_ty_data(cx->module, ty)->obj_class != MIR_OBJ_HANDLE || visited(cx, ty)) {
    return;
  }
  MirTy tree = MIR_NONE;
  const uint32_t text = own_method(cx, ty, "to_string", MIR_STR);
  const uint32_t json = own_json_method(cx, ty, &tree);
  if (text == MIR_NONE && json == MIR_NONE) {
    return;
  }
  const uint32_t text_fn = text != MIR_NONE ? text_hook(cx, ty, text) : MIR_NONE;
  const uint32_t json_fn = json != MIR_NONE ? json_hook(cx, ty, tree, json) : MIR_NONE;
  mir_obj_hook_list_push(&cx->module->obj_hooks, (MirObjHook){ty, text_fn != MIR_NONE ? text_fn + 1 : 0, json_fn != MIR_NONE ? json_fn + 1 : 0});
}

static void walk_fields(Lower *cx, const MirField *fields, uint32_t count) {
  for (uint32_t at = 0; at < count; at++) {
    walk(cx, fields[at].ty);
  }
}

static void walk(Lower *cx, MirTy ty) {
  const MirTyData *data = mir_ty_data(cx->module, ty);
  if (data->kind == MK_LIST || data->kind == MK_OPT) {
    walk(cx, data->elem);
    return;
  }
  if (data->kind == MK_OBJ) {
    const uint32_t nargs = data->nargs;
    for (uint32_t at = 0; at < nargs; at++) {
      walk(cx, mir_ty_data(cx->module, ty)->args[at]);
    }
    object_hooks(cx, ty);
    return;
  }
  if ((data->kind != MK_TYPE && data->kind != MK_ALT) || visited(cx, ty)) {
    return;
  }
  const bool record = data->kind == MK_TYPE;
  const uint32_t id = data->id;
  MirTy tree = MIR_NONE;
  const uint32_t text = own_method(cx, ty, "to_string", MIR_STR);
  const uint32_t json = own_json_method(cx, ty, &tree);
  const uint32_t text_fn = text != MIR_NONE ? text_hook(cx, ty, text) : MIR_NONE;
  const uint32_t json_fn = json != MIR_NONE ? json_hook(cx, ty, tree, json) : MIR_NONE;
  if (record) {
    cx->module->type_defs.ptr[id].text_fn1 = text_fn != MIR_NONE ? text_fn + 1 : 0;
    cx->module->type_defs.ptr[id].json_fn1 = json_fn != MIR_NONE ? json_fn + 1 : 0;
    const MirTypeDef *def = &cx->module->type_defs.ptr[id];
    walk_fields(cx, def->fields, def->nfields);
    return;
  }
  cx->module->alts.ptr[id].text_fn1 = text_fn != MIR_NONE ? text_fn + 1 : 0;
  cx->module->alts.ptr[id].json_fn1 = json_fn != MIR_NONE ? json_fn + 1 : 0;
  if (mir_json_tree_shape(cx->module, ty)) {
    const uint32_t tree_fn = mir_json_tree_ctor(cx->module, ty); /* a parse reads the untyped tree wherever it sits */
    cx->module->alts.ptr[id].tree_fn1 = tree_fn != MIR_NONE ? tree_fn + 1 : 0;
  }
  for (uint32_t kase = 0; kase < cx->module->alts.ptr[id].ncases; kase++) {
    const MirCaseDef *def = &cx->module->alts.ptr[id].cases[kase];
    walk_fields(cx, def->fields, def->nfields);
  }
}

void lower_shape_hooks(Lower *cx, MirTy ty) {
  walk(cx, ty);
}

MirValue fn_shape(LowerFn *fn, MirTy ty) {
  lower_shape_hooks(fn->cx, ty);
  const MirImm of_type = {.tag = MI_TY, .a = ty};
  return mir_b_emit(&fn->b, MOP_Shape, NULL, 0, of_type, MIR_PTR);
}
