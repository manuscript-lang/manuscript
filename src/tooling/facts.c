/* Owns facts.h. */
#include "tooling/facts.h"

#include "base/sort.h"
#include "base/message.h"
#include "compiler/own/class.h"
#include "compiler/own/result_borrows.h"
#include "compiler/own/taken.h"
#include "compiler/syntax/walk.h"
#include "tooling/flow.h"

MsViewNode *ms_view_node(MsArena *arena, MsSpan label) {
  MsViewNode *node = MS_ARENA_NEW(arena, MsViewNode);
  node->label = label;
  return node;
}

MsViewNode *ms_view_node_text(MsArena *arena, const char *label) {
  return ms_view_node(arena, ms_span_of_text(label));
}

const MsFact *ms_fact_find(const MsFactModel *model, MsSpan key) {
  size_t low = 0;
  size_t high = model->entities.len;
  while (low < high) {
    const size_t mid = low + (high - low) / 2;
    const int order = ms_span_compare(model->entities.ptr[mid].key, key);
    if (order == 0) {
      return &model->entities.ptr[mid];
    }
    if (order < 0) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return NULL;
}

static MsFact *fact_mut(MsFactModel *model, MsSpan key) {
  size_t low = 0;
  size_t high = model->entities.len;
  while (low < high) {
    const size_t mid = low + (high - low) / 2;
    const int order = ms_span_compare(model->entities.ptr[mid].key, key);
    if (order == 0) {
      return &model->entities.ptr[mid];
    }
    if (order < 0) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return NULL;
}

static void append_unique(MsArena *arena, MsSpans *list, MsSpan value) {
  if (!ms_spans_contains(list, value)) {
    ms_spans_push(arena, list, value);
  }
}

static void sort_spans(MsSpans *list) {
  ms_sort((uint8_t *)list->ptr, list->len, sizeof(MsSpan), ms_sort_compare_spans, NULL);
}

/* `E` of a function type whose result is `Result[T, E]`, or empty. */
static MsSpan error_type(MsSpan signature) {
  if (!ms_span_starts_with(signature, ms_span_of_text("fn("))) {
    return (MsSpan){0};
  }
  const uint8_t *params = signature.ptr + 3;
  const size_t length = signature.len - 3;
  size_t end = 0;
  int depth = 1;
  while (end < length && depth > 0) {
    depth += params[end] == '(' ? 1 : params[end] == ')' ? -1 : 0;
    end++;
  }
  MsSpan result = ms_span_of(params + end, length - end);
  while (result.len > 0 && result.ptr[0] == ' ') {
    result = ms_span_of(result.ptr + 1, result.len - 1);
  }
  if (depth != 0 || !ms_span_starts_with(result, ms_span_of_text("Result["))) {
    return (MsSpan){0};
  }
  MsSpan inner = ms_span_of(result.ptr + 7, result.len - 7);
  if (inner.len > 0 && inner.ptr[inner.len - 1] == ']') {
    inner.len--;
  }
  int nest = 0;
  for (size_t i = 0; i < inner.len; i++) {
    const uint8_t b = inner.ptr[i];
    nest += (b == '[' || b == '(') ? 1 : (b == ']' || b == ')') ? -1 : 0;
    if (b == ',' && nest == 0) {
      MsSpan rest = ms_span_of(inner.ptr + i + 1, inner.len - i - 1);
      while (rest.len > 0 && rest.ptr[0] == ' ') {
        rest = ms_span_of(rest.ptr + 1, rest.len - 1);
      }
      return rest;
    }
  }
  return (MsSpan){0};
}

/* ---- written types ---- */

static MsSpan type_text(MsArena *arena, const MsCheckProgram *program, const MsTypeRef *ref) {
  if (ref == NULL) {
    return (MsSpan){0};
  }
  MsStrBuild text = ms_strbuild_new();
  if (ref->kind == MS_TYPE_NAMED) {
    ms_strbuild_append(&text, ms_names_span(program->names, ref->name));
    if (ref->args.len > 0) {
      ms_strbuild_append_text(&text, "[");
      for (uint32_t i = 0; i < ref->args.len; i++) {
        ms_strbuild_append_text(&text, i == 0 ? "" : ", ");
        ms_strbuild_append(&text, type_text(arena, program, ref->args.ptr[i]));
      }
      ms_strbuild_append_text(&text, "]");
    }
  } else {
    ms_strbuild_append_text(&text, "fn(");
    bool first = true;
    for (uint32_t i = 0; i < ref->params.len; i++) {
      if (ref->params.ptr[i]->ty == NULL) {
        continue;
      }
      ms_strbuild_append_text(&text, first ? "" : ", ");
      ms_strbuild_append(&text, type_text(arena, program, ref->params.ptr[i]->ty));
      first = false;
    }
    ms_strbuild_append_text(&text, ") ");
    ms_strbuild_append(&text, type_text(arena, program, ref->result));
  }
  const MsSpan out = ms_message_take_builder(arena, &text);
  return out;
}

static MsSlot param_slot(MsArena *arena, const MsCheckProgram *program, const MsParam *p) {
  MsSlot slot = {.name = ms_names_span(program->names, p->name), .ty = type_text(arena, program, p->ty)};
  slot.var = p->is_mutable;
  return slot;
}

static MsSlot result_slot(MsArena *arena, const MsCheckProgram *program, const MsTypeRef *result) {
  MsSlot slot = {0};
  slot.ty = result == NULL ? ms_span_of_text("Void") : type_text(arena, program, result);
  return slot;
}

static void param_slots(MsArena *arena, const MsCheckProgram *program, MsParams params, MsSlots *out) {
  for (uint32_t i = 0; i < params.len; i++) {
    ms_slots_push(arena, out, param_slot(arena, program, params.ptr[i]));
  }
}

static MsSpan join_fields(MsArena *arena, const MsSlots *slots) {
  MsStrBuild text = ms_strbuild_new();
  for (size_t i = 0; i < slots->len; i++) {
    ms_strbuild_append_text(&text, i == 0 ? "" : ", ");
    ms_strbuild_append(&text, slots->ptr[i].name);
    ms_strbuild_append_text(&text, ": ");
    ms_strbuild_append(&text, slots->ptr[i].ty);
  }
  const MsSpan out = ms_message_take_builder(arena, &text);
  return out;
}

/* Fields, case payloads or parameters, and the result, of one declaration. */
static void declared_slots(MsArena *arena, const MsCheckProgram *program, const MsDecl *decl, MsFact *fact) {
  switch ((MsDeclKind)decl->kind) {
  case MS_D_TYPE: param_slots(arena, program, decl->u.type.fields, &fact->slots); break;
  case MS_D_ENUM:
    for (uint32_t i = 0; i < decl->u.enumeration.cases.len; i++) {
      const MsCase *c = decl->u.enumeration.cases.ptr[i];
      MsSlots fields = {0};
      param_slots(arena, program, c->fields, &fields);
      MsSlot slot = {.name = ms_names_span(program->names, c->name)};
      if (fields.len > 0) {
        slot.ty = ms_message_format(arena, "(%S)", join_fields(arena, &fields));
      }
      ms_slots_push(arena, &fact->slots, slot);
    }
    break;
  case MS_D_INTERFACE:
    for (uint32_t i = 0; i < decl->u.iface.methods.len; i++) {
      const MsMethod *m = decl->u.iface.methods.ptr[i];
      MsSlots params = {0};
      param_slots(arena, program, m->func.params, &params);
      const MsSlot result = result_slot(arena, program, m->func.result);
      MsSlot slot = {.name = ms_names_span(program->names, m->func.name), .var = m->mutating, .mode = MS_MODE_UNSPECIFIED};
      slot.ty = ms_message_format(arena, "(%S) %S", join_fields(arena, &params), result.ty);
      ms_slots_push(arena, &fact->slots, slot);
    }
    break;
  case MS_D_FN:
    param_slots(arena, program, decl->u.fn.params, &fact->slots);
    fact->has_result = true;
    fact->result = result_slot(arena, program, decl->u.fn.result);
    break;
  case MS_D_ALIAS: {
    MsStrBuild text = ms_strbuild_new();
    for (uint32_t i = 0; i < decl->u.alias.targets.len; i++) {
      ms_strbuild_append_text(&text, i == 0 ? "" : " | ");
      ms_strbuild_append(&text, type_text(arena, program, decl->u.alias.targets.ptr[i]));
    }
    fact->has_result = true;
    fact->result = (MsSlot){.ty = ms_arena_copy(arena, ms_strbuild_span(&text))};
    ms_strbuild_free(&text);
    break;
  }
  case MS_D_CONST:
  case MS_D_IMPL:
  case MS_D_TEST: break;
  }
}

/* ---- counting try sites and cleanup scopes ---- */

typedef struct Counts {
  const MsFacts *facts;
  size_t tries, scopes;
} Counts;

static void count_stmt(void *ctx, const MsStmt *s) {
  Counts *counts = ctx;
  if (s->kind == MS_S_BIND && ms_flow_scoped(counts->facts, s->u.bind.pattern->id)) {
    counts->scopes++;
  }
}

static void count_expr(void *ctx, const MsExpr *e) {
  Counts *counts = ctx;
  if (e->kind == MS_E_UNARY && e->op == MS_U_TRY) {
    counts->tries++;
  }
}

static Counts count_callable(const MsFacts *facts, MsParams params, MsStmts body) {
  Counts counts = {.facts = facts};
  const MsVisitor visitor = {.ctx = &counts, .stmt = count_stmt, .expr = count_expr};
  ms_walk_callable(&visitor, params, body);
  return counts;
}

static Counts count_declaration(const MsFacts *facts, const MsDecl *decl) {
  if (decl->kind == MS_D_FN) {
    return count_callable(facts, decl->u.fn.params, decl->u.fn.body);
  }
  if (decl->kind == MS_D_TEST) {
    return count_callable(facts, (MsParams){0}, decl->u.test.body);
  }
  Counts counts = {.facts = facts};
  if (decl->kind == MS_D_CONST) {
    const MsVisitor visitor = {.ctx = &counts, .stmt = count_stmt, .expr = count_expr};
    ms_walk_expr(&visitor, decl->u.konst.value);
  }
  return counts;
}

/* ---- the model ---- */

typedef struct Builder {
  MsArena *arena;
  MsCheckProgram *program;
  MsFactModel *model;
  const MsInspection *inspection;
  MsSpan *keys; /* the fact key of each inspection entity */
} Builder;

static MsSpan fact_key(MsArena *arena, MsSpan file, MsSpan kind, MsSpan name) {
  return ms_message_format(arena, "%S#%S#%S", file, kind, name);
}

MsSpan ms_entity_key(const MsInspection *inspection, const MsSpan *keys, MsSpan id) {
  size_t low = 0;
  size_t high = inspection->entities.len;
  while (low < high) {
    const size_t mid = low + (high - low) / 2;
    const int order = ms_span_compare(inspection->entities.ptr[mid].id, id);
    if (order == 0) {
      return keys[mid];
    }
    if (order < 0) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return (MsSpan){0};
}

static int64_t compare_fact(uint8_t *env, const uint8_t *left, const uint8_t *right) {
  (void)env;
  return ms_span_compare(((const MsFact *)(const void *)left)->key, ((const MsFact *)(const void *)right)->key);
}

/* One fact per inspection entity, keyed by `file#kind#name`, in key order. */
static void add_entities(Builder *b) {
  const MsInspection *inspection = b->inspection;
  b->keys = MS_ARENA_NEW_ARRAY(b->arena, MsSpan, inspection->entities.len + 1);
  for (size_t i = 0; i < inspection->entities.len; i++) {
    const MsEntity *e = &inspection->entities.ptr[i];
    b->keys[i] = fact_key(b->arena, e->file, e->kind, e->name);
    MsFact fact = {.key = b->keys[i], .file = e->file, .kind = e->kind, .name = e->name, .ty = e->ty,
                   .exported = e->exported, .line = e->pos.line, .error = error_type(e->ty)};
    for (size_t k = 0; k < e->effects.len; k++) {
      ms_spans_push(b->arena, &fact.effects, e->effects.ptr[k]);
      ms_spans_push(b->arena, &fact.reach, e->effects.ptr[k]);
    }
    ms_fact_list_push(b->arena, &b->model->entities, fact);
  }
  ms_sort((uint8_t *)b->model->entities.ptr, b->model->entities.len, sizeof(MsFact), compare_fact, NULL);
}

/* The call edges of every entity: project entities called, and everything else called. */
static void add_edges(Builder *b) {
  for (size_t i = 0; i < b->inspection->calls.len; i++) {
    const MsCallSite *call = &b->inspection->calls.ptr[i];
    const MsSpan owner_key = ms_entity_key(b->inspection, b->keys, call->owner);
    if (owner_key.len == 0) {
      continue;
    }
    MsFact *owner = fact_mut(b->model, owner_key);
    const MsSpan target_key = ms_entity_key(b->inspection, b->keys, call->target);
    if (target_key.len > 0) {
      append_unique(b->arena, &owner->calls, target_key);
    } else {
      append_unique(b->arena, &owner->external, call->target);
    }
  }
}

/* The lines of `source`, split at `\n`. */
static MsSpan *split_lines(MsArena *arena, MsSpan source, size_t *count) {
  size_t lines = 1;
  for (size_t i = 0; i < source.len; i++) {
    lines += source.ptr[i] == '\n' ? 1 : 0;
  }
  MsSpan *out = MS_ARENA_NEW_ARRAY(arena, MsSpan, lines);
  size_t start = 0;
  size_t at = 0;
  for (size_t i = 0; i <= source.len; i++) {
    if (i == source.len || source.ptr[i] == '\n') {
      out[at++] = ms_span_of(source.ptr + start, i - start);
      start = i + 1;
    }
  }
  *count = lines;
  return out;
}

static MsSpan method_key(Builder *b, MsSpan file, MsSpan owner, const MsMethod *method) {
  const MsSpan name = ms_message_format(b->arena, "%S.%S", owner, ms_names_span(b->program->names, method->func.name));
  return fact_key(b->arena, file, ms_span_of_text("method"), name);
}

static void method_slots(Builder *b, const MsMethod *method, MsFact *fact) {
  param_slots(b->arena, b->program, method->func.params, &fact->slots);
  fact->has_result = true;
  fact->result = result_slot(b->arena, b->program, method->func.result);
}

/* Records each declaration's line range, try and scope counts, slots and flow steps. */
static void collect_bodies(Builder *b, uint32_t module, const MsFlow *flow) {
  const MsModuleInfo *info = &b->program->modules.ptr[module];
  const MsModule *tree = info->tree;
  const MsSpan file = flow->file;
  const size_t total = flow->line_count;
  for (uint32_t d = 0; d < tree->ndecls; d++) {
    const MsDecl *decl = tree->decls[d];
    const size_t last = d + 1 < tree->ndecls ? tree->decls[d + 1]->pos.line - 1 : total;
    const MsSpan name = ms_decl_entity_name(b->arena, b->program, decl);
    const MsSpan kind = ms_span_of_text(ms_decl_entity_kind(decl));
    MsFact *fact = fact_mut(b->model, fact_key(b->arena, file, kind, name));
    if (fact != NULL) {
      fact->first = decl->pos.line;
      fact->last = last;
      const Counts counts = count_declaration(&info->facts, decl);
      fact->tries = counts.tries;
      fact->scopes = counts.scopes;
      MsViewNodes steps = {0};
      if (decl->kind == MS_D_FN) {
        ms_flow_body(flow, decl->u.fn.body, &steps);
      } else if (decl->kind == MS_D_TEST) {
        ms_flow_body(flow, decl->u.test.body, &steps);
      } else if (decl->kind == MS_D_CONST) {
        ms_flow_constant(flow, decl->u.konst.init_pos, decl->u.konst.value, &steps);
      }
      fact->flow = steps;
      fact->has_flow = true;
      declared_slots(b->arena, b->program, decl, fact);
    }
    if (decl->kind != MS_D_IMPL) {
      continue;
    }
    for (uint32_t i = 0; i < decl->u.impl.methods.len; i++) {
      const MsMethod *method = decl->u.impl.methods.ptr[i];
      const size_t end = i + 1 < decl->u.impl.methods.len ? decl->u.impl.methods.ptr[i + 1]->pos.line - 1 : last;
      MsFact *m = fact_mut(b->model, method_key(b, file, name, method));
      if (m == NULL) {
        continue;
      }
      m->label = ms_message_format(b->arena, "%S.%S", type_text(b->arena, b->program, decl->u.impl.receiver),
                                   ms_names_span(b->program->names, method->func.name));
      m->first = method->pos.line;
      m->last = end;
      const Counts counts = count_callable(&info->facts, method->func.params, method->func.body);
      m->tries = counts.tries;
      m->scopes = counts.scopes;
      method_slots(b, method, m);
      MsViewNodes steps = {0};
      ms_flow_body(flow, method->func.body, &steps);
      m->flow = steps;
      m->has_flow = true;
    }
  }
}

/* ---- ownership ---- */

static void callable_ownership(Builder *b, MsClassifier *classes, MsFact *fact, uint32_t module, MsNode node,
                               MsParams params, MsTy fn_ty, const MsMethod *method) {
  const MsTyTable *types = &b->program->types;
  const uint32_t taken = ms_own_taken_mask(b->program, module, node);
  for (uint32_t i = 0; i < params.len && i < fact->slots.len; i++) {
    MsTy ty = MS_TY_NONE;
    if (fn_ty != MS_TY_NONE && i < ms_ty_param_count(types, fn_ty)) {
      ty = ms_ty_params(types, fn_ty)[i].ty;
    }
    MsSlot *slot = &fact->slots.ptr[i];
    if (ty != MS_TY_NONE && ms_class_of(classes, ty) == MS_CLASS_COPY) {
      slot->mode = MS_MODE_COPY;
    } else if (params.ptr[i]->moving || ((taken >> i) & 1U) != 0) {
      slot->mode = MS_MODE_MOVE;
    } else {
      slot->mode = MS_MODE_BORROW;
    }
  }
  if (method != NULL) {
    fact->receiver = ms_span_of_text(method->mutating ? "var" : method->consuming ? "move" : "borrow");
  }
  const uint32_t borrows = ms_own_result_borrow_mask(b->program, module, node);
  fact->result_ownership = (borrows & MS_RESULT_BORROWED) != 0 ? MS_RESULT_BORROW : MS_RESULT_OWNED;
}

static MsTy symbol_type(const MsCheckProgram *program, uint32_t module, const MsDecl *decl) {
  MsName name = 0;
  if (!ms_check_declared_name(decl, &name)) {
    return MS_TY_NONE;
  }
  const MsSymbolId *found = ms_scope_get(&program->modules.ptr[module].scope, name);
  return found == NULL ? MS_TY_NONE : program->symbols.ptr[*found].ty;
}

static const MsMethodEntry *method_entry(const MsCheckProgram *program, uint32_t module, const MsMethod *method) {
  for (size_t i = 0; i < program->methods.len; i++) {
    const MsMethodEntry *entry = &program->methods.ptr[i];
    if (entry->module == module && entry->source == method) {
      return entry;
    }
  }
  return NULL;
}

static void collect_ownership(Builder *b, uint32_t module) {
  MsClassifier classes = ms_class_new(b->program);
  const MsModule *tree = b->program->modules.ptr[module].tree;
  const MsSpan file = ms_names_span(b->program->names, b->program->modules.ptr[module].file);
  for (uint32_t d = 0; d < tree->ndecls; d++) {
    const MsDecl *decl = tree->decls[d];
    const MsSpan name = ms_decl_entity_name(b->arena, b->program, decl);
    if (decl->kind == MS_D_FN) {
      MsFact *fact = fact_mut(b->model, fact_key(b->arena, file, ms_span_of_text("fn"), name));
      if (fact != NULL) {
        callable_ownership(b, &classes, fact, module, decl->id, decl->u.fn.params, symbol_type(b->program, module, decl), NULL);
      }
    }
    if (decl->kind != MS_D_IMPL) {
      continue;
    }
    for (uint32_t i = 0; i < decl->u.impl.methods.len; i++) {
      const MsMethod *method = decl->u.impl.methods.ptr[i];
      MsFact *fact = fact_mut(b->model, method_key(b, file, name, method));
      const MsMethodEntry *entry = method_entry(b->program, module, method);
      if (fact != NULL) {
        callable_ownership(b, &classes, fact, module, method->id, method->func.params, entry == NULL ? MS_TY_NONE : entry->ty, method);
      }
    }
  }
  ms_class_free(&classes);
}

/* ---- type references ---- */

/* The key of the project type declared by definition `def`, or empty. */
static MsSpan def_key(const Builder *b, uint32_t def) {
  const MsCheckProgram *program = b->program;
  if (def == 0 || def >= program->defs.count) {
    return (MsSpan){0};
  }
  const MsSymbol *symbol = &program->symbols.ptr[ms_defs_get(&program->defs, def)->symbol];
  if (symbol->decl == NULL || symbol->module >= program->user_modules) {
    return (MsSpan){0};
  }
  const MsSpan file = ms_names_span(program->names, program->modules.ptr[symbol->module].file);
  return fact_key(b->arena, file, ms_span_of_text(ms_decl_entity_kind(symbol->decl)),
                  ms_decl_entity_name(b->arena, program, symbol->decl));
}

/* The project types the components of the written type name, in the order the Rust port visits them. */
static void type_refs(Builder *b, MsTy root, MsSpans *refs) {
  const MsTyTable *types = &b->program->types;
  MsTyList pending = {0};
  MsTyList seen = {0};
  ms_ty_list_push(&pending, root);
  while (pending.len > 0) {
    const MsTy ty = pending.ptr[--pending.len];
    bool visited = false;
    for (size_t i = 0; i < seen.len; i++) {
      visited = visited || seen.ptr[i] == ty;
    }
    if (visited || ty == MS_TY_NONE) {
      continue;
    }
    ms_ty_list_push(&seen, ty);
    const MsTyRow *row = ms_ty_row(types, ty);
    const MsSpan key = def_key(b, row->def);
    if (key.len > 0 && (row->kind == MS_TY_TYPE || row->kind == MS_TY_ALTERNATIVE || row->kind == MS_TY_CONTRACT)) {
      append_unique(b->arena, refs, key);
    }
    if (row->result != MS_TY_NONE) {
      ms_ty_list_push(&pending, row->result);
    }
    for (size_t i = ms_ty_param_count(types, ty); i > 0; i--) {
      ms_ty_list_push(&pending, ms_ty_params(types, ty)[i - 1].ty);
    }
    for (size_t i = ms_ty_arg_count(types, ty); i > 0; i--) {
      ms_ty_list_push(&pending, ms_ty_args(types, ty)[i - 1]);
    }
  }
  ms_ty_list_free(&pending);
  ms_ty_list_free(&seen);
}

static void keep_project_refs(const MsFactModel *model, MsSpans *refs) {
  size_t kept = 0;
  for (size_t i = 0; i < refs->len; i++) {
    if (ms_fact_find(model, refs->ptr[i]) != NULL) {
      refs->ptr[kept++] = refs->ptr[i];
    }
  }
  refs->len = kept;
}

static void resolve_callable_refs(Builder *b, MsFact *fact, MsTy ty) {
  const MsTyTable *types = &b->program->types;
  for (size_t i = 0; i < fact->slots.len && i < ms_ty_param_count(types, ty); i++) {
    type_refs(b, ms_ty_params(types, ty)[i].ty, &fact->slots.ptr[i].refs);
  }
  if (fact->has_result && ms_ty_result(types, ty) != MS_TY_NONE) {
    type_refs(b, ms_ty_result(types, ty), &fact->result.refs);
  }
}

static void resolve_def_refs(Builder *b, MsFact *fact, const MsDef *def) {
  if (ms_span_is_text(fact->kind, "type")) {
    for (size_t i = 0; i < fact->slots.len && i < def->fields.len; i++) {
      type_refs(b, def->fields.ptr[i].ty, &fact->slots.ptr[i].refs);
    }
  } else if (ms_span_is_text(fact->kind, "alternative")) {
    for (size_t i = 0; i < fact->slots.len && i < def->cases.len; i++) {
      for (size_t f = 0; f < def->cases.ptr[i].fields.len; f++) {
        MsSpans found = {0};
        type_refs(b, def->cases.ptr[i].fields.ptr[f].ty, &found);
        for (size_t k = 0; k < found.len; k++) {
          append_unique(b->arena, &fact->slots.ptr[i].refs, found.ptr[k]);
        }
      }
    }
  } else if (ms_span_is_text(fact->kind, "interface")) {
    for (size_t i = 0; i < fact->slots.len && i < def->operations.len; i++) {
      type_refs(b, def->operations.ptr[i].ty, &fact->slots.ptr[i].refs);
    }
  }
}

static void resolve_type_refs(Builder *b) {
  const MsCheckProgram *program = b->program;
  for (uint32_t m = 0; m < program->user_modules; m++) {
    const MsModuleInfo *info = &program->modules.ptr[m];
    const MsSpan file = ms_names_span(program->names, info->file);
    for (uint32_t d = 0; d < info->tree->ndecls; d++) {
      const MsDecl *decl = info->tree->decls[d];
      MsName declared = 0;
      if (!ms_check_declared_name(decl, &declared)) {
        continue;
      }
      const MsSymbolId *found = ms_scope_get(&info->scope, declared);
      const MsSymbol *symbol = found == NULL ? NULL : &program->symbols.ptr[*found];
      if (symbol == NULL || symbol->decl != decl || symbol->ty == MS_TY_NONE) {
        continue;
      }
      MsFact *fact = fact_mut(b->model, fact_key(b->arena, file, ms_span_of_text(ms_decl_entity_kind(decl)),
                                                 ms_decl_entity_name(b->arena, program, decl)));
      if (fact == NULL) {
        continue;
      }
      if (decl->kind == MS_D_FN) {
        resolve_callable_refs(b, fact, symbol->ty);
      } else if (symbol->def != 0 && symbol->def < program->defs.count) {
        resolve_def_refs(b, fact, ms_defs_get(&program->defs, symbol->def));
      }
    }
    for (size_t i = 0; i < program->methods.len; i++) {
      const MsMethodEntry *entry = &program->methods.ptr[i];
      if (entry->module != m || entry->source == NULL) {
        continue;
      }
      for (uint32_t d = 0; d < info->tree->ndecls; d++) {
        const MsDecl *decl = info->tree->decls[d];
        if (decl->kind != MS_D_IMPL || decl->u.impl.methods.len == 0) {
          continue;
        }
        for (uint32_t k = 0; k < decl->u.impl.methods.len; k++) {
          if (decl->u.impl.methods.ptr[k] != entry->source) {
            continue;
          }
          MsFact *fact = fact_mut(b->model, method_key(b, file, ms_decl_entity_name(b->arena, program, decl), entry->source));
          if (fact != NULL) {
            resolve_callable_refs(b, fact, entry->ty);
          }
        }
      }
    }
  }
  for (size_t i = 0; i < b->model->entities.len; i++) {
    MsFact *fact = &b->model->entities.ptr[i];
    for (size_t s = 0; s < fact->slots.len; s++) {
      keep_project_refs(b->model, &fact->slots.ptr[s].refs);
    }
    if (fact->has_result) {
      keep_project_refs(b->model, &fact->result.refs);
    }
  }
}

/* ---- modules ---- */

static int64_t compare_imports(uint8_t *env, const uint8_t *left, const uint8_t *right) {
  (void)env;
  return ms_span_compare(((const MsImports *)(const void *)left)->file, ((const MsImports *)(const void *)right)->file);
}

static void collect_modules(Builder *b) {
  for (uint32_t m = 0; m < b->program->user_modules; m++) {
    const MsModuleInfo *info = &b->program->modules.ptr[m];
    MsImports imports = {.file = ms_names_span(b->program->names, info->file), .source = info->source};
    for (uint32_t i = 0; i < info->tree->nimports; i++) {
      append_unique(b->arena, &imports.paths, info->tree->imports[i].path);
    }
    sort_spans(&imports.paths);
    ms_import_list_push(b->arena, &b->model->imports, imports);
    size_t line_count = 0;
    const MsSpan *lines = split_lines(b->arena, info->source, &line_count);
    const MsFlow flow = {.arena = b->arena, .file = imports.file, .lines = lines, .line_count = line_count,
                         .inspection = b->inspection, .keys = b->keys, .facts = &info->facts};
    collect_bodies(b, m, &flow);
    collect_ownership(b, m);
  }
  ms_sort((uint8_t *)b->model->imports.ptr, b->model->imports.len, sizeof(MsImports), compare_imports, NULL);
}

MsFactModel ms_facts_collect(MsArena *arena, MsCheckProgram *program) {
  MsFactModel model = {0};
  MsInspection inspection = {0};
  ms_inspect_collect(arena, program, false, &inspection);
  Builder b = {.arena = arena, .program = program, .model = &model, .inspection = &inspection};
  add_entities(&b);
  add_edges(&b);
  collect_modules(&b);
  resolve_type_refs(&b);
  for (size_t i = 0; i < model.entities.len; i++) {
    MsFact *fact = &model.entities.ptr[i];
    sort_spans(&fact->calls);
    sort_spans(&fact->external);
    sort_spans(&fact->effects);
    sort_spans(&fact->reach);
  }
  ms_inspection_free(&inspection);
  return model;
}

MsSpan ms_spans_joined(MsArena *arena, const MsSpans *list, const char *separator) {
  MsStrBuild out = ms_strbuild_new();
  for (size_t i = 0; i < list->len; i++) {
    ms_strbuild_append_text(&out, i == 0 ? "" : separator);
    ms_strbuild_append(&out, list->ptr[i]);
  }
  return ms_message_take_builder(arena, &out);
}

MsSpan ms_effects_joined(MsArena *arena, const MsSpans *effects) {
  return effects->len == 0 ? ms_span_of_text("none") : ms_spans_joined(arena, effects, "+");
}
