/* compiler/own/closers.c: fills the `closers` fact table (see closers.h). */
#include "compiler/own/closers.h"

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

static uint8_t flags_of(const Closers *pass, const MsMethodEntry *entry) {
  const MsTyTable *types = &pass->program->types;
  const MsTy result = ms_ty_result(types, entry->ty);
  return (uint8_t)((ms_ty_is(types, result, MS_BUILTIN_Result) ? MS_CLOSER_FALLIBLE : 0) |
                   (entry->source->consuming ? MS_CLOSER_CONSUMES : 0) |
                   (entry->source->mutating ? MS_CLOSER_WRITES_BACK : 0));
}

bool ms_own_closer_of(MsCheckProgram *program, MsTy ty, MsCloser *out) {
  Closers pass = {.program = program, .close = ms_names_intern(program->names, ms_span_of_text("close"))};
  if (ty == MS_TY_NONE || !ms_check_closeable(program, ty)) {
    return false;
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
  if (ty != MS_TY_NONE && ms_ty_kind(&pass->program->types, ty) == MS_TY_VARIABLE) {
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
  if (stmt->kind != MS_S_BIND || stmt->u.bind.pattern->kind != MS_P_NAME) {
    return;
  }
  const MsNode node = stmt->u.bind.pattern->id;
  const MsRef *ref = ms_facts_ref(pass->facts, node);
  if (ref != NULL && ref->kind == MS_REF_LOCAL) {
    add_closer(pass, node, MS_REF_LOCAL, ref->local, ms_facts_type(pass->facts, node));
  }
}

/* A `move` parameter is owned by its body. */
static void add_params(Closers *pass, MsParams params) {
  for (uint32_t index = 0; index < params.len; index++) {
    const MsNode node = params.ptr[index]->id;
    const MsRef *ref = ms_facts_ref(pass->facts, node);
    if (params.ptr[index]->moving && ref != NULL && ref->kind == MS_REF_PARAM) {
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

/* The receiver of a method that consumes it is owned by the body, except in `close` itself. */
static void add_receiver(Closers *pass, const MsMethod *method) {
  const MsMethodEntry *entry = entry_of(pass, method);
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

static void flag(Closers *pass, const MsRef *ref, uint8_t flags) {
  MsCloser *closer = ref == NULL ? NULL : find(pass, ref->kind, ref->local);
  if (closer != NULL) {
    closer->flags = (uint8_t)(closer->flags | flags);
  }
}

/* A member assigned in a closed `var`, and a `var` argument or receiver, change the binding in place. */
static void flag_root(Closers *pass, const MsExpr *place, uint8_t flags) {
  const MsExpr *root = place;
  while (root->kind == MS_E_MEMBER) {
    root = root->u.member.left;
  }
  if (root->kind == MS_E_NAME) {
    flag(pass, ms_facts_ref(pass->facts, root->id), flags);
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
      flag_root(pass, written, MS_CLOSER_PARTIAL);
    }
  }
}

static void visit_stmt_changes(void *ctx, const MsStmt *stmt) {
  Closers *pass = ctx;
  if (stmt->kind == MS_S_ASSIGN && stmt->u.assign.member_target && stmt->u.assign.target != NULL) {
    flag_root(pass, stmt->u.assign.target, MS_CLOSER_PARTIAL);
  }
}

/* The uses of a closed binding that decide how its scope may close it. */
static void visit_expr(void *ctx, const MsExpr *expr) {
  Closers *pass = ctx;
  if (expr->kind == MS_E_LAMBDA) {
    pass->lambdas++;
    return;
  }
  if (expr->kind == MS_E_CALL) {
    visit_call_changes(pass, expr);
  }
  if (expr->kind == MS_E_CALL && expr->u.call.args.len == 0 && expr->u.call.callee->kind == MS_E_MEMBER &&
      expr->u.call.callee->u.member.name == pass->close && expr->u.call.callee->u.member.left->kind == MS_E_NAME) {
    flag(pass, ms_facts_ref(pass->facts, expr->u.call.callee->u.member.left->id), MS_CLOSER_EXPLICIT);
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
  if (pass->lambdas != 0) {
    flag(pass, ref, MS_CLOSER_PARTIAL);
  } else if (ms_facts_use(pass->facts, expr->id) == MS_USE_MOVE) {
    flag(pass, ref, expr->kind == MS_E_NAME ? MS_CLOSER_MOVED : MS_CLOSER_PARTIAL);
  }
}

static void leave_expr(void *ctx, const MsExpr *expr) {
  Closers *pass = ctx;
  if (expr->kind == MS_E_LAMBDA) {
    pass->lambdas--;
  }
}

static void callable(Closers *pass, const MsMethod *method, MsParams params, MsStmts body) {
  pass->first = pass->facts->closers.len;
  pass->lambdas = 0;
  if (method != NULL) {
    add_receiver(pass, method);
  }
  add_params(pass, params);
  const MsVisitor binds = {.ctx = pass, .stmt = visit_stmt};
  ms_walk_callable(&binds, params, body);
  const MsVisitor uses = {.ctx = pass, .stmt = visit_stmt_changes, .expr = visit_expr, .leave_expr = leave_expr};
  ms_walk_callable(&uses, params, body);
}

void ms_own_closers(MsCheckProgram *program) {
  Closers pass = {.program = program, .close = ms_names_intern(program->names, ms_span_of_text("close"))};
  for (uint32_t module = 0; module < program->user_modules; module++) {
    pass.facts = &program->modules.ptr[module].facts;
    pass.module = module;
    const MsModule *tree = program->modules.ptr[module].tree;
    for (uint32_t index = 0; index < tree->ndecls; index++) {
      const MsDecl *decl = tree->decls[index];
      if (decl->kind == MS_D_FN) {
        callable(&pass, NULL, decl->u.fn.params, decl->u.fn.body);
      }
      for (uint32_t at = 0; decl->kind == MS_D_IMPL && at < decl->u.impl.methods.len; at++) {
        const MsMethod *method = decl->u.impl.methods.ptr[at];
        callable(&pass, method, method->func.params, method->func.body);
      }
    }
    ms_sort((uint8_t *)(void *)pass.facts->closers.ptr, pass.facts->closers.len, sizeof(MsCloser), compare, NULL);
  }
}
