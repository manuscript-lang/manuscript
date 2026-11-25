/* Owns flow.h. */
#include "tooling/flow.h"

#include "compiler/syntax/walk.h"

#include "base/chars.h"

bool ms_flow_scoped(const MsFacts *facts, uint32_t pattern) {
  const MsCloser *closer = ms_facts_closer(facts, pattern);
  return closer != NULL && closer->method.node != 0;
}

/* ---- helpers ---- */

/* The source line of `pos`, trimmed, without a trailing `:`. */
static MsSpan source_line(const MsFlow *flow, MsPos pos) {
  if (pos.line < 1 || pos.line > flow->line_count) {
    return (MsSpan){0};
  }
  MsSpan text = ms_span_trim(flow->lines[pos.line - 1]);
  if (text.len > 0 && text.ptr[text.len - 1] == ':') {
    text.len--;
  }
  return ms_span_trim(text);
}

static MsViewNode *step(const MsFlow *flow, const char *kind, MsSpan label, MsPos pos) {
  MsViewNode *node = ms_view_node(flow->arena, label);
  node->kind = ms_span_of_text(kind);
  node->file = flow->file;
  node->line = pos.line;
  return node;
}

static MsSpan key_name(MsSpan key) {
  size_t first = 0;
  if (!ms_span_find(key, ms_span_of_text("#"), &first)) {
    return key;
  }
  const MsSpan rest = ms_span_of(key.ptr + first + 1, key.len - first - 1);
  size_t second = 0;
  if (!ms_span_find(rest, ms_span_of_text("#"), &second)) {
    return key;
  }
  return ms_span_of(rest.ptr + second + 1, rest.len - second - 1);
}

static MsViewNodes split_off(const MsFlow *flow, MsViewNodes *list, size_t at) {
  MsViewNodes tail = {0};
  for (size_t i = at; i < list->len; i++) {
    ms_view_nodes_push(flow->arena, &tail, list->ptr[i]);
  }
  list->len = at < list->len ? at : list->len;
  return tail;
}

static void extend(const MsFlow *flow, MsViewNodes *list, const MsViewNodes *more) {
  for (size_t i = 0; i < more->len; i++) {
    ms_view_nodes_push(flow->arena, list, more->ptr[i]);
  }
}

/* Whether the name node `id` reads a module-level constant. */
static bool is_constant_use(const MsFacts *facts, uint32_t id) {
  const MsRef *ref = ms_facts_ref(facts, id);
  return ref != NULL && ref->kind == MS_REF_CONSTANT;
}

/* ---- call sites ---- */

/* The call site at `e`, or NULL. */
static const MsCallSite *site_at(const MsFlow *flow, const MsExpr *e) {
  const MsSpan id = ms_message_format(flow->arena, "%S#call#%z", flow->file, (size_t)e->pos.offset);
  size_t low = 0;
  size_t high = flow->inspection->calls.len;
  while (low < high) {
    const size_t mid = low + (high - low) / 2;
    const int order = ms_span_compare(flow->inspection->calls.ptr[mid].id, id);
    if (order == 0) {
      return &flow->inspection->calls.ptr[mid];
    }
    if (order < 0) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return NULL;
}

/* The node of a call or constant use, and whether it spawns; NULL when it is not a step. */
static MsViewNode *call_node(const MsFlow *flow, const MsExpr *e, bool *spawn) {
  const MsCallSite *site = site_at(flow, e);
  if (site == NULL || ms_span_is_text(site->kind, "construct")) {
    return NULL;
  }
  *spawn = site->spawn;
  const MsSpan key = ms_entity_key(flow->inspection, flow->keys, site->target);
  MsViewNode *node = ms_view_node(flow->arena, (MsSpan){0});
  if (key.len > 0) {
    node->kind = ms_span_of_text("call");
    node->label = ms_message_format(flow->arena, "call %S", key_name(key));
    node->reference = key;
    return node;
  }
  node->kind = ms_span_of_text("native");
  node->label = ms_message_format(flow->arena, "native %S", ms_readable_id(flow->arena, site->target));
  return node;
}

/* ---- events: the calls and try markers inside one expression ---- */

typedef struct Pending {
  uint32_t id;
  MsViewNode *node;
  size_t start;
} Pending;
MS_AVEC(PendingList, pending_list, Pending)

typedef struct Open {
  uint32_t id;
  size_t at;
} Open;
MS_AVEC(OpenList, open_list, Open)

typedef struct Events {
  const MsFlow *flow;
  MsViewNodes out;
  bool pending_try;
  OpenList spawns;
  PendingList pending;
  OpenList closures;
} Events;

static void events_expr(void *ctx, const MsExpr *x) {
  Events *ev = ctx;
  const MsFlow *flow = ev->flow;
  if (x->kind == MS_E_UNARY && x->op == MS_U_TRY) {
    ev->pending_try = true;
    return;
  }
  if (x->kind == MS_E_LAMBDA) {
    MsViewNode *node = step(flow, "closure", (MsSpan){0}, x->pos);
    node->label = ms_message_format(flow->arena, "closure %S", source_line(flow, x->pos));
    open_list_push(flow->arena, &ev->closures, (Open){.id = x->id, .at = ev->out.len});
    ms_view_nodes_push(flow->arena, &ev->out, node);
    return;
  }
  const bool constant = x->kind == MS_E_NAME && is_constant_use(flow->facts, x->id);
  if (!constant && x->kind != MS_E_CALL) {
    return;
  }
  bool spawn = false;
  MsViewNode *node = call_node(flow, x, &spawn);
  if (node == NULL) {
    return;
  }
  node->file = flow->file;
  node->line = x->pos.line;
  if (spawn) {
    node->kind = ms_span_of_text("spawn");
    node->label = ms_message_format(flow->arena, "spawn  %S", source_line(flow, x->pos));
    open_list_push(flow->arena, &ev->spawns, (Open){.id = x->id, .at = ev->out.len});
  }
  const bool is_spawn = spawn;
  if (ev->pending_try) {
    node->label = ms_message_format(flow->arena, "try %S", node->label);
    node->kind = ms_span_of_text("try");
    ev->pending_try = false;
  }
  if (is_spawn) {
    ms_view_nodes_push(flow->arena, &ev->out, node);
  } else {
    pending_list_push(flow->arena, &ev->pending, (Pending){.id = x->id, .node = node, .start = ev->out.len});
  }
}

static void events_leave(void *ctx, const MsExpr *x) {
  Events *ev = ctx;
  const MsFlow *flow = ev->flow;
  if (ev->closures.len > 0 && ev->closures.ptr[ev->closures.len - 1].id == x->id) {
    const size_t at = ev->closures.ptr[--ev->closures.len].at;
    const MsViewNodes inside = split_off(flow, &ev->out, at + 1);
    extend(flow, &ev->out.ptr[at]->kids, &inside);
  }
  if (ev->pending.len > 0 && ev->pending.ptr[ev->pending.len - 1].id == x->id) {
    const Pending done = ev->pending.ptr[--ev->pending.len];
    const MsViewNodes args = split_off(flow, &ev->out, done.start);
    MsViewNodes closures = {0};
    for (size_t i = 0; i < args.len; i++) {
      if (ms_span_is_text(args.ptr[i]->kind, "closure")) {
        ms_view_nodes_push(flow->arena, &closures, args.ptr[i]);
      } else {
        ms_view_nodes_push(flow->arena, &ev->out, args.ptr[i]);
      }
    }
    extend(flow, &done.node->kids, &closures);
    ms_view_nodes_push(flow->arena, &ev->out, done.node);
  }
  if (ev->spawns.len > 0 && ev->spawns.ptr[ev->spawns.len - 1].id == x->id) {
    const size_t at = ev->spawns.ptr[--ev->spawns.len].at;
    const MsViewNodes inside = split_off(flow, &ev->out, at + 1);
    extend(flow, &ev->out.ptr[at]->kids, &inside);
  }
}

static void events(const MsFlow *flow, const MsExpr *e, MsViewNodes *into) {
  if (e == NULL) {
    return;
  }
  Events ev = {.flow = flow};
  const MsVisitor visitor = {.ctx = &ev, .expr = events_expr, .leave_expr = events_leave};
  ms_walk_expr(&visitor, e);
  extend(flow, into, &ev.out);
  if (ev.pending_try) {
    ms_view_nodes_push(flow->arena, into, step(flow, "try", ms_span_of_text("try"), e->pos));
  }
}

/* ---- statements ---- */

typedef enum Shape { SHAPE_BRANCH, SHAPE_LOOP, SHAPE_EXIT, SHAPE_RETURN, SHAPE_PLAIN } Shape;

typedef struct StmtView {
  MsPos pos;
  Shape shape;
  const MsExpr *target, *value;
  MsStmts body, else_body;
  const MsStmt *original;
} StmtView;

static StmtView view_of(const MsStmt *s) {
  StmtView view = {.pos = s->pos, .shape = SHAPE_PLAIN, .original = s};
  switch ((MsStmtKind)s->kind) {
  case MS_S_BIND: view.value = s->u.bind.value; break;
  case MS_S_ASSIGN:
    view.target = s->u.assign.member_target ? s->u.assign.target : NULL;
    view.value = s->u.assign.value;
    break;
  case MS_S_CALL: view.value = s->u.expr; break;
  case MS_S_RETURN:
    view.shape = SHAPE_RETURN;
    view.value = s->u.expr;
    break;
  case MS_S_BREAK:
  case MS_S_CONTINUE: view.shape = SHAPE_EXIT; break;
  case MS_S_IF:
    view.shape = SHAPE_BRANCH;
    view.value = s->u.branch.cond;
    view.body = s->u.branch.body;
    view.else_body = s->u.branch.else_body;
    break;
  case MS_S_WHILE:
    view.shape = SHAPE_LOOP;
    view.value = s->u.loop.cond;
    view.body = s->u.loop.body;
    break;
  case MS_S_FOR:
    view.shape = SHAPE_LOOP;
    view.value = s->u.each.iter;
    view.body = s->u.each.body;
    break;
  }
  return view;
}

static bool ends_with(MsSpan text, MsSpan suffix) {
  return ms_span_ends_with(text, suffix);
}

static void statement(const MsFlow *flow, const StmtView *s, MsViewNodes *out);

static MsViewNode *match_node(const MsFlow *flow, MsPos pos, const MsExpr *match) {
  MsViewNode *node = step(flow, "match", source_line(flow, pos), pos);
  for (uint32_t a = 0; a < match->u.match.arms.len; a++) {
    const MsArm *arm = match->u.match.arms.ptr[a];
    MsViewNode *child = step(flow, "arm", source_line(flow, arm->pos), arm->pos);
    MsViewNodes steps = {0};
    events(flow, arm->value, &steps);
    ms_flow_body(flow, arm->body, &steps);
    for (size_t i = 0; i < steps.len; i++) {
      if (ms_span_is_text(steps.ptr[i]->kind, "exit") && ends_with(child->label, steps.ptr[i]->label)) {
        continue;
      }
      ms_view_nodes_push(flow->arena, &child->kids, steps.ptr[i]);
    }
    ms_view_nodes_push(flow->arena, &node->kids, child);
  }
  return node;
}

static void statement(const MsFlow *flow, const StmtView *s, MsViewNodes *out) {
  if (s->shape == SHAPE_BRANCH || s->shape == SHAPE_LOOP) {
    MsViewNode *node = step(flow, s->shape == SHAPE_LOOP ? "loop" : "branch", source_line(flow, s->pos), s->pos);
    events(flow, s->value, out);
    MsViewNodes body = {0};
    ms_flow_body(flow, s->body, &body);
    for (size_t i = 0; i < body.len; i++) {
      if (!(ms_span_is_text(body.ptr[i]->kind, "exit") && ends_with(node->label, body.ptr[i]->label))) {
        ms_view_nodes_push(flow->arena, &node->kids, body.ptr[i]);
      }
    }
    ms_view_nodes_push(flow->arena, out, node);
    if (s->else_body.len > 0) {
      MsViewNode *other = ms_view_node_text(flow->arena, "else");
      other->kind = ms_span_of_text("branch");
      ms_flow_body(flow, s->else_body, &other->kids);
      ms_view_nodes_push(flow->arena, out, other);
    }
    return;
  }
  if (s->shape == SHAPE_EXIT) {
    const char *label = s->original != NULL && s->original->kind == MS_S_CONTINUE ? "continue" : "break";
    ms_view_nodes_push(flow->arena, out, step(flow, "exit", ms_span_of_text(label), s->pos));
    return;
  }
  const MsExpr *value = s->value;
  events(flow, s->target, out);
  if (value != NULL && value->kind == MS_E_MATCH) {
    events(flow, value->u.match.scrutinee, out);
    ms_view_nodes_push(flow->arena, out, match_node(flow, s->pos, value));
  } else {
    events(flow, value, out);
  }
  if (s->shape == SHAPE_RETURN) {
    ms_view_nodes_push(flow->arena, out, step(flow, "exit", source_line(flow, s->pos), s->pos));
  }
}

void ms_flow_body(const MsFlow *flow, MsStmts body, MsViewNodes *out) {
  for (uint32_t i = 0; i < body.len; i++) {
    const MsStmt *s = body.ptr[i];
    if (s->kind != MS_S_BIND || !ms_flow_scoped(flow->facts, s->u.bind.pattern->id)) {
      const StmtView view = view_of(s);
      statement(flow, &view, out);
      continue;
    }
    /* The rest of the block runs inside the resource's scope. */
    MsViewNode *node = step(flow, "scope",
                            ms_message_format(flow->arena, "%S  [closed on exit]", source_line(flow, s->pos)), s->pos);
    events(flow, s->u.bind.value, &node->kids);
    ms_flow_body(flow, (MsStmts){.ptr = body.ptr + i + 1, .len = body.len - i - 1}, &node->kids);
    ms_view_nodes_push(flow->arena, out, node);
    break;
  }
}

void ms_flow_constant(const MsFlow *flow, MsPos init_pos, const MsExpr *value, MsViewNodes *out) {
  const StmtView view = {.pos = init_pos, .shape = SHAPE_RETURN, .value = value};
  statement(flow, &view, out);
}
