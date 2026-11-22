/* compiler/lower/lower_for.c: `for x in <list or range>`.
 *
 * A counted loop: block parameters (through MirVars) carry the index; the head compares it with the length, the
 * body binds the element, `step` adds one. A list the loop owns whose elements need a drop lives in a cursor
 * in memory (the list and the index of the first element not yet taken); the loop owner `close` thunk releases
 * what the loop never reached, wherever the loop ends. The checker records the loop variable's local on the
 * statement node. */
#include "compiler/lower/lower_fn.h"
#include "compiler/mir/mir_analysis.h"

/* What the loop iterates and how it reaches each element. */
typedef struct ForSource {
  MirValue start, len;
  MirTy elem;
  MirValue list; /* a borrowed walk: the list */
  MirValue slot; /* a cursor walk: the slot holding the cursor */
  uint32_t cursor_type;
  MirTy list_ty;
  MirValue text;  /* a `chars` walk: the string, whose scalars are read in place */
  MirVar width;   /* a `chars` walk: the byte length of the scalar the round reads */
  bool cursor, range, chars;
} ForSource;

static MirImm imm_field(uint32_t type, uint32_t field) {
  return (MirImm){.tag = MI_FIELD, .a = type, .b = field};
}

static MirImm imm_ty(MirTy ty) {
  return (MirImm){.tag = MI_TY, .a = ty};
}

static MirValue emit(LowerFn *fn, MirOp op, const MirValue *args, uint32_t nargs, MirImm imm, MirTy ty) {
  return mir_b_emit(&fn->b, op, args, nargs, imm, ty);
}

/* ---- the cursor type and its close thunk ---- */

/* The name `base` or, for the n-th cursor of another list type, `base.n`. */
static MsName numbered(Lower *cx, const char *base, uint32_t n) {
  if (n == 0) {
    return mir_name(cx->module, ms_span_of_text(base));
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_printf(&text, "%s.%u", base, n);
  const MsName name = mir_name(cx->module, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  return name;
}

static uint32_t add_cursor_type(Lower *cx, MsName name, MirTy list_ty) {
  MirModule *module = cx->module;
  const uint32_t id = mir_add_type(module, name);
  MirField *fields = MS_ARENA_NEW_ARRAY(&module->arena, MirField, 2);
  fields[0] = (MirField){mir_name(module, ms_span_of_text("list")), list_ty, 0};
  fields[1] = (MirField){mir_name(module, ms_span_of_text("next")), MIR_INT, 0};
  module->type_defs.ptr[id].fields = fields;
  module->type_defs.ptr[id].nfields = 2;
  return id;
}

/* `fn close(cursor: ptr)`: releases the list from the first element the loop never took. */
static uint32_t add_cursor_close(Lower *cx, MsName name, uint32_t type, MirTy list_ty) {
  MirBuilder b;
  const MirParam param = {MIR_PTR, (uint8_t)MM_BORROW};
  mir_b_init(&b, cx->module, name, &param, 1, MIR_VOID);
  b.func.linkage = ML_INTERNAL;
  MirValue cursor = MIR_NONE;
  mir_b_params(&b, &cursor, 1);
  const MirValue list_at = mir_b_emit(&b, MOP_PtrField, &cursor, 1, imm_field(type, 0), MIR_PTR);
  const MirValue next_at = mir_b_emit(&b, MOP_PtrField, &cursor, 1, imm_field(type, 1), MIR_PTR);
  const MirValue next = mir_b_emit(&b, MOP_Load, &next_at, 1, imm_ty(MIR_INT), MIR_INT);
  const MirValue list = mir_b_emit(&b, MOP_Take, &list_at, 1, imm_ty(list_ty), list_ty);
  const MirValue release[2] = {list, next};
  (void)mir_b_emit(&b, MOP_ListRelease, release, 2, (MirImm){0}, MIR_NONE);
  mir_b_ret(&b, mir_b_unit(&b));
  uint32_t id = MIR_NONE;
  return mir_b_finish(&b, &id) ? id : MIR_NONE;
}

/* The cursor type for `list_ty` and the function closing it, made on first use. */
static bool cursor_for(LowerFn *fn, MirTy list_ty, uint32_t *type, uint32_t *close) {
  Lower *cx = fn->cx;
  for (uint32_t n = 0;; n++) {
    const MsName name = numbered(cx, "ListCursor", n);
    const uint32_t found = mir_type_by_name(cx->module, name);
    if (found == MIR_NONE) {
      *type = add_cursor_type(cx, name, list_ty);
      *close = add_cursor_close(cx, numbered(cx, "cursor.close", n), *type, list_ty);
      return *close != MIR_NONE || fn_fail(fn, "the loop cursor close function was not built");
    }
    if (cx->module->type_defs.ptr[found].fields[0].ty == list_ty) {
      *type = found;
      *close = mir_func_by_name(cx->module, numbered(cx, "cursor.close", n));
      return *close != MIR_NONE;
    }
  }
}

/* ---- the iterated value ---- */

/* `from..to` (the call `..`) written as the iterable. */
static bool is_range(const LowerFn *fn, const MsExpr *iter) {
  if (iter->kind != MS_E_CALL || iter->u.call.args.len != 2 || iter->u.call.callee->kind != MS_E_NAME) {
    return false;
  }
  const MsSpan name = ms_names_span(fn->cx->program->names, iter->u.call.callee->u.sym);
  return ms_span_is_text(name, "..");
}

/* `text.chars()` on a String written as the iterable: the loop reads each scalar from the string, with no list of
 * them. */
static const MsExpr *chars_receiver(const LowerFn *fn, const MsExpr *iter) {
  if (iter->kind != MS_E_CALL || iter->u.call.args.len != 0 || iter->u.call.callee->kind != MS_E_MEMBER ||
      !ms_span_is_text(ms_names_span(fn->cx->program->names, iter->u.call.callee->u.member.name), "chars")) {
    return NULL;
  }
  const MsExpr *receiver = iter->u.call.callee->u.member.left;
  const MsTy type = ms_ty_subst(&fn->cx->program->types, ms_facts_type(fn->facts, receiver->id), fn->subst.vars,
                                fn->subst.args, fn->subst.count);
  return ms_ty_is(&fn->cx->program->types, type, MS_BUILTIN_String) ? receiver : NULL;
}

static bool source_chars(LowerFn *fn, const MsExpr *receiver, ForSource *src) {
  const MirValue text = fn_expr(fn, receiver, LW_BORROW);
  if (text == MIR_NONE) {
    return false;
  }
  *src = (ForSource){.elem = MIR_STR, .text = text, .chars = true};
  src->start = mir_b_iconst(&fn->b, 0);
  src->len = emit(fn, MOP_StrBytes, &text, 1, (MirImm){0}, MIR_INT);
  src->width = mir_b_declare_var(&fn->b, MIR_INT, MM_BORROW);
  mir_b_def_var(&fn->b, src->width, mir_b_iconst(&fn->b, 1));
  return true;
}

/* The scalar at byte offset `index` of the string, an inline string whose length is the bytes the round used. */
static MirValue scalar_at(LowerFn *fn, const ForSource *src, MirValue index) {
  MirParam *wanted = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, MirParam, 3);
  wanted[0] = (MirParam){MIR_STR, (uint8_t)MM_BORROW};
  wanted[1] = (MirParam){MIR_INT, (uint8_t)MM_BORROW};
  const MirExtern def = {.name = mir_name(fn->cx->module, ms_span_of_text("msrt_string_scalar_text")),
                         .params = wanted, .nparams = 2, .ret = MIR_STR, .leaf = true};
  const uint32_t ext = mir_extern_intern(fn->cx->module, &def);
  const MirValue args[2] = {src->text, index};
  const MirValue scalar = mir_b_call_rt(&fn->b, ext, args, 2);
  mir_b_def_var(&fn->b, src->width, emit(fn, MOP_StrBytes, &scalar, 1, (MirImm){0}, MIR_INT));
  return scalar;
}

static bool source_range(LowerFn *fn, const MsExpr *iter, ForSource *src) {
  const MirValue from = fn_expr(fn, iter->u.call.args.ptr[0].value, LW_BORROW);
  const MirValue to = fn_expr(fn, iter->u.call.args.ptr[1].value, LW_BORROW);
  if (from == MIR_NONE || to == MIR_NONE) {
    return false;
  }
  *src = (ForSource){.start = from, .len = to, .elem = MIR_INT, .range = true};
  return true;
}

/* A map or set walks the list of its entries or values, a copy the loop owns: the `entries` of a map, the `values`
 * of a set. MIR_NONE when `value` is neither. */
static MirValue collection_items(LowerFn *fn, const MsExpr *iter, MirValue value) {
  MsTyTable *types = &fn->cx->program->types;
  const MsTy type = ms_ty_subst(types, ms_facts_type(fn->facts, iter->id), fn->subst.vars, fn->subst.args, fn->subst.count);
  const bool map = ms_ty_is(types, type, MS_BUILTIN_Map);
  if (!map && !ms_ty_is(types, type, MS_BUILTIN_Set)) {
    return MIR_NONE;
  }
  const uint32_t method = lower_named_method(fn->cx, type, map ? "entries" : "values");
  if (method != MIR_NONE) {
    const MirValue items = mir_b_call(&fn->b, method, &value, 1);
    fn_own_result(fn, items);
    return items;
  }
  /* a bodiless `values` is the runtime's own */
  const MirTyData *set = mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, value));
  MirValue items = MIR_NONE;
  const MirTy list_ty = set->nargs == 1 ? mir_ty_list(fn->cx->module, set->args[0]) : MIR_NONE;
  const MsSpan operation = ms_span_of_text("values");
  if (list_ty == MIR_NONE || !fn_native_on(fn, iter, type, operation, 1, &value, list_ty, &items)) {
    return MIR_NONE;
  }
  return items;
}

static bool source_list(LowerFn *fn, const MsExpr *iter, ForSource *src) {
  bool moved = ms_facts_use(fn->facts, iter->id) == MS_USE_MOVE;
  MirValue list = fn_expr(fn, iter, moved ? LW_MOVE : LW_BORROW);
  if (list == MIR_NONE) {
    return false;
  }
  const MirValue items = collection_items(fn, iter, list);
  if (items != MIR_NONE) {
    list = items;
    moved = false;
  }
  const MirModule *module = fn->cx->module;
  const MirTy list_ty = mir_b_ty(&fn->b, list);
  if (mir_ty_data(module, list_ty)->kind != MK_LIST) {
    return fn_fail(fn, "`for` iterates a list or a range for now");
  }
  const MirTy elem = mir_ty_data(module, list_ty)->elem;
  /* A name or field reads a value its binding owns, though the instruction that made it may still be in reach. */
  const bool place = iter->kind == MS_E_NAME || iter->kind == MS_E_MEMBER;
  const bool fresh = !place && fn_fresh_owner(fn, list);
  *src = (ForSource){.elem = elem, .list_ty = list_ty, .list = list};
  if ((moved || fresh) && mir_needs_drop(module, elem)) {
    if (fresh) {
      const MirImm none = {0};
      (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &list, 1, none, MIR_NONE);
    }
    uint32_t close = 0;
    if (!cursor_for(fn, list_ty, &src->cursor_type, &close)) {
      return false;
    }
    const MirTy cursor_ty = mir_ty_type(fn->cx->module, src->cursor_type);
    src->slot = emit(fn, MOP_Slot, NULL, 0, imm_ty(cursor_ty), MIR_PTR);
    const MirValue zero = mir_b_iconst(&fn->b, 0);
    const MirValue parts[2] = {list, zero};
    const MirImm type_imm = {.tag = MI_TYPE, .a = src->cursor_type};
    const MirValue held = emit(fn, MOP_TypeNew, parts, 2, type_imm, cursor_ty);
    const MirValue put[2] = {src->slot, held};
    (void)emit(fn, MOP_Put, put, 2, (MirImm){0}, MIR_NONE);
    const MirImm own = {.tag = MI_SCOPE, .a = fn_scope(fn), .b = close + 2};
    (void)emit(fn, MOP_ScopeOwn, &src->slot, 1, own, MIR_NONE);
    src->cursor = true;
  } else if (moved && !fresh) {
    fn_own(fn, fn_scope(fn), list);
  }
  return true;
}

/* ---- the loop ---- */

/* The list a cursor walk reads, as a borrow. */
static MirValue cursor_list(LowerFn *fn, const ForSource *src) {
  const MirValue at = emit(fn, MOP_PtrField, &src->slot, 1, imm_field(src->cursor_type, 0), MIR_PTR);
  return emit(fn, MOP_Load, &at, 1, imm_ty(src->list_ty), src->list_ty);
}

/* The element at `index`: the index itself for a range, a taken one when the loop owns the list. */
static MirValue element(LowerFn *fn, const ForSource *src, MirValue index, MirValue one) {
  if (src->range) {
    return index;
  }
  if (src->chars) {
    return scalar_at(fn, src, index);
  }
  if (!src->cursor) {
    const MirValue args[2] = {src->list, index};
    return emit(fn, MOP_ListGet, args, 2, (MirImm){0}, src->elem);
  }
  /* The cursor moves past the element before it is taken, so that leaving the loop anywhere after releases
   * only what comes after. */
  const MirValue sum[2] = {index, one};
  const MirValue next = emit(fn, MOP_IAdd, sum, 2, (MirImm){0}, MIR_INT);
  const MirValue at = emit(fn, MOP_PtrField, &src->slot, 1, imm_field(src->cursor_type, 1), MIR_PTR);
  const MirValue store[2] = {at, next};
  (void)emit(fn, MOP_Store, store, 2, (MirImm){0}, MIR_NONE);
  const MirValue args[2] = {cursor_list(fn, src), index};
  return fn_emit(fn, MOP_ListTake, args, 2, (MirImm){0}, src->elem);
}

static void enter(LowerFn *fn, MirBlock block) {
  mir_b_switch_to(&fn->b, block);
  fn->terminated = false;
}

static bool for_body(LowerFn *fn, const MsStmt *stmt, const ForSource *src, MirVar index, MirValue one,
                     MirBlock step, MirBlock exit, uint32_t local) {
  fn->loops[fn->nloops++] = (LowerLoop){exit, step, fn->nopen};
  (void)fn_scope_begin(fn);
  const MirValue item = element(fn, src, mir_b_use_var(&fn->b, index), one);
  bool ok = item != MIR_NONE;
  if (ok) {
    mir_b_def_var(&fn->b, fn_local(fn, local, src->elem), item);
    ok = fn_stmts(fn, stmt->u.each.body);
  }
  if (!fn->terminated) {
    fn_scope_end(fn);
  } else {
    fn->nopen--;
  }
  fn->nloops--;
  if (!fn->terminated) {
    mir_b_br(&fn->b, step, NULL, 0);
  }
  return ok;
}


/* ---- any iterator ---- */

/* `fn close(slot: ptr)`: drops the value a slot holds, for the loop that owns an iterator. */
static uint32_t drop_close_for(Lower *cx, MirTy ty) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_printf(&text, "drop.%u", (unsigned)ty);
  const MsName name = mir_name(cx->module, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  const uint32_t found = mir_func_by_name(cx->module, name);
  if (found != MIR_NONE) {
    return found;
  }
  MirBuilder b;
  const MirParam param = {MIR_PTR, (uint8_t)MM_BORROW};
  mir_b_init(&b, cx->module, name, &param, 1, MIR_VOID);
  b.func.linkage = ML_INTERNAL;
  MirValue slot = MIR_NONE;
  mir_b_params(&b, &slot, 1);
  const MirValue value = mir_b_emit(&b, MOP_Take, &slot, 1, imm_ty(ty), ty);
  (void)mir_b_emit(&b, MOP_Drop, &value, 1, (MirImm){0}, MIR_NONE);
  mir_b_ret(&b, mir_b_unit(&b));
  uint32_t id = MIR_NONE;
  return mir_b_finish(&b, &id) ? id : MIR_NONE;
}

/* `for item in source:` for a source that is not a list: the iterator lives in a slot the loop owns, and each
 * round calls the type's `next` on the slot; a `none` ends the loop. The item borrows from the result of `next`,
 * which the round owns. */
static bool for_iterator(LowerFn *fn, const MsStmt *stmt, const MsRef *binding) {
  const MsExpr *iter = stmt->u.each.iter;
  const MsTy type = ms_ty_subst(&fn->cx->program->types, ms_facts_type(fn->facts, iter->id), fn->subst.vars,
                                fn->subst.args, fn->subst.count);
  const uint32_t next = lower_named_method(fn->cx, type, "next");
  if (next == MIR_NONE) {
    return fn_fail(fn, "`for` needs a list, a range, or a value whose `next` has a body");
  }
  /* An iterator held in a variable is advanced in place: its value sits in a slot for the loop, and goes back
   * to the variable when the loop ends. */
  const bool on_variable = fn_place_changeable(fn, iter);
  VarSlot held = {0};
  MirValue slot = MIR_NONE;
  if (on_variable) {
    slot = fn_var_slot(fn, iter, &held);
    if (slot == MIR_NONE) {
      return false;
    }
  } else {
    MirValue value = fn_expr(fn, iter, LW_MOVE);
    if (value == MIR_NONE) {
      return false;
    }
    const MirTy iter_ty = mir_b_ty(&fn->b, value);
    const bool owns = mir_needs_drop(fn->cx->module, iter_ty);
    if (owns) {
      if (fn_fresh_owner(fn, value)) {
        (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &value, 1, (MirImm){0}, MIR_NONE);
      } else {
        value = fn_implicit_clone(fn, value, false);
      }
    }
    slot = emit(fn, MOP_Slot, NULL, 0, imm_ty(iter_ty), MIR_PTR);
    const MirValue stored[2] = {slot, value};
    (void)emit(fn, owns ? MOP_Put : MOP_Store, stored, 2, (MirImm){0}, MIR_NONE);
    if (owns) {
      const uint32_t close = drop_close_for(fn->cx, iter_ty);
      if (close == MIR_NONE) {
        return fn_fail(fn, "the iterator close function was not built");
      }
      const MirImm own = {.tag = MI_SCOPE, .a = fn_scope(fn), .b = close + 2};
      (void)emit(fn, MOP_ScopeOwn, &slot, 1, own, MIR_NONE);
    }
  }
  const MirBlock head = mir_b_new_block(&fn->b);
  const MirBlock body = mir_b_new_block(&fn->b);
  const MirBlock done = mir_b_new_block(&fn->b);
  const MirBlock exit = mir_b_new_block(&fn->b);
  mir_b_br(&fn->b, head, NULL, 0);
  enter(fn, head);
  mir_b_set_loc(&fn->b, fn_loc(fn, stmt->pos));
  /* The iterator is the receiver; each other parameter of `next` is an optional the loop leaves out. */
  const MirFunc *next_fn = &fn->cx->module->funcs.ptr[next];
  MirValue next_args[LOWER_MAX_ARGS] = {slot};
  if (next_fn->nparams > LOWER_MAX_ARGS) {
    return fn_fail(fn, "`next` takes too many parameters");
  }
  for (uint32_t at = 1; at < next_fn->nparams; at++) {
    const MirTy param_ty = next_fn->params[at].ty;
    if (param_ty != MIR_VOID && mir_ty_data(fn->cx->module, param_ty)->kind != MK_OPT) {
      return fn_fail(fn, "`next` of a `for` source takes only optional parameters");
    }
    next_args[at] = param_ty == MIR_VOID ? mir_b_unit(&fn->b) : fn_emit(fn, MOP_OptNone, NULL, 0, (MirImm){0}, param_ty);
  }
  const MirValue result = mir_b_call(&fn->b, next, next_args, next_fn->nparams);
  const MirInstList *insts = &fn->b.func.blocks.ptr[fn->b.cur].insts;
  MirMode mode = MM_BORROW;
  const bool result_owned = result != MIR_NONE && mir_result_mode(fn->cx->module, &fn->b.func, &insts->ptr[insts->len - 1], &mode) &&
                            mode == MM_MOVE;
  const MirValue more = fn_iflet_test(fn, result);
  if (more == MIR_NONE) {
    return false;
  }
  /* A source that can fail answers `T?!`: an error ends the loop, as does `none` inside an ok. */
  const MirTyData *answer = mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, result));
  MirValue payload = result;
  if (answer->kind == MK_ALT) {
    const MirCaseDef *ok_case = &fn->cx->module->alts.ptr[answer->id].cases[0];
    const MirTy payload_ty = ok_case->nfields > 0 ? ok_case->fields[0].ty : MIR_VOID;
    const MirBlock inner = mir_b_new_block(&fn->b);
    mir_b_br_if(&fn->b, more, inner, NULL, 0, done, NULL, 0);
    mir_b_seal_block(&fn->b, inner);
    enter(fn, inner);
    const MirImm field = {.tag = MI_ALTFIELD, .a = answer->id, .b = 0, .c = 0};
    payload = mir_b_emit(&fn->b, MOP_AltGet, &result, 1, field, payload_ty);
    mir_b_br_if(&fn->b, mir_b_emit(&fn->b, MOP_OptIsSome, &payload, 1, (MirImm){0}, MIR_BOOL), body, NULL, 0, done, NULL, 0);
  } else {
    mir_b_br_if(&fn->b, more, body, NULL, 0, done, NULL, 0);
  }
  mir_b_seal_block(&fn->b, body);
  mir_b_seal_block(&fn->b, done);
  enter(fn, done);
  if (result_owned) {
    (void)emit(fn, MOP_Drop, &result, 1, (MirImm){0}, MIR_NONE);
  }
  mir_b_br(&fn->b, exit, NULL, 0);
  enter(fn, body);
  fn->loops[fn->nloops++] = (LowerLoop){exit, head, fn->nopen};
  (void)fn_scope_begin(fn);
  if (result_owned) {
    fn_own(fn, fn_scope(fn), result);
  }
  const MirTyData *opt = mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, payload));
  const MirValue item = emit(fn, MOP_OptGet, &payload, 1, (MirImm){0}, opt->elem);
  mir_b_def_var(&fn->b, fn_local(fn, binding->local, opt->elem), item);
  bool ok = fn_stmts(fn, stmt->u.each.body);
  if (!fn->terminated) {
    fn_scope_end(fn);
  } else {
    fn->nopen--;
  }
  fn->nloops--;
  if (!fn->terminated) {
    mir_b_br(&fn->b, head, NULL, 0);
  }
  mir_b_seal_block(&fn->b, head);
  mir_b_seal_block(&fn->b, exit);
  enter(fn, exit);
  if (on_variable && !fn_var_slots_back(fn, &held, 1)) {
    return false;
  }
  fn_scope_end(fn);
  return ok && !fn->failed;
}

bool fn_for(LowerFn *fn, const MsStmt *stmt) {
  const MsRef *binding = ms_facts_ref(fn->facts, stmt->id);
  if (binding == NULL || binding->kind != MS_REF_LOCAL) {
    return fn_fail(fn, "a `for` loop has no loop variable");
  }
  if (fn->nloops == LOWER_MAX_LOOPS) {
    return fn_fail(fn, "loops nest too deeply");
  }
  const MsExpr *iter = stmt->u.each.iter;
  (void)fn_scope_begin(fn);
  const MsExpr *chars = chars_receiver(fn, iter);
  const MirTy iter_ty = is_range(fn, iter) || chars != NULL ? MIR_INT : fn_type(fn, ms_facts_type(fn->facts, iter->id));
  const MirTyData *iter_data = mir_ty_data(fn->cx->module, iter_ty);
  const bool collection = iter_data->kind == MK_OBJ && iter_data->obj_class == MIR_OBJ_COLLECTION;
  if (iter_ty != MIR_INT && iter_data->kind != MK_LIST && !collection) {
    return for_iterator(fn, stmt, binding);
  }
  ForSource src;
  const bool sourced = chars != NULL ? source_chars(fn, chars, &src)
                       : is_range(fn, iter) ? source_range(fn, iter, &src) : source_list(fn, iter, &src);
  if (!sourced) {
    return false;
  }
  if (!src.range && !src.chars) {
    src.start = mir_b_iconst(&fn->b, 0);
    const MirValue list = src.cursor ? cursor_list(fn, &src) : src.list;
    src.len = emit(fn, MOP_ListLen, &list, 1, (MirImm){0}, MIR_INT);
  }
  const MirValue one = mir_b_iconst(&fn->b, 1);
  const MirVar index = mir_b_declare_var(&fn->b, MIR_INT, MM_BORROW);
  mir_b_def_var(&fn->b, index, src.start);
  const MirBlock head = mir_b_new_block(&fn->b);
  const MirBlock body = mir_b_new_block(&fn->b);
  const MirBlock step = mir_b_new_block(&fn->b);
  const MirBlock exit = mir_b_new_block(&fn->b);
  mir_b_br(&fn->b, head, NULL, 0);
  enter(fn, head);
  const MirValue more = mir_b_icmp(&fn->b, MCC_LT, mir_b_use_var(&fn->b, index), src.len);
  mir_b_br_if(&fn->b, more, body, NULL, 0, exit, NULL, 0);
  mir_b_seal_block(&fn->b, body);
  enter(fn, body);
  const bool ok = for_body(fn, stmt, &src, index, one, step, exit, binding->local);
  mir_b_seal_block(&fn->b, step);
  if (fn->b.links.ptr[step].preds.len > 0) {
    enter(fn, step);
    mir_b_set_loc(&fn->b, fn_loc(fn, stmt->pos));
    const MirValue by = src.chars ? mir_b_use_var(&fn->b, src.width) : one;
    mir_b_def_var(&fn->b, index, mir_b_binop(&fn->b, MOP_IAdd, mir_b_use_var(&fn->b, index), by));
    mir_b_br(&fn->b, head, NULL, 0);
  }
  mir_b_seal_block(&fn->b, head);
  mir_b_seal_block(&fn->b, exit);
  enter(fn, exit);
  fn_scope_end(fn);
  return ok && !fn->failed;
}
