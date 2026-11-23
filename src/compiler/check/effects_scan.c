/* compiler/check/effects_scan.c: the effects scan over a checked program (see effects_scan.h). */
#include "compiler/check/effects_scan.h"

#include "compiler/check/effects_directives.h"
#include "compiler/check/properties.h"
#include "compiler/syntax/walk.h"

typedef struct Edge {
  uint32_t node;
  MsName callee;
  MsPos pos;
} Edge;

MS_LIST_DEFINE(EdgeList, edge_list, Edge)
MS_LIST_DEFINE(NodeList, node_list, MsReachNode)
MS_MAP_DEFINE(NodeIndex, node_index, uint64_t, uint32_t, ms_hash_u64_key, ms_equal_u64_key)

typedef struct NodeSource {
  uint32_t module;
  const MsFunc *func; /* a function or method, or NULL for a type or constant declaration: `decl` is walked */
  const MsDecl *decl;
} NodeSource;

MS_LIST_DEFINE(SourceList, source_list, NodeSource)

typedef struct Scan {
  const MsCheckProgram *program;
  MsArena *arena;
  NodeList nodes;
  SourceList sources; /* by node index: the function or method whose body the node scans */
  NodeIndex by_decl;  /* (module, function or method node) -> node index */
  EdgeList edges;
  uint32_t module;
  uint32_t holder;    /* the node whose body is walked */
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

/* A callable of `module`: the function `decl`, or one method of the impl `decl` (`method` not NULL), whose display
 * name is `Receiver.method`. */
static void add_node(Scan *scan, uint32_t module, const MsDecl *decl, const MsMethod *method) {
  const MsModuleInfo *info = &scan->program->modules.ptr[module];
  const bool callable = decl->kind == MS_D_FN || method != NULL;
  const MsFunc *func = !callable ? NULL : method != NULL ? &method->func : &decl->u.fn;
  const MsPos at = method != NULL ? method->pos : decl->pos;
  const uint32_t node_id = method != NULL ? method->id : decl->id;
  MsDirectives above = ms_directives_above(info->source, at.line);
  MsDirectives header = ms_directives_header(info->source);
  MsSpan *declared = MS_ARENA_NEW_ARRAY(scan->arena, MsSpan, above.declared.len + 1);
  for (size_t index = 0; index < above.declared.len; index++) {
    declared[index] = above.declared.ptr[index];
  }
  MsName own_name = decl->kind == MS_D_TYPE ? decl->u.type.name : decl->kind == MS_D_CONST ? decl->u.konst.name : MS_NAME_EMPTY;
  MsSpan label = ms_names_span(scan->program->names, func != NULL ? func->name : own_name);
  if (method != NULL) {
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_append(&text, ms_names_span(scan->program->names, decl->u.impl.receiver->name));
    ms_strbuild_append_byte(&text, '.');
    ms_strbuild_append(&text, label);
    label = ms_arena_copy(scan->arena, ms_strbuild_span(&text));
    ms_strbuild_free(&text);
  }
  MsReachNode node = {.id = callable_id(scan, module, node_id),
                      .file = info->file,
                      .label = label,
                      .pos = at,
                      .project = module < scan->program->user_modules,
                      .entry = method == NULL && module < scan->program->user_modules && ms_span_is_text(label, "main"),
                      .declared = declared,
                      .declared_count = (uint32_t)above.declared.len,
                      .allow_fn = scope_of(scan, &above),
                      .allow_file = scope_of(scan, &header)};
  node_index_put(&scan->by_decl, decl_key(module, node_id), (uint32_t)scan->nodes.len);
  node_list_push(&scan->nodes, node);
  source_list_push(&scan->sources, (NodeSource){.module = module, .func = func, .decl = decl});
  ms_directives_free(&above);
  ms_directives_free(&header);
}

/* The functions come first, in program order: `ms inspect` finds a function's effects by its place among them. Then
 * the methods, types and constants. */
static void add_nodes(Scan *scan) {
  for (uint32_t pass = 0; pass < 2; pass++) {
    for (uint32_t module = 0; module < scan->program->modules.len; module++) {
      const MsModule *tree = scan->program->modules.ptr[module].tree;
      for (uint32_t index = 0; index < tree->ndecls; index++) {
        const MsDecl *decl = tree->decls[index];
        if (pass == 0) {
          if (decl->kind == MS_D_FN && !decl->u.fn.external) {
            add_node(scan, module, decl, NULL);
          }
          continue;
        }
        if (decl->kind == MS_D_TYPE || decl->kind == MS_D_CONST) {
          add_node(scan, module, decl, NULL);
        }
        for (uint32_t at = 0; decl->kind == MS_D_IMPL && at < decl->u.impl.methods.len; at++) {
          if (!decl->u.impl.methods.ptr[at]->func.external) {
            add_node(scan, module, decl, decl->u.impl.methods.ptr[at]);
          }
        }
      }
    }
  }
}

/* A callable named by an expression of the walked body is an edge of the callable holding the body: a function or
 * a method, called or used as a value. A call's edge sits at the call, as its callee is visited after it. */
static void note_ref(Scan *scan, const MsRef *ref, MsPos pos) {
  if (ref == NULL || (ref->kind != MS_REF_FUNCTION && ref->kind != MS_REF_METHOD && ref->kind != MS_REF_TYPE &&
                      ref->kind != MS_REF_CONSTANT)) {
    return;
  }
  const uint32_t *target = node_index_get(&scan->by_decl, decl_key(ref->decl.module, ref->decl.node));
  if (target != NULL) {
    edge_list_push(&scan->edges, (Edge){.node = scan->holder, .callee = scan->nodes.ptr[*target].id, .pos = pos});
  }
}

/* The definition of an interface type, or NULL. */
static const MsDef *contract_def(const MsCheckProgram *program, MsTy ty) {
  const MsTyRow *row = ms_ty_row(&program->types, ty);
  return row->kind == MS_TY_CONTRACT && row->def != 0 ? ms_defs_get(&program->defs, row->def) : NULL;
}

/* The methods of `concrete` that `contract`'s operations name are edges of the holder, at `pos`. */
static void note_implementor(Scan *scan, const MsDef *contract, const MsDef *concrete, MsPos pos) {
  const MsCheckProgram *program = scan->program;
  for (size_t index = 0; contract != NULL && concrete != NULL && index < contract->operations.len; index++) {
    for (size_t at = 0; at < program->methods.len; at++) {
      const MsMethodEntry *entry = &program->methods.ptr[at];
      if (entry->name != contract->operations.ptr[index].name || entry->source == NULL ||
          ms_check_def_of(program, entry->receiver) != concrete) {
        continue;
      }
      const uint32_t *target = node_index_get(&scan->by_decl, decl_key(entry->module, entry->source->id));
      if (target != NULL) {
        edge_list_push(&scan->edges, (Edge){.node = scan->holder, .callee = scan->nodes.ptr[*target].id, .pos = pos});
      }
    }
  }
}

/* A value seen as an interface hands out the methods of its type that the interface's operations name: each is an
 * edge of the holder, where the conversion is. */
static void note_view(Scan *scan, const MsConversion *conversion, MsPos pos) {
  const MsCheckProgram *program = scan->program;
  note_implementor(scan, contract_def(program, conversion->to), ms_check_def_of(program, conversion->from), pos);
}

/* The symbol of the function declared at `ref`, or NULL. */
static const MsSymbol *function_symbol(const Scan *scan, const MsRef *ref) {
  const MsCheckProgram *program = scan->program;
  for (size_t index = 0; index < program->symbols.len; index++) {
    const MsSymbol *symbol = &program->symbols.ptr[index];
    if (symbol->decl != NULL && symbol->module == ref->decl.module && symbol->decl->id == ref->decl.node) {
      return symbol;
    }
  }
  return NULL;
}

/* A generic function called at a concrete type reaches that type's methods through the bounds of the parameter
 * (`fn f[T: Show](x: T)` called with a `Point` calls `Point.show` when its body calls `x.show()`): each method a
 * bound's operations name is an edge of the caller, at the call. */
static void note_closes(Scan *scan, MsTy ty, MsPos pos, uint32_t depth) {
  const MsCheckProgram *program = scan->program;
  const MsDef *concrete = ms_check_def_of(program, ty);
  for (size_t at = 0; concrete != NULL && at < program->methods.len; at++) {
    const MsMethodEntry *entry = &program->methods.ptr[at];
    if (entry->source != NULL && ms_span_is_text(ms_names_span(program->names, entry->name), "close") &&
        ms_check_def_of(program, entry->receiver) == concrete) {
      const uint32_t *target = node_index_get(&scan->by_decl, decl_key(entry->module, entry->source->id));
      if (target != NULL) {
        edge_list_push(&scan->edges, (Edge){.node = scan->holder, .callee = scan->nodes.ptr[*target].id, .pos = pos});
      }
    }
  }
  const size_t count = ms_ty_arg_count(&program->types, ty);
  for (size_t index = 0; depth < 4 && index < count; index++) {
    note_closes(scan, ms_ty_args(&program->types, ty)[index], pos, depth + 1);
  }
}

static void note_instantiation(Scan *scan, const MsCall *call, MsPos pos) {
  const MsCheckProgram *program = scan->program;
  if (call->callee.kind != MS_REF_FUNCTION || call->type_arg_count == 0) {
    return;
  }
  for (uint32_t index = 0; index < call->type_arg_count; index++) {
    note_closes(scan, call->type_args[index], pos, 0);
  }
  const MsSymbol *symbol = function_symbol(scan, &call->callee);
  for (uint32_t index = 0; symbol != NULL && index < call->type_arg_count && index < symbol->var_count; index++) {
    const MsTyRow *row = ms_ty_row(&program->types, program->symbol_vars.ptr[symbol->var_at + index]);
    const MsDef *concrete = ms_check_def_of(program, call->type_args[index]);
      if (row->kind != MS_TY_VARIABLE || concrete == NULL) {
      continue;
    }
    const MsTyList *bounds = &program->types.variables.ptr[row->def].bounds;
      for (size_t bound = 0; bound < bounds->len; bound++) {
      note_implementor(scan, contract_def(program, bounds->ptr[bound]), concrete, pos);
    }
  }
}

static void visit_expr(void *context, const MsExpr *expr) {
  Scan *scan = context;
  const MsFacts *facts = &scan->program->modules.ptr[scan->module].facts;
  if (expr->id >= facts->node_count) {
    return;
  }
  if (expr->kind == MS_E_CALL) {
    const MsCall *call = ms_facts_call(facts, expr->id);
    note_ref(scan, call != NULL ? &call->callee : NULL, expr->pos);
    if (call != NULL) {
      note_instantiation(scan, call, expr->pos);
    }
  }
  note_ref(scan, ms_facts_ref(facts, expr->id), expr->pos);
  const MsConversion *conversion = ms_facts_conversion(facts, expr->id);
  if (conversion != NULL && conversion->kind == MS_CONV_INTERFACE_VIEW) {
    note_view(scan, conversion, expr->pos);
  }
}

static void collect_edges(Scan *scan) {
  const MsVisitor visitor = {.ctx = scan, .expr = visit_expr};
  for (uint32_t node = 0; node < scan->nodes.len; node++) {
    scan->holder = node;
    scan->module = scan->sources.ptr[node].module;
    const MsFunc *func = scan->sources.ptr[node].func;
    if (func != NULL) {
      ms_walk_callable(&visitor, func->params, func->body);
    } else {
      ms_walk_decl(&visitor, scan->sources.ptr[node].decl);
    }
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
  source_list_free(&scan.sources);
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
