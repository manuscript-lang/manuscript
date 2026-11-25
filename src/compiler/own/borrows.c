/* compiler/own/borrows.c: a source changed while a binding borrowing it is still used (see borrows.h). */
#include "compiler/own/look_fields.h"
#include "compiler/own/result_borrows.h"
#include "compiler/own/borrows.h"

#include "compiler/check/methods.h"
#include "compiler/check/properties.h"
#include "compiler/own/bind.h"
#include "compiler/own/class.h"
#include "compiler/own/expr_text.h"
#include "compiler/own/uses.h"
#include "compiler/syntax/walk.h"

typedef struct Borrow {
  uint32_t binding; /* the borrowing binding */
  MsName name;
  MsPos at; /* where it is bound */
  uint32_t after; /* the offset its initializer ends at */
  bool mutable_;
  bool alias; /* bound from a bare name (`b := s`): a view that only a move of the source ends */
  bool loop; /* the variable of a `for`: the loop keeps the source frozen for its whole body */
  bool method_value; /* a method read as a value (`f := xs.any`): it keeps its receiver until it is last called */
  uint32_t root; /* the binding it borrows from */
  const MsExpr *place; /* the part of it that is borrowed */
} Borrow;

typedef struct Change {
  uint32_t root;
  MsPos pos;     /* where the changed place starts */
  uint32_t end;  /* the offset it ends at */
  bool moved;   /* a whole name goes to a `move` parameter */
  bool assign;  /* a whole name is assigned: a field or element store is a change of the name */
  MsPos at;     /* where the diagnostic points: a stored field's own name, else where the place starts */
  const MsExpr *place; /* the changed place; NULL when it is the whole binding */
  const MsExpr *lambda; /* the outermost open closure that captured the root and changes it, or NULL */
} Change;

typedef struct Use {
  uint32_t binding;
  uint32_t offset;
  uint32_t loop; /* a loop's own use of its variable at the end of the body: where that `for` starts, plus one; else 0 */
} Use;

/* A source range: a branch's two arms exclude each other; a loop body runs again after its end. */
typedef struct Range {
  uint32_t lo, split, hi; /* an if: [lo, split) is the then arm and [split, hi] the else arm; a loop: [lo, hi] */
  bool loop;
} Range;

/* What a borrowing expression was computed from: the place it reads and the innermost call applied to it. */
typedef struct Source {
  uint32_t root;
  const MsExpr *place;
  const MsExpr *call;
} Source;

/* A borrowing call in a position that keeps its result. */
typedef struct Keep {
  const MsExpr *kept;
  Source source;
  bool returned; /* a value the function hands back that it only reads in place: no borrow origin, see report_returned */
} Keep;

/* A block that ends in an unconditional `break` or `return`: a change in [lo, at) is followed by that exit, so no earlier
 * or later use in the loop (or, for a `return`, anywhere) runs after it. */
typedef struct Exit {
  uint32_t lo, at;
  bool is_return;
} Exit;

MS_LIST_DEFINE(RangeList, range_list, Range)
MS_LIST_DEFINE(ExitList, exit_list, Exit)
MS_LIST_DEFINE(SourceList, source_list, Source)
MS_LIST_DEFINE(KeepList, keep_list, Keep)
MS_LIST_DEFINE(BorrowList, borrow_list, Borrow)
MS_LIST_DEFINE(ChangeList, change_list, Change)
MS_LIST_DEFINE(UseList, use_list, Use)

typedef struct Borrows {
  MsCheckProgram *program;
  MsClassifier *classes;
  uint32_t module;
  MsFacts *facts;
  MsSpan source;
  BorrowList borrows;
  ChangeList changes;
  UseList uses;
  RangeList ranges;
  ExitList exits;
  KeepList keeps;
  SourceList extra; /* the origins after the first that the last origin_of_* query found */
  uint32_t high; /* the furthest end offset seen by the current measuring walk */
  uint32_t lambdas; /* open closures: what they return is theirs */
  const MsExpr *outer; /* the outermost open closure */
} Borrows;

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
  /* A resource field bound by name leaves its record (the next statement refills it): that is a take, not a borrow. */
  if (value->kind == MS_E_MEMBER && ms_check_holds_resource(pass->program, ms_facts_type(pass->facts, value->id))) {
    return;
  }
  /* A field read the callable moves (`old := self.f; self.f = g`) leaves its record: the name owns it. */
  if (value->kind == MS_E_MEMBER && ms_facts_use(pass->facts, value->id) == MS_USE_MOVE) {
    return;
  }
  Borrow borrow = {.binding = binding, .name = pattern->u.name, .at = pattern->pos, .after = value->end.offset,
                   .mutable_ = stmt->u.bind.is_mutable, .alias = value->kind == MS_E_NAME,
                   .root = source.root, .place = source.place};
  push_borrow(pass, borrow, answers_look_part(pass, source.call));
  /* a result that borrows from several arguments keeps every one of them frozen */
  for (size_t index = 0; index < pass->extra.len; index++) {
    borrow.root = pass->extra.ptr[index].root;
    borrow.place = pass->extra.ptr[index].place;
    push_borrow(pass, borrow, answers_look_part(pass, pass->extra.ptr[index].call));
  }
}

/* Records the place a store or `var` argument changes. */
static const MsExpr *captured_by_open_closure(const Borrows *pass, const MsExpr *name);

static void note_change(Borrows *pass, const MsExpr *place, bool assign, bool moved) {
  if (place == NULL) {
    return;
  }
  const MsExpr *at = place;
  for (;;) {
    MsExpr *left = NULL;
    MsExpr *index = NULL;
    if (at->kind == MS_E_MEMBER) {
      at = at->u.member.left;
    } else if (ms_expr_index(at, &left, &index)) {
      at = left;
    } else {
      break;
    }
  }
  uint32_t root = 0;
  if (at->kind == MS_E_NAME && local_of(pass->facts, at->id, &root)) {
    const bool stored_field = assign && place->kind == MS_E_MEMBER;
    change_list_push(&pass->changes, (Change){.root = root, .pos = ms_expr_start(place), .end = place->end.offset,
                                              .moved = moved, .assign = assign && !stored_field, .at = stored_field ? place->pos : ms_expr_start(place),
                                              .place = place, .lambda = captured_by_open_closure(pass, at)});
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
  }
}

/* The arguments of `call` that a new owner keeps: constructor arguments, `move` parameters, a taken receiver. */
static void note_call_keeps(Borrows *pass, const MsExpr *call) {
  const MsCall *fact = ms_facts_call(pass->facts, call->id);
  const MsExpr *callee = call->u.call.callee;
  const bool constructor = ms_bind_is_constructor(pass->facts, call);
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

/* The name a `view` of a local or parameter is rooted at, when `value` is a native `view` returning an owned `String` or
 * `Bytes`: the returned text would be owned, and the view only borrows. */
static bool returned_view(const Borrows *pass, const MsExpr *value, MsName *local) {
  const MsExpr *callee = value->kind == MS_E_CALL ? value->u.call.callee : NULL;
  const MsCall *fact = callee != NULL ? ms_facts_call(pass->facts, value->id) : NULL;
  if (fact == NULL || callee->kind != MS_E_MEMBER || fact->callee.kind == MS_REF_METHOD || fact->callee.kind == MS_REF_FUNCTION) {
    return false;
  }
  const MsSpan name = ms_names_span(pass->program->names, callee->u.member.name);
  const MsTyTable *types = &pass->program->types;
  const MsTy ty = ms_facts_type(pass->facts, value->id);
  if ((!ms_span_is_text(name, "view") && !ms_span_is_text(name, "view_bytes")) || ty == MS_TY_NONE ||
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
static bool describe_returned(Borrows *pass, const MsExpr *value, MsStrBuild *text) {
  MsName local = 0;
  const MsNames *names = pass->program->names;
  const MsTy ty = ms_facts_type(pass->facts, value->id);
  const MsNativeGet get = ty == MS_TY_NONE ? MS_NATIVE_GET_NONE : ms_own_native_get(pass->program, pass->facts, value);
  if (returned_view(pass, value, &local)) {
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
static bool lends_collection(const Borrows *pass, const MsExpr *call) {
  const MsCall *fact = ms_facts_call(pass->facts, call->id);
  const MsExpr *callee = call->u.call.callee;
  if (fact == NULL || callee->kind != MS_E_MEMBER || fact->callee.kind == MS_REF_METHOD || fact->callee.kind == MS_REF_FUNCTION) {
    return false;
  }
  const MsSpan name = ms_names_span(pass->program->names, callee->u.member.name);
  return ms_span_is_text(name, "keys") || ms_span_is_text(name, "values") || ms_span_is_text(name, "slice") ||
         ms_span_is_text(name, "split") || ms_span_is_text(name, "lines") || ms_span_is_text(name, "chars");
}

static void note_return(Borrows *pass, const MsStmt *stmt) {
  if (pass->lambdas != 0 || stmt->u.expr == NULL) {
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  if (describe_returned(pass, stmt->u.expr, &text)) {
    keep_list_push(&pass->keeps, (Keep){.kept = stmt->u.expr, .returned = true});
  } else {
    const MsExpr *call = kept_call(stmt->u.expr);
    if (call != NULL && lends_collection(pass, call)) {
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
                   .root = source.root, .place = source.place, .loop = true};
  push_borrow(pass, borrow, false);
  for (size_t index = 0; index < pass->extra.len; index++) {
    borrow.root = pass->extra.ptr[index].root;
    borrow.place = pass->extra.ptr[index].place;
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
    note_bind(pass, stmt);
  } else if (stmt->kind == MS_S_ASSIGN) {
    note_change(pass, stmt->u.assign.target, true, false);
    uint32_t root = 0;
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
  if (expr->kind == MS_E_NAME && local_of(pass->facts, expr->id, &binding)) {
    use_list_push(&pass->uses, (Use){.binding = binding, .offset = expr->pos.offset});
    return;
  }
  const MsCall *fact = expr->kind == MS_E_CALL ? ms_facts_call(pass->facts, expr->id) : NULL;
  if (fact != NULL && expr->u.call.callee->kind == MS_E_NAME && local_of(pass->facts, expr->u.call.callee->id, &binding)) {
    /* A function value is in use until its call returns: a change its arguments make still runs under the borrow. */
    use_list_push(&pass->uses, (Use){.binding = binding, .offset = expr->end.offset});
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

/* Whether an exit the change runs into (`xs.append(1); break`) leaves `use` unreachable: the exit ends the loop (or the
 * function), so a use before the change in the next round, or after the exit inside the loop, never runs. A loop that
 * ends inside the exit's block runs the change again, so it keeps the use reachable. */
static bool cut_by_exit(const Borrows *pass, uint32_t change, const Use *later) {
  const uint32_t use = later->offset;
  for (size_t index = 0; index < pass->exits.len; index++) {
    const Exit *exit = &pass->exits.ptr[index];
    if (change < exit->lo || change >= exit->at || (use > change && use < exit->at)) {
      continue;
    }
    bool straight = true;
    const Range *loop = NULL; /* the innermost loop around the exit */
    for (size_t at = 0; at < pass->ranges.len; at++) {
      const Range *range = &pass->ranges.ptr[at];
      if (!range->loop) {
        continue;
      }
      straight = straight && !(change >= range->lo && change <= range->hi && exit->at > range->hi);
      if (exit->at >= range->lo && exit->at <= range->hi && (loop == NULL || range->lo > loop->lo)) {
        loop = range;
      }
    }
    if (straight && (exit->is_return || (loop != NULL && use >= loop->lo && use <= loop->hi && (later->loop == 0 || later->loop > loop->lo)))) {
      return true;
    }
  }
  return false;
}

/* Whether a use at `use` can run after a change at `change`: later in the source, unless the two sit in
 * different arms of one branch; or anywhere in a loop that holds the change and not the borrow's binding. */
static bool runs_after(const Borrows *pass, const Borrow *borrow, uint32_t change, const Use *later, bool in_lambda) {
  const uint32_t use = later->offset;
  if (!in_lambda && cut_by_exit(pass, change, later)) {
    return false;
  }
  for (size_t index = 0; index < pass->ranges.len; index++) {
    const Range *range = &pass->ranges.ptr[index];
    if (range->loop) {
      if (change >= range->lo && change <= range->hi && use >= range->lo && use <= range->hi &&
          borrow->after < range->lo) {
        return true;
      }
      continue;
    }
    const bool change_then = change >= range->lo && change < range->split;
    const bool change_else = change >= range->split && change <= range->hi;
    const bool use_then = use >= range->lo && use < range->split;
    const bool use_else = use >= range->split && use <= range->hi;
    if ((change_then && use_else) || (change_else && use_then)) {
      return false;
    }
  }
  return use > change;
}

static bool used_after(const Borrows *pass, const Borrow *borrow, uint32_t offset, bool in_lambda) {
  for (size_t index = 0; index < pass->uses.len; index++) {
    if (pass->uses.ptr[index].binding == borrow->binding &&
        runs_after(pass, borrow, offset, &pass->uses.ptr[index], in_lambda)) {
      return true;
    }
  }
  return false;
}

static void append_name(const Borrows *pass, MsStrBuild *text, MsName name) {
  ms_strbuild_append(text, ms_names_span(pass->program->names, name));
}

static MsSpan source_text(const Borrows *pass, const MsExpr *expr) {
  const MsPos start = ms_expr_start(expr);
  return (MsSpan){pass->source.ptr + start.offset, expr->end.offset - start.offset};
}

/* The name a call is written with. */
static MsName call_name(const MsExpr *call) {
  const MsExpr *callee = call->u.call.callee;
  return callee->kind == MS_E_MEMBER ? callee->u.member.name : callee->u.sym;
}

/* A `get` that reads an element of its receiver in place: the position would own an element the receiver keeps. */
static void report_kept_read(Borrows *pass, const MsExpr *kept) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "`");
  ms_own_expr_text(&text, pass->program->names, kept);
  ms_strbuild_append_text(&text, "` reads an element that `");
  ms_own_expr_text(&text, pass->program->names, kept->u.call.callee->u.member.left);
  ms_strbuild_append_text(&text, "` keeps, and this position would own it too; store `.clone()` of it, or use it in place");
  ms_check_report(pass->program, pass->module, kept->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
}

static void report_keep(Borrows *pass, const Keep *keep) {
  if (keep->returned) {
    MsStrBuild text = ms_strbuild_new();
    if (describe_returned(pass, keep->kept, &text)) {
      ms_check_report(pass->program, pass->module, keep->kept->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
    } else {
      ms_strbuild_free(&text);
    }
    return;
  }
  if (!lends_collection(pass, keep->source.call) && ms_own_native_get(pass->program, pass->facts, keep->kept) != MS_NATIVE_GET_NONE) {
    report_kept_read(pass, keep->kept);
    return;
  }
  const MsExpr *base = keep->source.call;
  const MsCall *fact = ms_facts_call(pass->facts, base->id);
  const bool native = fact != NULL && fact->callee.kind != MS_REF_METHOD && fact->callee.kind != MS_REF_FUNCTION;
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "`");
  append_name(pass, &text, native ? call_name(base) : call_name(keep->kept));
  ms_strbuild_append_text(&text, native ? "` borrows `" : "` returns a reference into `");
  ms_strbuild_append(&text, source_text(pass, keep->source.place));
  ms_strbuild_append_text(&text, "`, which this position would keep; store `.clone()` of it, or use it in place");
  ms_check_report(pass->program, pass->module, keep->kept->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
}

static void report(Borrows *pass, const Borrow *borrow, const Change *change, MsPos at) {
  const MsPos start = change->pos;
  if (change->end <= start.offset || change->end > pass->source.len) {
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, change->assign ? "cannot reassign `" : change->moved ? "cannot move `" : "cannot change `");
  ms_strbuild_append(&text, (MsSpan){pass->source.ptr + start.offset, change->end - start.offset});
  if (borrow->loop) {
    ms_strbuild_append_text(&text, "` while the loop at ");
    ms_strbuild_append_u64(&text, borrow->at.line);
    ms_strbuild_append_text(&text, ":");
    ms_strbuild_append_u64(&text, borrow->at.column);
    ms_strbuild_append_text(&text, " iterates it; apply the change after the loop, or loop over a `.clone()` of it");
    ms_check_report(pass->program, pass->module, at, MS_CHECK_TYPE, ms_strbuild_finish(&text));
    return;
  }
  ms_strbuild_append_text(&text, "` while `");
  append_name(pass, &text, borrow->name);
  ms_strbuild_append_text(&text, borrow->method_value ? "` borrows it (method value, at "
                                 : borrow->mutable_   ? "` borrows it (mutable borrow, at "
                                                      : "` borrows it (binding of a part of it, at ");
  ms_strbuild_append_u64(&text, borrow->at.line);
  ms_strbuild_append_text(&text, ":");
  ms_strbuild_append_u64(&text, borrow->at.column);
  ms_strbuild_append_text(&text, "); finish using `");
  append_name(pass, &text, borrow->name);
  if (borrow->method_value) {
    ms_strbuild_append_text(&text, "` before this, or build `");
    append_name(pass, &text, borrow->name);
    ms_strbuild_append_text(&text, "` from a clone: bind `.clone()` of the captured value first and capture that binding");
  } else {
    ms_strbuild_append_text(&text, "` before this, or give `");
    append_name(pass, &text, borrow->name);
    ms_strbuild_append_text(&text, "` its own value by ending its initializer with `.clone()`");
  }
  ms_check_report(pass->program, pass->module, at, MS_CHECK_TYPE, ms_strbuild_finish(&text));
}

/* Whether two places of one binding can share storage: unless both are plain field chains, and neither is a prefix of
 * the other (`self.data` and `self.at` are separate fields). */
static bool places_overlap(const MsExpr *a, const MsExpr *b) {
  const MsExpr *chain[2][16];
  size_t length[2] = {0, 0};
  const MsExpr *both[2] = {a, b};
  for (int side = 0; side < 2; side++) {
    const MsExpr *at = both[side];
    for (;;) {
      MsExpr *left = NULL;
      MsExpr *index = NULL;
      if (at != NULL && ms_expr_index(at, &left, &index)) {
        at = left; /* an element lies inside its collection's place */
        continue;
      }
      if (at == NULL || at->kind != MS_E_MEMBER) {
        break;
      }
      if (length[side] == 16) {
        return true;
      }
      chain[side][length[side]++] = at;
      at = at->u.member.left;
    }
    if (at == NULL || at->kind != MS_E_NAME) {
      return true;
    }
  }
  const size_t shared = length[0] < length[1] ? length[0] : length[1];
  for (size_t at = 0; at < shared; at++) { /* chains run from the leaf to the root, so compare from the root */
    if (chain[0][length[0] - 1 - at]->u.member.name != chain[1][length[1] - 1 - at]->u.member.name) {
      return false;
    }
  }
  return true;
}

/* Each borrow reports its first later change of the source when the borrower is still used after it. */
static void judge(Borrows *pass) {
  for (size_t at = 0; at < pass->keeps.len; at++) {
    report_keep(pass, &pass->keeps.ptr[at]);
  }
  for (size_t at = 0; at < pass->borrows.len; at++) {
    const Borrow *borrow = &pass->borrows.ptr[at];
    for (size_t index = 0; index < pass->changes.len; index++) {
      const Change *change = &pass->changes.ptr[index];
      const uint32_t offset = change->pos.offset;
      if (borrow->alias && !change->moved) {
        continue;
      }
      if (change->root == borrow->root && offset >= borrow->after && used_after(pass, borrow, offset, change->lambda != NULL) &&
          (change->place == NULL || borrow->place == NULL || places_overlap(change->place, borrow->place))) {
        report(pass, borrow, change, change->at);
        if (change->lambda != NULL) { /* the closure that runs the change is itself a change of what it captured */
          report(pass, borrow, change, change->lambda->pos);
        }
        break;
      }
    }
  }
  borrow_list_clear(&pass->borrows);
  change_list_clear(&pass->changes);
  use_list_clear(&pass->uses);
  range_list_clear(&pass->ranges);
  exit_list_clear(&pass->exits);
  keep_list_clear(&pass->keeps);
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
      if (tree->decls[index]->kind == MS_D_FN) {
        note_exit(&pass, tree->decls[index]->u.fn.body);
      }
      ms_walk_decl(&visitor, tree->decls[index]);
      judge(&pass);
    }
    borrow_list_free(&pass.borrows);
    change_list_free(&pass.changes);
    use_list_free(&pass.uses);
    range_list_free(&pass.ranges);
    exit_list_free(&pass.exits);
    keep_list_free(&pass.keeps);
    source_list_free(&pass.extra);
  }
  ms_class_free(&classes);
}
