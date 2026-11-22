/* compiler/own/closers.c: fills the `closers` fact table (see closers.h). */
#include "compiler/own/closers.h"

#include "base/sort.h"
#include "compiler/check/methods.h"
#include "compiler/check/properties.h"
#include "compiler/own/bind.h"
#include "compiler/syntax/walk.h"

typedef struct Closers {
  MsCheckProgram *program;
  MsFacts *facts;
  MsName close;
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

static void visit_stmt(void *ctx, const MsStmt *stmt) {
  Closers *pass = ctx;
  if (stmt->kind != MS_S_BIND || stmt->u.bind.pattern->kind != MS_P_NAME) {
    return;
  }
  const MsTy ty = ms_facts_type(pass->facts, stmt->u.bind.pattern->id);
  if (ty == MS_TY_NONE || !ms_check_closeable(pass->program, ty)) {
    return;
  }
  const MsMethodEntry *entry = close_method(pass, ty);
  if (entry == NULL) {
    return;
  }
  ms_closer_list_push(&pass->facts->closers,
                      (MsCloser){.node = stmt->u.bind.pattern->id, .method = {entry->module, entry->source->id},
                                 .flags = flags_of(pass, entry)});
}

static int64_t compare(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  const MsNode left = ((const MsCloser *)(const void *)a)->node;
  const MsNode right = ((const MsCloser *)(const void *)b)->node;
  return left < right ? -1 : left > right;
}

static MsCloser *find(Closers *pass, MsNode node) {
  for (size_t index = 0; index < pass->facts->closers.len; index++) {
    if (pass->facts->closers.ptr[index].node == node) {
      return &pass->facts->closers.ptr[index];
    }
  }
  return NULL;
}

static void flag(Closers *pass, MsNode binding, uint8_t flags) {
  MsCloser *closer = find(pass, binding);
  if (closer != NULL) {
    closer->flags = (uint8_t)(closer->flags | flags);
  }
}

/* A use that moves the binding, or a closure that captures it. */
static void note_use(Closers *pass, const MsExpr *expr) {
  uint32_t binding = 0;
  if (expr->kind == MS_E_LAMBDA) {
    MsBindingList captures = ms_bind_captures(pass->facts, expr);
    for (size_t index = 0; index < captures.len; index++) {
      flag(pass, captures.ptr[index], MS_CLOSER_MOVED);
    }
    ms_binding_list_free(&captures);
    return;
  }
  const MsExpr *root = expr;
  while (root->kind == MS_E_MEMBER) {
    root = root->u.member.left;
  }
  if ((expr->kind == MS_E_NAME || expr->kind == MS_E_MEMBER) && ms_facts_use(pass->facts, expr->id) == MS_USE_MOVE &&
      root->kind == MS_E_NAME && ms_bind_of(pass->facts, root->id, &binding)) {
    flag(pass, binding, MS_CLOSER_MOVED);
  }
}

/* `x.close()` by hand on a closed binding, and the uses that move one. */
static void visit_expr(void *ctx, const MsExpr *expr) {
  Closers *pass = ctx;
  note_use(pass, expr);
  if (expr->kind != MS_E_CALL || expr->u.call.args.len != 0 || expr->u.call.callee->kind != MS_E_MEMBER ||
      expr->u.call.callee->u.member.name != pass->close) {
    return;
  }
  const MsExpr *receiver = expr->u.call.callee->u.member.left;
  uint32_t binding = 0;
  if (receiver->kind != MS_E_NAME || !ms_bind_of(pass->facts, receiver->id, &binding)) {
    return;
  }
  flag(pass, binding, MS_CLOSER_EXPLICIT);
}

void ms_own_closers(MsCheckProgram *program) {
  Closers pass = {.program = program, .close = ms_names_intern(program->names, ms_span_of_text("close"))};
  for (uint32_t module = 0; module < program->user_modules; module++) {
    pass.facts = &program->modules.ptr[module].facts;
    const MsModule *tree = program->modules.ptr[module].tree;
    const MsVisitor binds = {.ctx = &pass, .stmt = visit_stmt};
    for (uint32_t index = 0; index < tree->ndecls; index++) {
      ms_walk_decl(&binds, tree->decls[index]);
    }
    ms_sort((uint8_t *)(void *)pass.facts->closers.ptr, pass.facts->closers.len, sizeof(MsCloser), compare, NULL);
    const MsVisitor hand = {.ctx = &pass, .expr = visit_expr};
    for (uint32_t index = 0; index < tree->ndecls; index++) {
      ms_walk_decl(&hand, tree->decls[index]);
    }
  }
}
