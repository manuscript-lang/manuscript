/* compiler/own/look_stores.c: see look_stores.h. */
#include "compiler/own/look_stores.h"

#include "base/arena.h"
#include "compiler/own/bind.h"
#include "compiler/own/look_fields.h"
#include "compiler/own/result_borrows.h"
#include "compiler/syntax/walk.h"

enum { MAX_DEPTH = 16 };

typedef struct Scope {
  uint32_t binding;
  uint32_t decl; /* the offset it is bound at */
  uint32_t end;  /* the offset its block ends at */
  MsPos at;
  MsName name;
} Scope;

typedef struct Link {
  uint32_t holder, source;
} Link;

typedef struct Use {
  uint32_t binding, offset;
} Use;

typedef struct Loop {
  uint32_t lo, hi;
} Loop;

/* A look stored into a place whose root is `holder`: the store ends at `end`. */
typedef struct Store {
  uint32_t holder, source, start, end;
  bool holder_param; /* the holder is a parameter: it outlives every local of the callee */
  MsPos at;
} Store;

MS_LIST_DEFINE(ScopeList, scope_list, Scope)
MS_LIST_DEFINE(LinkList, link_list, Link)
MS_LIST_DEFINE(UseList, use_list, Use)
MS_LIST_DEFINE(LoopList, loop_list, Loop)
MS_LIST_DEFINE(StoreList, store_list, Store)

typedef struct Stores {
  MsCheckProgram *program;
  uint32_t module;
  MsFacts *facts;
  ScopeList scopes;
  LinkList links;
  UseList uses;
  LoopList loops;
  StoreList stores;
  uint32_t high;
} Stores;

static bool param_binding(const MsFacts *facts, MsNode node) {
  const MsRef *ref = ms_facts_ref(facts, node);
  return ref != NULL && ref->kind == MS_REF_PARAM;
}

static bool is_look(const Stores *pass, const MsExpr *expr) {
  const MsTy ty = ms_facts_type(pass->facts, expr->id);
  return ty != MS_TY_NONE && ms_own_look_record(pass->program, ty);
}

/* The name a place starts at: through members, indexes and `?`. */
static const MsExpr *root_name(const MsExpr *place) {
  for (;;) {
    MsExpr *left = NULL;
    MsExpr *index = NULL;
    if (place->kind == MS_E_MEMBER) {
      place = place->u.member.left;
    } else if (ms_expr_index(place, &left, &index)) {
      place = left;
    } else if (place->kind == MS_E_UNARY && place->op == MS_U_TRY) {
      place = place->u.bin.left;
    } else {
      return place;
    }
  }
}

static void add_source(Stores *pass, uint32_t holder, uint32_t source) {
  for (size_t at = 0; at < pass->links.len; at++) {
    if (pass->links.ptr[at].holder == holder && pass->links.ptr[at].source == source) {
      return;
    }
  }
  link_list_push(&pass->links, (Link){holder, source});
}

/* Adds to `out` the bindings the value of `expr` looks at: the owners a constructor was given for its `&` fields, the
 * owners a look it was given looks at, the arguments a call's result keeps. */
static void sources_of(Stores *pass, const MsExpr *expr, uint32_t holder, int depth) {
  if (expr == NULL || depth > MAX_DEPTH) {
    return;
  }
  const MsExpr *root = root_name(expr);
  if (root->kind == MS_E_NAME) {
    uint32_t binding = 0;
    if (!ms_bind_of(pass->facts, root->id, &binding)) {
      return;
    }
    /* a look keeps what it looks at; a binding that only borrows another owner stands for that owner */
    bool through = false;
    for (size_t at = 0; at < pass->links.len; at++) {
      if (pass->links.ptr[at].holder == binding && pass->links.ptr[at].source != holder) {
        add_source(pass, holder, pass->links.ptr[at].source);
        through = true;
      }
    }
    if (!through && !is_look(pass, root)) {
      add_source(pass, holder, binding);
    }
    return;
  }
  if (expr->kind == MS_E_BINARY && expr->op == MS_B_OR) {
    sources_of(pass, expr->u.bin.left, holder, depth + 1);
    sources_of(pass, expr->u.bin.right, holder, depth + 1);
    return;
  }
  if (expr->kind != MS_E_CALL) {
    return;
  }
  const MsCall *fact = ms_facts_call(pass->facts, expr->id);
  if (fact == NULL) {
    return;
  }
  const MsExpr *callee = expr->u.call.callee;
  const bool constructor = ms_bind_is_constructor(pass->facts, expr);
  const bool receiver = !constructor && callee->kind == MS_E_MEMBER && fact->callee.kind == MS_REF_METHOD;
  if (receiver && ms_own_call_borrows(pass->program, fact, 0)) {
    sources_of(pass, callee->u.member.left, holder, depth + 1);
  }
  for (uint32_t index = 0; index < expr->u.call.args.len; index++) {
    const MsExpr *value = expr->u.call.args.ptr[index].value;
    bool looks = false;
    for (uint32_t at = 0; constructor && at < fact->arg_count; at++) {
      looks = looks || (fact->args[at].source == MS_ARG_WRITTEN && fact->args[at].node.node == value->id &&
                        (ms_own_look_field(pass->program, fact, at) || ms_own_look_carrier(pass->program, fact, at)));
    }
    if (looks || (!constructor && ms_own_call_borrows(pass->program, fact, index + (receiver ? 1u : 0u)))) {
      sources_of(pass, value, holder, depth + 1);
    }
  }
}

static void measure_expr(void *ctx, const MsExpr *expr) {
  Stores *pass = ctx;
  if (expr->end.offset > pass->high) {
    pass->high = expr->end.offset;
  }
}

/* The furthest offset any expression of `body` ends at. */
static uint32_t body_end(Stores *pass, MsStmts body) {
  pass->high = 0;
  ms_walk_block(&(MsVisitor){.ctx = pass, .expr = measure_expr}, body);
  return pass->high;
}

static void visit_block(void *ctx, MsStmts body) {
  Stores *pass = ctx;
  uint32_t end = 0;
  for (uint32_t index = 0; index < body.len; index++) {
    const MsStmt *stmt = body.ptr[index];
    const MsPattern *pattern = stmt->kind == MS_S_BIND ? stmt->u.bind.pattern : NULL;
    uint32_t binding = 0;
    if (pattern == NULL || pattern->kind != MS_P_NAME || !ms_bind_of(pass->facts, pattern->id, &binding)) {
      continue;
    }
    if (end == 0) {
      end = body_end(pass, body);
    }
    scope_list_push(&pass->scopes, (Scope){.binding = binding, .decl = pattern->pos.offset, .end = end,
                                           .at = pattern->pos, .name = pattern->u.name});
  }
}

/* Records that a look made from `value` is stored in the place rooted at `holder`, written over `start..end`. */
static void note_store(Stores *pass, uint32_t holder, bool holder_param, const MsExpr *value, uint32_t start,
                       uint32_t end, MsPos at) {
  const size_t before = pass->links.len;
  sources_of(pass, value, holder, 0);
  for (size_t index = before; index < pass->links.len; index++) {
    store_list_push(&pass->stores, (Store){.holder = holder, .source = pass->links.ptr[index].source,
                                           .start = start, .end = end, .holder_param = holder_param, .at = at});
  }
}

static void note_bind(Stores *pass, const MsStmt *stmt) {
  const MsPattern *pattern = stmt->u.bind.pattern;
  const MsExpr *value = stmt->u.bind.value;
  uint32_t binding = 0;
  if (pattern == NULL || pattern->kind != MS_P_NAME || value == NULL || !ms_bind_of(pass->facts, pattern->id, &binding)) {
    return;
  }
  /* a look, or a name that borrows another owner (a name moved in owns its value) */
  if (is_look(pass, value) || ms_facts_use(pass->facts, value->id) != MS_USE_MOVE) {
    sources_of(pass, value, binding, 0);
  }
}

static void note_assign(Stores *pass, const MsStmt *stmt) {
  const MsExpr *value = stmt->u.assign.value;
  if (value == NULL || !is_look(pass, value)) {
    return;
  }
  uint32_t holder = 0;
  MsNode node = stmt->id;
  if (stmt->u.assign.member_target) {
    const MsExpr *name = stmt->u.assign.target != NULL ? root_name(stmt->u.assign.target) : NULL;
    if (name == NULL || name->kind != MS_E_NAME) {
      return;
    }
    node = name->id;
  }
  if (ms_bind_of(pass->facts, node, &holder)) {
    note_store(pass, holder, param_binding(pass->facts, node), value, stmt->pos.offset, value->end.offset, stmt->pos);
  }
}

/* A look passed to a `move` parameter of a call that also changes a place (`list.append(look)`) is stored there. */
static void note_call(Stores *pass, const MsExpr *call) {
  const MsCall *fact = ms_facts_call(pass->facts, call->id);
  if (fact == NULL || ms_bind_is_constructor(pass->facts, call)) {
    return;
  }
  const MsExpr *callee = call->u.call.callee;
  for (uint32_t at = 0; at < fact->arg_count; at++) {
    const MsCallArg *var = &fact->args[at];
    if (var->source != MS_ARG_WRITTEN || (var->flags & MS_PARAM_VAR) == 0) {
      continue;
    }
    const MsExpr *place = NULL;
    if (callee->kind == MS_E_MEMBER && var->node.node == callee->u.member.left->id) {
      place = callee->u.member.left;
    }
    for (uint32_t index = 0; place == NULL && index < call->u.call.args.len; index++) {
      if (call->u.call.args.ptr[index].value->id == var->node.node) {
        place = call->u.call.args.ptr[index].value;
      }
    }
    const MsExpr *name = place != NULL ? root_name(place) : NULL;
    uint32_t holder = 0;
    if (name == NULL || name->kind != MS_E_NAME || !ms_bind_of(pass->facts, name->id, &holder)) {
      continue;
    }
    for (uint32_t index = 0; index < call->u.call.args.len; index++) {
      const MsExpr *value = call->u.call.args.ptr[index].value;
      for (uint32_t other = 0; other < fact->arg_count; other++) {
        if (fact->args[other].source == MS_ARG_WRITTEN && fact->args[other].node.node == value->id &&
            (fact->args[other].flags & MS_PARAM_MOVE) != 0 && is_look(pass, value)) {
          note_store(pass, holder, param_binding(pass->facts, name->id), value, ms_expr_start(call).offset,
                     call->end.offset, call->pos);
        }
      }
    }
  }
}

static void visit_stmt(void *ctx, const MsStmt *stmt) {
  Stores *pass = ctx;
  if (stmt->kind == MS_S_BIND) {
    note_bind(pass, stmt);
  } else if (stmt->kind == MS_S_ASSIGN) {
    note_assign(pass, stmt);
  } else if (stmt->kind == MS_S_WHILE || stmt->kind == MS_S_FOR) {
    const MsStmts body = stmt->kind == MS_S_WHILE ? stmt->u.loop.body : stmt->u.each.body;
    if (body.len != 0) {
      loop_list_push(&pass->loops, (Loop){.lo = stmt->pos.offset, .hi = body_end(pass, body)});
    }
  }
}

static void visit_expr(void *ctx, const MsExpr *expr) {
  Stores *pass = ctx;
  uint32_t binding = 0;
  if (expr->kind == MS_E_NAME && ms_bind_of(pass->facts, expr->id, &binding)) {
    use_list_push(&pass->uses, (Use){binding, expr->pos.offset});
  } else if (expr->kind == MS_E_CALL) {
    note_call(pass, expr);
  }
}

static const Scope *scope_of(const Stores *pass, uint32_t binding) {
  for (size_t at = 0; at < pass->scopes.len; at++) {
    if (pass->scopes.ptr[at].binding == binding) {
      return &pass->scopes.ptr[at];
    }
  }
  return NULL;
}

/* Whether `holder` is read after `source` has ended: a use past the end of its block, or in a loop that declares the
 * source anew each round while the holder lives outside it. Uses inside the store itself do not count. */
static bool outlives(const Stores *pass, const Store *store, const Scope *source, const Scope *holder) {
  for (size_t at = 0; at < pass->uses.len; at++) {
    const Use *use = &pass->uses.ptr[at];
    if (use->binding != store->holder || (use->offset >= store->start && use->offset < store->end)) {
      continue;
    }
    if (use->offset > source->end) {
      return true;
    }
    for (size_t index = 0; holder != NULL && index < pass->loops.len; index++) {
      const Loop *loop = &pass->loops.ptr[index];
      if (use->offset >= loop->lo && use->offset <= loop->hi && store->start >= loop->lo && store->start <= loop->hi &&
          source->decl >= loop->lo && source->decl <= loop->hi && holder->decl < loop->lo) {
        return true;
      }
    }
  }
  return false;
}

static void report(Stores *pass, const Store *store, const Scope *source) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "this stores a value that looks at `");
  ms_strbuild_append(&text, ms_names_span(pass->program->names, source->name));
  ms_strbuild_append_text(&text, "` (bound at ");
  ms_strbuild_append_u64(&text, source->at.line);
  ms_strbuild_append_text(&text, ":");
  ms_strbuild_append_u64(&text, source->at.column);
  ms_strbuild_append_text(&text, ") in a place that is used after `");
  ms_strbuild_append(&text, ms_names_span(pass->program->names, source->name));
  ms_strbuild_append_text(&text, "` ends; declare the owner before the place that holds the view, or store `.clone()` of the part you need");
  ms_check_report(pass->program, pass->module, store->at, MS_CHECK_TYPE, ms_strbuild_finish(&text));
}

static void judge(Stores *pass) {
  for (size_t at = 0; at < pass->stores.len; at++) {
    const Store *store = &pass->stores.ptr[at];
    const Scope *source = scope_of(pass, store->source);
    if (source == NULL || store->source == store->holder) {
      continue; /* a parameter, loop variable or pattern lives as long as the call or round that reads it */
    }
    const Scope *holder = scope_of(pass, store->holder);
    if (store->holder_param ? true : holder != NULL && outlives(pass, store, source, holder)) {
      report(pass, store, source);
    }
  }
  scope_list_clear(&pass->scopes);
  link_list_clear(&pass->links);
  use_list_clear(&pass->uses);
  loop_list_clear(&pass->loops);
  store_list_clear(&pass->stores);
}

void ms_own_look_stores(MsCheckProgram *program) {
  if (program->diagnostics.len != 0 || program->modules.len <= program->user_modules) {
    return;
  }
  for (uint32_t module = 0; module < (uint32_t)program->modules.len; module++) {
    Stores pass = {.program = program, .module = module, .facts = &program->modules.ptr[module].facts};
    const MsModule *tree = program->modules.ptr[module].tree;
    const MsVisitor visitor = {.ctx = &pass, .block = visit_block, .stmt = visit_stmt, .expr = visit_expr};
    for (uint32_t index = 0; index < tree->ndecls; index++) {
      ms_walk_decl(&visitor, tree->decls[index]);
      judge(&pass);
    }
    scope_list_free(&pass.scopes);
    link_list_free(&pass.links);
    use_list_free(&pass.uses);
    loop_list_free(&pass.loops);
    store_list_free(&pass.stores);
  }
}
