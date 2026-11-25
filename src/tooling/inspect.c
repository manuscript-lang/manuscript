/* Owns inspect.h. */
#include "tooling/inspect.h"

#include "base/message.h"
#include "base/sort.h"
#include "compiler/check/effects_scan.h"
#include "compiler/syntax/walk.h"

typedef struct Collect {
  MsArena *arena;
  const MsCheckProgram *program;
  MsInspection *out;
  const MsReach *reach;
  uint32_t module;
  MsSpan file;
  MsSpan owner;
} Collect;

static MsSpan keep(Collect *c, MsStrBuild *text) {
  const MsSpan span = ms_arena_copy(c->arena, ms_strbuild_span(text));
  ms_strbuild_free(text);
  return span;
}

static MsSpan name_text(const Collect *c, MsName name) {
  return ms_names_span(c->program->names, name);
}

static MsSpan show_type(Collect *c, MsTy ty) {
  MsStrBuild text = ms_strbuild_new();
  ms_ty_show(&text, c->program->names, &c->program->types, ty);
  return keep(c, &text);
}

static MsSpan join_id(Collect *c, MsSpan file, const char *kind, MsSpan name) {
  return ms_message_format(c->arena, "%S#%s#%S", file, kind, name);
}

/* ---- declarations ---- */

static MsSpan decl_name(Collect *c, const MsDecl *decl);
static const char *entity_kind(const MsDecl *decl);

const char *ms_decl_entity_kind(const MsDecl *decl) {
  return entity_kind(decl);
}

MsSpan ms_decl_entity_name(MsArena *arena, const MsCheckProgram *program, const MsDecl *decl) {
  Collect c = {.arena = arena, .program = program};
  return decl_name(&c, decl);
}

static const char *entity_kind(const MsDecl *decl) {
  switch ((MsDeclKind)decl->kind) {
  case MS_D_FN: return "fn";
  case MS_D_CONST: return "constant";
  case MS_D_TYPE: return "type";
  case MS_D_ENUM: return "alternative";
  case MS_D_ALIAS: return "alias";
  case MS_D_INTERFACE: return "interface";
  case MS_D_IMPL: return "impl";
  case MS_D_TEST: return decl->u.test.bench ? "bench" : "test";
  }
  return "fn";
}

/* The name a declaration binds, or the empty span (an impl, a test). */
static MsSpan bound_name(const Collect *c, const MsDecl *decl) {
  MsName name = 0;
  return ms_decl_name(decl, &name) ? name_text(c, name) : (MsSpan){0};
}

/* The text of a written type: `Shape`, `List[Int]`. */
static MsSpan type_ref_name(const Collect *c, const MsTypeRef *ref) {
  return ref != NULL && ref->kind == MS_TYPE_NAMED ? name_text(c, ref->name) : (MsSpan){0};
}

static MsSpan decl_name(Collect *c, const MsDecl *decl) {
  if (decl->kind == MS_D_TEST) {
    return decl->u.test.name;
  }
  if (decl->kind == MS_D_IMPL) {
    const MsSpan receiver = type_ref_name(c, decl->u.impl.receiver);
    if (decl->u.impl.contract != NULL && !decl->synthetic) {
      return ms_message_format(c->arena, "%S for %S", type_ref_name(c, decl->u.impl.contract), receiver);
    }
    return receiver;
  }
  return bound_name(c, decl);
}

static MsSpan decl_id(Collect *c, MsSpan file, const MsDecl *decl) {
  if (decl->kind == MS_D_IMPL) {
    return ms_message_format(c->arena, "%S#impl#%z", file, (size_t)decl->pos.offset);
  }
  return join_id(c, file, entity_kind(decl), decl->kind == MS_D_TEST ? decl->u.test.name : bound_name(c, decl));
}

/* Whether a file declares native operations (a bodiless inherent `impl`) and also has bodies: the Rust loader splits
 * it into a native half and a `+source` half, and ids name the half. */
static bool is_mixed(const MsModule *tree) {
  bool native = false;
  bool body = false;
  for (uint32_t d = 0; d < tree->ndecls; d++) {
    const MsDecl *decl = tree->decls[d];
    body = body || ms_decl_has_body(decl);
    if (decl->kind == MS_D_IMPL && decl->u.impl.contract == NULL) {
      for (uint32_t i = 0; i < decl->u.impl.methods.len; i++) {
        native = native || !ms_func_has_body(&decl->u.impl.methods.ptr[i]->func);
      }
    }
  }
  return native && body;
}

/* The file an id names for `decl`: a mixed standard module's declarations with bodies sit in its `+source` half. */
static MsSpan id_file(Collect *c, uint32_t module, const MsDecl *decl) {
  const MsModuleInfo *info = &c->program->modules.ptr[module];
  const MsSpan file = ms_names_span(c->program->names, info->file);
  if (module < c->program->user_modules || !ms_decl_has_body(decl) || !is_mixed(info->tree)) {
    return file;
  }
  return ms_message_format(c->arena, "%S+source", file);
}

/* The id of the declaration node `node` of `module`, or empty. */
static MsSpan id_of_node(Collect *c, uint32_t module, uint32_t node, const MsDecl **found) {
  const MsModuleInfo *info = &c->program->modules.ptr[module];
  for (uint32_t i = 0; i < info->tree->ndecls; i++) {
    const MsDecl *decl = info->tree->decls[i];
    if (decl->id == node && decl->kind != MS_D_IMPL && decl->kind != MS_D_TEST) {
      if (found != NULL) {
        *found = decl;
      }
      return decl_id(c, id_file(c, module, decl), decl);
    }
  }
  return (MsSpan){0};
}

/* The user method declared by node `node` of `module`, as its entry, or NULL. */
static const MsMethodEntry *method_of_node(const Collect *c, uint32_t module, uint32_t node) {
  for (size_t i = 0; i < c->program->methods.len; i++) {
    const MsMethodEntry *entry = &c->program->methods.ptr[i];
    if (entry->module == module && entry->source != NULL && entry->source->id == node) {
      return entry;
    }
  }
  return NULL;
}

static MsSpan method_id(Collect *c, const MsMethodEntry *entry) {
  const MsSpan file = ms_names_span(c->program->names, c->program->modules.ptr[entry->module].file);
  return ms_message_format(c->arena, "%S#method#%z", file, (size_t)entry->source->pos.offset);
}

static bool has_body(const MsMethodEntry *entry) {
  return entry->source != NULL && ms_func_has_body(&entry->source->func);
}

/* ---- call sites ---- */

static void add_site(Collect *c, MsSpan id, MsSpan target, const char *kind, bool spawn, MsPos pos) {
  const MsCallSite site = {.id = id, .owner = c->owner, .target = target, .kind = ms_span_of_text(kind), .spawn = spawn,
                           .file = c->file, .pos = pos};
  ms_call_site_list_push(&c->out->calls, site);
}

static MsSpan callee_text(const Collect *c, const MsExpr *callee) {
  if (callee->kind == MS_E_NAME) {
    return name_text(c, callee->u.sym);
  }
  return callee->kind == MS_E_MEMBER ? name_text(c, callee->u.member.name) : (MsSpan){0};
}

static MsSpan call_id(Collect *c, const char *kind, MsPos pos) {
  return ms_message_format(c->arena, "%S#%s#%z", c->file, kind, (size_t)pos.offset);
}

/* A method or operation called: its entity when the project declares one with a body, else `Receiver.name`. */
static void method_site(Collect *c, const MsExpr *e, const MsCall *call) {
  const MsExpr *callee = e->u.call.callee;
  const MsMethodEntry *entry = call->callee.kind == MS_REF_METHOD ? method_of_node(c, call->callee.decl.module, call->callee.decl.node) : NULL;
  MsSpan target = {0};
  if (entry != NULL && has_body(entry) && call->callee.decl.module < c->program->user_modules) {
    target = method_id(c, entry);
  } else {
    target = ms_message_format(c->arena, "%S.%S", show_type(c, call->callee.owner), callee_text(c, callee));
  }
  const bool spawn = ms_ty_is(&c->program->types, call->callee.owner, MS_BUILTIN_TaskGroup) &&
                     ms_span_is_text(callee_text(c, callee), "spawn");
  add_site(c, call_id(c, "call", e->pos), target, "operation", spawn, e->pos);
}

static void visit_call(Collect *c, const MsExpr *e) {
  const MsFacts *facts = &c->program->modules.ptr[c->module].facts;
  const MsCall *call = ms_facts_call(facts, e->id);
  const MsRefKind kind = call == NULL ? MS_REF_NONE : call->callee.kind;
  if (kind == MS_REF_METHOD || kind == MS_REF_OPERATION) {
    method_site(c, e, call);
  } else if (kind == MS_REF_TYPE || kind == MS_REF_CASE) {
    add_site(c, call_id(c, "call", e->pos), show_type(c, ms_facts_type(facts, e->id)), "construct", false, e->pos);
  } else if (kind == MS_REF_NATIVE && call->callee.owner != MS_TY_NONE) {
    method_site(c, e, call);
  } else if (kind == MS_REF_FUNCTION || kind == MS_REF_NATIVE) {
    MsSpan target = id_of_node(c, call->callee.decl.module, call->callee.decl.node, NULL);
    if (target.len == 0) {
      target = ms_message_format(c->arena, "%S#%S", ms_names_span(c->program->names, c->program->modules.ptr[call->callee.decl.module].file),
                                 callee_text(c, e->u.call.callee));
    }
    add_site(c, call_id(c, "call", e->pos), target, "function", false, e->pos);
  } else {
    add_site(c, call_id(c, "call", e->pos), ms_span_of_text("indirect"), "function", false, e->pos);
  }
}

/* A module-level constant read. */
static void visit_constant(Collect *c, const MsExpr *e) {
  const MsRef *ref = ms_facts_ref(&c->program->modules.ptr[c->module].facts, e->id);
  if (ref == NULL || ref->kind != MS_REF_CONSTANT) {
    return;
  }
  const MsSpan target = id_of_node(c, ref->decl.module, ref->decl.node, NULL);
  add_site(c, call_id(c, "call", e->pos), target.len > 0 ? target : ms_span_of_text("indirect"), "constant", false, e->pos);
}

static void visit_expr(void *context, const MsExpr *e) {
  Collect *c = context;
  if (e->kind == MS_E_CALL) {
    visit_call(c, e);
  } else if (e->kind == MS_E_NAME) {
    visit_constant(c, e);
  }
}

/* A binding closed where its scope ends. */
static void visit_stmt(void *context, const MsStmt *s) {
  Collect *c = context;
  ms_statement_site_list_push(&c->out->statements, (MsStatementSite){.module = c->module, .pos = s->pos});
  if (s->kind != MS_S_BIND || s->u.bind.pattern->kind != MS_P_NAME) {
    return;
  }
  const MsFacts *facts = &c->program->modules.ptr[c->module].facts;
  const MsCloser *closer = ms_facts_closer(facts, s->u.bind.pattern->id);
  if (closer == NULL || closer->method.node == 0) {
    return;
  }
  const MsMethodEntry *entry = method_of_node(c, closer->method.module, closer->method.node);
  MsSpan target = {0};
  if (entry != NULL && has_body(entry) && closer->method.module < c->program->user_modules) {
    target = method_id(c, entry);
  } else {
    target = ms_message_format(c->arena, "%S.close", show_type(c, ms_facts_type(facts, s->u.bind.pattern->id)));
  }
  add_site(c, call_id(c, "cleanup", s->pos), target, "cleanup", false, s->pos);
}

static void walk_body(Collect *c, MsParams params, MsStmts body) {
  const MsVisitor visitor = {.ctx = c, .stmt = visit_stmt, .expr = visit_expr};
  ms_walk_callable(&visitor, params, body);
}

/* What a declaration itself executes: a function or test body, or a constant's initializer. */
static void walk_declaration(Collect *c, const MsDecl *decl) {
  const MsVisitor visitor = {.ctx = c, .stmt = visit_stmt, .expr = visit_expr};
  if (decl->kind == MS_D_FN) {
    walk_body(c, decl->u.fn.params, decl->u.fn.body);
  } else if (decl->kind == MS_D_TEST) {
    walk_body(c, (MsParams){0}, decl->u.test.body);
  } else if (decl->kind == MS_D_CONST) {
    ms_statement_site_list_push(&c->out->statements, (MsStatementSite){.module = c->module, .pos = decl->u.konst.init_pos});
    ms_walk_expr(&visitor, decl->u.konst.value);
  }
}

/* ---- entities ---- */

static void add_entity(Collect *c, MsSpan id, MsSpan checker_id, const char *kind, MsSpan name, MsSpan ty, MsPos pos,
                       bool exported, const MsEffectNames *effects, const MsEffectNames *permits) {
  MsEntity entity = {.id = id, .checker_id = checker_id, .kind = ms_span_of_text(kind), .name = name, .ty = ty, .file = c->file, .pos = pos,
                     .exported = exported};
  for (uint32_t i = 0; effects != NULL && i < effects->count; i++) {
    ms_span_list_push(&entity.effects, effects->names[i]);
  }
  for (uint32_t i = 0; permits != NULL && i < permits->count; i++) {
    ms_span_list_push(&entity.permits, permits->names[i]);
  }
  ms_entity_list_push(&c->out->entities, entity);
}

/* The symbol the module binds `decl` to, or NULL. */
static const MsSymbol *symbol_of(const Collect *c, const MsDecl *decl) {
  MsName name = 0;
  if (!ms_decl_name(decl, &name)) {
    return NULL;
  }
  const MsSymbolId *found = ms_scope_get(&c->program->modules.ptr[c->module].scope, name);
  const MsSymbol *symbol = found == NULL ? NULL : &c->program->symbols.ptr[*found];
  return symbol != NULL && symbol->decl == decl ? symbol : NULL;
}

/* The index of `decl` among the callables the effects scan numbers: module order, then functions with a body. */
static uint32_t callable_index(const Collect *c, const MsDecl *decl, bool *found) {
  uint32_t index = 0;
  for (uint32_t m = 0; m < c->program->modules.len; m++) {
    const MsModule *tree = c->program->modules.ptr[m].tree;
    for (uint32_t d = 0; d < tree->ndecls; d++) {
      if (tree->decls[d]->kind == MS_D_FN && !tree->decls[d]->u.fn.external) {
        if (tree->decls[d] == decl) {
          *found = true;
          return index;
        }
        index++;
      }
    }
  }
  *found = false;
  return 0;
}

static void collect_decl(Collect *c, const MsDecl *decl) {
  if (decl->synthetic && decl->kind == MS_D_INTERFACE) {
    return;
  }
  const MsSymbol *symbol = symbol_of(c, decl);
  MsSpan ty = {0};
  const MsEffectNames *effects = NULL;
  const MsEffectNames *permits = NULL;
  bool found = false;
  const uint32_t index = decl->kind == MS_D_FN ? callable_index(c, decl, &found) : 0;
  if (decl->kind == MS_D_FN && found) {
    effects = &c->reach->declared[index];
    permits = &c->reach->permits[index];
  }
  if (symbol != NULL && decl->kind == MS_D_FN && symbol->ty != MS_TY_NONE) {
    ty = show_type(c, symbol->ty);
  }
  const MsSpan id = decl_id(c, c->file, decl);
  const MsSpan checker_id = symbol != NULL ? name_text(c, symbol->id) : (MsSpan){0};
  add_entity(c, id, checker_id, entity_kind(decl), decl_name(c, decl), ty, decl->pos, decl->is_exported, effects, permits);
  c->owner = id;
  walk_declaration(c, decl);
}

static void collect_methods(Collect *c) {
  for (size_t i = 0; i < c->program->methods.len; i++) {
    const MsMethodEntry *entry = &c->program->methods.ptr[i];
    if (entry->module != c->module || !has_body(entry)) {
      continue;
    }
    MsStrBuild receiver = ms_strbuild_new();
    ms_ty_show(&receiver, c->program->names, &c->program->types, entry->receiver);
    const MsSpan id = method_id(c, entry);
    const MsSpan name = ms_message_format(c->arena, "%S.%S", ms_strbuild_span(&receiver), name_text(c, entry->source->func.name));
    ms_strbuild_free(&receiver);
    add_entity(c, id, ms_message_format(c->arena, "method%z", i), "method", name, show_type(c, entry->ty), entry->source->pos, false,
               NULL, NULL);
    c->owner = id;
    walk_body(c, entry->source->func.params, entry->source->func.body);
  }
}

static int64_t compare_entity(uint8_t *env, const uint8_t *left, const uint8_t *right) {
  (void)env;
  return ms_span_compare(((const MsEntity *)(const void *)left)->id, ((const MsEntity *)(const void *)right)->id);
}

static int64_t compare_site(uint8_t *env, const uint8_t *left, const uint8_t *right) {
  (void)env;
  return ms_span_compare(((const MsCallSite *)(const void *)left)->id, ((const MsCallSite *)(const void *)right)->id);
}

void ms_inspect_collect(MsArena *arena, const MsCheckProgram *program, bool std, MsInspection *out) {
  const MsReach reach = ms_check_effects(program, arena);
  Collect c = {.arena = arena, .program = program, .out = out, .reach = &reach};
  for (uint32_t m = 0; m < (std ? (uint32_t)program->modules.len : program->user_modules); m++) {
    c.module = m;
    c.file = ms_names_span(program->names, program->modules.ptr[m].file);
    const MsModule *tree = program->modules.ptr[m].tree;
    for (uint32_t d = 0; d < tree->ndecls; d++) {
      collect_decl(&c, tree->decls[d]);
    }
    collect_methods(&c);
  }
  ms_sort((uint8_t *)out->entities.ptr, out->entities.len, sizeof(MsEntity), compare_entity, NULL);
  ms_sort((uint8_t *)out->calls.ptr, out->calls.len, sizeof(MsCallSite), compare_site, NULL);
}

void ms_inspection_free(MsInspection *inspection) {
  for (size_t i = 0; i < inspection->entities.len; i++) {
    ms_span_list_free(&inspection->entities.ptr[i].effects);
    ms_span_list_free(&inspection->entities.ptr[i].permits);
  }
  ms_entity_list_free(&inspection->entities);
  ms_call_site_list_free(&inspection->calls);
  ms_statement_site_list_free(&inspection->statements);
}

MsSpan ms_readable_id(MsArena *arena, MsSpan id) {
  size_t first = 0;
  size_t second = 0;
  if (!ms_span_find(id, ms_span_of_text("#"), &first) || first == 0) {
    return id;
  }
  const MsSpan rest = ms_span_of(id.ptr + first + 1, id.len - first - 1);
  if (!ms_span_find(rest, ms_span_of_text("#"), &second) || second == 0 || second + 1 >= rest.len) {
    return id;
  }
  MsSpan file = ms_span_of(id.ptr, first);
  if (ms_span_ends_with_text(file, "+source")) {
    file.len -= 7;
  }
  return ms_message_format(arena, "%S::%S", file, ms_span_of(rest.ptr + second + 1, rest.len - second - 1));
}
