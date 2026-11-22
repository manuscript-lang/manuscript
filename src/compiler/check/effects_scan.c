/* compiler/check/effects_scan.c: the effects scan over a checked program (see effects_scan.h). */
#include "compiler/check/effects_scan.h"

#include "compiler/check/effects_directives.h"
#include "compiler/check/scope_walk.h"

typedef struct Edge {
  uint32_t node;
  MsName callee;
  MsPos pos;
} Edge;

MS_LIST_DEFINE(EdgeList, edge_list, Edge)
MS_LIST_DEFINE(NodeList, node_list, MsReachNode)
MS_MAP_DEFINE(NodeIndex, node_index, uint64_t, uint32_t, ms_hash_u64_key, ms_equal_u64_key)

typedef struct Scan {
  const MsCheckProgram *program;
  MsArena *arena;
  NodeList nodes;
  NodeIndex by_decl; /* (module, decl node) -> node index */
  EdgeList edges;
  uint32_t module;
} Scan;

static uint64_t decl_key(uint32_t module, uint32_t node) {
  return ((uint64_t)module << 32) | node;
}

/* The id of the callable declared by node `node` of module `module`. */
static MsName callable_id(const Scan *scan, uint32_t module, uint32_t node) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_printf(&text, "callable:%u:%u", module, node);
  const MsName id = ms_names_intern(scan->program->names, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  return id;
}

static MsEffectScope scope_of(Scan *scan, const MsDirectives *directives) {
  MsEffectScope scope = {.present = directives->has_allow, .count = (uint32_t)directives->allow.len};
  MsSpan *copy = MS_ARENA_NEW_ARRAY(scan->arena, MsSpan, directives->allow.len + 1);
  for (size_t index = 0; index < directives->allow.len; index++) {
    copy[index] = directives->allow.ptr[index];
  }
  scope.patterns = copy;
  return scope;
}

static void add_node(Scan *scan, uint32_t module, const MsDecl *decl) {
  const MsModuleInfo *info = &scan->program->modules.ptr[module];
  MsDirectives above = ms_directives_above(info->source, decl->pos.line);
  MsDirectives header = ms_directives_header(info->source);
  MsSpan *declared = MS_ARENA_NEW_ARRAY(scan->arena, MsSpan, above.declared.len + 1);
  for (size_t index = 0; index < above.declared.len; index++) {
    declared[index] = above.declared.ptr[index];
  }
  const MsSpan label = ms_names_span(scan->program->names, decl->u.fn.name);
  MsReachNode node = {.id = callable_id(scan, module, decl->id),
                      .file = info->file,
                      .label = label,
                      .pos = decl->pos,
                      .project = module < scan->program->user_modules,
                      .entry = module < scan->program->user_modules && ms_span_is_text(label, "main"),
                      .declared = declared,
                      .declared_count = (uint32_t)above.declared.len,
                      .allow_fn = scope_of(scan, &above),
                      .allow_file = scope_of(scan, &header)};
  node_index_put(&scan->by_decl, decl_key(module, decl->id), (uint32_t)scan->nodes.len);
  node_list_push(&scan->nodes, node);
  ms_directives_free(&above);
  ms_directives_free(&header);
}

static void add_nodes(Scan *scan) {
  for (uint32_t module = 0; module < scan->program->modules.len; module++) {
    const MsModule *tree = scan->program->modules.ptr[module].tree;
    for (uint32_t index = 0; index < tree->ndecls; index++) {
      const MsDecl *decl = tree->decls[index];
      if (decl->kind == MS_D_FN && !decl->u.fn.external) {
        add_node(scan, module, decl);
      }
    }
  }
}

/* A function named by an expression of the walked body is an edge of the callable holding the body. */
static void visit_expr(void *context, const MsExpr *expr, const MsBindingList *scope, const MsScopeSite *site) {
  (void)scope;
  Scan *scan = context;
  const MsRef *ref = ms_facts_ref(&scan->program->modules.ptr[scan->module].facts, expr->id);
  if (ref == NULL || ref->kind != MS_REF_FUNCTION || site->decl == NULL || site->decl->kind != MS_D_FN) {
    return;
  }
  const uint32_t *holder = node_index_get(&scan->by_decl, decl_key(scan->module, site->decl->id));
  const uint32_t *target = node_index_get(&scan->by_decl, decl_key(ref->decl.module, ref->decl.node));
  if (holder != NULL && target != NULL) {
    edge_list_push(&scan->edges, (Edge){.node = *holder, .callee = scan->nodes.ptr[*target].id, .pos = expr->pos});
  }
}

static void collect_edges(Scan *scan) {
  for (uint32_t module = 0; module < scan->program->modules.len; module++) {
    scan->module = module;
    const MsScopeVisitor visitor = {.context = scan, .expr = visit_expr};
    ms_scope_walk_module(scan->program->modules.ptr[module].tree, &visitor, scan->program->names);
  }
}

/* Gives each node its edges: the first reference to each callee, in source order. The walk visits a function's
 * body in one go, so the edges of a node are contiguous. */
static void attach_edges(Scan *scan) {
  size_t index = 0;
  while (index < scan->edges.len) {
    const uint32_t node = scan->edges.ptr[index].node;
    size_t end = index;
    while (end < scan->edges.len && scan->edges.ptr[end].node == node) {
      end++;
    }
    MsReachEdge *edges = MS_ARENA_NEW_ARRAY(scan->arena, MsReachEdge, end - index);
    uint32_t count = 0;
    for (size_t at = index; at < end; at++) {
      bool seen = false;
      for (uint32_t prior = 0; prior < count && !seen; prior++) {
        seen = edges[prior].callee == scan->edges.ptr[at].callee;
      }
      if (!seen) {
        edges[count++] = (MsReachEdge){.callee = scan->edges.ptr[at].callee, .pos = scan->edges.ptr[at].pos};
      }
    }
    scan->nodes.ptr[node].edges = edges;
    scan->nodes.ptr[node].edge_count = count;
    index = end;
  }
}

MsReach ms_check_effects(const MsCheckProgram *program, MsArena *arena) {
  Scan scan = {.program = program, .arena = arena};
  add_nodes(&scan);
  collect_edges(&scan);
  attach_edges(&scan);
  const MsReach reach = ms_effects_resolve(scan.nodes.ptr, (uint32_t)scan.nodes.len, arena);
  node_list_free(&scan.nodes);
  node_index_free(&scan.by_decl);
  edge_list_free(&scan.edges);
  return reach;
}

void ms_effect_message(MsStrBuild *out, MsSpan label, const MsReachViolation *violation) {
  ms_strbuild_append_text(out, "`");
  ms_strbuild_append(out, label);
  ms_strbuild_append_text(out, "` reaches ");
  ms_strbuild_append(out, violation->effect);
  if (violation->path_count > 1) {
    ms_strbuild_append_text(out, ": ");
    for (uint32_t index = 0; index < violation->path_count; index++) {
      ms_strbuild_append_text(out, index == 0 ? "" : " -> ");
      ms_strbuild_append(out, violation->path[index]);
    }
  }
  ms_strbuild_append_text(out, "; permit it with `// ms: allow_effect ");
  ms_strbuild_append(out, violation->effect);
  ms_strbuild_append_text(out, "`, move the call to the caller, or take a capability parameter");
}
