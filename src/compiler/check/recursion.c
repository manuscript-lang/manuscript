/* compiler/check/recursion.c: finite generic applications of type declarations.
 *
 * A type, alternative or interface may refer to a generic declaration of the program, itself included, only
 * with the type arguments of the application being followed, or its instances would never end. The graph has one
 * node per declaration and an edge for every mention of a declaration in a field, case field or operation, with
 * the arguments written there. Only nodes that lie on a path to a cycle are walked.
 *
 * Ownership: the pass owns its node edges and tables and frees them before returning. */
#include "compiler/check/program.h"
#include "compiler/check/resolve_internal.h"

typedef struct Edge {
  MsSymbolId owner;
  MsSymbolId target;
  MsTy ty;         /* the mention, whose arguments are the edge's */
  MsPos pos;
  MsName part[2];  /* the case and the field, the field, or the operation: the end of the diagnostic's name */
} Edge;

MS_LIST_DEFINE(EdgeList, edge_list, Edge)

typedef struct Node {
  bool present;
  bool recursive;
  EdgeList edges;     /* owned */
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
      edge_list_push(&pass->nodes[owner].edges,
                     (Edge){.owner = owner, .target = target, .ty = ty, .pos = pos, .part = {first, second}});
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
  ms_strbuild_append_text(&text, "recursive generic applications must preserve their parameters in ");
  ms_strbuild_append(&text, ms_names_span(program->names, program->symbols.ptr[edge->owner].name));
  for (size_t index = 0; index < 2; index++) {
    if (edge->part[index] != MS_NAME_EMPTY) {
      ms_strbuild_append_text(&text, ".");
      ms_strbuild_append(&text, ms_names_span(program->names, edge->part[index]));
    }
  }
  ms_strbuild_append_text(&text, "; keep the same type arguments in the same positions along a recursive cycle");
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
  const MsDef *def = ms_defs_get(&program->defs, program->symbols.ptr[id].def);
  node->active = args;
  node->active_count = count;
  for (size_t index = 0; index < node->edges.len; index++) {
    const Edge *edge = &node->edges.ptr[index];
    if (!pass->nodes[edge->target].recursive) {
      continue;
    }
    const size_t wanted = ms_ty_arg_count(&program->types, edge->ty);
    MsTy *next = MS_ARENA_NEW_ARRAY(&program->arena, MsTy, wanted + 1);
    for (size_t at = 0; at < wanted; at++) {
      next[at] = ms_ty_subst(&program->types, ms_ty_args(&program->types, edge->ty)[at], def->variables.ptr, args, count < def->variables.len ? count : def->variables.len);
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

void ms_check_finite_types(MsCheckProgram *program) {
  Pass pass = {.program = program};
  pass.nodes = MS_ARENA_NEW_ARRAY(&program->arena, Node, program->symbols.len + 1);
  for (MsSymbolId id = 1; id < program->symbols.len; id++) {
    pass.nodes[id] = (Node){.present = is_node(program, id)};
  }
  for (MsSymbolId id = 1; id < program->symbols.len; id++) {
    if (pass.nodes[id].present) {
      collect_declaration(&pass, id);
    }
  }
  mark_recursive(&pass);
  for (MsSymbolId id = 1; id < program->symbols.len; id++) {
    if (pass.nodes[id].recursive) {
      const MsDef *def = ms_defs_get(&program->defs, program->symbols.ptr[id].def);
      visit(&pass, id, def->variables.ptr, def->variables.len);
    }
  }
  for (MsSymbolId id = 1; id < program->symbols.len; id++) {
    edge_list_free(&pass.nodes[id].edges);
  }
  ms_ty_list_free(&pass.visited);
  edge_list_free(&pass.reported);
}
