/* compiler/own/borrows.c: a source changed while a binding borrowing it is still used (see borrows.h). */
#include "compiler/own/look_fields.h"
#include "compiler/own/result_borrows.h"
#include "compiler/own/borrows.h"

#include "compiler/check/methods.h"
#include "compiler/check/properties.h"
#include "compiler/own/bind.h"
#include "compiler/own/class.h"
#include "compiler/own/expr_text.h"
#include "compiler/own/taken.h"
#include "compiler/own/uses.h"
#include "compiler/syntax/walk.h"

#include "compiler/own/borrows_internal.h"


/* The function-wide id of the local or parameter `node` names: the checker numbers locals densely and gives
 * parameters their own index space. */
static bool local_of(const MsFacts *facts, MsNode node, uint32_t *id) {
  const MsRef *ref = ms_facts_ref(facts, node);
  if (ref == NULL || (ref->kind != MS_REF_LOCAL && ref->kind != MS_REF_PARAM)) {
    return false;
  }
  *id = ref->kind == MS_REF_PARAM ? ref->local | 0x80000000u : ref->local;
  return true;
}

static bool is_value_ref(MsRefKind kind) {
  return kind == MS_REF_FUNCTION || kind == MS_REF_METHOD || kind == MS_REF_NATIVE || kind == MS_REF_OPERATION || kind == MS_REF_TYPE;
}

static bool origin_of_call(Borrows *pass, const MsExpr *call, Source *out);

/* The local an argument expression borrows from: a local, a field of one, or a borrowing call on one. */
static bool origin_of_arg(Borrows *pass, const MsExpr *arg, Source *out) {
  const MsExpr *at = arg;
  for (;;) {
    MsExpr *left = NULL;
    MsExpr *index = NULL;
    if (at->kind == MS_E_MEMBER) {
      at = at->u.member.left;
    } else if (ms_expr_index(at, &left, &index)) {
      at = left; /* an element read in place borrows the collection it sits in */
    } else {
      break;
    }
  }
  if (at->kind == MS_E_NAME && ms_class_owns_memory(pass->facts, pass->classes, arg)) {
    out->place = arg;
    out->call = NULL;
    return local_of(pass->facts, at->id, &out->root);
  }
  if (arg->kind == MS_E_UNARY && arg->op == MS_U_TRY) {
    return origin_of_arg(pass, arg->u.bin.left, out);
  }
  if (arg->kind == MS_E_BINARY && arg->op == MS_B_OR &&
      ms_ty_is(&pass->program->types, ms_facts_type(pass->facts, arg->u.bin.left->id), MS_BUILTIN_Optional)) {
    /* `x or d` takes the payload out of a place; only a call's result (`m.get(k) or d`) is a view of something else */
    return arg->u.bin.left->kind == MS_E_CALL && origin_of_arg(pass, arg->u.bin.left, out);
  }
  return arg->kind == MS_E_CALL && origin_of_call(pass, arg, out);
}

/* Whether the callee's result borrows from its argument number `position`: the callable's own `borrows` fact (own/result_borrows.c);
 * one the runtime provides borrows from any argument. */
static bool borrows_from(Borrows *pass, const MsCall *fact, uint32_t position) {
  return ms_own_call_borrows(pass->program, fact, position);
}

/* Whether `call` takes the payload out of an optional or result held in a place: its result is the receiver's
 * first type argument. An owned `T?` owns its payload or nothing, so the payload leaves with the value. */
static bool takes_payload(Borrows *pass, const MsExpr *call) {
  const MsExpr *callee = call->u.call.callee;
  if (callee->kind != MS_E_MEMBER) {
    return false;
  }
  const MsExpr *receiver = callee->u.member.left;
  const MsTyTable *types = &pass->program->types;
  const MsTy held = ms_facts_type(pass->facts, receiver->id);
  if (held == MS_TY_NONE || ms_ty_arg_count(types, held) == 0 ||
      (!ms_ty_is(types, held, MS_BUILTIN_Optional) && !ms_ty_is(types, held, MS_BUILTIN_Result))) {
    return false;
  }
  return ms_facts_type(pass->facts, call->id) == ms_ty_args(types, held)[0];
}

/* Which type arguments of its receiver a method's result mentions: `Map[T, U].keys() &List[T]` covers only T. A view of
 * the storage of some arguments leaves the storage of the others unchanged; 0 when it mentions all or none. */
static void collect_names(const MsTypeRef *type, const MsTypeRefs *args, uint32_t *mask) {
  if (type == NULL) {
    return;
  }
  for (uint32_t index = 0; index < args->len && index < 32; index++) {
    if (type->kind == MS_TYPE_NAMED && args->ptr[index]->name == type->name && type->args.len == 0) {
      *mask |= UINT32_C(1) << index;
    }
  }
  for (uint32_t index = 0; index < type->args.len; index++) {
    collect_names(type->args.ptr[index], args, mask);
  }
  collect_names(type->result, args, mask);
}

static uint32_t result_parts(const Borrows *pass, const MsCall *fact) {
  if (fact->callee.kind != MS_REF_METHOD && fact->callee.kind != MS_REF_NATIVE) {
    return 0;
  }
  const MsMethodEntry *entry = ms_check_method_at(pass->program, fact->callee.decl.module, fact->callee.decl.node);
  if (entry == NULL || entry->source == NULL || entry->source->receiver_args.len < 2) {
    return 0;
  }
  uint32_t mask = 0;
  collect_names(entry->source->func.result, &entry->source->receiver_args, &mask);
  const uint32_t all = (UINT32_C(1) << entry->source->receiver_args.len) - 1;
  return mask == all ? 0 : mask;
}

/* A call whose result is not declared `move` borrows from its first argument that has an origin. */
static bool origin_of_call(Borrows *pass, const MsExpr *call, Source *out) {
  const MsCall *fact = ms_facts_call(pass->facts, call->id);
  if (fact == NULL || !is_value_ref(fact->callee.kind) || !ms_class_owns_memory(pass->facts, pass->classes, call)) {
    return false;
  }
  const MsExpr *callee = call->u.call.callee;
  const bool receiver = callee->kind == MS_E_MEMBER && fact->callee.kind != MS_REF_FUNCTION && fact->callee.kind != MS_REF_TYPE;
  if (receiver && takes_payload(pass, call) && callee->u.member.left->kind != MS_E_CALL) {
    return false;
  }
  /* every argument the result borrows from keeps its source frozen: the first fills `out`, the rest go to `extra` */
  bool found = false;
  const uint32_t first = receiver ? 0 : 1;
  for (uint32_t index = first; index <= call->u.call.args.len; index++) {
    const uint32_t position = receiver ? index : index - 1; /* the receiver is position 0 */
    const MsExpr *value = index == 0 ? callee->u.member.left : call->u.call.args.ptr[index - 1].value;
    Source origin = {0};
    if (!borrows_from(pass, fact, position) || !origin_of_arg(pass, value, &origin)) {
      continue;
    }
    if (origin.call == NULL) {
      origin.call = call;
      origin.parts = receiver && index == 0 ? result_parts(pass, fact) : 0;
    }
    if (found) {
      source_list_push(&pass->extra, origin);
    } else {
      *out = origin;
      found = true;
    }
  }
  return found;
}

/* Records a borrow, and with it the borrow of everything its source borrows: a view of a view keeps the owner frozen. */
static void push_borrow(Borrows *pass, Borrow borrow, bool through_look) {
  const size_t count = pass->borrows.len;
  bool derived_any = false;
  for (size_t index = 0; index < count; index++) {
    const Borrow parent = pass->borrows.ptr[index];
    if (parent.binding == borrow.root && parent.root != borrow.binding) {
      Borrow derived = borrow;
      derived.root = parent.root;
      derived.place = parent.place;
      derived.parts = parent.parts;
      derived.alias = false;
      borrow_list_push(&pass->borrows, derived);
      derived_any = true;
    }
  }
  if (!through_look || !derived_any) { /* an item of a look looks at the look's sources, so the look itself stays free */
    borrow_list_push(&pass->borrows, borrow);
  }
}

/* Whether the call answers a part of its look-record receiver without `hold`: the result keeps what the look keeps. */
static bool answers_look_part(const Borrows *pass, const MsExpr *call) {
  const MsCall *fact = call != NULL ? ms_facts_call(pass->facts, call->id) : NULL;
  if (fact == NULL || fact->callee.kind != MS_REF_METHOD || call->u.call.callee->kind != MS_E_MEMBER) {
    return false;
  }
  const MsMethodEntry *entry = ms_check_method_at(pass->program, fact->callee.decl.module, fact->callee.decl.node);
  return entry != NULL && !entry->source->holding && ms_own_look_record(pass->program, entry->receiver) &&
         ms_own_result_is_borrowed(pass->program, fact->callee.decl.module, fact->callee.decl.node);
}

/* A closure argument of `call` that the callee keeps running after the call returns (`promise(() => ...)`) and that stays
 * in the function: it reads what it captures for as long as the value the call returns lives. */
static void kept_closures(const Borrows *pass, const MsExpr *call, LambdaList *out) {
  const MsCall *fact = ms_facts_call(pass->facts, call->id);
  if (fact == NULL || (fact->callee.kind != MS_REF_FUNCTION && fact->callee.kind != MS_REF_METHOD)) {
    return;
  }
  const uint32_t taken = ms_own_taken_mask(pass->program, fact->callee.decl.module, fact->callee.decl.node);
  for (uint32_t index = 0; index < call->u.call.args.len; index++) {
    const MsExpr *value = call->u.call.args.ptr[index].value;
    if (value->kind != MS_E_LAMBDA || ms_facts_use(pass->facts, value->id) != MS_USE_BORROW) {
      continue;
    }
    for (uint32_t at = 0; at < fact->arg_count && at < 32; at++) {
      if (fact->args[at].source == MS_ARG_WRITTEN && fact->args[at].node.node == value->id &&
          (taken & (UINT32_C(1) << at)) != 0) {
        lambda_list_push(out, value);
      }
    }
  }
}

typedef struct Captured {
  Borrows *pass;
  MsBindingList captures;
  const MsStmt *stmt;
  uint32_t binding;
  MsPos at;
  uint32_t after;
  bool local; /* a closure that stays in the function borrows every capture; a kept one only what owns memory */
  MsBindingList done;
} Captured;

static void tie_capture(void *ctx, const MsExpr *expr) {
  Captured *scan = ctx;
  uint32_t decl = 0;
  uint32_t root = 0;
  if (expr->kind != MS_E_NAME || !ms_bind_of(scan->pass->facts, expr->id, &decl) ||
      !ms_binding_list_contains(&scan->captures, decl) || ms_binding_list_contains(&scan->done, decl) ||
      !local_of(scan->pass->facts, expr->id, &root) ||
      (!scan->local && (!ms_class_owns_memory(scan->pass->facts, scan->pass->classes, expr) ||
                        ms_check_holds_resource(scan->pass->program, ms_facts_type(scan->pass->facts, expr->id))))) {
    return; /* a resource the promise takes at its last use is its own: only a plain value stays borrowed */
  }
  ms_binding_list_push(&scan->done, decl);
  push_borrow(scan->pass, (Borrow){.binding = scan->binding, .name = scan->stmt->u.bind.pattern->u.name, .at = scan->at,
                                   .after = scan->after, .root = root, .place = expr, .captured = true}, false);
}

/* `p := promise(() => ...)`: the promise reads what its closure captures until it is last used. `f := fn() ...`: a
 * closure that stays in the function borrows what it captures until `f` is last used. */
static void note_kept_captures(Borrows *pass, const MsStmt *stmt) {
  const MsExpr *value = stmt->u.bind.value;
  const MsPattern *pattern = stmt->u.bind.pattern;
  uint32_t binding = 0;
  while (value != NULL && value->kind == MS_E_UNARY && value->op == MS_U_TRY) {
    value = value->u.bin.left;
  }
  if (value == NULL || (value->kind != MS_E_CALL && value->kind != MS_E_LAMBDA) || pattern == NULL || pattern->kind != MS_P_NAME ||
      !local_of(pass->facts, pattern->id, &binding)) {
    return;
  }
  LambdaList closures = {0};
  const bool local = value->kind == MS_E_LAMBDA && ms_facts_use(pass->facts, value->id) == MS_USE_BORROW;
  if (local) {
    local_list_push(&pass->closures, (Local){.binding = binding, .lambda = value});
    lambda_list_push(&closures, value);
  } else {
    kept_closures(pass, value, &closures);
  }
  for (size_t index = 0; index < closures.len; index++) {
    Captured scan = {.pass = pass, .captures = ms_bind_captures(pass->facts, closures.ptr[index]), .stmt = stmt,
                     .binding = binding, .at = pattern->pos, .after = stmt->u.bind.value->end.offset, .local = local};
    ms_walk_expr(&(MsVisitor){.ctx = &scan, .expr = tie_capture}, closures.ptr[index]);
    ms_binding_list_free(&scan.captures);
    ms_binding_list_free(&scan.done);
  }
  lambda_list_free(&closures);
}

static void note_keep(Borrows *pass, const MsExpr *kept);

/* Whether `value` is a call of a declared function or method that answers a view. */
static bool declared_view_call(const Borrows *pass, const MsExpr *value) {
  const MsCall *called = value != NULL && value->kind == MS_E_CALL ? ms_facts_call(pass->facts, value->id) : NULL;
  return called != NULL && (called->callee.kind == MS_REF_FUNCTION || called->callee.kind == MS_REF_METHOD) &&
         ms_own_result_is_borrowed(pass->program, called->callee.decl.module, called->callee.decl.node);
}

static bool holds_view(const Borrows *pass, uint32_t binding) {
  for (size_t index = 0; index < pass->view_vars.len; index++) {
    if (pass->view_vars.ptr[index].binding == binding) {
      return true;
    }
  }
  return false;
}

static void note_bind(Borrows *pass, const MsStmt *stmt) {
  const MsPattern *pattern = stmt->u.bind.pattern;
  const MsExpr *value = stmt->u.bind.value;
  Source source = {0};
  uint32_t binding = 0;
  source_list_clear(&pass->extra);
  const MsRef *member = pattern != NULL && pattern->kind == MS_P_NAME && value != NULL && value->kind == MS_E_MEMBER
                            ? ms_facts_ref(pass->facts, value->id)
                            : NULL;
  if (member != NULL && member->kind == MS_REF_METHOD && local_of(pass->facts, pattern->id, &binding) &&
      origin_of_arg(pass, value->u.member.left, &source)) {
    push_borrow(pass, (Borrow){.binding = binding, .name = pattern->u.name, .at = value->pos, .after = value->end.offset,
                                              .method_value = true, .root = source.root, .place = source.place}, false);
    return;
  }
  if (pattern == NULL || pattern->kind != MS_P_NAME || value == NULL || !origin_of_arg(pass, value, &source) ||
      !local_of(pass->facts, pattern->id, &binding)) {
    return;
  }
  if (stmt->u.bind.is_mutable && declared_view_call(pass, value)) {
    use_list_push(&pass->view_vars, (Use){.binding = binding}); /* the `var` holds the view; nothing is kept */
  }
  /* A resource field bound by name leaves its record (the next statement refills it): that is a take, not a borrow. */
  if (value->kind == MS_E_MEMBER && ms_check_holds_resource(pass->program, ms_facts_type(pass->facts, value->id))) {
    return;
  }
  /* A field read the callable moves (`old := self.f; self.f = g`) leaves its record: the name owns it. */
  if (value->kind == MS_E_MEMBER && ms_facts_use(pass->facts, value->id) == MS_USE_MOVE) {
    return;
  }
  Borrow borrow = {.binding = binding, .name = pattern->u.name, .at = pattern->pos, .after = value->end.offset,
                   .mutable_ = stmt->u.bind.is_mutable, .alias = value->kind == MS_E_NAME && ms_facts_use(pass->facts, value->id) == MS_USE_MOVE,
                   .root = source.root, .place = source.place, .parts = source.parts};
  push_borrow(pass, borrow, answers_look_part(pass, source.call));
  /* a result that borrows from several arguments keeps every one of them frozen */
  for (size_t index = 0; index < pass->extra.len; index++) {
    borrow.root = pass->extra.ptr[index].root;
    borrow.place = pass->extra.ptr[index].place;
    borrow.parts = pass->extra.ptr[index].parts;
    push_borrow(pass, borrow, answers_look_part(pass, pass->extra.ptr[index].call));
  }
}

/* Calling a name bound to a closure runs the changes the closure makes to what it captured: they take effect here. */
static void note_closure_call(Borrows *pass, uint32_t binding, MsPos at) {
  for (size_t index = 0; index < pass->closures.len; index++) {
    if (pass->closures.ptr[index].binding != binding) {
      continue;
    }
    const size_t count = pass->changes.len;
    for (size_t change = 0; change < count; change++) {
      Change derived = pass->changes.ptr[change];
      if (derived.lambda != pass->closures.ptr[index].lambda) {
        continue;
      }
      derived.lambda = pass->outer; /* inside another closure the call runs when that closure does */
      derived.via_binding = binding;
      derived.via = at.offset;
      derived.at = at;
      change_list_push(&pass->changes, derived);
    }
  }
}

/* Records the place a store or `var` argument changes. */
static const MsExpr *captured_by_open_closure(const Borrows *pass, const MsExpr *name);

static void note_change(Borrows *pass, const MsExpr *place, bool assign, bool moved) {
  if (place == NULL) {
    return;
  }
  const MsExpr *at = place;
  const MsExpr *map_value = NULL; /* the map the step next to the root indexes, when it is one */
  for (;;) {
    MsExpr *left = NULL;
    MsExpr *index = NULL;
    if (at->kind == MS_E_MEMBER) {
      at = at->u.member.left;
      map_value = NULL;
    } else if (ms_expr_index(at, &left, &index)) {
      at = left;
      map_value = left;
    } else {
      break;
    }
  }
  const bool value_write = !assign && !moved && map_value != NULL &&
                           ms_ty_is(&pass->program->types, ms_facts_type(pass->facts, map_value->id), MS_BUILTIN_Map);
  uint32_t root = 0;
  if (at->kind == MS_E_NAME && local_of(pass->facts, at->id, &root)) {
    const bool stored_field = assign && place->kind == MS_E_MEMBER;
    change_list_push(&pass->changes, (Change){.root = root, .pos = ms_expr_start(place), .end = place->end.offset,
                                              .moved = moved, .assign = assign && !stored_field, .at = stored_field ? place->pos : ms_expr_start(place),
                                              .place = place, .lambda = captured_by_open_closure(pass, at), .value_write = value_write});
  }
}

/* The outermost open closure when `name` is bound outside it. */
static const MsExpr *captured_by_open_closure(const Borrows *pass, const MsExpr *name) {
  uint32_t binding = 0;
  if (pass->outer == NULL || !ms_bind_of(pass->facts, name->id, &binding)) {
    return NULL;
  }
  MsBindingList captures = ms_bind_captures(pass->facts, pass->outer);
  bool captured = false;
  for (size_t index = 0; index < captures.len && !captured; index++) {
    captured = captures.ptr[index] == binding;
  }
  ms_binding_list_free(&captures);
  return captured ? pass->outer : NULL;
}

static void measure_expr(void *ctx, const MsExpr *expr) {
  Borrows *pass = ctx;
  if (expr->end.offset > pass->high) {
    pass->high = expr->end.offset;
  }
}

static void measure_stmt(void *ctx, const MsStmt *stmt) {
  Borrows *pass = ctx;
  if (stmt->pos.offset > pass->high) {
    pass->high = stmt->pos.offset; /* a `break` or `return` ends no expression */
  }
}

/* The furthest offset any expression of `body` ends at, or any statement starts at. */
static uint32_t body_end(Borrows *pass, MsStmts body) {
  pass->high = 0;
  const MsVisitor measure = {.ctx = pass, .stmt = measure_stmt, .expr = measure_expr};
  ms_walk_block(&measure, body);
  return pass->high;
}

/* Notes the exit a block ends in, if any: statements after an unconditional exit never run. */
static void note_exit(Borrows *pass, MsStmts body) {
  for (uint32_t index = 0; pass->lambdas == 0 && index < body.len; index++) {
    const MsStmt *stmt = body.ptr[index];
    if (stmt->kind == MS_S_BREAK || stmt->kind == MS_S_RETURN) {
      /* `return value` evaluates its value first: uses inside it still run after the change */
      const uint32_t at = stmt->kind == MS_S_RETURN && stmt->u.expr != NULL ? stmt->u.expr->end.offset : stmt->pos.offset;
      exit_list_push(&pass->exits, (Exit){.lo = body.ptr[0]->pos.offset, .at = at, .is_return = stmt->kind == MS_S_RETURN});
      return;
    }
  }
}

static void note_ranges(Borrows *pass, const MsStmt *stmt) {
  if (stmt->kind == MS_S_IF) {
    note_exit(pass, stmt->u.branch.body);
    note_exit(pass, stmt->u.branch.else_body);
  } else if (stmt->kind == MS_S_WHILE || stmt->kind == MS_S_FOR) {
    note_exit(pass, stmt->kind == MS_S_WHILE ? stmt->u.loop.body : stmt->u.each.body);
  }
  if (stmt->kind == MS_S_IF && stmt->u.branch.else_body.len != 0 && stmt->u.branch.body.len != 0) {
    const uint32_t split = stmt->u.branch.else_body.ptr[0]->pos.offset;
    range_list_push(&pass->ranges, (Range){.lo = stmt->pos.offset, .split = split,
                                           .hi = body_end(pass, stmt->u.branch.else_body)});
  } else if (stmt->kind == MS_S_WHILE || stmt->kind == MS_S_FOR) {
    const MsStmts body = stmt->kind == MS_S_WHILE ? stmt->u.loop.body : stmt->u.each.body;
    if (body.len != 0) {
      range_list_push(&pass->ranges, (Range){.lo = stmt->pos.offset, .hi = body_end(pass, body), .loop = true});
    }
  }
}

/* The call an expression keeps once `?` is peeled, or NULL. */
static const MsExpr *kept_call(const MsExpr *expr) {
  while (expr->kind == MS_E_UNARY && expr->op == MS_U_TRY) {
    expr = expr->u.bin.left;
  }
  return expr->kind == MS_E_CALL ? expr : NULL;
}

/* A place that starts at `self`: a method's receiver is not a local that a view could outlive. */
static bool rooted_at_self(const Borrows *pass, const MsExpr *place) {
  while (place != NULL && place->kind == MS_E_MEMBER) {
    place = place->u.member.left;
  }
  return place != NULL && place->kind == MS_E_NAME &&
         ms_span_is_text(ms_names_span(pass->program->names, place->u.sym), "self");
}

/* A borrowing call on a value the statement builds and drops (`text.slice(1, n).trim()`): what it answers points
 * into a temporary that is gone when the statement ends. */
static bool borrows_temporary(Borrows *pass, const MsExpr *call) {
  const MsCall *fact = ms_facts_call(pass->facts, call->id);
  const MsExpr *callee = call->u.call.callee;
  if (fact == NULL || !is_value_ref(fact->callee.kind) || callee->kind != MS_E_MEMBER || !borrows_from(pass, fact, 0) ||
      takes_payload(pass, call)) {
    return false; /* the payload of a temporary optional or result leaves with it */
  }
  const MsExpr *receiver = kept_call(callee->u.member.left);
  const MsCall *made = receiver != NULL ? ms_facts_call(pass->facts, receiver->id) : NULL;
  Source ignored = {0};
  return made != NULL && is_value_ref(made->callee.kind) && ms_class_owns_memory(pass->facts, pass->classes, receiver) &&
         !origin_of_call(pass, receiver, &ignored);
}

static void note_keep(Borrows *pass, const MsExpr *kept) {
  if (!ms_class_owns_memory(pass->facts, pass->classes, kept)) {
    return; /* a scalar is copied out of the result, so nothing is kept */
  }
  if (ms_own_look_record(pass->program, ms_facts_type(pass->facts, kept->id))) {
    return; /* a look holds a view, not the part itself: its holder is tied to the sources instead */
  }
  const MsExpr *call = kept_call(kept);
  Keep keep = {.kept = call};
  if (call != NULL && origin_of_arg(pass, call, &keep.source) && !rooted_at_self(pass, keep.source.place)) {
    keep_list_push(&pass->keeps, keep);
  } else if (call != NULL && ms_own_declared_ref_result(pass->program, &ms_facts_call(pass->facts, call->id)->callee) &&
             borrows_temporary(pass, call)) {
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_append_text(&text, "`");
    ms_own_expr_text(&text, pass->program->names, call);
    ms_strbuild_append_text(&text, "` borrows a temporary value that is gone when this statement ends; store `.clone()` of it");
    ms_check_report(pass->program, pass->module, call->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  }
}

/* The arguments of `call` that a new owner keeps: constructor arguments, `move` parameters, a taken receiver. */
static void note_call_keeps(Borrows *pass, const MsExpr *call) {
  const MsCall *fact = ms_facts_call(pass->facts, call->id);
  const MsExpr *callee = call->u.call.callee;
  const bool constructor = ms_bind_is_constructor(pass->facts, call);
  if (pass->ref_result && fact != NULL && fact->callee.kind == MS_REF_CASE) {
    return; /* `ok(part)` in a `&` function wraps a view of the part: its holder keeps the part, not the wrapper */
  }
  for (uint32_t index = 0; index < call->u.call.args.len; index++) {
    const MsExpr *value = call->u.call.args.ptr[index].value;
    bool moves = constructor;
    for (uint32_t at = 0; fact != NULL && at < fact->arg_count; at++) {
      if (constructor && fact->args[at].source == MS_ARG_WRITTEN && fact->args[at].node.node == value->id &&
          (ms_own_look_field(pass->program, fact, at) || ms_own_look_carrier(pass->program, fact, at))) {
        moves = false; /* the record is tied to it, not given it */
        break;
      }
      moves = moves || (fact->args[at].source == MS_ARG_WRITTEN && fact->args[at].node.node == value->id &&
                        (fact->args[at].flags & MS_PARAM_MOVE) != 0);
    }
    if (moves) {
      note_keep(pass, value);
    }
  }
  if (fact != NULL && fact->arg_count != 0 && callee->kind == MS_E_MEMBER && fact->args[0].source == MS_ARG_WRITTEN &&
      fact->args[0].node.node == callee->u.member.left->id &&
      ((fact->args[0].flags & MS_PARAM_MOVE) != 0 || ms_own_consuming_method(pass->program, &fact->callee)) &&
      !ms_own_result_is_borrowed(pass->program, fact->callee.decl.module, fact->callee.decl.node)) {
    /* A method that answers a view of its receiver (`get_or`) keeps nothing: whatever holds the view does. */
    note_keep(pass, callee->u.member.left);
  }
}

static void note_keeps(Borrows *pass, const MsExpr *expr) {
  if (expr->kind == MS_E_CALL) {
    note_call_keeps(pass, expr);
  } else if (expr->kind == MS_E_LIST) {
    for (uint32_t index = 0; index < expr->u.list.len; index++) {
      note_keep(pass, expr->u.list.ptr[index]);
    }
  } else if (expr->kind == MS_E_MAP) {
    for (uint32_t index = 0; index < expr->u.map.len; index++) {
      note_keep(pass, expr->u.map.ptr[index].key);
      note_keep(pass, expr->u.map.ptr[index].value);
    }
  }
}

/* The name a borrowed `String` or `Bytes` result (`view`, `trim`, ...) of a local or parameter is rooted at, when the
 * function returns it as an owned value: the returned text would be owned, and the result only borrows. */
static bool returned_view(const Borrows *pass, const MsExpr *value, MsName *local) {
  const MsExpr *callee = value->kind == MS_E_CALL ? value->u.call.callee : NULL;
  const MsCall *fact = callee != NULL ? ms_facts_call(pass->facts, value->id) : NULL;
  if (fact == NULL || callee->kind != MS_E_MEMBER || fact->callee.kind == MS_REF_METHOD || fact->callee.kind == MS_REF_FUNCTION) {
    return false;
  }
  const MsTyTable *types = &pass->program->types;
  const MsTy ty = ms_facts_type(pass->facts, value->id);
  if (!ms_own_declared_ref_result(pass->program, &fact->callee) || ty == MS_TY_NONE ||
      (!ms_ty_is(types, ty, MS_BUILTIN_Bytes) && !ms_ty_is(types, ty, MS_BUILTIN_String))) {
    return false;
  }
  const MsExpr *root = callee->u.member.left;
  uint32_t binding = 0;
  while (root->kind == MS_E_MEMBER) {
    root = root->u.member.left;
  }
  if (root->kind != MS_E_NAME || !local_of(pass->facts, root->id, &binding)) {
    return false;
  }
  *local = root->u.sym;
  return true;
}

/* Writes the diagnostic for a returned value that is read in place out of something the function keeps: a view of a local
 * or parameter, a resource read out of a collection, or a payload read from a field. The caller would own what its owner
 * still holds. False when the value is none of those. */
bool ms_borrows_describe_returned(Borrows *pass, const MsExpr *value, MsStrBuild *text) {
  MsName local = 0;
  const MsNames *names = pass->program->names;
  const MsTy ty = ms_facts_type(pass->facts, value->id);
  const MsNativeGet get = ty == MS_TY_NONE ? MS_NATIVE_GET_NONE : ms_own_native_get(pass->program, pass->facts, value);
  if (!pass->ref_result && returned_view(pass, value, &local)) { /* a `&` result may be a view: result borrows check it */
    ms_strbuild_append_text(text, "cannot return a view of `");
    ms_strbuild_append(text, ms_names_span(names, local));
    ms_strbuild_append_text(text, "`: a returned `");
    ms_strbuild_append_text(text, ms_ty_is(&pass->program->types, ty, MS_BUILTIN_Bytes) ? "Bytes" : "String");
    ms_strbuild_append_text(text, "` is owned and a view only borrows `");
    ms_strbuild_append(text, ms_names_span(names, local));
    ms_strbuild_append_text(text, "`; copy it with `.clone()` after the view");
    return true;
  }
  const MsExpr *receiver = get == MS_NATIVE_GET_NONE ? NULL : value->u.call.callee->u.member.left;
  if ((get == MS_NATIVE_GET_LIST || get == MS_NATIVE_GET_MAP) && ms_check_holds_resource(pass->program, ty)) {
    ms_strbuild_append_text(text, "`");
    ms_own_expr_text(text, names, value);
    ms_strbuild_append_text(text, "` reads an element that `");
    ms_own_expr_text(text, names, receiver);
    ms_strbuild_append_text(text, "` keeps, and this position would own it too; store `.clone()` of it, or use it in place");
    return true;
  }
  const bool nullable_or = value->kind == MS_E_BINARY && value->op == MS_B_OR &&
                           ms_ty_is(&pass->program->types, ms_facts_type(pass->facts, value->u.bin.left->id), MS_BUILTIN_Optional);
  if (nullable_or) {
    receiver = value->u.bin.left;
  }
  if ((get == MS_NATIVE_GET_PAYLOAD || nullable_or) && receiver->kind == MS_E_MEMBER &&
      ms_class_of(pass->classes, ty) != MS_CLASS_COPY && !ms_check_property(pass->program, ty, MS_PROPERTY_CLONABLE)) {
    ms_strbuild_append_text(text, "cannot move `");
    ms_own_expr_text(text, names, nullable_or ? receiver : value);
    ms_strbuild_append_text(text, nullable_or ? " or ..` out: it is read in place from `" : "` out: it is read in place from `");
    ms_own_expr_text(text, names, receiver);
    ms_strbuild_append_text(text, "`, which keeps it; it has one owner and no `clone`, so use it in place or move `");
    ms_own_expr_text(text, names, receiver);
    ms_strbuild_append_text(text, "` itself");
    return true;
  }
  return false;
}

/* `if var x = value` borrows the entry `place[key]?` or `map.get(key)` finds in place; any other place has no entry to lend. */
static void note_if_var(Borrows *pass, const MsStmt *stmt) {
  const MsExpr *cond = stmt->u.branch.cond;
  MsExpr *left = NULL;
  MsExpr *index = NULL;
  const MsExpr *root = cond;
  while (root->kind == MS_E_MEMBER || ms_expr_index(root, &left, &index)) {
    root = root->kind == MS_E_MEMBER ? root->u.member.left : left;
  }
  uint32_t binding = 0;
  if (cond->kind == MS_E_PROBE || root->kind != MS_E_NAME || !local_of(pass->facts, root->id, &binding) ||
      cond->kind == MS_E_NAME) {
    return; /* a name at its last use moves into the binding (checked with the moves) */
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "`if var` borrows an entry written as `place[key]?` or `map.get(key)`, but `");
  ms_own_expr_text(&text, pass->program->names, cond);
  ms_strbuild_append_text(&text, "` is not one; read the payload by testing `if value != null { ... }`, then use `var copy = x.clone()` for an independent "
                                 "mutable copy, or write the changed value back");
  ms_check_report(pass->program, pass->module, stmt->u.branch.binding->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
}

/* Whether `call` is a native that lends a collection of its receiver (`m.keys()`, `text.split(..)`): a function that
 * returns it would hand out something that only borrows. */
bool ms_borrows_lends_collection(const Borrows *pass, const MsExpr *call) {
  const MsCall *fact = ms_facts_call(pass->facts, call->id);
  const MsExpr *callee = call->u.call.callee;
  if (fact == NULL || callee->kind != MS_E_MEMBER || fact->callee.kind == MS_REF_METHOD || fact->callee.kind == MS_REF_FUNCTION) {
    return false;
  }
  const MsSpan name = ms_names_span(pass->program->names, callee->u.member.name);
  return ms_span_is_text(name, "keys") || ms_span_is_text(name, "values") || ms_span_is_text(name, "slice") ||
         ms_span_is_text(name, "chars");
}

static void note_return(Borrows *pass, const MsStmt *stmt) {
  if (stmt->u.expr == NULL) {
    return;
  }
  if (pass->lambdas != 0) {
    /* A closure's value is stored by whoever calls it (`map` builds a list of them), so a borrowed text it answers from
     * its own parameter or a capture would outlive the owner: it returns `.clone()` unless it writes a `&` result. */
    MsName local = 0;
    const bool written_ref = pass->outer != NULL && pass->outer->u.lambda.result != NULL && pass->outer->u.lambda.result->is_ref;
    if (!written_ref && returned_view(pass, stmt->u.expr, &local)) {
      keep_list_push(&pass->keeps, (Keep){.kept = stmt->u.expr, .returned = true});
    }
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  if (ms_borrows_describe_returned(pass, stmt->u.expr, &text)) {
    keep_list_push(&pass->keeps, (Keep){.kept = stmt->u.expr, .returned = true});
  } else {
    const MsExpr *call = kept_call(stmt->u.expr);
    if (call != NULL && ms_borrows_lends_collection(pass, call)) {
      note_keep(pass, stmt->u.expr);
    }
  }
  ms_strbuild_free(&text);
}

/* `for item in source`: the loop keeps `source` frozen, and the loop variable a borrow of it, until the body ends. */
static void note_loop(Borrows *pass, const MsStmt *stmt) {
  const MsExpr *iter = stmt->u.each.iter;
  const MsRef *ref = ms_facts_ref(pass->facts, stmt->id);
  Source source = {0};
  source_list_clear(&pass->extra);
  if (stmt->u.each.body.len == 0 || ref == NULL || ref->kind != MS_REF_LOCAL || !origin_of_arg(pass, iter, &source)) {
    return;
  }
  Borrow borrow = {.binding = ref->local, .name = stmt->u.each.name, .at = stmt->pos, .after = iter->end.offset,
                   .root = source.root, .place = source.place, .parts = source.parts, .loop = true};
  push_borrow(pass, borrow, false);
  for (size_t index = 0; index < pass->extra.len; index++) {
    borrow.root = pass->extra.ptr[index].root;
    borrow.place = pass->extra.ptr[index].place;
    borrow.parts = pass->extra.ptr[index].parts;
    push_borrow(pass, borrow, false);
  }
  /* the next round reads the source again: the loop uses its variable's borrow until the body's end */
  use_list_push(&pass->uses, (Use){.binding = ref->local, .offset = body_end(pass, stmt->u.each.body), .loop = stmt->pos.offset + 1});
}

static void visit_stmt(void *ctx, const MsStmt *stmt) {
  Borrows *pass = ctx;
  note_ranges(pass, stmt);
  if (stmt->kind == MS_S_FOR) {
    note_loop(pass, stmt);
  }
  if (stmt->kind == MS_S_RETURN) {
    note_return(pass, stmt);
  }
  if (stmt->kind == MS_S_IF && stmt->u.branch.binding != NULL && stmt->u.branch.is_mutable) {
    note_if_var(pass, stmt);
  }
  if (stmt->kind == MS_S_BIND) {
    note_kept_captures(pass, stmt);
    note_bind(pass, stmt);
  } else if (stmt->kind == MS_S_ASSIGN) {
    note_change(pass, stmt->u.assign.target, true, false);
    uint32_t root = 0;
    if (!stmt->u.assign.member_target && !stmt->u.assign.has_compound && declared_view_call(pass, stmt->u.assign.value) &&
        local_of(pass->facts, stmt->id, &root) && !holds_view(pass, root)) {
      note_keep(pass, stmt->u.assign.value); /* an owning `var` would keep the view: clone it */
    }
    if (!stmt->u.assign.member_target && local_of(pass->facts, stmt->id, &root)) {
      const uint32_t length = (uint32_t)ms_names_span(pass->program->names, stmt->u.assign.name).len;
      change_list_push(&pass->changes, (Change){.root = root, .pos = stmt->pos, .end = stmt->pos.offset + length,
                                                .assign = true, .at = stmt->pos});
    }
  }
}

static void leave_expr(void *ctx, const MsExpr *expr) {
  Borrows *pass = ctx;
  if (expr->kind == MS_E_LAMBDA && pass->lambdas > 0) {
    pass->lambdas--;
    if (pass->lambdas == 0) {
      pass->outer = NULL;
    }
  }
}

static void visit_expr(void *ctx, const MsExpr *expr) {
  Borrows *pass = ctx;
  uint32_t binding = 0;
  if (expr->kind == MS_E_LAMBDA) {
    pass->outer = pass->lambdas++ == 0 ? expr : pass->outer;
  }
  note_keeps(pass, expr);
  if (expr->kind == MS_E_CALL) {
    kept_closures(pass, expr, &pass->kept);
  }
  if (expr->kind == MS_E_NAME && local_of(pass->facts, expr->id, &binding)) {
    use_list_push(&pass->uses, (Use){.binding = binding, .offset = expr->pos.offset});
    return;
  }
  const MsCall *fact = expr->kind == MS_E_CALL ? ms_facts_call(pass->facts, expr->id) : NULL;
  if (fact != NULL && expr->u.call.callee->kind == MS_E_NAME && local_of(pass->facts, expr->u.call.callee->id, &binding)) {
    /* A function value is in use until its call returns: a change its arguments make still runs under the borrow. */
    use_list_push(&pass->uses, (Use){.binding = binding, .offset = expr->end.offset});
    note_closure_call(pass, binding, expr->u.call.callee->pos);
  }
  for (uint32_t index = 0; fact != NULL && index < fact->arg_count; index++) {
    const MsCallArg *arg = &fact->args[index];
    if (arg->source == MS_ARG_WRITTEN && (arg->flags & MS_PARAM_MOVE) != 0) {
      /* A whole name handed to a `move` parameter is gone: a view bound from it must not be used after. */
      for (uint32_t at = 0; at < expr->u.call.args.len; at++) {
        const MsExpr *value = expr->u.call.args.ptr[at].value;
        if (value->id == arg->node.node && value->kind == MS_E_NAME) {
          note_change(pass, value, false, true);
        }
      }
    }
    if (arg->source != MS_ARG_WRITTEN || (arg->flags & MS_PARAM_VAR) == 0) {
      continue;
    }
    const MsExpr *callee = expr->u.call.callee;
    if (callee->kind == MS_E_MEMBER && arg->node.node == callee->u.member.left->id) {
      note_change(pass, callee->u.member.left, false, false);
      continue;
    }
    for (uint32_t at = 0; at < expr->u.call.args.len; at++) {
      if (expr->u.call.args.ptr[at].value->id == arg->node.node) {
        note_change(pass, expr->u.call.args.ptr[at].value, false, false);
      }
    }
  }
}

void ms_own_borrows(MsCheckProgram *program) {
  if (program->diagnostics.len != 0 || program->modules.len <= program->user_modules) {
    /* without the standard library no result is known to be new, and every call result would read as a borrow */
    return;
  }
  MsClassifier classes = ms_class_new(program);
  for (uint32_t module = 0; module < (uint32_t)program->modules.len; module++) {
    Borrows pass = {.program = program, .classes = &classes, .module = module,
                    .facts = &program->modules.ptr[module].facts, .source = program->modules.ptr[module].source};
    const MsModule *tree = program->modules.ptr[module].tree;
    const MsVisitor visitor = {.ctx = &pass, .stmt = visit_stmt, .expr = visit_expr, .leave_expr = leave_expr};
    for (uint32_t index = 0; index < tree->ndecls; index++) {
      const MsDecl *decl = tree->decls[index];
      if (decl->kind == MS_D_FN && decl->u.fn.deferred) {
        continue;
      }
      if (decl->kind == MS_D_FN) {
        note_exit(&pass, decl->u.fn.body);
        pass.ref_result = ms_own_result_is_borrowed(program, module, decl->id);
        ms_walk_callable(&visitor, decl->u.fn.params, decl->u.fn.body);
      } else if (decl->kind == MS_D_IMPL) {
        for (uint32_t at = 0; at < decl->u.impl.methods.len; at++) {
          const MsMethod *method = decl->u.impl.methods.ptr[at];
          if (method->func.deferred) {
            continue;
          }
          pass.ref_result = ms_own_result_is_borrowed(program, module, method->id);
          ms_walk_callable(&visitor, method->func.params, method->func.body);
        }
      } else {
        ms_walk_decl(&visitor, decl);
      }
      pass.ref_result = false;
      ms_borrows_judge(&pass);
    }
    borrow_list_free(&pass.borrows);
    change_list_free(&pass.changes);
    use_list_free(&pass.uses);
    use_list_free(&pass.view_vars);
    range_list_free(&pass.ranges);
    exit_list_free(&pass.exits);
    lambda_list_free(&pass.kept);
    keep_list_free(&pass.keeps);
    local_list_free(&pass.closures);
    source_list_free(&pass.extra);
  }
  ms_class_free(&classes);
}
