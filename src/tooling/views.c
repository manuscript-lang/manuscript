/* Owns views.h: port of crates/ms-tooling/src/{views,tree}.rs. */
#include "tooling/views.h"
#include "tooling/views_private.h"

#include "base/message.h"
#include "compiler/syntax/diag_json.h"

/* ---- small helpers ---- */

static MsSpan upper(MsArena *arena, MsSpan word) {
  uint8_t *copy = MS_ARENA_NEW_ARRAY(arena, uint8_t, word.len + 1);
  for (size_t i = 0; i < word.len; i++) {
    copy[i] = word.ptr[i] >= 'a' && word.ptr[i] <= 'z' ? (uint8_t)(word.ptr[i] - 'a' + 'A') : word.ptr[i];
  }
  return ms_span_of(copy, word.len);
}

static MsSpan or_none(MsSpan value) {
  return value.len == 0 ? text("none") : value;
}

static MsViewNode *kid(MsArena *arena, MsViewNode *parent, MsViewNode *child) {
  ms_view_nodes_push(arena, &parent->kids, child);
  return child;
}

static MsViewNode *leaf(MsArena *arena, MsSpan label) {
  return ms_view_node(arena, label);
}

static MsViewNode *copy_shallow(MsArena *arena, const MsViewNode *n) {
  MsViewNode *node = ms_view_node(arena, n->label);
  node->kind = n->kind;
  node->reference = n->reference;
  node->file = n->file;
  node->line = n->line;
  return node;
}

static MsViewNode *head_node(MsArena *arena, const MsFact *f) {
  MsViewNode *node = ms_view_node(arena, ms_message_format(arena, "%S  [%S] %S:%z", f->name, f->kind, f->file, f->line));
  node->reference = f->key;
  node->kind = f->kind;
  node->file = f->file;
  node->line = f->line;
  return node;
}

static void capped(MsArena *arena, MsViewNode *root, size_t skipped) {
  if (skipped > 0) {
    root->omitted = skipped;
    kid(arena, root, leaf(arena, ms_message_format(arena, "+%z more (output capped at %z nodes)", skipped, (size_t)MS_NODE_CAP)));
  }
}

const MsFact *ms_views_fact_of(const MsFactModel *model, MsSpan key) {
  return ms_fact_find(model, key);
}

/* ---- entity lookup ---- */

static MsSpan qualified(MsArena *arena, const MsFact *f) {
  return ms_message_format(arena, "%S::%S", f->file, f->name);
}

const MsFact *ms_find_entity(MsArena *arena, const MsFactModel *model, MsSpan name, MsSpan *error) {
  const MsFact *exact = ms_fact_find(model, name);
  if (exact != NULL) {
    return exact;
  }
  const MsFact *matches[64];
  size_t count = 0;
  size_t total = 0;
  for (size_t i = 0; i < model->entities.len; i++) {
    const MsFact *f = &model->entities.ptr[i];
    if (ms_span_equal(f->name, name) || ms_span_equal(qualified(arena, f), name)) {
      if (count < 64) {
        matches[count++] = f;
      }
      total++;
    }
  }
  if (total == 1) {
    return matches[0];
  }
  if (total == 0) {
    *error = ms_message_format(arena,
        "no entity named %S; use a declaration name, file::name, or full entity ID file#kind#name (ms review lists the public surface)",
        name);
    return NULL;
  }
  /* A type and its impl share file::name; test names can equal another entity's qualified name or key. Count every
   * name match before offering qualified names as the remedy. */
  bool usable = true;
  for (size_t m = 0; m < count; m++) {
    const MsSpan key = qualified(arena, matches[m]);
    size_t hits = 0;
    for (size_t i = 0; i < model->entities.len; i++) {
      const MsFact *f = &model->entities.ptr[i];
      hits += ms_span_equal(f->name, key) ? 1 : 0;
      const MsSpan q = qualified(arena, f);
      hits += (!ms_span_equal(q, f->name) && ms_span_equal(q, key)) ? 1 : 0;
    }
    const MsFact *exact_match = ms_fact_find(model, key);
    usable = usable && (exact_match != NULL ? ms_span_equal(exact_match->key, matches[m]->key) : hits == 1);
  }
  MsStrBuild list = ms_strbuild_new();
  for (size_t m = 0; m < count; m++) {
    ms_strbuild_append_text(&list, m == 0 ? "" : ", ");
    ms_strbuild_append(&list, usable ? qualified(arena, matches[m]) : matches[m]->key);
  }
  *error = ms_message_format(arena, "%S is ambiguous; use one of: %S", name, ms_strbuild_span(&list));
  ms_strbuild_free(&list);
  return NULL;
}

/* ---- calls, effects and errors ---- */

typedef struct Expander {
  MsArena *arena;
  const MsFactModel *model;
  MsSpan view;
  int64_t depth;
  size_t count, skipped;
} Expander;

static bool relevant(MsSpan view, const MsFact *f) {
  if (is(view, "effects")) {
    return f->effects.len > 0;
  }
  if (is(view, "errors")) {
    return f->error.len > 0 || f->tries > 0;
  }
  return true;
}

static MsSpan expander_label(Expander *x, const MsFact *f) {
  if (is(x->view, "effects")) {
    return ms_message_format(x->arena, "%S  effects: %S", f->name, ms_effects_joined(x->arena, &f->effects));
  }
  if (is(x->view, "errors")) {
    return ms_message_format(x->arena, "%S  error: %S, try sites: %z", f->name, or_none(f->error), f->tries);
  }
  return ms_message_format(x->arena, "%S  [%S] %S:%z", f->name, f->kind, f->file, f->line);
}

static MsViewNode *expand(Expander *x, const MsFact *f, int64_t level, MsSpans *path) {
  MsViewNode *node = ms_view_node(x->arena, expander_label(x, f));
  node->reference = f->key;
  node->kind = f->kind;
  node->file = f->file;
  node->line = f->line;
  x->count++;
  if (level >= x->depth) {
    return node;
  }
  ms_spans_push(x->arena, path, f->key);
  for (size_t i = 0; i < f->calls.len; i++) {
    const MsSpan key = f->calls.ptr[i];
    const MsFact *callee = ms_views_fact_of(x->model, key);
    if (callee == NULL || !relevant(x->view, callee)) {
      continue;
    }
    if (ms_spans_contains(path, key)) {
      if (x->count >= MS_NODE_CAP) {
        x->skipped++;
        continue;
      }
      x->count++;
      MsViewNode *cycle = leaf(x->arena, ms_message_format(x->arena, "%S  (cycle)", callee->name));
      cycle->kind = text("cycle");
      cycle->reference = callee->key;
      cycle->file = callee->file;
      cycle->line = callee->line;
      kid(x->arena, node, cycle);
      continue;
    }
    if (x->count >= MS_NODE_CAP) {
      x->skipped++;
      continue;
    }
    kid(x->arena, node, expand(x, callee, level + 1, path));
  }
  if (is(x->view, "effects") || is(x->view, "calls")) {
    for (size_t i = 0; i < f->external.len; i++) {
      if (is(x->view, "effects") && f->effects.len == 0) {
        break;
      }
      if (x->count >= MS_NODE_CAP) {
        x->skipped++;
        continue;
      }
      x->count++;
      MsViewNode *external = leaf(x->arena, ms_readable_id(x->arena, f->external.ptr[i]));
      external->kind = text("external");
      external->reference = f->external.ptr[i];
      kid(x->arena, node, external);
    }
  }
  path->len--;
  return node;
}

static bool is_callable(const MsFact *f) {
  return one_of(f->kind, "fn", "method", "test");
}

static void mark_reachable(const MsFactModel *model, MsSpan view, MsSpan start, MsSpans *seen, MsArena *arena) {
  MsSpans pending = {0};
  ms_spans_push(arena, &pending, start);
  while (pending.len > 0) {
    const MsSpan key = pending.ptr[--pending.len];
    if (ms_spans_contains(seen, key)) {
      continue;
    }
    ms_spans_push(arena, seen, key);
    const MsFact *fact = ms_views_fact_of(model, key);
    for (size_t i = 0; fact != NULL && i < fact->calls.len; i++) {
      const MsFact *callee = ms_views_fact_of(model, fact->calls.ptr[i]);
      if (callee != NULL && relevant(view, callee)) {
        ms_spans_push(arena, &pending, fact->calls.ptr[i]);
      }
    }
  }
}

void ms_views_roots_push(MsArena *arena, Roots *roots, const MsFact *f) {
  if (roots->len == roots->cap) {
    const size_t cap = roots->cap == 0 ? 8 : roots->cap * 2;
    const MsFact **grown = MS_ARENA_NEW_ARRAY(arena, const MsFact *, cap);
    for (size_t i = 0; i < roots->len; i++) {
      grown[i] = roots->ptr[i];
    }
    roots->ptr = grown;
    roots->cap = cap;
  }
  roots->ptr[roots->len++] = f;
}

static bool view_roots(MsArena *arena, const MsFactModel *model, MsSpan view, MsSpan entity, Roots *roots, MsSpan *error) {
  if (entity.len > 0) {
    const MsFact *f = ms_find_entity(arena, model, entity, error);
    if (f == NULL) {
      return false;
    }
    ms_views_roots_push(arena, roots, f);
    return true;
  }
  MsSpans called = {0};
  for (size_t i = 0; i < model->entities.len; i++) {
    const MsFact *f = &model->entities.ptr[i];
    if (!relevant(view, f)) {
      continue;
    }
    for (size_t c = 0; c < f->calls.len; c++) {
      const MsFact *callee = ms_views_fact_of(model, f->calls.ptr[c]);
      if (callee != NULL && relevant(view, callee)) {
        ms_spans_push(arena, &called, f->calls.ptr[c]);
      }
    }
  }
  for (size_t i = 0; i < model->entities.len; i++) {
    const MsFact *f = &model->entities.ptr[i];
    if (is_callable(f) && relevant(view, f) && !ms_spans_contains(&called, f->key)) {
      ms_views_roots_push(arena, roots, f);
    }
  }
  /* Every callable must be reachable from a root, including disconnected recursive groups. */
  MsSpans reached = {0};
  for (size_t i = 0; i < roots->len; i++) {
    mark_reachable(model, view, roots->ptr[i]->key, &reached, arena);
  }
  for (size_t i = 0; i < model->entities.len; i++) {
    const MsFact *f = &model->entities.ptr[i];
    if (is_callable(f) && relevant(view, f) && !ms_spans_contains(&reached, f->key)) {
      ms_views_roots_push(arena, roots, f);
      mark_reachable(model, view, f->key, &reached, arena);
    }
  }
  return true;
}

static bool call_view(MsArena *arena, const MsFactModel *model, MsSpan view, MsSpan entity, int64_t depth,
                      MsViewNode **out, MsSpan *error) {
  Roots roots = {0};
  if (!view_roots(arena, model, view, entity, &roots, error)) {
    return false;
  }
  Expander x = {.arena = arena, .model = model, .view = view, .depth = depth};
  MsViewNode *root = leaf(arena, ms_message_format(arena, "%S VIEW", upper(arena, view)));
  for (size_t i = 0; i < roots.len; i++) {
    if (x.count >= MS_NODE_CAP) {
      x.skipped++;
      continue;
    }
    MsSpans path = {0};
    kid(arena, root, expand(&x, roots.ptr[i], 0, &path));
  }
  if (roots.len == 0) {
    kid(arena, root, leaf(arena, text("none")));
  }
  capped(arena, root, x.skipped);
  *out = root;
  return true;
}

/* ---- modules ---- */

static bool modules_view(MsArena *arena, const MsFactModel *model, MsSpan entity, MsViewNode **out, MsSpan *error) {
  size_t chosen = 0;
  for (size_t i = 0; i < model->imports.len; i++) {
    chosen += (entity.len == 0 || ms_span_equal(model->imports.ptr[i].file, entity)) ? 1 : 0;
  }
  if (entity.len > 0 && chosen == 0) {
    *error = ms_message_format(arena, "no module named %S; use a project-relative path such as src/main.ms", entity);
    return false;
  }
  MsViewNode *root = leaf(arena, text("MODULES VIEW"));
  size_t count = 0;
  size_t skipped = 0;
  for (size_t i = 0; i < model->imports.len; i++) {
    const MsImports *imports = &model->imports.ptr[i];
    if (entity.len > 0 && !ms_span_equal(imports->file, entity)) {
      continue;
    }
    if (count >= MS_NODE_CAP) {
      skipped++;
      continue;
    }
    count++;
    MsViewNode *module = leaf(arena, imports->file);
    module->kind = text("module");
    module->file = imports->file;
    for (size_t p = 0; p < imports->paths.len; p++) {
      if (count >= MS_NODE_CAP) {
        skipped++;
        continue;
      }
      count++;
      kid(arena, module, leaf(arena, imports->paths.ptr[p]));
    }
    kid(arena, root, module);
  }
  if (chosen == 0) {
    kid(arena, root, leaf(arena, text("none")));
  }
  capped(arena, root, skipped);
  *out = root;
  return true;
}

/* ---- flow, scope and tasks ---- */

typedef struct FlowExpander {
  MsArena *arena;
  const MsFactModel *model;
  int64_t depth;
  size_t count, skipped;
} FlowExpander;

static void flow_expand(FlowExpander *x, const MsViewNodes *nodes, int64_t level, MsSpans *path, MsViewNodes *out) {
  for (size_t i = 0; i < nodes->len; i++) {
    const MsViewNode *n = nodes->ptr[i];
    if (x->count >= MS_NODE_CAP) {
      x->skipped++;
      continue;
    }
    x->count++;
    MsViewNode *copy = copy_shallow(x->arena, n);
    flow_expand(x, &n->kids, level, path, &copy->kids);
    if (n->reference.len > 0 && level < x->depth) {
      if (ms_spans_contains(path, n->reference)) {
        kid(x->arena, copy, leaf(x->arena, text("(cycle)")));
      } else {
        ms_spans_push(x->arena, path, n->reference);
        const MsFact *callee = ms_views_fact_of(x->model, n->reference);
        if (callee != NULL) {
          flow_expand(x, &callee->flow, level + 1, path, &copy->kids);
        }
        path->len--;
      }
    }
    ms_view_nodes_push(x->arena, out, copy);
  }
}

static void prune_scopes(MsArena *arena, const MsViewNodes *nodes, bool in_scope, MsViewNodes *out) {
  for (size_t i = 0; i < nodes->len; i++) {
    const MsViewNode *n = nodes->ptr[i];
    MsViewNodes kids = {0};
    prune_scopes(arena, &n->kids, in_scope || is(n->kind, "scope"), &kids);
    const bool exit = in_scope && (is(n->kind, "exit") || is(n->kind, "try"));
    if (is(n->kind, "scope") || exit || kids.len > 0) {
      MsViewNode *node = ms_view_node(arena, n->label);
      node->kind = n->kind;
      node->file = n->file;
      node->line = n->line;
      node->kids = kids;
      ms_view_nodes_push(arena, out, node);
    }
  }
}

static void prune_tasks(MsArena *arena, const MsViewNodes *nodes, MsViewNodes *out) {
  for (size_t i = 0; i < nodes->len; i++) {
    MsViewNode *n = nodes->ptr[i];
    if (is(n->kind, "spawn")) {
      ms_view_nodes_push(arena, out, n);
      continue;
    }
    MsViewNodes kids = {0};
    prune_tasks(arena, &n->kids, &kids);
    if (kids.len > 0) {
      MsViewNode *node = ms_view_node(arena, n->label);
      node->kind = n->kind;
      node->file = n->file;
      node->line = n->line;
      node->kids = kids;
      ms_view_nodes_push(arena, out, node);
    }
  }
}

static bool flow_view(MsArena *arena, const MsFactModel *model, MsSpan view, MsSpan entity, int64_t depth,
                      MsViewNode **out, MsSpan *error) {
  if (entity.len == 0) {
    *error = ms_message_format(arena, "%S needs --entity; name a function or method (ms review lists the public surface)", view);
    return false;
  }
  const MsFact *f = ms_find_entity(arena, model, entity, error);
  if (f == NULL) {
    return false;
  }
  FlowExpander x = {.arena = arena, .model = model, .depth = depth};
  MsViewNode *root = leaf(arena, ms_message_format(arena, "%S VIEW", upper(arena, view)));
  MsSpans path = {0};
  ms_spans_push(arena, &path, f->key);
  MsViewNodes body = {0};
  flow_expand(&x, &f->flow, 1, &path, &body);
  if (is(view, "scope")) {
    MsViewNodes pruned = {0};
    prune_scopes(arena, &body, false, &pruned);
    body = pruned;
  }
  if (is(view, "tasks")) {
    MsViewNodes pruned = {0};
    prune_tasks(arena, &body, &pruned);
    body = pruned;
  }
  MsViewNode *header = head_node(arena, f);
  header->kids = body;
  if (header->kids.len == 0) {
    kid(arena, header, leaf(arena, text("none")));
  }
  kid(arena, root, header);
  capped(arena, root, x.skipped);
  *out = root;
  return true;
}

/* ---- ownership ---- */

const char *ms_passing_mode(const MsSlot *s) {
  if (s->var) {
    return "var";
  }
  switch ((MsParamMode)s->mode) {
  case MS_MODE_COPY: return "copy";
  case MS_MODE_MOVE: return "move";
  case MS_MODE_BORROW: return "borrow";
  case MS_MODE_UNSPECIFIED: return "";
  }
  return "";
}

const char *ms_result_label(uint8_t ownership) {
  switch ((MsResultOwnership)ownership) {
  case MS_RESULT_OWNED: return "owned";
  case MS_RESULT_BORROW: return "borrow";
  case MS_RESULT_VIEW: return "owned view";
  case MS_RESULT_BORROWED_OK: return "owned; borrowed ok";
  case MS_RESULT_BORROWED_ERROR: return "owned; borrowed error";
  case MS_RESULT_BORROWED_BOTH: return "owned; borrowed ok and error";
  }
  return "owned";
}

static bool has_var_slot(const MsFact *f) {
  for (size_t i = 0; i < f->slots.len; i++) {
    if (f->slots.ptr[i].var) {
      return true;
    }
  }
  return false;
}

bool ms_views_ownership_candidate(const MsFact *f) {
  return one_of(f->kind, "fn", "method", NULL) && (f->scopes > 0 || has_var_slot(f));
}

static MsViewNode *ownership_node(MsArena *arena, const MsFactModel *model, const MsFact *f, int64_t level, int64_t depth,
                                  MsSpans *path, size_t *count) {
  MsViewNode *node = head_node(arena, f);
  (*count)++;
  if (is(f->kind, "interface")) {
    for (size_t i = 0; i < f->slots.len; i++) {
      const MsSlot *op = &f->slots.ptr[i];
      kid(arena, node, leaf(arena, ms_message_format(arena, "%S%S  self %s", op->name, op->ty, op->var ? "var (exclusive borrow)" : "borrow")));
    }
    return node;
  }
  for (size_t i = 0; i < f->slots.len; i++) {
    const MsSlot *s = &f->slots.ptr[i];
    const char *mode = s->var ? "var (exclusive borrow)" : ms_passing_mode(s);
    kid(arena, node, leaf(arena, mode[0] == '\0' ? ms_message_format(arena, "%S: %S", s->name, s->ty)
                                                    : ms_message_format(arena, "%S: %S  %s", s->name, s->ty, mode)));
  }
  if (f->has_result) {
    kid(arena, node, leaf(arena, ms_message_format(arena, "returns %S  %s", f->result.ty, ms_result_label(f->result_ownership))));
  }
  if (f->receiver.len > 0) {
    kid(arena, node, leaf(arena, is(f->receiver, "var") ? text("self  var (exclusive borrow)")
                                                       : ms_message_format(arena, "self  %S", f->receiver)));
  }
  if (f->scopes > 0) {
    kid(arena, node, leaf(arena, ms_message_format(arena, "closes %z resource scope(s)", f->scopes)));
  }
  if (level >= depth) {
    return node;
  }
  ms_spans_push(arena, path, f->key);
  for (size_t i = 0; i < f->calls.len; i++) {
    const MsFact *callee = ms_views_fact_of(model, f->calls.ptr[i]);
    if (callee == NULL || ms_spans_contains(path, f->calls.ptr[i]) || *count >= MS_NODE_CAP) {
      continue;
    }
    kid(arena, node, ownership_node(arena, model, callee, level + 1, depth, path, count));
  }
  path->len--;
  return node;
}

static bool ownership_view(MsArena *arena, const MsFactModel *model, MsSpan entity, int64_t depth, MsViewNode **out, MsSpan *error) {
  Roots roots = {0};
  if (entity.len == 0) {
    for (size_t i = 0; i < model->entities.len; i++) {
      if (ms_views_ownership_candidate(&model->entities.ptr[i])) {
        ms_views_roots_push(arena, &roots, &model->entities.ptr[i]);
      }
    }
  } else {
    const MsFact *f = ms_find_entity(arena, model, entity, error);
    if (f == NULL) {
      return false;
    }
    ms_views_roots_push(arena, &roots, f);
  }
  MsViewNode *root = leaf(arena, text("OWNERSHIP VIEW"));
  size_t count = 0;
  size_t skipped = 0;
  for (size_t i = 0; i < roots.len; i++) {
    if (count >= MS_NODE_CAP) {
      skipped++;
      continue;
    }
    MsSpans path = {0};
    kid(arena, root, ownership_node(arena, model, roots.ptr[i], 0, depth, &path, &count));
  }
  if (roots.len == 0) {
    kid(arena, root, leaf(arena, text("none")));
  }
  capped(arena, root, skipped);
  *out = root;
  return true;
}

/* ---- types ---- */

static MsViewNode *type_node(MsArena *arena, const MsFactModel *model, const MsFact *f, int64_t level, int64_t depth,
                             MsSpans *path, size_t *count) {
  MsViewNode *node = head_node(arena, f);
  (*count)++;
  if (level >= depth) {
    return node;
  }
  ms_spans_push(arena, path, f->key);
  const size_t slots = f->slots.len + (f->has_result ? 1 : 0);
  for (size_t i = 0; i < slots; i++) {
    if (*count >= MS_NODE_CAP) {
      break;
    }
    const MsSlot *s = i < f->slots.len ? &f->slots.ptr[i] : &f->result;
    MsSpan label = {0};
    if (s->name.len == 0) {
      label = ms_message_format(arena, "returns %S", s->ty);
    } else if (is(f->kind, "alternative") && (s->ty.len == 0 || s->ty.ptr[0] == '(')) {
      label = ms_message_format(arena, "case %S%S", s->name, s->ty);
    } else {
      label = ms_message_format(arena, "%S: %S", s->name, s->ty);
    }
    (*count)++;
    MsViewNode *child = leaf(arena, label);
    for (size_t r = 0; r < s->refs.len; r++) {
      const MsFact *target = ms_views_fact_of(model, s->refs.ptr[r]);
      if (target == NULL) {
        continue;
      }
      if (ms_spans_contains(path, s->refs.ptr[r])) {
        MsViewNode *cycle = leaf(arena, ms_message_format(arena, "%S  (cycle)", target->name));
        cycle->kind = text("cycle");
        cycle->reference = s->refs.ptr[r];
        kid(arena, child, cycle);
      } else if (*count < MS_NODE_CAP) {
        kid(arena, child, type_node(arena, model, target, level + 1, depth, path, count));
      }
    }
    kid(arena, node, child);
  }
  path->len--;
  return node;
}

bool ms_views_is_data_type(const MsFact *f) {
  return one_of(f->kind, "type", "alternative", "interface");
}

static bool types_view(MsArena *arena, const MsFactModel *model, MsSpan entity, int64_t depth, MsViewNode **out, MsSpan *error) {
  Roots roots = {0};
  if (entity.len == 0) {
    MsSpans held = {0};
    for (size_t i = 0; i < model->entities.len; i++) {
      const MsFact *f = &model->entities.ptr[i];
      if (!one_of(f->kind, "type", "alternative", NULL)) {
        continue;
      }
      for (size_t s = 0; s < f->slots.len; s++) {
        for (size_t r = 0; r < f->slots.ptr[s].refs.len; r++) {
          ms_spans_push(arena, &held, f->slots.ptr[s].refs.ptr[r]);
        }
      }
    }
    Roots all = {0};
    for (size_t i = 0; i < model->entities.len; i++) {
      const MsFact *f = &model->entities.ptr[i];
      if (ms_views_is_data_type(f)) {
        ms_views_roots_push(arena, &all, f);
        if (!ms_spans_contains(&held, f->key)) {
          ms_views_roots_push(arena, &roots, f);
        }
      }
    }
    if (roots.len == 0) {
      roots = all;
    }
  } else {
    const MsFact *f = ms_find_entity(arena, model, entity, error);
    if (f == NULL) {
      return false;
    }
    ms_views_roots_push(arena, &roots, f);
  }
  MsViewNode *root = leaf(arena, text("TYPES VIEW"));
  size_t count = 0;
  size_t skipped = 0;
  for (size_t i = 0; i < roots.len; i++) {
    if (count >= MS_NODE_CAP) {
      skipped++;
      continue;
    }
    MsSpans path = {0};
    kid(arena, root, type_node(arena, model, roots.ptr[i], 0, depth, &path, &count));
  }
  if (roots.len == 0) {
    kid(arena, root, leaf(arena, text("none")));
  }
  capped(arena, root, skipped);
  *out = root;
  return true;
}

/* ---- overview ---- */

typedef struct Module {
  MsSpan file;
  size_t fns, types, tests;
  bool entry;
  MsSpans effects;
  MsSpans call_files;
  size_t *call_counts;
  size_t call_cap;
} Module;

static void module_call(MsArena *arena, Module *m, MsSpan file) {
  for (size_t i = 0; i < m->call_files.len; i++) {
    if (ms_span_equal(m->call_files.ptr[i], file)) {
      m->call_counts[i]++;
      return;
    }
  }
  if (m->call_files.len == m->call_cap) {
    const size_t cap = m->call_cap == 0 ? 4 : m->call_cap * 2;
    size_t *grown = MS_ARENA_NEW_ARRAY(arena, size_t, cap);
    for (size_t i = 0; i < m->call_files.len; i++) {
      grown[i] = m->call_counts[i];
    }
    m->call_counts = grown;
    m->call_cap = cap;
  }
  m->call_counts[m->call_files.len] = 1;
  ms_spans_push(arena, &m->call_files, file);
}

static void sort_module(Module *m) {
  /* effects and calls ascending; the calls carry counts with them */
  for (size_t i = 1; i < m->effects.len; i++) {
    for (size_t j = i; j > 0 && ms_span_compare(m->effects.ptr[j - 1], m->effects.ptr[j]) > 0; j--) {
      const MsSpan t = m->effects.ptr[j];
      m->effects.ptr[j] = m->effects.ptr[j - 1];
      m->effects.ptr[j - 1] = t;
    }
  }
  for (size_t i = 1; i < m->call_files.len; i++) {
    for (size_t j = i; j > 0 && ms_span_compare(m->call_files.ptr[j - 1], m->call_files.ptr[j]) > 0; j--) {
      const MsSpan t = m->call_files.ptr[j];
      m->call_files.ptr[j] = m->call_files.ptr[j - 1];
      m->call_files.ptr[j - 1] = t;
      const size_t n = m->call_counts[j];
      m->call_counts[j] = m->call_counts[j - 1];
      m->call_counts[j - 1] = n;
    }
  }
}

static Module *overview(MsArena *arena, const MsFactModel *model, size_t *count) {
  Module *modules = MS_ARENA_NEW_ARRAY(arena, Module, model->imports.len + 1);
  for (size_t i = 0; i < model->imports.len; i++) {
    modules[i].file = model->imports.ptr[i].file;
  }
  for (size_t e = 0; e < model->entities.len; e++) {
    const MsFact *f = &model->entities.ptr[e];
    Module *m = NULL;
    for (size_t i = 0; i < model->imports.len; i++) {
      if (ms_span_equal(modules[i].file, f->file)) {
        m = &modules[i];
      }
    }
    if (m == NULL) {
      continue;
    }
    if (one_of(f->kind, "fn", "method", NULL)) {
      m->fns++;
      m->entry = m->entry || is(f->name, "main");
    } else if (ms_views_is_data_type(f)) {
      m->types++;
    } else if (one_of(f->kind, "test", "bench", NULL)) {
      m->tests++;
    }
    for (size_t i = 0; i < f->effects.len; i++) {
      if (!ms_spans_contains(&m->effects, f->effects.ptr[i])) {
        ms_spans_push(arena, &m->effects, f->effects.ptr[i]);
      }
    }
    for (size_t i = 0; i < f->calls.len; i++) {
      const MsFact *target = ms_views_fact_of(model, f->calls.ptr[i]);
      if (target != NULL && !ms_span_equal(target->file, f->file)) {
        module_call(arena, m, target->file);
      }
    }
  }
  for (size_t i = 0; i < model->imports.len; i++) {
    sort_module(&modules[i]);
  }
  *count = model->imports.len;
  return modules;
}

static MsSpan plural(MsArena *arena, size_t n, const char *word) {
  return ms_message_format(arena, "%z %s%s", n, word, n == 1 ? "" : "s");
}

static MsSpan module_summary(MsArena *arena, const Module *m) {
  MsStrBuild out = ms_strbuild_new();
  ms_strbuild_printf(&out, "%zu fn", m->fns);
  if (m->tests > 0) {
    ms_strbuild_append_text(&out, ", ");
    ms_strbuild_append(&out, plural(arena, m->tests, "test"));
  }
  if (m->types > 0) {
    ms_strbuild_append_text(&out, ", ");
    ms_strbuild_append(&out, plural(arena, m->types, "type"));
  }
  const MsSpan summary = ms_arena_copy(arena, ms_strbuild_span(&out));
  ms_strbuild_free(&out);
  return summary;
}

static MsSpan module_line(MsArena *arena, const Module *m) {
  return ms_message_format(arena, "%S%s  %S  effects: %S", m->file, m->entry ? "  [entry]" : "", module_summary(arena, m),
                           ms_effects_joined(arena, &m->effects));
}

static void overview_ascii(MsArena *arena, const Module *modules, size_t count, MsStrBuild *out) {
  for (size_t i = 0; i < count && i < MS_NODE_CAP; i++) {
    ms_strbuild_append(out, module_line(arena, &modules[i]));
    ms_strbuild_append_text(out, "\n");
    for (size_t c = 0; c < modules[i].call_files.len; c++) {
      ms_strbuild_append(out, ms_message_format(arena, "  -> %S  (%S)\n", modules[i].call_files.ptr[c],
                                                plural(arena, modules[i].call_counts[c], "call")));
    }
  }
  if (count == 0) {
    ms_strbuild_append_text(out, "none\n");
  }
}

MsSpan ms_views_sanitize(MsArena *arena, MsSpan word, bool alnum_only_underscore) {
  uint8_t *copy = MS_ARENA_NEW_ARRAY(arena, uint8_t, word.len + 1);
  for (size_t i = 0; i < word.len; i++) {
    const uint8_t b = word.ptr[i];
    const bool keep = (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z') || (b >= '0' && b <= '9') || b >= 0x80 ||
                      (alnum_only_underscore && b == '_');
    copy[i] = keep ? b : '_';
  }
  return ms_span_of(copy, word.len);
}

static void overview_mermaid(MsArena *arena, const Module *modules, size_t count, MsStrBuild *out) {
  ms_strbuild_append_text(out, "flowchart LR\n");
  for (size_t i = 0; i < count && i < MS_NODE_CAP; i++) {
    const Module *m = &modules[i];
    const char *class_name = m->entry ? "entry" : m->effects.len == 0 ? "pure" : "effect";
    ms_strbuild_append(out, ms_message_format(arena, "    m_%S[\"%S<br/>%S<br/>%S\"]:::%s\n", ms_views_sanitize(arena, m->file, false), m->file,
                                              module_summary(arena, m), ms_effects_joined(arena, &m->effects), class_name));
  }
  for (size_t i = 0; i < count && i < MS_NODE_CAP; i++) {
    for (size_t c = 0; c < modules[i].call_files.len; c++) {
      ms_strbuild_append(out, ms_message_format(arena, "    m_%S -->|%S| m_%S\n", ms_views_sanitize(arena, modules[i].file, false),
                                                plural(arena, modules[i].call_counts[c], "call"),
                                                ms_views_sanitize(arena, modules[i].call_files.ptr[c], false)));
    }
  }
  ms_strbuild_append_text(out, "    classDef entry fill:#d6e9ff,stroke:#37b,stroke-width:3px\n");
  ms_strbuild_append_text(out, "    classDef pure fill:#dff5e1,stroke:#2a2\n");
  ms_strbuild_append_text(out, "    classDef effect fill:#fff3cd,stroke:#b8860b\n");
}

static MsViewNode *overview_tree(MsArena *arena, const Module *modules, size_t count) {
  MsViewNode *root = leaf(arena, text("OVERVIEW VIEW"));
  for (size_t i = 0; i < count && i < MS_NODE_CAP; i++) {
    MsViewNode *node = leaf(arena, module_line(arena, &modules[i]));
    node->kind = text("module");
    node->file = modules[i].file;
    for (size_t c = 0; c < modules[i].call_files.len; c++) {
      kid(arena, node, leaf(arena, ms_message_format(arena, "-> %S  (%S)", modules[i].call_files.ptr[c],
                                                     plural(arena, modules[i].call_counts[c], "call"))));
    }
    kid(arena, root, node);
  }
  if (count == 0) {
    kid(arena, root, leaf(arena, text("none")));
  }
  return root;
}

/* ---- build_view ---- */

bool ms_build_view(MsArena *arena, const MsFactModel *model, MsSpan view, MsSpan entity, int64_t depth, MsViewNode **out,
                   MsSpan *error) {
  if (depth <= 0) {
    depth = (is(view, "flow") || is(view, "scope") || is(view, "tasks") || is(view, "ownership")) ? 1 : 3;
  }
  if (is(view, "modules")) {
    return modules_view(arena, model, entity, out, error);
  }
  if (is(view, "overview")) {
    size_t count = 0;
    const Module *modules = overview(arena, model, &count);
    *out = overview_tree(arena, modules, count);
    return true;
  }
  if (is(view, "types")) {
    return types_view(arena, model, entity, depth, out, error);
  }
  if (is(view, "ownership")) {
    return ownership_view(arena, model, entity, depth, out, error);
  }
  if (is(view, "flow") || is(view, "scope") || is(view, "tasks")) {
    return flow_view(arena, model, view, entity, depth, out, error);
  }
  return call_view(arena, model, view, entity, depth, out, error);
}

/* ---- renderings of the tree ---- */

static void write_children(const MsViewNodes *kids, MsStrBuild *out, MsSpan prefix) {
  for (size_t i = 0; i < kids->len; i++) {
    const bool last = i + 1 == kids->len;
    ms_strbuild_append(out, prefix);
    ms_strbuild_append_text(out, last ? "`- " : "|- ");
    ms_strbuild_append(out, kids->ptr[i]->label);
    ms_strbuild_append_text(out, "\n");
    MsStrBuild next = ms_strbuild_new();
    ms_strbuild_append(&next, prefix);
    ms_strbuild_append_text(&next, last ? "   " : "|  ");
    write_children(&kids->ptr[i]->kids, out, ms_strbuild_span(&next));
    ms_strbuild_free(&next);
  }
}

void ms_view_ascii(const MsViewNode *root, MsStrBuild *out) {
  ms_strbuild_append(out, root->label);
  ms_strbuild_append_text(out, "\n");
  write_children(&root->kids, out, (MsSpan){0});
}

static void escape_label(MsStrBuild *out, MsSpan label) {
  for (size_t i = 0; i < label.len; i++) {
    const uint8_t b = label.ptr[i];
    const char *t = b == '&' ? "&amp;" : b == '"' ? "&quot;" : b == '<' ? "&lt;" : b == '>' ? "&gt;" : NULL;
    if (t != NULL) {
      ms_strbuild_append_text(out, t);
    } else {
      ms_strbuild_append_byte(out, b);
    }
  }
}

static size_t mermaid_into(const MsViewNode *node, MsStrBuild *out, size_t *count) {
  const size_t id = (*count)++;
  ms_strbuild_printf(out, "    n%zu[\"", id);
  escape_label(out, node->label);
  ms_strbuild_append_text(out, "\"]\n");
  for (size_t i = 0; i < node->kids.len; i++) {
    const size_t child = mermaid_into(node->kids.ptr[i], out, count);
    ms_strbuild_printf(out, "    n%zu --> n%zu\n", id, child);
  }
  return id;
}

void ms_view_mermaid(const MsViewNode *root, MsStrBuild *out) {
  size_t count = 0;
  ms_strbuild_append_text(out, "flowchart TD\n");
  (void)mermaid_into(root, out, &count);
}

/* ---- the views' own renderings ---- */

void ms_views_overview_ascii(MsArena *arena, const MsFactModel *model, MsStrBuild *out) {
  size_t count = 0;
  const Module *modules = overview(arena, model, &count);
  overview_ascii(arena, modules, count, out);
}

void ms_views_overview_mermaid(MsArena *arena, const MsFactModel *model, MsStrBuild *out) {
  size_t count = 0;
  const Module *modules = overview(arena, model, &count);
  overview_mermaid(arena, modules, count, out);
}
