/* compiler/own/moves.c: a moved value used again (see moves.h). */
#include "compiler/own/moves.h"

#include "compiler/check/methods.h"
#include "compiler/own/bind.h"
#include "compiler/own/class.h"
#include "compiler/own/live.h"
#include "compiler/syntax/walk.h"

/* A name use, to say where a later use is. */
typedef struct Spot {
  MsNode node;
  MsPos pos;
} Spot;

MS_LIST_DEFINE(SpotList, spot_list, Spot)

typedef struct Moves {
  MsCheckProgram *program;
  uint32_t module;
  const MsFacts *facts;
  const MsLiveness *live;
  SpotList spots;
  MsClassifier *classes;
  MsArena *arena;
  MsBindingList vars;   /* binding sites of `var` locals of the body */
  MsBindingList reads;  /* `if p := name:` scrutinees that are not resources: the payload is a view, the name stays whole */
  MsBindingList moving; /* binding sites of `move` parameters of the body */
  MsBindingList outer;  /* what the lambdas around the current expression capture: only borrowed inside them */
  uint32_t depth;       /* lambdas open around the current expression */
  uint32_t marks[16];   /* `outer.len` before each open lambda's captures */
} Moves;

static void note_spot(void *ctx, const MsExpr *expr) {
  Moves *pass = ctx;
  if (expr->kind == MS_E_NAME || expr->kind == MS_E_LAMBDA) {
    spot_list_push(&pass->spots, (Spot){expr->id, expr->pos});
  }
}

static MsPos spot_of(const Moves *pass, MsNode node) {
  for (size_t index = 0; index < pass->spots.len; index++) {
    if (pass->spots.ptr[index].node == node) {
      return pass->spots.ptr[index].pos;
    }
  }
  return (MsPos){0};
}

static void report(const Moves *pass, const MsExpr *expr, MsNode next) {
  const MsPos later = spot_of(pass, next);
  const MsTy ty = ms_facts_type(pass->facts, expr->id);
  const MsSpan name = ms_names_span(pass->program->names, expr->u.sym);
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "`");
  ms_strbuild_append(&text, name);
  ms_strbuild_append_text(&text, "` is moved here but used again");
  const bool again = next == expr->id;
  if (again) {
    ms_strbuild_append_text(&text, " on the next loop iteration");
  } else if (later.line != 0) {
    ms_strbuild_append_text(&text, " at ");
    ms_strbuild_append_u64(&text, later.line);
    ms_strbuild_append_text(&text, ":");
    ms_strbuild_append_u64(&text, later.column);
  }
  if (ty != MS_TY_NONE && ms_ty_kind(&pass->program->types, ty) == MS_TY_FUNCTION) {
    ms_strbuild_append_text(&text, "; a function value has one owner and cannot be cloned, so move it only at its last use or declare a named `fn`, which can be passed as often as needed");
  } else if (ty != MS_TY_NONE && ms_check_holds_resource(pass->program, ty)) {
    ms_strbuild_append_text(&text, "; a resource has one owner and cannot be cloned, so move it only at its last use, or pass it where it is only read");
  } else {
    ms_strbuild_append_text(&text, "; a value has one owner, so move it only at its last use, or pass `");
    ms_strbuild_append(&text, name);
    ms_strbuild_append_text(&text, ".clone()` if the original is still needed");
  }
  ms_check_report(pass->program, pass->module, expr->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
}

/* The first use of `binding` inside a lambda. */
typedef struct FirstUse {
  const MsFacts *facts;
  uint32_t binding;
  const MsExpr *use;
} FirstUse;

static void find_use(void *ctx, const MsExpr *expr) {
  FirstUse *first = ctx;
  uint32_t binding = 0;
  if (first->use == NULL && expr->kind == MS_E_NAME && ms_bind_of(first->facts, expr->id, &binding) &&
      binding == first->binding) {
    first->use = expr;
  }
}

static bool contains(const MsBindingList *list, uint32_t binding) {
  for (size_t index = 0; index < list->len; index++) {
    if (list->ptr[index] == binding) {
      return true;
    }
  }
  return false;
}

static void append_later(const Moves *pass, MsStrBuild *text, MsNode next) {
  const MsPos later = spot_of(pass, next);
  ms_strbuild_append_text(text, ", which is used again");
  if (later.line != 0) {
    ms_strbuild_append_text(text, " at ");
    ms_strbuild_append_u64(text, later.line);
    ms_strbuild_append_text(text, ":");
    ms_strbuild_append_u64(text, later.column);
  }
}

/* Whether the lambda assigns the binding or a field of it. */
typedef struct Changes {
  const MsFacts *facts;
  MsArena *arena;
  uint32_t binding;
  bool changed;
} Changes;

static void find_change(void *ctx, const MsStmt *stmt) {
  Changes *changes = ctx;
  uint32_t binding = 0;
  if (stmt->kind != MS_S_ASSIGN) {
    return;
  }
  const MsExpr *root = NULL;
  MsLivePath path = {0};
  if (stmt->u.assign.target == NULL) {
    changes->changed = changes->changed || (ms_bind_of(changes->facts, stmt->id, &binding) && binding == changes->binding);
  } else if (ms_bind_field_chain(changes->facts, changes->arena, stmt->u.assign.target, &root, &binding, &path)) {
    changes->changed = changes->changed || binding == changes->binding;
  }
}

/* An escaping closure owns what it captures: the maker may not use it afterwards, and a borrowed parameter has
 * nothing to give. */
static void check_lambda(const Moves *pass, const MsExpr *lambda) {
  MsBindingList captures = ms_bind_captures(pass->facts, lambda);
  for (size_t outer = 0; outer < captures.len; outer++) { /* in the order the names were declared */
    for (size_t inner = outer + 1; inner < captures.len; inner++) {
      if (captures.ptr[inner] < captures.ptr[outer]) {
        const uint32_t swap = captures.ptr[outer];
        captures.ptr[outer] = captures.ptr[inner];
        captures.ptr[inner] = swap;
      }
    }
  }
  for (size_t index = 0; index < captures.len; index++) {
    FirstUse first = {.facts = pass->facts, .binding = captures.ptr[index]};
    ms_walk_expr(&(MsVisitor){.ctx = &first, .expr = find_use}, lambda);
    if (first.use == NULL) {
      continue;
    }
    const MsRef *ref = ms_facts_ref(pass->facts, first.use->id);
    const MsTy ty = ms_facts_type(pass->facts, first.use->id);
    if (ref == NULL || ty == MS_TY_NONE) {
      continue;
    }
    const bool copy = ms_class_of(pass->classes, ty) == MS_CLASS_COPY;
    const MsSpan name = ms_names_span(pass->program->names, first.use->u.sym);
    MsStrBuild text = ms_strbuild_new();
    const MsUseLive *use = ms_live_map_get(&pass->live->uses, ms_live_key(lambda->id, first.binding));
    const bool again = use != NULL && !use->last;
    Changes changes = {.facts = pass->facts, .arena = pass->arena, .binding = first.binding};
    ms_walk_expr(&(MsVisitor){.ctx = &changes, .stmt = find_change}, lambda);
    if (changes.changed) {
      MsStrBuild changed = ms_strbuild_new();
      ms_strbuild_append_text(&changed, "this closure changes captured `");
      ms_strbuild_append(&changed, name);
      ms_strbuild_append_text(&changed, "`, so it cannot be returned, stored or passed to a moving parameter; keep the closure local, or have it return a new value instead of changing `");
      ms_strbuild_append(&changed, name);
      ms_strbuild_append_text(&changed, "`");
      ms_check_report(pass->program, pass->module, lambda->pos, MS_CHECK_TYPE, ms_strbuild_finish(&changed));
    }
    if (!copy && contains(&pass->outer, first.binding)) {
      ms_strbuild_append_text(&text, "this closure outlives the statement but captures `");
      ms_strbuild_append(&text, name);
      ms_strbuild_append_text(&text, "`, which is borrowed, not owned; bind `own := ");
      ms_strbuild_append(&text, name);
      ms_strbuild_append_text(&text, ".clone()` before the closure and capture `own` instead");
    } else if (again && copy && contains(&pass->vars, first.binding)) {
      ms_strbuild_append_text(&text, "this closure outlives the statement but captures the `var` `");
      ms_strbuild_append(&text, name);
      ms_strbuild_append_text(&text, "`");
      append_later(pass, &text, use->next);
      ms_strbuild_append_text(&text, "; the closure would keep a stale value, so bind an immutable snapshot with `snapshot := ");
      ms_strbuild_append(&text, name);
      ms_strbuild_append_text(&text, "` before the closure and capture `snapshot`");
    } else if (again && !copy) {
      ms_strbuild_append_text(&text, "this closure outlives the statement, so it takes `");
      ms_strbuild_append(&text, name);
      ms_strbuild_append_text(&text, "` with it, but `");
      ms_strbuild_append(&text, name);
      ms_strbuild_append_text(&text, "` is used again");
      const MsPos later = spot_of(pass, use->next);
      if (later.line != 0) {
        ms_strbuild_append_text(&text, " at ");
        ms_strbuild_append_u64(&text, later.line);
        ms_strbuild_append_text(&text, ":");
        ms_strbuild_append_u64(&text, later.column);
      }
      ms_strbuild_append_text(&text, "; capture `");
      ms_strbuild_append(&text, name);
      ms_strbuild_append_text(&text, ".clone()` to keep the original");
    } else {
      ms_strbuild_free(&text);
      continue;
    }
    ms_check_report(pass->program, pass->module, lambda->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  }
  ms_binding_list_free(&captures);
}

static void leave_expr(void *ctx, const MsExpr *expr) {
  Moves *pass = ctx;
  if (expr->kind == MS_E_LAMBDA && pass->depth > 0) {
    pass->depth--;
    pass->outer.len = pass->marks[pass->depth < 16 ? pass->depth : 15];
  }
}

static void visit_expr(void *ctx, const MsExpr *expr) {
  Moves *pass = ctx;
  uint32_t binding = 0;
  if (expr->kind == MS_E_LAMBDA) {
    if (ms_facts_use(pass->facts, expr->id) == MS_USE_MOVE) {
      check_lambda(pass, expr);
    }
    MsBindingList captures = ms_bind_captures(pass->facts, expr);
    pass->marks[pass->depth < 16 ? pass->depth : 15] = (uint32_t)pass->outer.len;
    for (size_t index = 0; index < captures.len; index++) {
      ms_binding_list_push(&pass->outer, captures.ptr[index]);
    }
    pass->depth++;
    ms_binding_list_free(&captures);
    return;
  }
  if (expr->kind != MS_E_NAME || ms_facts_use(pass->facts, expr->id) != MS_USE_MOVE || contains(&pass->reads, expr->id) ||
      !ms_bind_of(pass->facts, expr->id, &binding)) {
    return;
  }
  const MsUseLive *use = ms_live_map_get(&pass->live->uses, ms_live_key(expr->id, binding));
  if (use != NULL && !use->last) {
    report(pass, expr, use->next);
  }
}

static void note_var(void *ctx, const MsStmt *stmt) {
  Moves *pass = ctx;
  if (stmt->kind == MS_S_BIND && stmt->u.bind.is_mutable && stmt->u.bind.pattern->kind == MS_P_NAME) {
    ms_binding_list_push(&pass->vars, stmt->u.bind.pattern->id);
  }
  if (stmt->kind == MS_S_IF && stmt->u.branch.binding != NULL && stmt->u.branch.cond->kind == MS_E_NAME &&
      !ms_check_holds_resource(pass->program, ms_facts_type(pass->facts, stmt->u.branch.cond->id))) {
    ms_binding_list_push(&pass->reads, stmt->u.branch.cond->id);
  }
}

static void check_body(Moves *pass, MsArena *arena, MsStmts body, MsParams params) {
  if (body.len == 0) {
    return;
  }
  for (uint32_t index = 0; index < params.len; index++) {
    if (params.ptr[index]->moving) {
      ms_binding_list_push(&pass->moving, params.ptr[index]->id);
    }
  }
  ms_walk_callable(&(MsVisitor){.ctx = pass, .stmt = note_var}, params, body);
  MsLiveness live = ms_live_compute(pass->facts, pass->program->names, arena, body);
  pass->live = &live;
  ms_walk_callable(&(MsVisitor){.ctx = pass, .expr = note_spot}, params, body);
  ms_walk_callable(&(MsVisitor){.ctx = pass, .expr = visit_expr, .leave_expr = leave_expr}, params, body);
  spot_list_clear(&pass->spots);
  ms_binding_list_clear(&pass->vars);
  ms_binding_list_clear(&pass->reads);
  ms_binding_list_clear(&pass->moving);
  ms_binding_list_clear(&pass->outer);
  pass->depth = 0;
  ms_liveness_free(&live);
}

static void check_decl(Moves *pass, MsArena *arena, const MsDecl *decl) {
  switch ((MsDeclKind)decl->kind) {
  case MS_D_FN:
    check_body(pass, arena, decl->u.fn.body, decl->u.fn.params);
    return;
  case MS_D_TEST:
    check_body(pass, arena, decl->u.test.body, (MsParams){0});
    return;
  case MS_D_IMPL:
    for (uint32_t index = 0; index < decl->u.impl.methods.len; index++) {
      const MsFunc *func = &decl->u.impl.methods.ptr[index]->func;
      check_body(pass, arena, func->body, func->params);
    }
    return;
  case MS_D_CONST:
  case MS_D_TYPE:
  case MS_D_ENUM:
  case MS_D_ALIAS:
  case MS_D_INTERFACE:
    return;
  }
}

void ms_own_moves(MsCheckProgram *program) {
  MsArena arena = ms_arena_new();
  MsClassifier classes = ms_class_new(program);
  for (uint32_t module = 0; module < program->user_modules; module++) {
    Moves pass = {.program = program, .module = module, .facts = &program->modules.ptr[module].facts,
                  .classes = &classes, .arena = &arena};
    const MsModule *tree = program->modules.ptr[module].tree;
    for (uint32_t index = 0; index < tree->ndecls; index++) {
      check_decl(&pass, &arena, tree->decls[index]);
    }
    spot_list_free(&pass.spots);
    ms_binding_list_free(&pass.vars);
    ms_binding_list_free(&pass.reads);
    ms_binding_list_free(&pass.moving);
    ms_binding_list_free(&pass.outer);
  }
  ms_class_free(&classes);
  ms_arena_free(&arena);
}
