/* compiler/check/constants.c: what a module-level constant may contain, and constant cycles. */
#include "compiler/check/constants.h"
#include "compiler/check/symbol_text.h"

typedef struct Constants {
  MsCheckProgram *program;
  uint32_t module;
  uint8_t *state; /* per symbol: 0 unvisited, 1 visiting, 2 done */
  bool *reported; /* per symbol: a cycle was reported */
} Constants;

static const MsSymbol *find_symbol(const Constants *pass, MsName name) {
  const MsSymbolId *id = ms_scope_get(&pass->program->modules.ptr[pass->module].scope, name);
  return id == NULL ? NULL : &pass->program->symbols.ptr[*id];
}

static void reject(Constants *pass, MsPos pos) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "a constant takes literals, operators, collections, and other constants; "
                                 "compute this value in a function");
  ms_check_report(pass->program, pass->module, pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
}

static void reject_name(Constants *pass, const MsExpr *expr, const MsSymbol *symbol) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "a constant can refer only to other constants, but ");
  ms_strbuild_append(&text, ms_names_span(pass->program->names, expr->u.sym));
  ms_strbuild_append_text(&text, " is a ");
  ms_strbuild_append_text(&text, ms_symbol_description(pass->module, symbol));
  ms_strbuild_append_text(&text, "; compute the value in a function");
  ms_check_report(pass->program, pass->module, expr->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
}

static bool acceptable(Constants *pass, const MsExpr *expr);

static bool all_acceptable(Constants *pass, const MsExpr *const *items, uint32_t count) {
  for (uint32_t index = 0; index < count; index++) {
    if (!acceptable(pass, items[index])) {
      return false;
    }
  }
  return true;
}

static bool acceptable_text(Constants *pass, const MsExpr *expr) {
  for (uint32_t index = 0; index < expr->u.text.len; index++) {
    const MsExpr *part = expr->u.text.ptr[index].expr;
    if (part != NULL && !acceptable(pass, part)) {
      return false;
    }
  }
  return true;
}

static bool acceptable_map(Constants *pass, const MsExpr *expr) {
  for (uint32_t index = 0; index < expr->u.map.len; index++) {
    if (!acceptable(pass, expr->u.map.ptr[index].key) || !acceptable(pass, expr->u.map.ptr[index].value)) {
      return false;
    }
  }
  return true;
}

/* `Type.Case` names a payloadless case; the checker rejects other members. */
static bool acceptable_member(Constants *pass, const MsExpr *expr) {
  const MsExpr *left = expr->u.member.left;
  const MsSymbol *symbol = left->kind == MS_E_NAME ? find_symbol(pass, left->u.sym) : NULL;
  if (symbol == NULL || symbol->kind != MS_SYMBOL_TYPE) {
    reject(pass, expr->pos);
    return false;
  }
  return true;
}

static bool acceptable_name(Constants *pass, const MsExpr *expr) {
  const MsSymbol *symbol = find_symbol(pass, expr->u.sym);
  if (symbol != NULL && !ms_symbol_is_constant(symbol)) {
    reject_name(pass, expr, symbol);
    return false;
  }
  return true;
}

static bool acceptable(Constants *pass, const MsExpr *expr) {
  switch ((MsExprKind)expr->kind) {
  case MS_E_NUMBER:
  case MS_E_BOOL:
  case MS_E_VOID:
    return true;
  case MS_E_TEXT:
    return acceptable_text(pass, expr);
  case MS_E_LIST:
    return all_acceptable(pass, (const MsExpr *const *)expr->u.list.ptr, expr->u.list.len);
  case MS_E_MAP:
    return acceptable_map(pass, expr);
  case MS_E_UNARY:
    return acceptable(pass, expr->u.bin.left);
  case MS_E_BINARY:
    return acceptable(pass, expr->u.bin.left) && acceptable(pass, expr->u.bin.right);
  case MS_E_MEMBER:
    return acceptable_member(pass, expr);
  case MS_E_NAME:
    return acceptable_name(pass, expr);
  case MS_E_APPLY:
  case MS_E_INDEX:
  case MS_E_PROBE:
  case MS_E_LAMBDA:
  case MS_E_CALL:
  case MS_E_MATCH:
    reject(pass, expr->pos);
    return false;
  }
  return false;
}

static void visit(Constants *pass, MsSymbolId id);

static void walk_references(Constants *pass, const MsExpr *expr) {
  switch ((MsExprKind)expr->kind) {
  case MS_E_NAME: {
    const MsSymbol *symbol = find_symbol(pass, expr->u.sym);
    if (symbol != NULL && ms_symbol_is_constant(symbol) && symbol->module == pass->module) {
      visit(pass, (MsSymbolId)(symbol - pass->program->symbols.ptr));
    }
    return;
  }
  case MS_E_MEMBER:
    walk_references(pass, expr->u.member.left);
    return;
  case MS_E_UNARY:
    walk_references(pass, expr->u.bin.left);
    return;
  case MS_E_BINARY:
    walk_references(pass, expr->u.bin.left);
    walk_references(pass, expr->u.bin.right);
    return;
  case MS_E_LIST:
    for (uint32_t index = 0; index < expr->u.list.len; index++) {
      walk_references(pass, expr->u.list.ptr[index]);
    }
    return;
  case MS_E_MAP:
    for (uint32_t index = 0; index < expr->u.map.len; index++) {
      walk_references(pass, expr->u.map.ptr[index].key);
      walk_references(pass, expr->u.map.ptr[index].value);
    }
    return;
  case MS_E_TEXT:
    for (uint32_t index = 0; index < expr->u.text.len; index++) {
      if (expr->u.text.ptr[index].expr != NULL) {
        walk_references(pass, expr->u.text.ptr[index].expr);
      }
    }
    return;
  case MS_E_NUMBER:
  case MS_E_BOOL:
  case MS_E_VOID:
  case MS_E_APPLY:
  case MS_E_INDEX:
  case MS_E_PROBE:
  case MS_E_LAMBDA:
  case MS_E_CALL:
  case MS_E_MATCH:
    return;
  }
}

static void report_cycle(Constants *pass, MsSymbolId id) {
  if (pass->reported[id]) {
    return;
  }
  pass->reported[id] = true;
  const MsSymbol *symbol = &pass->program->symbols.ptr[id];
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "constant ");
  ms_strbuild_append(&text, ms_names_span(pass->program->names, symbol->name));
  ms_strbuild_append_text(&text, " depends on itself; break the cycle or compute the value in a function");
  ms_check_report(pass->program, pass->module, symbol->decl->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
}

static void visit(Constants *pass, MsSymbolId id) {
  if (pass->state[id] == 1) {
    report_cycle(pass, id);
    return;
  }
  if (pass->state[id] == 2) {
    return;
  }
  pass->state[id] = 1;
  walk_references(pass, pass->program->symbols.ptr[id].decl->u.konst.value);
  pass->state[id] = 2;
}

void ms_check_constants(MsCheckProgram *program, uint32_t module) {
  Constants pass = {.program = program, .module = module};
  const MsModule *tree = program->modules.ptr[module].tree;
  for (uint32_t index = 0; index < tree->ndecls; index++) {
    if (tree->decls[index]->kind == MS_D_CONST) {
      (void)acceptable(&pass, tree->decls[index]->u.konst.value);
    }
  }
  pass.state = MS_ARENA_NEW_ARRAY(&program->arena, uint8_t, program->symbols.len);
  pass.reported = MS_ARENA_NEW_ARRAY(&program->arena, bool, program->symbols.len);
  for (size_t id = 1; id < program->symbols.len; id++) {
    const MsSymbol *symbol = &program->symbols.ptr[id];
    if (symbol->module == module && ms_symbol_is_constant(symbol)) {
      visit(&pass, (MsSymbolId)id);
    }
  }
}
