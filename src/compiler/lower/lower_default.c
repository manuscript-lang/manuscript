/* compiler/lower/lower_default.c: record field defaults. A field written `port: Int = 8080` has a function
 * `fn(out, record) Void` that builds the default in place at `out`; the shape table of the type names it, so a
 * parse that finds no member builds the default as a call of the type does. */
#include "compiler/lower/lower_fn.h"
#include "compiler/lower/lower.h"
#include "compiler/mir/mir_analysis.h"

uint32_t lower_field_default(Lower *cx, uint32_t module, const MsExpr *expr, MirTy ty, const LowerSubst *subst) {
  MirParam *params = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirParam, 3);
  params[0] = (MirParam){MIR_PTR, (uint8_t)MM_BORROW};
  params[1] = (MirParam){MIR_PTR, (uint8_t)MM_BORROW};
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_printf(&text, "default.%zu", (size_t)cx->module->funcs.len);
  const MsName name = mir_name(cx->module, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  MirFunc func;
  mir_func_init(cx->module, &func, name, params, 2, MIR_VOID);
  func.linkage = ML_INTERNAL;
  const uint32_t id = mir_add_func(cx->module, &func);
  LowerSubst copy = subst != NULL ? *subst : (LowerSubst){0};
  if (copy.count != 0) {
    MsTy *vars = MS_ARENA_NEW_ARRAY(&cx->program->arena, MsTy, copy.count * 2 + 1);
    for (size_t index = 0; index < copy.count; index++) {
      vars[index] = copy.vars[index];
      vars[copy.count + index] = copy.args[index];
    }
    copy.vars = vars;
    copy.args = vars + copy.count;
  }
  lower_default_list_push(&cx->defaults, (LowerDefault){expr, module, id, ty, copy, false});
  return id;
}

static bool lower_default(Lower *cx, uint32_t index) {
  const LowerDefault item = cx->defaults.ptr[index];
  const MirFunc reserved = cx->module->funcs.ptr[item.func];
  LowerFn fn = {.cx = cx,
                .facts = &cx->program->modules.ptr[item.module].facts,
                .module_index = item.module,
                .file = lower_file(cx, item.module),
                .subst = item.subst,
                .ret = MIR_VOID,
                .hint = item.ty};
  mir_b_init(&fn.b, cx->module, reserved.name, reserved.params, reserved.nparams, MIR_VOID);
  fn.b.func.loc = (MirLoc){fn.file, 0, 0, 0};
  (void)fn_scope_begin(&fn);
  MirValue params[2];
  mir_b_params(&fn.b, params, 2);
  fn.nvars = 16;
  fn.vars = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirVar, (size_t)fn.nvars + 1);
  mir_b_set_loc(&fn.b, fn_loc(&fn, item.expr->pos));
  MirValue value = fn_expr(&fn, item.expr, LW_MOVE);
  bool ok = value != MIR_NONE && !fn.failed;
  if (ok) {
    const MirTy ty = mir_b_ty(&fn.b, value);
    const bool owns = mir_needs_drop(cx->module, ty);
    if (owns) {
      (void)mir_b_emit(&fn.b, MOP_ScopeDisown, &value, 1, (MirImm){0}, MIR_NONE);
    }
    const MirValue stored[2] = {params[0], value};
    (void)mir_b_emit(&fn.b, owns ? MOP_Put : MOP_Store, stored, 2, (MirImm){0}, MIR_NONE);
    fn_scope_unwind(&fn, 0);
    mir_b_ret(&fn.b, MIR_NONE);
  }
  MirFunc built;
  if (!mir_b_into_func(&fn.b, &built) || !ok) {
    return !fn.failed ? lower_fail(cx, "a field default could not be built") : false;
  }
  built.linkage = ML_INTERNAL;
  mir_func_release(&cx->module->funcs.ptr[item.func]);
  cx->module->funcs.ptr[item.func] = built;
  cx->defaults.ptr[index].lowered = true;
  return true;
}

bool lower_default_bodies(Lower *cx, bool *progressed) {
  for (size_t index = 0; index < cx->defaults.len; index++) {
    if (!cx->defaults.ptr[index].lowered) {
      *progressed = true;
      if (!lower_default(cx, (uint32_t)index)) {
        return lower_fail(cx, "  while lowering a field default at %u:%u", cx->defaults.ptr[index].expr->pos.line,
                          cx->defaults.ptr[index].expr->pos.column);
      }
    }
  }
  return true;
}
