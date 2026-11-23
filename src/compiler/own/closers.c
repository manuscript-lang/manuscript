/* compiler/own/closers.c: fills the `closers` fact table (see closers.h). */
#include "compiler/own/closers.h"
#include "compiler/own/bind.h"
#include "compiler/own/taken.h"
#include "compiler/own/result_borrows.h"

#include "base/sort.h"
#include "compiler/check/methods.h"
#include "compiler/check/properties.h"
#include "compiler/syntax/walk.h"

typedef struct Closers {
  MsCheckProgram *program;
  MsFacts *facts;
  uint32_t module;
  MsName close;
  size_t first;        /* the first closer of the callable being walked */
  uint32_t lambdas;    /* lambdas open around the node being visited */
  uint32_t escaping;   /* of those, the lambdas that outlive the statement: they take what they capture */
  MsNode receiver;     /* the receiver name of the call being visited */
  MsBindingList own;   /* parameters of the lambdas visited: used in their body they are not captures */
} Closers;

/* The `close()` method `ty` implements, or NULL. */
static const MsMethodEntry *close_method(Closers *pass, MsTy ty) {
  MsMethodMatchList found = {0};
  ms_check_find_method(pass->program, ty, pass->close, &found);
  const MsMethodEntry *entry = NULL;
  for (size_t index = 0; entry == NULL && index < found.len; index++) {
    const MsMethodEntry *candidate = found.ptr[index].entry;
    if (candidate != NULL && candidate->source->func.params.len == 0 && !candidate->source->func.external) {
      entry = candidate;
    }
  }
  ms_method_match_list_free(&found);
  return entry;
}

static uint16_t flags_of(const Closers *pass, const MsMethodEntry *entry) {
  const MsTyTable *types = &pass->program->types;
  const MsTy result = ms_ty_result(types, entry->ty);
  return (uint16_t)((ms_ty_is(types, result, MS_BUILTIN_Result) ? MS_CLOSER_FALLIBLE : 0) |
                   (entry->source->consuming ? MS_CLOSER_CONSUMES : 0) |
                   (entry->source->mutating ? MS_CLOSER_WRITES_BACK : 0));
}

bool ms_own_closer_of(MsCheckProgram *program, MsTy ty, MsCloser *out) {
  Closers pass = {.program = program, .close = ms_names_intern(program->names, ms_span_of_text("close"))};
  if (ty == MS_TY_NONE) {
    return false;
  }
  if (ms_ty_kind(&program->types, ty) == MS_TY_CONTRACT) {
    /* An interface value closes through its own `close` operation, which takes it. */
    *out = (MsCloser){.flags = MS_CLOSER_IFACE | MS_CLOSER_CONSUMES | MS_CLOSER_FALLIBLE};
    return ms_check_closeable(program, ty);
  }
  if (!ms_check_closeable(program, ty)) {
    /* A holder without a close of its own closes the resources it holds. */
    *out = (MsCloser){.flags = MS_CLOSER_PARTS | MS_CLOSER_CONSUMES};
    return ms_check_holds_resource(program, ty);
  }
  const MsMethodEntry *entry = close_method(&pass, ty);
  if (entry == NULL) {
    return false;
  }
  *out = (MsCloser){.method = {entry->module, entry->source->id}, .flags = flags_of(&pass, entry)};
  return true;
}

/* Records the closer of the binding site `node`, a binding `ref_kind`/`local` of type `ty`, when `ty` is closed
 * at scope end. A type variable may be closed in some instances, so it is recorded to be decided there. */
static void add_closer(Closers *pass, MsNode node, MsRefKind ref_kind, uint32_t local, MsTy ty) {
  MsCloser closer = {.node = node, .ref_kind = ref_kind, .local = local};
  if (ty != MS_TY_NONE && ms_ty_has_variable(&pass->program->types, ty)) {
    closer.flags = MS_CLOSER_GENERIC;
  } else if (!ms_own_closer_of(pass->program, ty, &closer)) {
    return;
  } else {
    closer.node = node;
    closer.ref_kind = ref_kind;
    closer.local = local;
  }
  ms_closer_list_push(&pass->facts->closers, closer);
}

static void visit_stmt(void *ctx, const MsStmt *stmt) {
  Closers *pass = ctx;
  if (stmt->kind == MS_S_IF && stmt->u.branch.binding != NULL && stmt->u.branch.binding->kind == MS_P_NAME &&
      (!stmt->u.branch.is_mutable || stmt->u.branch.cond->kind == MS_E_CALL)) {
    /* `if r := value:` owns the payload it binds, and so does `if var r = call():`, whose result has no place to
     * write back to. */
    const MsRef *bound = ms_facts_ref(pass->facts, stmt->u.branch.binding->id);
    if (bound != NULL && bound->kind == MS_REF_LOCAL) {
      const size_t before = pass->facts->closers.len;
      add_closer(pass, stmt->u.branch.binding->id, MS_REF_LOCAL, bound->local, ms_facts_type(pass->facts, stmt->u.branch.binding->id));
      if (stmt->u.branch.is_mutable && pass->facts->closers.len > before) {
        pass->facts->closers.ptr[before].flags |= MS_CLOSER_VAR;
      }
    }
    return;
  }
  if (stmt->kind == MS_S_FOR && ms_facts_use(pass->facts, stmt->u.each.iter->id) == MS_USE_MOVE) {
    /* A loop that consumes its list owns each element in its round. */
    const MsRef *item = ms_facts_ref(pass->facts, stmt->id);
    const MsTyTable *types = &pass->program->types;
    const MsTy list = ms_facts_type(pass->facts, stmt->u.each.iter->id);
    if (item != NULL && item->kind == MS_REF_LOCAL && list != MS_TY_NONE && ms_ty_arg_count(types, list) == 1) {
      add_closer(pass, stmt->id, MS_REF_LOCAL, item->local, ms_ty_args(types, list)[0]);
    }
    return;
  }
  if (stmt->kind != MS_S_BIND || stmt->u.bind.pattern->kind != MS_P_NAME) {
    return;
  }
  const MsNode node = stmt->u.bind.pattern->id;
  const MsRef *ref = ms_facts_ref(pass->facts, node);
  if (ref == NULL || ref->kind != MS_REF_LOCAL) {
    return;
  }
  const size_t before = pass->facts->closers.len;
  add_closer(pass, node, MS_REF_LOCAL, ref->local, ms_facts_type(pass->facts, node));
  if (stmt->u.bind.is_mutable && pass->facts->closers.len > before) {
    pass->facts->closers.ptr[before].flags |= MS_CLOSER_VAR;
  }
  if (stmt->u.bind.is_mutable && pass->facts->closers.len == before) {
    /* A `var` holds its value in a slot that drops it, so that a move out of the `var` leaves nothing to drop. */
    const MsCloser drop = {.node = node, .ref_kind = MS_REF_LOCAL, .local = ref->local,
                           .flags = MS_CLOSER_DROP | MS_CLOSER_CONSUMES};
    ms_closer_list_push(&pass->facts->closers, drop);
  }
}

/* The type of what binding `at` of an arm over the case `kase` of `scrutinee` binds. */
static MsTy bound_type(const Closers *pass, MsTy scrutinee, uint32_t kase, uint32_t at) {
  const MsTyTable *types = &pass->program->types;
  const bool result = ms_ty_is(types, scrutinee, MS_BUILTIN_Result);
  if (result || ms_ty_is(types, scrutinee, MS_BUILTIN_Optional)) {
    const uint32_t which = result ? kase : 0; /* `ok` and `error` carry the first and second argument, `some` its only one */
    return at == 0 && ms_ty_arg_count(types, scrutinee) > which ? ms_ty_args(types, scrutinee)[which] : MS_TY_NONE;
  }
  const MsDef *def = ms_check_def_of(pass->program, scrutinee);
  if (def == NULL || ms_ty_kind(types, scrutinee) != MS_TY_ALTERNATIVE || kase >= def->cases.len ||
      at >= def->cases.ptr[kase].fields.len) {
    return MS_TY_NONE;
  }
  return ms_check_part_type(pass->program, scrutinee, def, def->cases.ptr[kase].fields.ptr[at].ty);
}

/* `match call():` over an alternative: an arm that binds a part of a call's result owns it, so a resource it holds
 * closes where the arm ends unless the arm moves it on. The closer is keyed on the arm and names the first binding
 * that holds a resource. */
static void visit_match(void *ctx, const MsExpr *expr) {
  Closers *pass = ctx;
  const MsExpr *subject = expr->kind == MS_E_MATCH ? expr->u.match.scrutinee : NULL;
  const MsTy scrutinee = subject != NULL && subject->kind == MS_E_CALL ? ms_facts_type(pass->facts, subject->id) : MS_TY_NONE;
  if (scrutinee == MS_TY_NONE) {
    return;
  }
  for (uint32_t index = 0; index < expr->u.match.arms.len; index++) {
    const MsArm *arm = expr->u.match.arms.ptr[index];
    const MsRef *bound = ms_facts_ref(pass->facts, arm->id);
    if (bound == NULL || bound->kind != MS_REF_CASE) {
      continue;
    }
    for (uint32_t at = 0; at < arm->bindings.len; at++) {
      const MsTy ty = bound_type(pass, scrutinee, bound->index, at);
      if (ty != MS_TY_NONE && ms_check_holds_resource(pass->program, ty)) {
        add_closer(pass, arm->id, MS_REF_LOCAL, bound->local + at, ty);
        break;
      }
    }
  }
}

/* A `move` parameter is owned by its body. */
static void add_params(Closers *pass, MsParams params, uint32_t taken) {
  for (uint32_t index = 0; index < params.len; index++) {
    const MsNode node = params.ptr[index]->id;
    const MsRef *ref = ms_facts_ref(pass->facts, node);
    if ((params.ptr[index]->moving || (index < 32 && (taken >> index & 1u) != 0)) && ref != NULL && ref->kind == MS_REF_PARAM) {
      add_closer(pass, node, MS_REF_PARAM, ref->local, ms_facts_type(pass->facts, node));
    }
  }
}

static const MsMethodEntry *entry_of(const Closers *pass, const MsMethod *method) {
  for (size_t index = 0; index < pass->program->methods.len; index++) {
    const MsMethodEntry *entry = &pass->program->methods.ptr[index];
    if (entry->module == pass->module && entry->source == method) {
      return entry;
    }
  }
  return NULL;
}

/* Whether a field of `ty` holds a resource. */
static bool fields_hold_resource(Closers *pass, MsTy ty) {
  const MsDef *def = ms_check_def_of(pass->program, ty);
  for (size_t index = 0; def != NULL && ms_ty_kind(&pass->program->types, ty) == MS_TY_TYPE && index < def->fields.len; index++) {
    if (ms_check_holds_resource(pass->program, ms_check_part_type(pass->program, ty, def, def->fields.ptr[index].ty))) {
      return true;
    }
  }
  return false;
}

/* The receiver of a method that consumes it is owned by the body; in `close` itself it only closes its fields. */
static void add_receiver(Closers *pass, const MsMethod *method) {
  const MsMethodEntry *entry = entry_of(pass, method);
  if (method->consuming && entry != NULL && method->func.name == pass->close && fields_hold_resource(pass, entry->receiver) &&
      !ms_ty_has_variable(&pass->program->types, entry->receiver)) {
    ms_closer_list_push(&pass->facts->closers, (MsCloser){.node = method->id, .ref_kind = MS_REF_PARAM, .local = 0,
                                                            .flags = MS_CLOSER_PARTS | MS_CLOSER_CONSUMES | MS_CLOSER_FIELDS});
    return;
  }
  if (!method->consuming || entry == NULL || method->func.name == pass->close) {
    return;
  }
  add_closer(pass, method->id, MS_REF_PARAM, 0, entry->receiver);
}

static int64_t compare(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  const MsNode left = ((const MsCloser *)(const void *)a)->node;
  const MsNode right = ((const MsCloser *)(const void *)b)->node;
  return left < right ? -1 : left > right;
}

static MsCloser *find(Closers *pass, MsRefKind ref_kind, uint32_t local) {
  for (size_t index = pass->first; index < pass->facts->closers.len; index++) {
    MsCloser *closer = &pass->facts->closers.ptr[index];
    if (closer->ref_kind == ref_kind && closer->local == local) {
      return closer;
    }
  }
  return NULL;
}

static void flag(Closers *pass, const MsRef *ref, uint16_t flags) {
  MsCloser *closer = ref == NULL ? NULL : find(pass, ref->kind, ref->local);
  if (closer != NULL) {
    closer->flags = (uint16_t)(closer->flags | flags);
  }
}

/* A member assigned in a closed `var`, and a `var` argument or receiver, change the binding in place. */
static void flag_root(Closers *pass, const MsExpr *place, uint16_t flags) {
  const MsExpr *root = place;
  while (root->kind == MS_E_MEMBER) {
    root = root->u.member.left;
  }
  if (root->kind == MS_E_NAME) {
    flag(pass, ms_facts_ref(pass->facts, root->id), flags);
  }
}

/* A call that returns a value which may hold a resource (or whose type is not known yet) may take a part out of
 * a holder it is given, or called on: a holder closes whole only when no call does. */
/* Whether `call` leaves the holder `value` whole: its result is a view of it, or the callee changes it in place (a
 * `var` argument, a mutating method), so what it hands out leaves the holder consistent. */
static bool keeps_holder(const Closers *pass, const MsExpr *call, const MsExpr *value) {
  const MsCall *fact = ms_facts_call(pass->facts, call->id);
  for (uint32_t index = 0; fact != NULL && index < fact->arg_count; index++) {
    if (fact->args[index].source != MS_ARG_WRITTEN || fact->args[index].node.node != value->id) {
      continue;
    }
    if (ms_own_call_borrows(pass->program, fact, index) || (fact->args[index].flags & MS_PARAM_VAR) != 0) {
      return true;
    }
    for (size_t at = 0; at < pass->program->methods.len; at++) {
      const MsMethodEntry *entry = &pass->program->methods.ptr[at];
      if (entry->module == fact->callee.decl.module && entry->source->id == fact->callee.decl.node && entry->source->mutating &&
          !entry->source->consuming) {
        return true;
      }
    }
  }
  return false;
}

/* A parameter the callable owns (`move`) hands its payload out through a view of it at its last use; a borrowed
 * parameter has no closer, so flagging it changes nothing. */
static bool names_param(const Closers *pass, const MsExpr *place) {
  const MsRef *ref = place->kind == MS_E_NAME ? ms_facts_ref(pass->facts, place->id) : NULL;
  return ref != NULL && ref->kind == MS_REF_PARAM;
}

static void flag_taken_by(Closers *pass, const MsExpr *call) {
  const MsTy result = ms_facts_type(pass->facts, call->id);
  if (result == MS_TY_NONE ||
      !(ms_ty_has_variable(&pass->program->types, result) || ms_check_holds_resource(pass->program, result))) {
    return;
  }
  for (uint32_t index = 0; index < call->u.call.args.len; index++) {
    const MsExpr *arg = call->u.call.args.ptr[index].value;
    const MsTy arg_ty = ms_facts_type(pass->facts, arg->id);
    /* An argument that holds no resource has none to hand to the result. */
    if (arg_ty != MS_TY_NONE && !ms_ty_has_variable(&pass->program->types, arg_ty) &&
        !ms_check_holds_resource(pass->program, arg_ty)) {
      continue;
    }
    if (!keeps_holder(pass, call, arg) || names_param(pass, arg)) {
      flag_root(pass, arg, MS_CLOSER_TAKEN);
    }
  }
  if (call->u.call.callee->kind == MS_E_MEMBER &&
      (!keeps_holder(pass, call, call->u.call.callee->u.member.left) || names_param(pass, call->u.call.callee->u.member.left))) {
    flag_root(pass, call->u.call.callee->u.member.left, MS_CLOSER_TAKEN);
  }
}

static void visit_call_changes(Closers *pass, const MsExpr *call) {
  const MsCall *fact = ms_facts_call(pass->facts, call->id);
  if (fact == NULL) {
    return;
  }
  for (uint32_t index = 0; index < fact->arg_count; index++) {
    const MsCallArg *arg = &fact->args[index];
    const MsExpr *written = NULL;
    if (arg->source != MS_ARG_WRITTEN) {
      continue;
    }
    for (uint32_t at = 0; at < call->u.call.args.len; at++) {
      if (call->u.call.args.ptr[at].value->id == arg->node.node) {
        written = call->u.call.args.ptr[at].value;
      }
    }
    if (written == NULL && call->u.call.callee->kind == MS_E_MEMBER && call->u.call.callee->u.member.left->id == arg->node.node) {
      written = call->u.call.callee->u.member.left;
    }
    const MsMethodEntry *entry = NULL;
    for (size_t at = 0; fact->callee.kind == MS_REF_METHOD && index == 0 && at < pass->program->methods.len; at++) {
      const MsMethodEntry *candidate = &pass->program->methods.ptr[at];
      if (candidate->module == fact->callee.decl.module && candidate->source->id == fact->callee.decl.node) {
        entry = candidate;
      }
    }
    if (written != NULL && ((arg->flags & MS_PARAM_VAR) != 0 || (entry != NULL && entry->source->mutating))) {
      flag_root(pass, written, MS_CLOSER_MUTATED);
    }
  }
}

static void visit_stmt_changes(void *ctx, const MsStmt *stmt) {
  Closers *pass = ctx;
  if (stmt->kind == MS_S_ASSIGN && stmt->u.assign.member_target && stmt->u.assign.target != NULL) {
    flag_root(pass, stmt->u.assign.target, MS_CLOSER_MUTATED);
    if (stmt->u.assign.target->kind == MS_E_MEMBER && !stmt->u.assign.has_compound) {
      /* A field that holds a resource closes the value an assignment replaces. */
      add_closer(pass, stmt->u.assign.target->id, MS_REF_LOCAL, 0, ms_facts_type(pass->facts, stmt->u.assign.target->id));
    }
  }
}

/* The uses of a closed binding that decide how its scope may close it. */
static void visit_expr(void *ctx, const MsExpr *expr) {
  Closers *pass = ctx;
  if (expr->kind == MS_E_LAMBDA) {
    pass->lambdas++;
    pass->escaping += ms_facts_use(pass->facts, expr->id) == MS_USE_MOVE ? 1u : 0u;
    for (size_t index = 0; index < expr->u.lambda.params.len; index++) {
      ms_binding_list_push(&pass->own, expr->u.lambda.params.ptr[index]->id);
    }
    /* A parameter the lambda's function type takes by `move` is owned by its body, as a function's is. */
    const MsTy fn_ty = ms_facts_type(pass->facts, expr->id);
    const MsTyTable *types = &pass->program->types;
    for (uint32_t index = 0; fn_ty != MS_TY_NONE && ms_ty_kind(types, fn_ty) == MS_TY_FUNCTION &&
                             index < expr->u.lambda.params.len && index < ms_ty_param_count(types, fn_ty);
         index++) {
      const MsNode node = expr->u.lambda.params.ptr[index]->id;
      const MsRef *ref = ms_facts_ref(pass->facts, node);
      if ((ms_ty_params(types, fn_ty)[index].flags & MS_PARAM_MOVE) != 0 && ref != NULL && ref->kind == MS_REF_PARAM) {
        add_closer(pass, node, MS_REF_PARAM, ref->local, ms_facts_type(pass->facts, node));
      }
    }
    return;
  }
  if (expr->kind == MS_E_CALL) {
    visit_call_changes(pass, expr);
    flag_taken_by(pass, expr);
    pass->receiver = expr->u.call.callee->kind == MS_E_MEMBER ? expr->u.call.callee->u.member.left->id : 0;
  }
  if (expr->kind == MS_E_CALL && expr->u.call.args.len == 0 && expr->u.call.callee->kind == MS_E_MEMBER &&
      expr->u.call.callee->u.member.name == pass->close && expr->u.call.callee->u.member.left->kind == MS_E_NAME) {
    flag(pass, ms_facts_ref(pass->facts, expr->u.call.callee->u.member.left->id), MS_CLOSER_EXPLICIT);
  }
  if (expr->kind == MS_E_UNARY && expr->op == MS_U_TRY && expr->u.bin.left->kind == MS_E_NAME &&
      ms_facts_use(pass->facts, expr->id) == MS_USE_MOVE) { /* `r?` moves the payload out of the Result `r` */
    flag(pass, ms_facts_ref(pass->facts, expr->u.bin.left->id), MS_CLOSER_PARTIAL);
  }
  const MsExpr *root = expr;
  while (root->kind == MS_E_MEMBER) {
    root = root->u.member.left;
  }
  if (expr->kind != MS_E_NAME && expr->kind != MS_E_MEMBER) {
    return;
  }
  const MsRef *ref = root->kind == MS_E_NAME ? ms_facts_ref(pass->facts, root->id) : NULL;
  if (ref == NULL || (ref->kind != MS_REF_LOCAL && ref->kind != MS_REF_PARAM)) {
    return;
  }
  bool own_param = false;
  for (size_t index = 0; index < pass->own.len; index++) {
    own_param = own_param || pass->own.ptr[index] == ref->decl.node;
  }
  if (pass->lambdas != 0 && own_param) {
    return; /* a lambda's own parameter, not a capture: judged by its own closer */
  }
  if (pass->lambdas != 0) {
    /* A local a lambda that outlives the statement captures moves into it, on the paths that build the lambda, and its
     * scope closes it on the others; any other capture leaves the ownership to the closure. */
    flag(pass, ref, pass->escaping != 0 && ref->kind == MS_REF_LOCAL ? MS_CLOSER_MOVED : MS_CLOSER_PARTIAL);
  } else if (ms_facts_use(pass->facts, expr->id) == MS_USE_MOVE) {
    flag(pass, ref, expr->kind != MS_E_NAME ? MS_CLOSER_PARTIAL : expr->id == pass->receiver ? MS_CLOSER_MOVED | MS_CLOSER_RECEIVER : MS_CLOSER_MOVED);
  }
}

static void leave_expr(void *ctx, const MsExpr *expr) {
  Closers *pass = ctx;
  if (expr->kind == MS_E_LAMBDA) {
    pass->lambdas--;
    pass->escaping -= ms_facts_use(pass->facts, expr->id) == MS_USE_MOVE ? 1u : 0u;
  }
}

static void callable(Closers *pass, MsNode node, const MsMethod *method, MsParams params, MsStmts body) {
  pass->first = pass->facts->closers.len;
  pass->lambdas = 0;
  pass->escaping = 0;
  pass->own.len = 0;
  if (method != NULL) {
    add_receiver(pass, method);
  }
  add_params(pass, params, ms_own_taken_mask(pass->program, pass->module, node));
  const MsVisitor binds = {.ctx = pass, .stmt = visit_stmt, .expr = visit_match};
  ms_walk_callable(&binds, params, body);
  const MsVisitor uses = {.ctx = pass, .stmt = visit_stmt_changes, .expr = visit_expr, .leave_expr = leave_expr};
  ms_walk_callable(&uses, params, body);
}

void ms_own_closers(MsCheckProgram *program) {
  Closers pass = {.program = program, .close = ms_names_intern(program->names, ms_span_of_text("close"))};
  for (uint32_t module = 0; module < program->modules.len; module++) {
    pass.facts = &program->modules.ptr[module].facts;
    pass.module = module;
    const MsModule *tree = program->modules.ptr[module].tree;
    for (uint32_t index = 0; index < tree->ndecls; index++) {
      const MsDecl *decl = tree->decls[index];
      if (decl->kind == MS_D_FN) {
        callable(&pass, decl->id, NULL, decl->u.fn.params, decl->u.fn.body);
      }
      if (decl->kind == MS_D_TEST) {
        callable(&pass, decl->id, NULL, (MsParams){0}, decl->u.test.body);
      }
      for (uint32_t at = 0; decl->kind == MS_D_IMPL && at < decl->u.impl.methods.len; at++) {
        const MsMethod *method = decl->u.impl.methods.ptr[at];
        callable(&pass, method->id, method, method->func.params, method->func.body);
      }
    }
    ms_sort((uint8_t *)(void *)pass.facts->closers.ptr, pass.facts->closers.len, sizeof(MsCloser), compare, NULL);
  }
}
