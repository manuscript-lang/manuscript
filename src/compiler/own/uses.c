/* compiler/own/uses.c: fills the `uses` fact column (see uses.h). */
#include "compiler/own/uses.h"

#include <stdlib.h>
#include <string.h>

#include "compiler/check/methods.h"
#include "compiler/check/properties.h"
#include "compiler/own/bind.h"
#include "compiler/own/class.h"
#include "compiler/own/result_borrows.h"
#include "compiler/own/taken.h"
#include "compiler/syntax/walk.h"

typedef struct Uses {
  MsCheckProgram *program;
  uint32_t module;
  bool report; /* the pass that only reports moves out of a borrowed call result: its markings are discarded */
  MsClassifier *classes;
  MsFacts *facts;
  const MsNames *names;
  MsParams params; /* the callable being marked */
  MsStmts body;
  uint32_t moving; /* the parameters of the callable being marked that it owns, by index */
  MsBindingList cand_locals, cand_nodes; /* `x := y` binds of a local `y` that nothing has read or assigned since */
  MsBindingList swapped; /* the reads that bind a local assigned while the binding lives (`old := a; a = b`) */
  const MsExpr *cand_places[16]; /* `x := a.f` binds of a field place that nothing has read or assigned since */
  uint32_t ncand_places;
  MsBindingList moved; /* the locals a name moves in the callable being marked */
  MsBindingList arms; /* the arms of the module's matches: what an arm binds is a view of the scrutinee */
} Uses;

/* Whether `expr` is a local name or a field read of one. */
static bool place_root(const Uses *pass, const MsExpr *expr) {
  const MsExpr *at = expr;
  while (at->kind == MS_E_MEMBER) {
    at = at->u.member.left;
  }
  uint32_t binding = 0;
  return at->kind == MS_E_NAME && ms_bind_of(pass->facts, at->id, &binding);
}

/* Whether `scrutinee` names a local or a parameter the callable owns: the arms of a match over it take its payload. */
static bool owned_name(const Uses *pass, const MsExpr *scrutinee) {
  if (scrutinee->kind == MS_E_CALL) { /* a call's result is a new owner: its arms own what they bind */
    return true;
  }
  const MsRef *ref = scrutinee->kind == MS_E_NAME ? ms_facts_ref(pass->facts, scrutinee->id) : NULL;
  return ref != NULL && (ref->kind == MS_REF_LOCAL || (ref->kind == MS_REF_PARAM && ref->local < 32 &&
                                                       (pass->moving >> ref->local & 1u) != 0));
}

/* Whether `expr` reads a name an arm of a match binds: it views the scrutinee, which stays its owner. */
static bool is_view(const Uses *pass, const MsExpr *expr) {
  const MsExpr *root = expr;
  while (root->kind == MS_E_MEMBER) {
    root = root->u.member.left;
  }
  const MsRef *ref = ms_facts_ref(pass->facts, root->id);
  for (size_t index = 0; ref != NULL && ref->kind == MS_REF_LOCAL && index < pass->arms.len; index++) {
    if (ref->local == pass->arms.ptr[index]) {
      return true;
    }
  }
  return false;
}

/* Whether `call` answers a new value: a function or method with a body whose result borrows none of its arguments. */
static bool fresh_call(const Uses *pass, const MsExpr *call) {
  const MsCall *fact = ms_facts_call(pass->facts, call->id);
  if (!pass->report || fact == NULL || (fact->callee.kind != MS_REF_FUNCTION && fact->callee.kind != MS_REF_METHOD)) {
    return false;
  }
  const MsFunc *func = ms_own_find_func(pass->program, &fact->callee);
  if (func == NULL || func->bodiless || func->external) {
    return false;
  }
  for (uint32_t index = 0; index < fact->arg_count; index++) {
    if (ms_own_call_borrows(pass->program, fact, index)) {
      return false;
    }
  }
  return true;
}

/* A field read of a temporary (`make().name`): the temporary dies with the statement, so the field moves out of it. */
static bool part_of_fresh_call(const Uses *pass, const MsExpr *expr) {
  const MsExpr *at = expr;
  while (at->kind == MS_E_MEMBER) {
    at = at->u.member.left;
  }
  return at != expr && at->kind == MS_E_CALL && fresh_call(pass, at);
}

/* A parameter of a generic type that a constructor stores (`ok(value)`): it may be a resource, so the call takes it. */
static bool stored_param(const Uses *pass, const MsExpr *expr) {
  const MsRef *ref = expr->kind == MS_E_NAME ? ms_facts_ref(pass->facts, expr->id) : NULL;
  const MsTy ty = ref != NULL && ref->kind == MS_REF_PARAM ? ms_facts_type(pass->facts, expr->id) : MS_TY_NONE;
  return ty != MS_TY_NONE && ms_ty_kind(&pass->program->types, ty) == MS_TY_VARIABLE;
}

/* A field read of a call whose answer views another owner's value (`result.err().message`): the owner keeps the field,
 * so handing it on needs `.clone()`. Reports it and answers true. */
static bool moves_out_of_borrowed_result(const Uses *pass, const MsExpr *expr) {
  const MsExpr *root = expr;
  while (root->kind == MS_E_MEMBER) {
    root = root->u.member.left;
  }
  if (expr->kind != MS_E_MEMBER || root->kind != MS_E_CALL) {
    return false;
  }
  const MsCall *fact = ms_facts_call(pass->facts, root->id);
  const MsTy ty = ms_facts_type(pass->facts, expr->id);
  if (fact == NULL || (fact->callee.kind != MS_REF_FUNCTION && fact->callee.kind != MS_REF_METHOD) || ty == MS_TY_NONE ||
      ms_class_of(pass->classes, ty) == MS_CLASS_COPY ||
      !ms_own_result_is_borrowed(pass->program, fact->callee.decl.module, fact->callee.decl.node)) {
    return false;
  }
  /* A value the call borrows from a temporary dies with the statement, so the field leaves with it. */
  const MsExpr *owner = root->u.call.callee->kind == MS_E_MEMBER && fact->callee.kind == MS_REF_METHOD
                            ? root->u.call.callee->u.member.left
                            : (root->u.call.args.len != 0 ? root->u.call.args.ptr[0].value : NULL);
  if (owner != NULL && owner->kind == MS_E_CALL) {
    return false;
  }
  ms_check_report(pass->program, pass->module, expr->pos, MS_CHECK_TYPE,
                  ms_string_from_span(ms_span_of_text("this field belongs to a borrowed call result, which keeps owning it; end it with `.clone()` to take a copy")));
  return true;
}

/* The operand hands its value to a new owner: a local or a field of one that is not Copy moves. */
static void mark_move(Uses *pass, const MsExpr *expr) {
  if (expr == NULL) {
    return;
  }
  if (expr->kind == MS_E_UNARY && expr->op == MS_U_TRY) { /* `r?` hands the payload of the local `r` on */
    if (expr->u.bin.left->kind == MS_E_NAME && place_root(pass, expr->u.bin.left)) {
      pass->facts->uses[expr->id] = MS_USE_MOVE;
    }
    return;
  }
  if (expr->kind == MS_E_MATCH) { /* `if c: a else: b` hands on whichever arm it picks */
    for (uint32_t at = 0; at < expr->u.match.arms.len; at++) {
      if (expr->u.match.arms.ptr[at]->from_if && expr->u.match.arms.ptr[at]->value != NULL) {
        mark_move(pass, expr->u.match.arms.ptr[at]->value);
      }
    }
    return;
  }
  if (moves_out_of_borrowed_result(pass, expr)) {
    return;
  }
  const bool temporary = expr->kind == MS_E_MEMBER && part_of_fresh_call(pass, expr);
  if (!temporary && ((expr->kind != MS_E_NAME && expr->kind != MS_E_MEMBER) || !place_root(pass, expr) || is_view(pass, expr))) {
    return;
  }
  const MsTy ty = ms_facts_type(pass->facts, expr->id);
  if (ty == MS_TY_NONE || ms_class_of(pass->classes, ty) == MS_CLASS_COPY) {
    return;
  }
  pass->facts->uses[expr->id] = MS_USE_MOVE;
}

static bool is_clone(const Uses *pass, const MsExpr *call) {
  const MsExpr *callee = call->u.call.callee;
  return call->u.call.args.len == 0 && callee->kind == MS_E_MEMBER &&
         ms_span_is_text(ms_names_span(pass->names, callee->u.member.name), "clone");
}

static const MsCallArg *arg_for(const MsCall *call, const MsExpr *value) {
  for (uint32_t index = 0; index < call->arg_count; index++) {
    if (call->args[index].source == MS_ARG_WRITTEN && call->args[index].node.node == value->id) {
      return &call->args[index];
    }
  }
  return NULL;
}

static bool is_constructor(const Uses *pass, const MsExpr *call) {
  const MsExpr *callee = call->u.call.callee;
  if (callee->kind == MS_E_APPLY && callee->u.apply.types.len != 0) { /* `Box[Int](...)`: the type is applied first */
    callee = callee->u.apply.left;
  }
  const MsRef *ref = ms_facts_ref(pass->facts, callee->id);
  return ref != NULL && (ref->kind == MS_REF_TYPE || ref->kind == MS_REF_CASE);
}

/* Whether the callee is a method declared `move fn`, which takes its receiver. */
bool ms_own_consuming_method(const MsCheckProgram *program, const MsRef *callee) {
  if (callee->kind != MS_REF_METHOD) {
    return false;
  }
  for (size_t index = 0; index < program->methods.len; index++) {
    const MsMethodEntry *entry = &program->methods.ptr[index];
    if (entry->module == callee->decl.module && entry->source->id == callee->decl.node) {
      return entry->source->consuming;
    }
  }
  return false;
}

static void visit_call(Uses *pass, const MsExpr *call) {
  const MsExpr *callee = call->u.call.callee;
  if (is_clone(pass, call)) {
    const MsExpr *receiver = callee->u.member.left;
    if ((receiver->kind == MS_E_NAME || receiver->kind == MS_E_MEMBER) && place_root(pass, receiver)) {
      pass->facts->uses[receiver->id] = MS_USE_CLONE;
    }
    return;
  }
  const MsCall *fact = ms_facts_call(pass->facts, call->id);
  const bool constructor = is_constructor(pass, call);
  for (uint32_t index = 0; index < call->u.call.args.len; index++) {
    const MsExpr *value = call->u.call.args.ptr[index].value;
    const MsCallArg *arg = fact == NULL ? NULL : arg_for(fact, value);
    if (constructor && stored_param(pass, value)) {
      pass->facts->uses[value->id] = MS_USE_MOVE;
    }
    if (constructor || (arg != NULL && ((arg->flags & MS_PARAM_MOVE) != 0 ||
                                        ms_own_call_takes(pass->program, fact, (uint32_t)(arg - fact->args))))) {
      mark_move(pass, value);
    }
  }
  if (fact != NULL && fact->arg_count != 0 && callee->kind == MS_E_MEMBER && fact->args[0].source == MS_ARG_WRITTEN &&
      fact->args[0].node.node == callee->u.member.left->id &&
      ((fact->args[0].flags & MS_PARAM_MOVE) != 0 || ms_own_consuming_method(pass->program, &fact->callee))) {
    mark_move(pass, callee->u.member.left);
  }
}

static void visit_expr(void *ctx, const MsExpr *expr) {
  Uses *pass = ctx;
  switch ((MsExprKind)expr->kind) {
  case MS_E_LIST:
    for (uint32_t index = 0; index < expr->u.list.len; index++) {
      mark_move(pass, expr->u.list.ptr[index]);
    }
    return;
  case MS_E_MAP:
    for (uint32_t index = 0; index < expr->u.map.len; index++) {
      mark_move(pass, expr->u.map.ptr[index].key);
      mark_move(pass, expr->u.map.ptr[index].value);
    }
    return;
  case MS_E_CALL:
    visit_call(pass, expr);
    return;
  case MS_E_MATCH:
    /* An arm over a call's result owns what it binds, so an arm that yields it hands it on. */
    for (uint32_t arm = 0; expr->u.match.scrutinee->kind == MS_E_CALL && arm < expr->u.match.arms.len; arm++) {
      mark_move(pass, expr->u.match.arms.ptr[arm]->value);
    }
    return;
  case MS_E_NAME:
  case MS_E_NUMBER:
  case MS_E_BOOL:
  case MS_E_VOID:
  case MS_E_TEXT:
  case MS_E_MEMBER:
  case MS_E_APPLY:
  case MS_E_INDEX:
  case MS_E_PROBE:
  case MS_E_UNARY:
  case MS_E_BINARY:
  case MS_E_LAMBDA:
    return;
  }
}

/* Whether the scrutinee is a resource or a place the callable owns: a local, or a parameter it takes by `move`. */
static bool owns_place(const Uses *pass, const MsExpr *cond) {
  if (ms_check_holds_resource(pass->program, ms_facts_type(pass->facts, cond->id))) {
    return true;
  }
  const MsRef *ref = cond->kind == MS_E_NAME ? ms_facts_ref(pass->facts, cond->id) : NULL;
  return ref != NULL && (ref->kind == MS_REF_LOCAL || (ref->kind == MS_REF_PARAM && ref->local < 32 &&
                                                       (pass->moving >> ref->local & 1u) != 0));
}

/* The local a bind reads whole: `old := a`, or `n := cur.get()`, whose payload the binding takes from `cur`. */
static const MsExpr *bound_local_source(const Uses *pass, const MsExpr *value) {
  if (value->kind == MS_E_NAME) {
    return value;
  }
  const MsExpr *callee = value->kind == MS_E_CALL ? value->u.call.callee : NULL;
  if (callee == NULL || value->u.call.args.len != 0 || callee->kind != MS_E_MEMBER ||
      callee->u.member.left->kind != MS_E_NAME ||
      !ms_span_is_text(ms_names_span(pass->names, callee->u.member.name), "get")) {
    return NULL;
  }
  return callee->u.member.left;
}

static bool binds_assigned_local(const Uses *pass, const MsExpr *expr) {
  const MsExpr *source = expr->kind == MS_E_MEMBER ? expr : bound_local_source(pass, expr);
  for (size_t index = 0; source != NULL && index < pass->swapped.len; index++) {
    if (pass->swapped.ptr[index] == source->id) {
      return true;
    }
  }
  return false;
}

static bool last_use_outside_loops(const Uses *pass, MsParams params, MsStmts body, const MsStmt *loop, const MsExpr *iter);

/* Whether `if r := o:` gives the payload of `o` to `r`: always for a resource or a parameter, and for another local only when `o` is
 * not read again, so a later read of `o` still finds its payload. */
static bool hands_payload_on(const Uses *pass, const MsStmt *stmt) {
  const MsExpr *cond = stmt->u.branch.cond;
  if (ms_check_holds_resource(pass->program, ms_facts_type(pass->facts, cond->id))) {
    return true;
  }
  const MsRef *ref = cond->kind == MS_E_NAME ? ms_facts_ref(pass->facts, cond->id) : NULL;
  return ref == NULL || ref->kind != MS_REF_LOCAL || last_use_outside_loops(pass, pass->params, pass->body, stmt, cond);
}

static void visit_stmt(void *ctx, const MsStmt *stmt) {
  Uses *pass = ctx;
  if (stmt->kind == MS_S_RETURN) {
    mark_move(pass, stmt->u.expr);
  } else if (stmt->kind == MS_S_BIND && stmt->u.bind.pattern->kind == MS_P_NAME &&
             (stmt->u.bind.is_mutable || binds_assigned_local(pass, stmt->u.bind.value))) {
    mark_move(pass, stmt->u.bind.is_mutable          ? stmt->u.bind.value
                    : stmt->u.bind.value->kind == MS_E_MEMBER ? stmt->u.bind.value
                                                              : bound_local_source(pass, stmt->u.bind.value));
  } else if (stmt->kind == MS_S_BIND && stmt->u.bind.pattern->kind == MS_P_TYPE && !stmt->u.bind.is_mutable &&
             stmt->u.bind.value->kind == MS_E_NAME) {
    mark_move(pass, stmt->u.bind.value); /* `{a: x, b: y} := record` hands the parts to the names */
  } else if (stmt->kind == MS_S_BIND && stmt->u.bind.pattern->kind == MS_P_NAME && stmt->u.bind.value->kind == MS_E_MATCH) {
    mark_move(pass, stmt->u.bind.value); /* `x := if c: a else: b` owns the arm it picks */
  } else if (stmt->kind == MS_S_ASSIGN && !stmt->u.assign.has_compound) {
    mark_move(pass, stmt->u.assign.value);
  } else if (stmt->kind == MS_S_IF && stmt->u.branch.binding != NULL && stmt->u.branch.binding->kind == MS_P_NAME &&
             !stmt->u.branch.is_mutable &&
             owns_place(pass, stmt->u.branch.cond) && hands_payload_on(pass, stmt)) {
    mark_move(pass, stmt->u.branch.cond); /* `if r := o:` hands the payload of a resource `o` to `r` */
  }
}

static void note_pattern_views(Uses *pass, const MsPattern *pattern) {
  if (pattern->kind == MS_P_NAME) {
    const MsRef *ref = ms_facts_ref(pass->facts, pattern->id);
    if (ref != NULL && ref->kind == MS_REF_LOCAL) {
      ms_binding_list_push(&pass->arms, ref->local);
    }
    return;
  }
  for (uint32_t at = 0; pattern->kind == MS_P_LIST && at < pattern->u.list.len; at++) {
    note_pattern_views(pass, pattern->u.list.ptr[at]);
  }
  for (uint32_t at = 0; pattern->kind == MS_P_TYPE && at < pattern->u.fields.len; at++) {
    note_pattern_views(pass, pattern->u.fields.ptr[at].pattern);
  }
}

/* A destructuring of a place binds views of its parts; of a call's result, owners. So does an `if` binding of a
 * place the callable does not own (a borrowed parameter or a field): returning it copies. */
static void collect_views(void *ctx, const MsStmt *stmt) {
  Uses *pass = ctx;
  /* `value := result?` over a place the callable does not own binds a view of its payload: returning it copies. */
  if (stmt->kind == MS_S_BIND && stmt->u.bind.pattern->kind == MS_P_NAME && stmt->u.bind.value->kind == MS_E_UNARY &&
      stmt->u.bind.value->op == MS_U_TRY && stmt->u.bind.value->u.bin.left->kind == MS_E_NAME &&
      !owns_place(pass, stmt->u.bind.value->u.bin.left)) {
    note_pattern_views(pass, stmt->u.bind.pattern);
  }
  if (stmt->kind == MS_S_BIND && stmt->u.bind.pattern->kind != MS_P_NAME &&
      (stmt->u.bind.value->kind == MS_E_NAME || stmt->u.bind.value->kind == MS_E_MEMBER)) {
    note_pattern_views(pass, stmt->u.bind.pattern);
  }
  /* An `if` binding of an owned local that is read again views its payload: the local stays the owner. */
  if (stmt->kind == MS_S_IF && stmt->u.branch.binding != NULL && stmt->u.branch.binding->kind == MS_P_NAME &&
      !stmt->u.branch.is_mutable && stmt->u.branch.cond->kind == MS_E_NAME && owns_place(pass, stmt->u.branch.cond) &&
      !hands_payload_on(pass, stmt)) {
    note_pattern_views(pass, stmt->u.branch.binding);
  }
}

/* The first pass marks every local name BORROW; the second upgrades moving operands (a parent is visited before
 * its children, so one pass would let the child's mark overwrite the move). */
static void borrow_expr(void *ctx, const MsExpr *expr) {
  Uses *pass = ctx;
  uint32_t binding = 0;
  if (expr->kind == MS_E_NAME && ms_bind_of(pass->facts, expr->id, &binding)) {
    pass->facts->uses[expr->id] = MS_USE_BORROW;
  }
  for (uint32_t arm = 0; expr->kind == MS_E_MATCH && !owned_name(pass, expr->u.match.scrutinee) &&
                         arm < expr->u.match.arms.len;
       arm++) {
    const MsArm *one = expr->u.match.arms.ptr[arm];
    const MsRef *bound = ms_facts_ref(pass->facts, one->id);
    for (uint32_t at = 0; bound != NULL && bound->kind == MS_REF_CASE && at < one->bindings.len; at++) {
      ms_binding_list_push(&pass->arms, bound->local + at);
    }
  }
}

/* A match over a name the callable owns hands its payload to an arm's binding that the arm moves on: the scrutinee
 * is consumed. */
static void note_moved_names(void *ctx, const MsExpr *expr) {
  Uses *pass = ctx;
  const MsRef *ref = expr->kind == MS_E_NAME ? ms_facts_ref(pass->facts, expr->id) : NULL;
  if (ref != NULL && ref->kind == MS_REF_LOCAL && pass->facts->uses[expr->id] == MS_USE_MOVE) {
    ms_binding_list_push(&pass->moved, ref->local);
  }
}

static void consume_scrutinees(void *ctx, const MsExpr *expr) {
  Uses *pass = ctx;
  if (expr->kind != MS_E_MATCH || expr->u.match.scrutinee->kind != MS_E_NAME || !owned_name(pass, expr->u.match.scrutinee)) {
    return;
  }
  for (uint32_t arm = 0; arm < expr->u.match.arms.len; arm++) {
    const MsArm *one = expr->u.match.arms.ptr[arm];
    const MsRef *bound = ms_facts_ref(pass->facts, one->id);
    for (uint32_t at = 0; bound != NULL && bound->kind == MS_REF_CASE && at < one->bindings.len; at++) {
      for (size_t index = 0; index < pass->moved.len; index++) {
        if (pass->moved.ptr[index] == bound->local + at) {
          pass->facts->uses[expr->u.match.scrutinee->id] = MS_USE_MOVE;
        }
      }
    }
  }
}

/* Whether two expressions name the same local or the same field path of one. */
static bool same_place(const Uses *pass, const MsExpr *a, const MsExpr *b) {
  if (a->kind != b->kind) {
    return false;
  }
  if (a->kind == MS_E_NAME) {
    const MsRef *left = ms_facts_ref(pass->facts, a->id);
    const MsRef *right = ms_facts_ref(pass->facts, b->id);
    return left != NULL && right != NULL && left->kind == right->kind && left->local == right->local;
  }
  return a->kind == MS_E_MEMBER && ms_span_equal(ms_names_span(pass->names, a->u.member.name), ms_names_span(pass->names, b->u.member.name)) &&
         same_place(pass, a->u.member.left, b->u.member.left);
}

/* `old := a` borrows `a`; if the next thing the callable does with `a` is assign it, the binding must own the value,
 * or the assignment frees what the binding still reads. A read of `a` in between keeps the plain borrow. */
static void note_swap_stmt(void *ctx, const MsStmt *stmt) {
  Uses *pass = ctx;
  if (stmt->kind == MS_S_BIND && !stmt->u.bind.is_mutable && stmt->u.bind.pattern->kind == MS_P_NAME) {
    if (stmt->u.bind.value->kind == MS_E_MEMBER && place_root(pass, stmt->u.bind.value) &&
        pass->ncand_places < sizeof pass->cand_places / sizeof pass->cand_places[0]) {
      pass->cand_places[pass->ncand_places++] = stmt->u.bind.value; /* `old := self.f; self.f = g` */
      return;
    }
    const MsExpr *source_name = bound_local_source(pass, stmt->u.bind.value);
    const MsRef *source = source_name == NULL ? NULL : ms_facts_ref(pass->facts, source_name->id);
    if (source != NULL && source->kind == MS_REF_LOCAL) {
      ms_binding_list_push(&pass->cand_locals, source->local);
      ms_binding_list_push(&pass->cand_nodes, source_name->id);
    }
    return;
  }
  if (stmt->kind == MS_S_ASSIGN && stmt->u.assign.member_target && !stmt->u.assign.has_compound) {
    for (uint32_t at = 0; at < pass->ncand_places; at++) {
      if (pass->cand_places[at] != NULL && same_place(pass, pass->cand_places[at], stmt->u.assign.target)) {
        ms_binding_list_push(&pass->swapped, pass->cand_places[at]->id);
        pass->cand_places[at] = NULL;
      }
    }
    return;
  }
  if (stmt->kind != MS_S_ASSIGN || stmt->u.assign.member_target || stmt->u.assign.has_compound) {
    return;
  }
  const MsRef *target = ms_facts_ref(pass->facts, stmt->id);
  for (size_t index = 0; target != NULL && target->kind == MS_REF_LOCAL && index < pass->cand_locals.len; index++) {
    if (pass->cand_locals.ptr[index] == target->local) {
      ms_binding_list_push(&pass->swapped, pass->cand_nodes.ptr[index]);
      pass->cand_locals.ptr[index] = UINT32_MAX;
    }
  }
}

static void note_swap_expr(void *ctx, const MsExpr *expr) {
  Uses *pass = ctx;
  for (uint32_t at = 0; expr->kind == MS_E_MEMBER && at < pass->ncand_places; at++) {
    if (pass->cand_places[at] != NULL && pass->cand_places[at] != expr && same_place(pass, pass->cand_places[at], expr)) {
      pass->cand_places[at] = NULL; /* read again before any assignment */
    }
  }
  const MsRef *ref = expr->kind == MS_E_NAME ? ms_facts_ref(pass->facts, expr->id) : NULL;
  for (size_t index = 0; ref != NULL && ref->kind == MS_REF_LOCAL && index < pass->cand_locals.len; index++) {
    if (pass->cand_locals.ptr[index] == ref->local && pass->cand_nodes.ptr[index] != expr->id) {
      pass->cand_locals.ptr[index] = UINT32_MAX; /* read again before any assignment */
    }
  }
}

/* Marks one function or method: the arms' locals are numbered per callable, so each is walked on its own. */
typedef struct Moved {
  const Uses *pass;
  uint32_t local;
  bool found;
} Moved;

static void find_moved_loop_name(void *ctx, const MsExpr *expr) {
  Moved *moved = ctx;
  const MsRef *ref = expr->kind == MS_E_NAME ? ms_facts_ref(moved->pass->facts, expr->id) : NULL;
  moved->found = moved->found || (ref != NULL && ref->kind == MS_REF_LOCAL && ref->local == moved->local &&
                                  moved->pass->facts->uses[expr->id] == MS_USE_MOVE);
}

/* The reads of one local: where the last one starts, and the furthest offset any expression of a scan ends at. */
typedef struct LastRead {
  const Uses *pass;
  uint32_t local;
  uint32_t last;
  uint32_t end;
} LastRead;

static void note_last_read(void *ctx, const MsExpr *expr) {
  LastRead *scan = ctx;
  const MsRef *ref = expr->kind == MS_E_NAME ? ms_facts_ref(scan->pass->facts, expr->id) : NULL;
  if (ref != NULL && ref->kind == MS_REF_LOCAL && ref->local == scan->local && ms_expr_start(expr).offset >= scan->last) {
    scan->last = ms_expr_start(expr).offset;
  }
  if (expr->end.offset > scan->end) {
    scan->end = expr->end.offset;
  }
}

/* The furthest offset any expression of a scan ends at. */
static void note_extent(void *ctx, const MsExpr *expr) {
  uint32_t *end = ctx;
  if (expr->end.offset > *end) {
    *end = expr->end.offset;
  }
}

typedef struct Enclosing {
  uint32_t at;
  bool inside;
  MsStmts body;
} Enclosing;

static void note_enclosing(void *ctx, const MsStmt *stmt) {
  Enclosing *scan = ctx;
  const MsStmts body = stmt->kind == MS_S_WHILE ? stmt->u.loop.body : stmt->kind == MS_S_FOR ? stmt->u.each.body : (MsStmts){0};
  if (body.len == 0 || stmt->pos.offset >= scan->at) {
    return;
  }
  uint32_t end = 0;
  ms_walk_block(&(MsVisitor){.ctx = &end, .expr = note_extent}, body);
  scan->inside = scan->inside || end > scan->at;
}

/* Whether the name `iter` of a `for` is the last read of its local and the loop is not inside another loop: the loop
 * is then the last owner of the list, so it takes the list's elements. */
static bool last_use_outside_loops(const Uses *pass, MsParams params, MsStmts body, const MsStmt *loop, const MsExpr *iter) {
  const MsRef *ref = ms_facts_ref(pass->facts, iter->id);
  LastRead reads = {.pass = pass, .local = ref->local};
  ms_walk_callable(&(MsVisitor){.ctx = &reads, .expr = note_last_read}, params, body);
  Enclosing enclosing = {.at = loop->pos.offset};
  ms_walk_callable(&(MsVisitor){.ctx = &enclosing, .stmt = note_enclosing}, params, body);
  return reads.last == ms_expr_start(iter).offset && !enclosing.inside;
}

/* `for item in items:` over a local list of resources whose body moves `item` on: the loop owns the elements, so each
 * one is closed in its round unless the body moves it away. */
static void consume_loops(void *ctx, const MsStmt *stmt) {
  Uses *pass = ctx;
  const MsRef *binding = stmt->kind == MS_S_FOR ? ms_facts_ref(pass->facts, stmt->id) : NULL;
  const MsExpr *iter = stmt->kind == MS_S_FOR ? stmt->u.each.iter : NULL;
  if (binding == NULL || binding->kind != MS_REF_LOCAL || iter->kind != MS_E_NAME || !place_root(pass, iter)) {
    return;
  }
  const MsTyTable *types = &pass->program->types;
  const MsTy list = ms_facts_type(pass->facts, iter->id);
  if (list == MS_TY_NONE || !ms_ty_is(types, list, MS_BUILTIN_List) || ms_ty_arg_count(types, list) != 1 ||
      !ms_check_holds_resource(pass->program, ms_ty_args(types, list)[0])) {
    return;
  }
  Moved moved = {.pass = pass, .local = binding->local};
  ms_walk_block(&(MsVisitor){.ctx = &moved, .expr = find_moved_loop_name}, stmt->u.each.body);
  if (moved.found || last_use_outside_loops(pass, pass->params, pass->body, stmt, iter)) {
    pass->facts->uses[iter->id] = MS_USE_MOVE;
  }
}

static void mark_callable(Uses *pass, MsParams params, MsStmts body, bool consuming) {
  pass->params = params;
  pass->body = body;
  pass->arms.len = 0;
  pass->moved.len = 0;
  pass->cand_locals.len = 0;
  pass->cand_nodes.len = 0;
  pass->swapped.len = 0;
  pass->ncand_places = 0;
  pass->moving = consuming ? 1u : 0u; /* the receiver of a consuming method is parameter 0 */
  for (uint32_t at = 0; at < params.len; at++) {
    const MsRef *ref = ms_facts_ref(pass->facts, params.ptr[at]->id);
    if (params.ptr[at]->moving && ref != NULL && ref->kind == MS_REF_PARAM && ref->local < 32) {
      pass->moving |= UINT32_C(1) << ref->local;
    }
  }
  ms_walk_callable(&(MsVisitor){.ctx = pass, .stmt = collect_views, .expr = borrow_expr}, params, body);
  ms_walk_callable(&(MsVisitor){.ctx = pass, .stmt = note_swap_stmt, .expr = note_swap_expr}, params, body);
  ms_walk_callable(&(MsVisitor){.ctx = pass, .stmt = visit_stmt, .expr = visit_expr}, params, body);
  ms_walk_callable(&(MsVisitor){.ctx = pass, .expr = note_moved_names}, params, body);
  ms_walk_callable(&(MsVisitor){.ctx = pass, .expr = consume_scrutinees}, params, body);
  ms_walk_callable(&(MsVisitor){.ctx = pass, .stmt = consume_loops}, params, body);
}

static void mark_module(Uses *pass, const MsModule *tree) {
  for (uint32_t index = 0; index < tree->ndecls; index++) {
    const MsDecl *decl = tree->decls[index];
    if (decl->kind == MS_D_FN) {
      mark_callable(pass, decl->u.fn.params, decl->u.fn.body, false);
    } else if (decl->kind == MS_D_IMPL) {
      for (uint32_t at = 0; at < decl->u.impl.methods.len; at++) {
        mark_callable(pass, decl->u.impl.methods.ptr[at]->func.params, decl->u.impl.methods.ptr[at]->func.body,
                    decl->u.impl.methods.ptr[at]->consuming);
      }
    } else {
      ms_walk_decl(&(MsVisitor){.ctx = pass, .stmt = collect_views, .expr = borrow_expr}, decl);
      ms_walk_decl(&(MsVisitor){.ctx = pass, .stmt = visit_stmt, .expr = visit_expr}, decl);
    }
  }
}

static void run_uses(MsCheckProgram *program, bool report) {
  MsClassifier classes = ms_class_new(program);
  for (uint32_t module = 0; module < program->modules.len; module++) {
    Uses pass = {.program = program, .module = module, .report = report, .classes = &classes, .facts = &program->modules.ptr[module].facts,
                 .names = program->names};
    if (pass.facts->uses == NULL) {
      continue;
    }
    mark_module(&pass, program->modules.ptr[module].tree);
    ms_binding_list_free(&pass.arms);
    ms_binding_list_free(&pass.moved);
    ms_binding_list_free(&pass.cand_locals);
    ms_binding_list_free(&pass.cand_nodes);
    ms_binding_list_free(&pass.swapped);
  }
  ms_class_free(&classes);
}

void ms_own_uses(MsCheckProgram *program) {
  run_uses(program, false);
}

void ms_own_uses_report(MsCheckProgram *program) {
  /* The borrowed-result masks exist only now, so the walk runs again with them; what it marks is already settled. */
  size_t total = 0;
  for (uint32_t module = 0; module < program->modules.len; module++) {
    total += program->modules.ptr[module].facts.uses == NULL ? 0 : program->modules.ptr[module].facts.node_count;
  }
  uint8_t *saved = malloc(total == 0 ? 1 : total);
  size_t at = 0;
  for (uint32_t module = 0; saved != NULL && module < program->modules.len; module++) {
    const MsFacts *facts = &program->modules.ptr[module].facts;
    if (facts->uses != NULL) {
      memcpy(saved + at, facts->uses, facts->node_count);
      at += facts->node_count;
    }
  }
  if (saved == NULL) {
    return;
  }
  run_uses(program, true);
  at = 0;
  for (uint32_t module = 0; module < program->modules.len; module++) {
    const MsFacts *facts = &program->modules.ptr[module].facts;
    if (facts->uses != NULL) {
      memcpy(facts->uses, saved + at, facts->node_count);
      at += facts->node_count;
    }
  }
  free(saved);
}
