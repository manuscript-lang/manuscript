/* compiler/check/recursion.c: finite generic applications of type declarations.
 *
 * A type, alternative or interface may refer to a generic declaration of the program, itself included, only
 * with the type arguments of the application being followed, or its instances would never end. The graph has one
 * node per declaration and an edge for every mention of a declaration in a field, case field or operation, with
 * the arguments written there. Only nodes that lie on a path to a cycle are walked.
 *
 * Ownership: the pass owns its node edges and tables and frees them before returning. */
#include "compiler/check/program.h"
#include "compiler/check/methods.h"
#include "compiler/check/resolve_internal.h"
#include "compiler/syntax/walk.h"

typedef struct Edge {
  MsSymbolId owner;
  MsSymbolId target;
  const MsTy *args; /* the arguments written at the mention, copied to the arena */
  size_t arg_count;
  bool plain;      /* an expression of a function body: the diagnostic names no field */
  MsPos pos;
  MsName part[2];  /* the case and the field, the field, or the operation: the end of the diagnostic's name */
} Edge;

MS_LIST_DEFINE(EdgeList, edge_list, Edge)

typedef struct Node {
  bool present;
  bool recursive;
  EdgeList edges;     /* owned */
  const MsTy *variables; /* the declaration's type variables */
  size_t variable_count;
  const MsTy *active; /* the arguments of the application being followed, or NULL */
  size_t active_count;
} Node;

typedef struct Pass {
  MsCheckProgram *program;
  Node *nodes;      /* owned: by symbol id */
  MsTyList visited; /* owned: the applications already followed, as interned types */
  EdgeList reported; /* owned: the edges already reported */
} Pass;

static bool is_node(const MsCheckProgram *program, MsSymbolId id) {
  const MsSymbol *symbol = &program->symbols.ptr[id];
  return symbol->module < program->user_modules && symbol->kind == MS_SYMBOL_TYPE && symbol->def != 0 && symbol->decl != NULL &&
         (symbol->decl->kind == MS_D_TYPE || symbol->decl->kind == MS_D_ENUM || symbol->decl->kind == MS_D_INTERFACE);
}

/* Adds an edge for every declaration `ty` mentions, nested arguments and function parts included. */
static void collect(Pass *pass, MsSymbolId owner, MsTy ty, MsPos pos, MsName first, MsName second) {
  const MsCheckProgram *program = pass->program;
  const MsTyTable *types = &program->types;
  if (ty == MS_TY_NONE) {
    return;
  }
  const MsTyKind kind = ms_ty_kind(types, ty);
  const uint32_t def = kind == MS_TY_TYPE || kind == MS_TY_ALTERNATIVE || kind == MS_TY_CONTRACT ? ms_ty_row(types, ty)->def : 0;
  if (def != 0) {
    const MsSymbolId target = ms_defs_get(&program->defs, def)->symbol;
    if (target != 0 && pass->nodes[target].present) {
      const size_t count = ms_ty_arg_count(types, ty);
      MsTy *copy = MS_ARENA_NEW_ARRAY(&pass->program->arena, MsTy, count + 1);
      for (size_t at = 0; at < count; at++) {
        copy[at] = ms_ty_args(types, ty)[at];
      }
      edge_list_push(&pass->nodes[owner].edges, (Edge){.owner = owner, .target = target, .args = copy, .arg_count = count, .pos = pos, .part = {first, second}});
    }
  }
  for (size_t index = 0; index < ms_ty_arg_count(types, ty); index++) {
    collect(pass, owner, ms_ty_args(types, ty)[index], pos, first, second);
  }
  for (size_t index = 0; index < ms_ty_param_count(types, ty); index++) {
    collect(pass, owner, ms_ty_params(types, ty)[index].ty, pos, first, second);
  }
  collect(pass, owner, ms_ty_result(types, ty), pos, first, second);
}

/* The edges of one declaration: its fields, its case fields and its operations. */
static void collect_declaration(Pass *pass, MsSymbolId id) {
  const MsSymbol *symbol = &pass->program->symbols.ptr[id];
  const MsDef *def = ms_defs_get(&pass->program->defs, symbol->def);
  const MsDecl *decl = symbol->decl;
  for (size_t index = 0; decl->kind == MS_D_TYPE && index < def->fields.len && index < decl->u.type.fields.len; index++) {
    collect(pass, id, def->fields.ptr[index].ty, decl->u.type.fields.ptr[index]->pos, def->fields.ptr[index].name, MS_NAME_EMPTY);
  }
  for (size_t index = 0; decl->kind == MS_D_ENUM && index < def->cases.len && index < decl->u.enumeration.cases.len; index++) {
    const MsTyCase *row = &def->cases.ptr[index];
    const MsCase *written = decl->u.enumeration.cases.ptr[index];
    for (size_t at = 0; at < row->fields.len && at < written->fields.len; at++) {
      collect(pass, id, row->fields.ptr[at].ty, written->fields.ptr[at]->pos, row->name, row->fields.ptr[at].name);
    }
  }
  for (size_t index = 0; decl->kind == MS_D_INTERFACE && index < def->operations.len && index < decl->u.iface.methods.len; index++) {
    collect(pass, id, def->operations.ptr[index].ty, decl->u.iface.methods.ptr[index]->pos, def->operations.ptr[index].name, MS_NAME_EMPTY);
  }
}

/* Marks the nodes that can reach a cycle: removing nodes without outgoing edges, and their incoming edges, leaves
 * exactly those. */
static void mark_recursive(Pass *pass) {
  const size_t count = pass->program->symbols.len;
  size_t *degree = MS_ARENA_NEW_ARRAY(&pass->program->arena, size_t, count);
  bool changed = true;
  for (size_t id = 1; id < count; id++) {
    degree[id] = pass->nodes[id].edges.len;
    pass->nodes[id].recursive = pass->nodes[id].present;
  }
  while (changed) {
    changed = false;
    for (size_t id = 1; id < count; id++) {
      size_t live = 0;
      for (size_t at = 0; pass->nodes[id].recursive && at < pass->nodes[id].edges.len; at++) {
        live += pass->nodes[pass->nodes[id].edges.ptr[at].target].recursive ? 1 : 0;
      }
      if (pass->nodes[id].recursive && live == 0) {
        pass->nodes[id].recursive = false;
        changed = true;
      }
      degree[id] = live;
    }
  }
}

static MsTy application(Pass *pass, MsSymbolId id, const MsTy *args, size_t count) {
  return resolver_apply(pass->program, pass->program->symbols.ptr[id].ty, args, count);
}

static bool seen_before(Pass *pass, MsTy application_ty) {
  for (size_t index = 0; index < pass->visited.len; index++) {
    if (pass->visited.ptr[index] == application_ty) {
      return true;
    }
  }
  ms_ty_list_push(&pass->visited, application_ty);
  return false;
}

static bool same_arguments(const MsTy *left, size_t left_count, const MsTy *right, size_t right_count) {
  if (left_count != right_count) {
    return false;
  }
  for (size_t index = 0; index < left_count; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

static void report_edge(Pass *pass, const Edge *edge) {
  const MsCheckProgram *program = pass->program;
  for (size_t index = 0; index < pass->reported.len; index++) {
    if (pass->reported.ptr[index].pos.offset == edge->pos.offset &&
        program->symbols.ptr[pass->reported.ptr[index].owner].module == program->symbols.ptr[edge->owner].module) {
      return;
    }
  }
  edge_list_push(&pass->reported, *edge);
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "recursive generic applications must preserve their parameters");
  if (edge->plain) {
    ms_strbuild_append_text(&text, "; a type may refer to itself only with the same type arguments (e.g. List[Node[T]] inside Node[T])");
  } else {
    ms_strbuild_append_text(&text, " in ");
    ms_strbuild_append(&text, ms_names_span(program->names, program->symbols.ptr[edge->owner].name));
    for (size_t index = 0; index < 2; index++) {
      if (edge->part[index] != MS_NAME_EMPTY) {
        ms_strbuild_append_text(&text, ".");
        ms_strbuild_append(&text, ms_names_span(program->names, edge->part[index]));
      }
    }
    ms_strbuild_append_text(&text, "; keep the same type arguments in the same positions along a recursive cycle");
  }
  ms_check_report(pass->program, program->symbols.ptr[edge->owner].module, edge->pos,
                  MS_CHECK_TYPE, ms_strbuild_finish(&text));
}

/* Follows the application of `id` to `args`, comparing every mention of an active declaration with the application
 * that is active for it. */
static void visit(Pass *pass, MsSymbolId id, const MsTy *args, size_t count) {
  MsCheckProgram *program = pass->program;
  if (seen_before(pass, application(pass, id, args, count))) {
    return;
  }
  Node *node = &pass->nodes[id];
  node->active = args;
  node->active_count = count;
  for (size_t index = 0; index < node->edges.len; index++) {
    const Edge *edge = &node->edges.ptr[index];
    if (!pass->nodes[edge->target].recursive) {
      continue;
    }
    const size_t wanted = edge->arg_count;
    MsTy *next = MS_ARENA_NEW_ARRAY(&program->arena, MsTy, wanted + 1);
    for (size_t at = 0; at < wanted; at++) {
      next[at] = ms_ty_subst(&program->types, edge->args[at], node->variables, args, count < node->variable_count ? count : node->variable_count);
    }
    const Node *target = &pass->nodes[edge->target];
    if (target->active != NULL) {
      if (!same_arguments(target->active, target->active_count, next, wanted)) {
        report_edge(pass, edge);
      }
      continue;
    }
    visit(pass, edge->target, next, wanted);
  }
  node->active = NULL;
}

/* Walks every node that can reach a cycle from its own variables, then frees the graph. */
static void finish(Pass *pass) {
  MsCheckProgram *program = pass->program;
  mark_recursive(pass);
  for (MsSymbolId id = 1; id < program->symbols.len; id++) {
    if (pass->nodes[id].recursive) {
      visit(pass, id, pass->nodes[id].variables, pass->nodes[id].variable_count);
    }
  }
  for (MsSymbolId id = 1; id < program->symbols.len; id++) {
    edge_list_free(&pass->nodes[id].edges);
  }
  ms_ty_list_free(&pass->visited);
  edge_list_free(&pass->reported);
}

void ms_check_finite_types(MsCheckProgram *program) {
  Pass pass = {.program = program};
  pass.nodes = MS_ARENA_NEW_ARRAY(&program->arena, Node, program->symbols.len + 1);
  for (MsSymbolId id = 1; id < program->symbols.len; id++) {
    pass.nodes[id] = (Node){.present = is_node(program, id)};
    if (pass.nodes[id].present) {
      const MsDef *def = ms_defs_get(&program->defs, program->symbols.ptr[id].def);
      pass.nodes[id].variables = def->variables.ptr;
      pass.nodes[id].variable_count = def->variables.len;
    }
  }
  for (MsSymbolId id = 1; id < program->symbols.len; id++) {
    if (pass.nodes[id].present) {
      collect_declaration(&pass, id);
    }
  }
  finish(&pass);
}

/* ---- generic functions and types, followed through the calls of their bodies ---- */

typedef struct Scan {
  Pass *pass;
  MsSymbolId owner;
  const MsFacts *facts;
  MsNode callee; /* the callee of the call being visited: its edge is the call's */
} Scan;

static bool is_generic_body(const MsCheckProgram *program, MsSymbolId id) {
  const MsSymbol *symbol = &program->symbols.ptr[id];
  if (symbol->module >= program->user_modules || symbol->decl == NULL || symbol->var_count == 0) {
    return false;
  }
  return (symbol->kind == MS_SYMBOL_FN && symbol->decl->kind == MS_D_FN) || (symbol->kind == MS_SYMBOL_TYPE && symbol->decl->kind == MS_D_TYPE);
}

/* The node that declares `ref`, or 0. */
static MsSymbolId target_of(const Pass *pass, const MsRef *ref) {
  const MsCheckProgram *program = pass->program;
  for (MsSymbolId id = 1; id < program->symbols.len; id++) {
    const MsSymbol *symbol = &program->symbols.ptr[id];
    if (pass->nodes[id].present && symbol->module == ref->decl.module && symbol->decl != NULL && symbol->decl->id == ref->decl.node) {
      return id;
    }
  }
  return 0;
}

static void push_edge(Scan *scan, MsSymbolId target, const MsTy *args, size_t count, MsPos pos) {
  MsCheckProgram *program = scan->pass->program;
  MsTy *copy = MS_ARENA_NEW_ARRAY(&program->arena, MsTy, count + 1);
  for (size_t index = 0; index < count; index++) {
    copy[index] = args[index];
  }
  edge_list_push(&scan->pass->nodes[scan->owner].edges,
                 (Edge){.owner = scan->owner, .target = target, .args = copy, .arg_count = count, .plain = true, .pos = pos});
}

static void scan_call(Scan *scan, const MsExpr *expr) {
  const MsCall *call = ms_facts_call(scan->facts, expr->id);
  scan->callee = expr->u.call.callee->id;
  if (call == NULL || call->type_arg_count == 0 || (call->callee.kind != MS_REF_FUNCTION && call->callee.kind != MS_REF_TYPE)) {
    return;
  }
  const MsSymbolId target = target_of(scan->pass, &call->callee);
  if (target != 0) {
    push_edge(scan, target, call->type_args, call->type_arg_count, expr->pos);
  }
}

/* `f[Args]` named as a value: the arguments are read back from its type. */
static void scan_value(Scan *scan, const MsExpr *expr) {
  const MsRef *ref = ms_facts_ref(scan->facts, expr->id);
  const MsCheckProgram *program = scan->pass->program;
  if (ref == NULL || ref->kind != MS_REF_FUNCTION) {
    return;
  }
  const MsSymbolId target = target_of(scan->pass, ref);
  const MsTy shown = ms_facts_type(scan->facts, expr->id);
  if (target == 0 || shown == MS_TY_NONE) {
    return;
  }
  const Node *node = &scan->pass->nodes[target];
  MsTy *bound = MS_ARENA_NEW_ARRAY(&scan->pass->program->arena, MsTy, node->variable_count + 1);
  if (ms_check_unify(&program->types, program->symbols.ptr[target].ty, shown, node->variables, node->variable_count, bound)) {
    push_edge(scan, target, bound, node->variable_count, expr->pos);
  }
}

static void on_scan_expr(void *context, const MsExpr *expr) {
  Scan *scan = context;
  if (expr->kind == MS_E_CALL) {
    scan_call(scan, expr);
  } else if (expr->kind == MS_E_APPLY && expr->u.apply.types.len != 0 && expr->id != scan->callee) {
    scan_value(scan, expr);
  }
}

void ms_check_finite_functions(MsCheckProgram *program) {
  Pass pass = {.program = program};
  pass.nodes = MS_ARENA_NEW_ARRAY(&program->arena, Node, program->symbols.len + 1);
  for (MsSymbolId id = 1; id < program->symbols.len; id++) {
    const MsSymbol *symbol = &program->symbols.ptr[id];
    pass.nodes[id] = (Node){.present = is_generic_body(program, id)};
    pass.nodes[id].variables = program->symbol_vars.ptr + symbol->var_at;
    pass.nodes[id].variable_count = symbol->var_count;
  }
  for (MsSymbolId id = 1; id < program->symbols.len; id++) {
    if (pass.nodes[id].present) {
      Scan scan = {.pass = &pass, .owner = id, .facts = &program->modules.ptr[program->symbols.ptr[id].module].facts};
      const MsVisitor visitor = {.ctx = &scan, .expr = on_scan_expr};
      ms_walk_decl(&visitor, program->symbols.ptr[id].decl);
    }
  }
  finish(&pass);
}
