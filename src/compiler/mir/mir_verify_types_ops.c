/* Rules for calls, ownership, raw memory, runtime services and scope markers. (see mir_verify_types.h) */
#include "compiler/mir/mir_layout.h"
#include "compiler/mir/mir_verify_types.h"

/* ---- calls ---- */

/* Operands `first..` against the parameter types `types`, reporting a count or type mismatch. */
static const char *mvt_args_match(const MvtCx *c, const char *callee, uint32_t first,
                 const MirTy *types, uint32_t count) {
  if (c->n - first != count) {
    return mvt_fmt(c->v->arena, "%s takes %u arguments, found %u", callee, count, c->n - first);
  }
  for (uint32_t i = 0; i < count; i++) {
    if (mvt_t(c, first + i) != types[i]) {
      return mvt_mismatch(c, mvt_label(c, "argument", i), mvt_t(c, first + i), types[i]);
    }
  }
  return NULL;
}

static const char *mvt_param_types(const MvtCx *c, const MirParam *params, uint32_t n,
                 const char *callee, uint32_t first) {
  if (c->n - first != n) {
    return mvt_fmt(c->v->arena, "%s takes %u arguments, found %u", callee, n, c->n - first);
  }
  for (uint32_t i = 0; i < n; i++) {
    if (mvt_t(c, first + i) != params[i].ty) {
      return mvt_mismatch(c, mvt_label(c, "argument", i), mvt_t(c, first + i), params[i].ty);
    }
  }
  return NULL;
}

static const char *mvt_call(const MvtCx *c) {
  if (c->in->imm.tag != MI_FUNC) {
    return "missing callee";
  }
  if (c->in->imm.a >= c->m->funcs.len) {
    return "bad callee";
  }
  const MirFunc *callee = &c->m->funcs.ptr[c->in->imm.a];
  MVT_TRY(mvt_param_types(c, callee->params, callee->nparams, mvt_name(c, callee->name), 0));
  return mvt_want(mvt_res_is(c, callee->ret), "call yields the callee's result type");
}

static const char *mvt_call_ind(const MvtCx *c) {
  if (c->n == 0) {
    return "call.ind needs a closure";
  }
  const MirTyData *fn = mvt_data(c, mvt_t(c, 0));
  if (fn->kind != MK_FN) {
    return "operand 0 must be a closure";
  }
  if (c->n - 1 != fn->nargs) {
    return mvt_fmt(c->v->arena, "closure takes %u arguments, found %u", fn->nargs, c->n - 1);
  }
  for (uint32_t i = 0; i < fn->nargs; i++) {
    if (mvt_t(c, i + 1) != fn->args[i]) {
      return mvt_mismatch(c, mvt_label(c, "argument", i), mvt_t(c, i + 1), fn->args[i]);
    }
  }
  return mvt_want(mvt_res_is(c, fn->elem), "call.ind yields the closure's result type");
}

static const char *mvt_call_rt(const MvtCx *c) {
  if (c->in->imm.tag != MI_EXT) {
    return "missing runtime function";
  }
  if (c->in->imm.a >= c->m->externs.len) {
    return "bad runtime function";
  }
  const MirExtern *ext = &c->m->externs.ptr[c->in->imm.a];
  MVT_TRY(mvt_param_types(c, ext->params, ext->nparams, mvt_name(c, ext->name), 0));
  return mvt_want(mvt_res_is(c, ext->ret), "call.rt yields the declared result type");
}

static const char *mvt_call_method(const MvtCx *c) {
  const MirImm *im = &c->in->imm;
  if (im->tag != MI_METHOD) {
    return "missing method";
  }
  if (im->a >= c->m->ifaces.len || im->b >= c->m->ifaces.ptr[im->a].nmethods) {
    return "bad method";
  }
  const MirMethodSig *sig = &c->m->ifaces.ptr[im->a].methods[im->b];
  if (c->n == 0 || !mvt_is_kind_id(c, mvt_t(c, 0), MK_IFACE, im->a)) {
    return "operand 0 must be the interface value";
  }
  MVT_TRY(mvt_args_match(c, mvt_name(c, sig->name), 1, sig->params, sig->nparams));
  return mvt_want(mvt_res_is(c, sig->ret), "call.method yields the method's result type");
}

/* ---- ownership ---- */

static const char *mvt_clone(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  /* Copying a borrowing variant into itself would own what it must not drop: use alt.own. */
  bool ok = mvt_res_is(c, mvt_t(c, 0)) && mvt_needs_drop(c, mvt_t(c, 0)) &&
       !mvt_alt_has_borrowed_cases(c, mvt_t(c, 0));
  return mvt_want(ok, "copy duplicates a droppable value");
}

static const char *mvt_alt_own(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  if (mvt_kind(c, mvt_t(c, 0)) != MK_ALT || !c->has_res) {
    return "alt.own takes a borrowing variant";
  }
  if (mvt_kind(c, c->res) != MK_ALT) {
    return "alt.own yields an alternative";
  }
  return mvt_want(mvt_plain_of(c) && mvt_needs_drop(c, c->res),
          "alt.own copies a borrowing variant into its ordinary alternative");
}

static const char *mvt_move_out(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  return mvt_want(mvt_res_is(c, mvt_t(c, 0)) && mvt_needs_drop(c, mvt_t(c, 0)),
          "move.out takes ownership of a droppable value");
}

static const char *mvt_drop(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  return mvt_want(mvt_needs_drop(c, mvt_t(c, 0)), "drop takes a droppable value");
}

static const char *mvt_one_operand(const MvtCx *c) { return mvt_arity(c, 1); }

static const char *mvt_drop_if(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 2));
  return mvt_want(mvt_t(c, 0) == MIR_BOOL && mvt_needs_drop(c, mvt_t(c, 1)),
          "drop.if takes a flag and a droppable value");
}

/* ---- raw memory ---- */

static const char *mvt_slot(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 0));
  return mvt_want(c->in->imm.tag == MI_TY && mvt_res_is(c, MIR_PTR), "slot yields ptr");
}

static const char *mvt_list_addr(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 2));
  MirTy elem = 0;
  return mvt_want(mvt_list_elem(c, mvt_t(c, 0), &elem) && mvt_t(c, 1) == MIR_INT &&
            mvt_res_is(c, MIR_PTR),
          "list.addr takes a list and an index and yields a ptr to the element");
}

static bool mvt_access_width(const MirImm *im) {
  return im->tag == MI_INT && (im->i == 1 || im->i == 2 || im->i == 4 || im->i == 8);
}

static const char *mvt_ptr_load_u(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  return mvt_want(mvt_t(c, 0) == MIR_PTR && mvt_access_width(&c->in->imm) && mvt_res_is(c, MIR_INT),
          "ptr.loadu reads 1, 2, 4 or 8 unaligned bytes at a ptr into an int");
}

static const char *mvt_ptr_store_u(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 2));
  return mvt_want(mvt_t(c, 0) == MIR_PTR && mvt_t(c, 1) == MIR_INT &&
            mvt_access_width(&c->in->imm) && !c->has_res,
          "ptr.storeu writes the low 1, 2, 4 or 8 bytes of an int unaligned at a ptr");
}

static const char *mvt_ptr_null(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 0));
  return mvt_want(mvt_res_is(c, MIR_PTR), "ptr.null yields a ptr");
}

static const char *mvt_ptr_add(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 2));
  return mvt_want(mvt_t(c, 0) == MIR_PTR && mvt_t(c, 1) == MIR_INT && mvt_res_is(c, MIR_PTR),
          "ptr.add takes a ptr and a byte offset and yields a ptr");
}

static const char *mvt_ptr_is_null(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  return mvt_want(mvt_t(c, 0) == MIR_PTR && mvt_res_is(c, MIR_BOOL),
          "ptr.is_null tests a ptr and yields bool");
}

static const char *mvt_ptr_field(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  const MirImm *im = &c->in->imm;
  if (im->tag != MI_FIELD) {
    return "missing field";
  }
  if (im->a >= c->m->type_defs.len) {
    return "bad type";
  }
  if (im->b >= c->m->type_defs.ptr[im->a].nfields) {
    return "bad field index";
  }
  return mvt_want(mvt_t(c, 0) == MIR_PTR && mvt_res_is(c, MIR_PTR),
          "ptr.field takes a ptr and yields a ptr");
}

static const char *mvt_load(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  if (c->in->imm.tag != MI_TY) {
    return "missing type";
  }
  return mvt_want(mvt_t(c, 0) == MIR_PTR && mvt_res_is(c, c->in->imm.a),
          "load reads a value through a ptr; a droppable result is a borrow");
}

static const char *mvt_take(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  if (c->in->imm.tag != MI_TY) {
    return "missing type";
  }
  return mvt_want(mvt_t(c, 0) == MIR_PTR && mvt_res_is(c, c->in->imm.a),
          "take moves a value out of memory through a ptr; the result is owned");
}

static const char *mvt_put(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 2));
  return mvt_want(mvt_t(c, 0) == MIR_PTR, "put moves an owned value into memory through a ptr");
}

static const char *mvt_store(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 2));
  return mvt_want(mvt_t(c, 0) == MIR_PTR,
          "store writes a value through a ptr; the memory does not own a droppable value, it holds a borrow");
}

static const char *mvt_func_addr(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 0));
  if (c->in->imm.tag != MI_FUNC) {
    return "missing function";
  }
  return mvt_want(c->in->imm.a < c->m->funcs.len && mvt_res_is(c, MIR_PTR),
          "func.addr yields the ptr of a function");
}

static const char *mvt_type_desc(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 0));
  return mvt_want(c->in->imm.tag == MI_TY && mvt_res_is(c, MIR_PTR), "typedesc yields ptr");
}

/* ---- runtime services ---- */

static const char *mvt_no_operands(const MvtCx *c) { return mvt_arity(c, 0); }

static const char *mvt_stack_low(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 0));
  return mvt_want(mvt_res_is(c, MIR_BOOL),
          "stack.low yields whether the stack pointer is below the stack segment's limit");
}

static const char *mvt_stack_near(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 0));
  return mvt_want(c->in->imm.tag == MI_INT && c->in->imm.i >= 0 && mvt_res_is(c, MIR_BOOL),
          "stack.near N yields whether the stack pointer is within N bytes of the stack segment's limit");
}

static const char *mvt_cleanup_run(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  return mvt_want(mvt_t(c, 0) == MIR_INT, "cleanup.run takes the handle returned by cleanup.push");
}

static const char *mvt_cleanup_push(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  if (c->in->imm.tag != MI_FUNC) {
    return "missing closer";
  }
  if (c->in->imm.a >= c->m->funcs.len) {
    return "bad closer";
  }
  const MirFunc *callee = &c->m->funcs.ptr[c->in->imm.a];
  return mvt_want(callee->nparams == 1 && callee->params[0].ty == mvt_t(c, 0) &&
            mvt_res_is(c, MIR_INT),
          "closer takes the registered value; cleanup.push yields an int handle");
}

static const char *mvt_global_get(const MvtCx *c) {
  if (c->in->imm.tag != MI_GLOBAL) {
    return "missing global";
  }
  if (c->in->imm.a >= c->m->globals.len) {
    return "bad global";
  }
  MVT_TRY(mvt_arity(c, 0));
  return mvt_want(mvt_res_is(c, c->m->globals.ptr[c->in->imm.a].ty),
          "global.get yields the global's type");
}

static const char *mvt_global_set(const MvtCx *c) {
  if (c->in->imm.tag != MI_GLOBAL) {
    return "missing global";
  }
  if (c->in->imm.a >= c->m->globals.len) {
    return "bad global";
  }
  MVT_TRY(mvt_arity(c, 1));
  return mvt_want(mvt_t(c, 0) == c->m->globals.ptr[c->in->imm.a].ty,
          "stored value must have the global's type");
}

/* ---- scope markers: `begin S P`, `own v S K`, `end S` ---- */

static const char *mvt_scope_marker(const MvtCx *c) {
  if (c->in->imm.tag != MI_SCOPE) {
    return "a scope marker takes scope numbers";
  }
  MVT_TRY(mvt_want(!c->has_res, "a scope marker has no result"));
  if (c->in->op != MOP_ScopeOwn) {
    return mvt_arity(c, 0);
  }
  MVT_TRY(mvt_arity(c, 1));
  if (c->in->imm.b >= 2 && mvt_t(c, 0) == MIR_PTR) { // a close function (its index plus two) runs on a slot address
    return NULL;
  }
  return mvt_want(mvt_needs_drop(c, mvt_t(c, 0)), "scope.own takes a value that needs a drop");
}

static const char *mvt_scope_disown(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  return mvt_want(!c->has_res, "scope.disown has no result");
}

static const char *mvt_scope_mark(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  return mvt_want(!c->has_res, "scope.mark has no result");
}

const MvtRule mvt_rules_ops[MOP_COUNT] = {
  [MOP_Call] = mvt_call, [MOP_CallInd] = mvt_call_ind, [MOP_CallRt] = mvt_call_rt,
  [MOP_CallMethod] = mvt_call_method, [MOP_Clone] = mvt_clone, [MOP_AltOwn] = mvt_alt_own,
  [MOP_MoveOut] = mvt_move_out, [MOP_Drop] = mvt_drop, [MOP_Forget] = mvt_one_operand,
  [MOP_DropIf] = mvt_drop_if, [MOP_Free] = mvt_one_operand, [MOP_Slot] = mvt_slot,
  [MOP_ListAddr] = mvt_list_addr, [MOP_ListAddrU] = mvt_list_addr, [MOP_PtrIsNull] = mvt_ptr_is_null,
  [MOP_PtrAdd] = mvt_ptr_add, [MOP_PtrNull] = mvt_ptr_null, [MOP_PtrLoadU] = mvt_ptr_load_u,
  [MOP_PtrStoreU] = mvt_ptr_store_u, [MOP_PtrField] = mvt_ptr_field, [MOP_Load] = mvt_load,
  [MOP_Take] = mvt_take, [MOP_Put] = mvt_put, [MOP_Store] = mvt_store, [MOP_FuncAddr] = mvt_func_addr,
  [MOP_TypeDesc] = mvt_type_desc, [MOP_Shape] = mvt_type_desc, [MOP_Poll] = mvt_no_operands, [MOP_DepthEnter] = mvt_no_operands,
  [MOP_DepthLeave] = mvt_no_operands, [MOP_StackLow] = mvt_stack_low, [MOP_StackNear] = mvt_stack_near,
  [MOP_CleanupRun] = mvt_cleanup_run, [MOP_CleanupPush] = mvt_cleanup_push,
  [MOP_GlobalGet] = mvt_global_get, [MOP_GlobalSet] = mvt_global_set, [MOP_ScopeBegin] = mvt_scope_marker,
  [MOP_ScopeOwn] = mvt_scope_marker, [MOP_ScopeEnd] = mvt_scope_marker,
  [MOP_ScopeDisown] = mvt_scope_disown, [MOP_ScopeMark] = mvt_scope_mark,
};
