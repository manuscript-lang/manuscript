/* compiler/own/uses.c: fills the `uses` fact column (see uses.h). */
#include "compiler/own/uses.h"

#include "compiler/check/methods.h"
#include "compiler/check/properties.h"
#include "compiler/own/bind.h"
#include "compiler/own/class.h"
#include "compiler/own/taken.h"
#include "compiler/syntax/walk.h"

typedef struct Uses {
  MsCheckProgram *program;
  MsClassifier *classes;
  MsFacts *facts;
  const MsNames *names;
  uint32_t moving; /* the parameters of the callable being marked that it owns, by index */
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
  if ((expr->kind != MS_E_NAME && expr->kind != MS_E_MEMBER) || !place_root(pass, expr) || is_view(pass, expr)) {
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
  const MsRef *ref = ms_facts_ref(pass->facts, call->u.call.callee->id);
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
  case MS_E_MATCH:
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

static void visit_stmt(void *ctx, const MsStmt *stmt) {
  Uses *pass = ctx;
  if (stmt->kind == MS_S_RETURN) {
    mark_move(pass, stmt->u.expr);
  } else if (stmt->kind == MS_S_BIND && stmt->u.bind.is_mutable) {
    mark_move(pass, stmt->u.bind.value);
  } else if (stmt->kind == MS_S_ASSIGN && !stmt->u.assign.has_compound) {
    mark_move(pass, stmt->u.assign.value);
  } else if (stmt->kind == MS_S_IF && stmt->u.branch.binding != NULL && stmt->u.branch.binding->kind == MS_P_NAME &&
             !stmt->u.branch.is_mutable &&
             owns_place(pass, stmt->u.branch.cond)) {
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

/* A destructuring of a place binds views of its parts; of a call's result, owners. */
static void collect_views(void *ctx, const MsStmt *stmt) {
  Uses *pass = ctx;
  if (stmt->kind == MS_S_BIND && stmt->u.bind.pattern->kind != MS_P_NAME &&
      (stmt->u.bind.value->kind == MS_E_NAME || stmt->u.bind.value->kind == MS_E_MEMBER)) {
    note_pattern_views(pass, stmt->u.bind.pattern);
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
  for (uint32_t arm = 0; expr->kind == MS_E_MATCH && arm < expr->u.match.arms.len; arm++) {
    const MsArm *one = expr->u.match.arms.ptr[arm];
    const MsRef *bound = ms_facts_ref(pass->facts, one->id);
    for (uint32_t at = 0; bound != NULL && bound->kind == MS_REF_CASE && at < one->bindings.len; at++) {
      ms_binding_list_push(&pass->arms, bound->local + at);
    }
  }
}

/* Marks one function or method: the arms' locals are numbered per callable, so each is walked on its own. */
static void mark_callable(Uses *pass, MsParams params, MsStmts body) {
  pass->arms.len = 0;
  pass->moving = 0;
  for (uint32_t at = 0; at < params.len; at++) {
    const MsRef *ref = ms_facts_ref(pass->facts, params.ptr[at]->id);
    if (params.ptr[at]->moving && ref != NULL && ref->kind == MS_REF_PARAM && ref->local < 32) {
      pass->moving |= UINT32_C(1) << ref->local;
    }
  }
  ms_walk_callable(&(MsVisitor){.ctx = pass, .stmt = collect_views, .expr = borrow_expr}, params, body);
  ms_walk_callable(&(MsVisitor){.ctx = pass, .stmt = visit_stmt, .expr = visit_expr}, params, body);
}

static void mark_module(Uses *pass, const MsModule *tree) {
  for (uint32_t index = 0; index < tree->ndecls; index++) {
    const MsDecl *decl = tree->decls[index];
    if (decl->kind == MS_D_FN) {
      mark_callable(pass, decl->u.fn.params, decl->u.fn.body);
    } else if (decl->kind == MS_D_IMPL) {
      for (uint32_t at = 0; at < decl->u.impl.methods.len; at++) {
        mark_callable(pass, decl->u.impl.methods.ptr[at]->func.params, decl->u.impl.methods.ptr[at]->func.body);
      }
    } else {
      ms_walk_decl(&(MsVisitor){.ctx = pass, .stmt = collect_views, .expr = borrow_expr}, decl);
      ms_walk_decl(&(MsVisitor){.ctx = pass, .stmt = visit_stmt, .expr = visit_expr}, decl);
    }
  }
}

void ms_own_uses(MsCheckProgram *program) {
  MsClassifier classes = ms_class_new(program);
  for (uint32_t module = 0; module < program->modules.len; module++) {
    Uses pass = {.program = program, .classes = &classes, .facts = &program->modules.ptr[module].facts,
                 .names = program->names};
    if (pass.facts->uses == NULL) {
      continue;
    }
    mark_module(&pass, program->modules.ptr[module].tree);
    ms_binding_list_free(&pass.arms);
  }
  ms_class_free(&classes);
}
