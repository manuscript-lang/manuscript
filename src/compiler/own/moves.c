/* compiler/own/moves.c: a moved value used again (see moves.h). */
#include "compiler/own/look_fields.h"
#include "compiler/own/moves.h"
#include "compiler/own/taken.h"

#include "compiler/check/methods.h"
#include "compiler/own/bind.h"
#include "compiler/own/expr_text.h"
#include "compiler/own/class.h"
#include "compiler/own/live.h"
#include "compiler/own/result_borrows.h"
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
  MsBindingList reads;  /* `if p := name { ... }` scrutinees that are not resources: the payload is a view, the name stays whole */
  MsBindingList moving; /* binding sites of `move` parameters of the body */
  MsBindingList taking; /* binding sites of parameters the body hands on without declaring them `move`: it owns them too */
  uint32_t assigning; /* the binding the statement being visited assigns whole, or UINT32_MAX */
  MsBindingList plainparams; /* binding sites of parameters that are neither `move` nor `var`: the caller keeps them */
  MsBindingList varparams; /* binding sites of `var` parameters: the caller's place, which a closure cannot take */
  MsBindingList borrowed; /* binding sites of names bound to a view of another value */
  MsBindingList owners;   /* binding sites of locals that hold a value of their own: made by a call or literal, or a `var` */
  MsBindingList outer;  /* what the lambdas around the current expression capture: only borrowed inside them */
  bool ref_result;      /* the callable answers a `&` result: `ok(part)` wraps the part without taking it */
  uint32_t taken;       /* the parameters of the body being checked that its callers' arguments move into, by index */
  uint32_t depth;       /* lambdas open around the current expression */
  bool instance;        /* checking one instance of a generic body: only a type variable that became a resource is reported */
  const MsTy *subst_vars, *subst_args;
  uint32_t nsubst;
  bool found;
  MsPos at;
  MsName who;
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
  if (ty != MS_TY_NONE && ms_check_holds_resource(pass->program, ty)) {
    ms_strbuild_append_text(&text, "; a resource has one owner and cannot be cloned, so move it only at its last use, or pass it where it is only read");
  } else {
    ms_strbuild_append_text(&text, "; a value has one owner, so move it only at its last use, or pass `");
    ms_strbuild_append(&text, name);
    ms_strbuild_append_text(&text, ".clone()` if the original is still needed");
  }
  ms_check_report(pass->program, pass->module, expr->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
}

/* A plain parameter is the caller's: handing it on needs `move` on the parameter, or `.clone()` to give a copy. */
static void report_borrowed(Moves *pass, const MsExpr *expr) {
  if (pass->instance) {
    if (!pass->found) {
      pass->found = true;
      pass->at = expr->pos;
      pass->who = expr->u.sym;
    }
    return;
  }
  const MsSpan name = ms_names_span(pass->program->names, expr->u.sym);
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "`");
  ms_strbuild_append(&text, name);
  ms_strbuild_append_text(&text, "` is a view of another value, not an owner, and cannot be moved here; take the owner with `move`, or pass `");
  ms_strbuild_append(&text, name);
  ms_strbuild_append_text(&text, ".clone()`");
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
    if (ms_own_look_record(pass->program, ty)) {
      /* a look has no copy of its own, so the closure would keep a pointer into a value its owner may free first */
      ms_strbuild_append_text(&text, "this closure outlives the statement but captures `");
      ms_strbuild_append(&text, name);
      ms_strbuild_append_text(&text, "`, which looks at a value another binding owns; capture a `.clone()` of the part it needs, or keep the closure local");
      ms_check_report(pass->program, pass->module, lambda->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
      continue;
    }
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
    if (!copy && ms_binding_list_contains(&pass->varparams, first.binding)) {
      ms_strbuild_append_text(&text, "this closure outlives the statement but captures the `var` parameter `");
      ms_strbuild_append(&text, name);
      ms_strbuild_append_text(&text, "`, which the caller keeps; bind `own := ");
      ms_strbuild_append(&text, name);
      ms_strbuild_append_text(&text, ".clone()` before the closure and capture `own` instead, or take it by `move`");
    } else if (!copy && (ms_binding_list_contains(&pass->outer, first.binding) ||
                  ((ms_binding_list_contains(&pass->borrowed, first.binding) || ms_binding_list_contains(&pass->plainparams, first.binding)) &&
                   ms_ty_kind(&pass->program->types, ty) != MS_TY_FUNCTION))) { /* a function value is shared: the closure takes its own reference */
      ms_strbuild_append_text(&text, "this closure outlives the statement but captures `");
      ms_strbuild_append(&text, name);
      ms_strbuild_append_text(&text, "`, which is borrowed, not owned; bind `own := ");
      ms_strbuild_append(&text, name);
      ms_strbuild_append_text(&text, ".clone()` before the closure and capture `own` instead");
    } else if (again && copy && ms_binding_list_contains(&pass->vars, first.binding)) {
      ms_strbuild_append_text(&text, "this closure outlives the statement but captures the `var` `");
      ms_strbuild_append(&text, name);
      ms_strbuild_append_text(&text, "`");
      append_later(pass, &text, use->next);
      ms_strbuild_append_text(&text, "; the closure would keep a stale value, so bind an immutable snapshot with `snapshot := ");
      ms_strbuild_append(&text, name);
      ms_strbuild_append_text(&text, "` before the closure and capture `snapshot`");
    } else if (again && !copy && ms_ty_kind(&pass->program->types, ty) == MS_TY_FUNCTION) {
      pass->facts->uses[first.use->id] = MS_USE_CLONE; /* the closure takes a copy of the function value; the maker keeps the original */
      ms_strbuild_free(&text);
      continue;
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

/* A value whose copy a program can write: it owns memory and has a `.clone()`. A function value is shared, and an
 * interface or opaque runtime handle has no `.clone()` to ask for. */
static bool copy_is_written(Moves *pass, MsTy ty) {
  const MsTyKind kind = ms_ty_kind(&pass->program->types, ty);
  return kind != MS_TY_FUNCTION && kind != MS_TY_CONTRACT && kind != MS_TY_NATIVE && ms_class_of(pass->classes, ty) != MS_CLASS_COPY;
}

/* A borrowed parameter, or a payload of one, written where a new owner is made: a constructor argument, a `move`
 * parameter's argument, or the returned value. */
static void check_handed_on(Moves *pass, const MsExpr *value, bool any_data) {
  uint32_t binding = 0;
  const MsTy ty = ms_facts_type(pass->facts, value->id);
  const MsTy concrete = pass->instance && ty != MS_TY_NONE && ms_ty_has_variable(&pass->program->types, ty)
                            ? ms_ty_subst(&pass->program->types, ty, pass->subst_vars, pass->subst_args, pass->nsubst)
                            : (pass->instance ? MS_TY_NONE : ty);
  if (pass->depth == 0 && value->kind == MS_E_NAME && ms_bind_of(pass->facts, value->id, &binding) &&
      (ms_binding_list_contains(&pass->borrowed, binding) || (any_data && !pass->instance && ms_binding_list_contains(&pass->plainparams, binding))) &&
      concrete != MS_TY_NONE && (ms_check_holds_resource(pass->program, concrete) ||
       (any_data && !pass->instance && !ms_ty_has_variable(&pass->program->types, concrete) && copy_is_written(pass, concrete)))) {
    report_borrowed(pass, value);
  }
}

static bool owner_at_last_use(Moves *pass, const MsExpr *name, bool allow_var);
static MsSpan place_text(const Moves *pass, const MsExpr *expr);

/* The root name of a field or element path (`self.rows[0]`), and whether an element is on the way. */
static const MsExpr *path_root(const MsExpr *expr, bool *element) {
  MsExpr *left = NULL;
  MsExpr *at = NULL;
  while (expr->kind == MS_E_MEMBER || ms_expr_index(expr, &left, &at)) {
    *element = *element || expr->kind != MS_E_MEMBER;
    expr = expr->kind == MS_E_MEMBER ? expr->u.member.left : left;
  }
  return expr;
}

/* A field or element of an existing value, written where a new owner is made (a constructor argument or a `move`
 * parameter's argument). Only a field read at its record's last use leaves the record; anything else would be copied
 * behind the source's back, and `.clone()` is the only copy. */
static void check_place_handed_on(Moves *pass, const MsExpr *value) {
  uint32_t binding = 0;
  MsExpr *left = NULL;
  MsExpr *at = NULL;
  if (pass->depth != 0 || (value->kind != MS_E_MEMBER && !ms_expr_index(value, &left, &at))) {
    return;
  }
  const MsRef *member = value->kind == MS_E_MEMBER ? ms_facts_ref(pass->facts, value->id) : NULL;
  if (member != NULL && member->kind == MS_REF_CASE) {
    return; /* `Color.Red` names a case */
  }
  bool element = false;
  const MsExpr *root = path_root(value, &element);
  if (root->kind != MS_E_NAME || !ms_bind_of(pass->facts, root->id, &binding)) {
    return; /* the field of a call's result leaves the temporary */
  }
  const MsTy ty = ms_facts_type(pass->facts, value->id);
  const MsTy concrete = pass->instance && ty != MS_TY_NONE && ms_ty_has_variable(&pass->program->types, ty)
                            ? ms_ty_subst(&pass->program->types, ty, pass->subst_vars, pass->subst_args, pass->nsubst)
                            : (pass->instance ? MS_TY_NONE : ty);
  if (concrete == MS_TY_NONE || (!pass->instance && ms_ty_has_variable(&pass->program->types, concrete)) || !copy_is_written(pass, concrete)) {
    return;
  }
  const bool looks = value->kind == MS_E_MEMBER && ms_own_look_member(pass->program, pass->facts, value);
  const bool leaves = !element && !looks && value->kind == MS_E_MEMBER && root == value->u.member.left && !pass->instance &&
                      !ms_binding_list_contains(&pass->borrowed, binding) && !ms_binding_list_contains(&pass->vars, binding) &&
                      !ms_binding_list_contains(&pass->varparams, binding) && owner_at_last_use(pass, root, false);
  if (leaves || ms_check_holds_resource(pass->program, concrete)) {
    return; /* a resource is reported by `check_move_receiver` and the borrowed-name rule */
  }
  if (pass->instance) {
    return; /* a generic body is checked once, where its type is still a variable */
  }
  const MsSpan place_span = place_text(pass, value);
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "`");
  ms_strbuild_append(&text, place_span);
  if (looks) {
    ms_strbuild_append_text(&text, "` looks at a value its record does not own (the field is written `&`), so a new owner needs a copy; write `");
  } else {
    ms_strbuild_append_text(&text, "` belongs to `");
    ms_strbuild_append(&text, ms_names_span(pass->program->names, root->u.sym));
    ms_strbuild_append_text(&text, "`, so a new owner would get a hidden copy; write `");
  }
  ms_strbuild_append(&text, place_span);
  ms_strbuild_append_text(&text, ".clone()` to copy it");
  if (!element && !looks) {
    ms_strbuild_append_text(&text, ", or use the field at the last use of the record to move it");
  }
  ms_check_report(pass->program, pass->module, value->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
}

/* A value handed to a new owner (a constructor, a `move` parameter, a literal element, a binding or a return). `x or d`
 * read in place answers a view and copies nothing, but handed to an owner it must give `x`'s payload up: a borrowed `x`
 * is the same error as a borrowed argument. */
static void check_new_owner(Moves *pass, const MsExpr *value);

/* The left side of an `x or d` that is handed to a new owner. */
static void check_or_left(Moves *pass, const MsExpr *value) {
  if (value->kind == MS_E_BINARY && value->op == MS_B_OR &&
      ms_ty_is(&pass->program->types, ms_facts_type(pass->facts, value->u.bin.left->id), MS_BUILTIN_Optional) &&
      !ms_ty_is(&pass->program->types, ms_facts_type(pass->facts, value->u.bin.right->id), MS_BUILTIN_Never)) {
    check_new_owner(pass, value->u.bin.left);
  }
}

static void check_new_owner(Moves *pass, const MsExpr *value) {
  check_handed_on(pass, value, true);
  check_place_handed_on(pass, value);
  check_or_left(pass, value);
}

static void visit_stmt(void *ctx, const MsStmt *stmt) {
  Moves *pass = ctx;
  uint32_t assigned = 0;
  pass->assigning = stmt->kind == MS_S_ASSIGN && stmt->u.assign.target == NULL && !stmt->u.assign.has_compound &&
                            ms_bind_of(pass->facts, stmt->id, &assigned)
                        ? assigned
                        : UINT32_MAX;
  uint32_t returned = 0;
  /* Returning a plain parameter whole answers a view of it: the lowering gives the caller that borrowed result. */
  const bool whole_param = pass->instance && stmt->kind == MS_S_RETURN && stmt->u.expr != NULL &&
                           stmt->u.expr->kind == MS_E_NAME && ms_bind_of(pass->facts, stmt->u.expr->id, &returned) &&
                           (pass->ref_result || ms_binding_list_contains(&pass->plainparams, returned));
  if (stmt->kind == MS_S_RETURN && stmt->u.expr != NULL && !whole_param) {
    check_handed_on(pass, stmt->u.expr, false);
    check_or_left(pass, stmt->u.expr);
  }
  if (stmt->kind == MS_S_BIND && stmt->u.bind.value != NULL) {
    check_or_left(pass, stmt->u.bind.value);
  }
  if (stmt->kind == MS_S_ASSIGN && stmt->u.assign.value != NULL && !stmt->u.assign.has_compound) {
    check_or_left(pass, stmt->u.assign.value);
  }
}

static bool owner_at_last_use(Moves *pass, const MsExpr *name, bool allow_var);
static bool mark_last_use(Moves *pass, const MsExpr *name);

/* A field read from a name that owns its value, at that name's last use, may leave the record: nothing of the name is
 * read afterwards. The lowering moves it only where the consumer takes ownership. */
static void note_last_field(Moves *pass, const MsExpr *expr) {
  if (expr->u.member.left->kind == MS_E_NAME && expr->id < pass->facts->node_count) {
    pass->facts->last[expr->id] = owner_at_last_use(pass, expr->u.member.left, false);
  }
}

/* The source text of an expression. */
static MsSpan place_text(const Moves *pass, const MsExpr *expr) {
  const MsSpan source = pass->program->modules.ptr[pass->module].source;
  const MsPos start = ms_expr_start(expr);
  return (MsSpan){source.ptr + start.offset, expr->end.offset - start.offset};
}

/* A place as the diagnostics write it: names and members as written, every index as `[..]`. */
static void append_place_text(const Moves *pass, MsStrBuild *out, const MsExpr *expr) {
  MsExpr *left = NULL;
  MsExpr *index = NULL;
  if (expr->kind == MS_E_MEMBER) {
    append_place_text(pass, out, expr->u.member.left);
    ms_strbuild_append_text(out, ".");
    ms_strbuild_append(out, ms_names_span(pass->program->names, expr->u.member.name));
  } else if (ms_expr_index(expr, &left, &index)) {
    append_place_text(pass, out, left);
    ms_strbuild_append_text(out, "[..]");
  } else if (expr->kind == MS_E_NAME) {
    ms_strbuild_append(out, ms_names_span(pass->program->names, expr->u.sym));
  } else {
    ms_strbuild_append(out, place_text(pass, expr));
  }
}

/* `res.close()` on a parameter the caller keeps: a `move` receiver must be declared `move`. */
static void check_move_receiver(Moves *pass, const MsExpr *call) {
  const MsCall *fact = ms_facts_call(pass->facts, call->id);
  const MsExpr *callee = call->u.call.callee;
  uint32_t binding = 0;
  if (pass->instance || pass->depth != 0 || fact == NULL || fact->arg_count == 0 || callee->kind != MS_E_MEMBER ||
      fact->args[0].source != MS_ARG_WRITTEN || fact->args[0].node.node != callee->u.member.left->id ||
      (fact->args[0].flags & MS_PARAM_MOVE) == 0) {
    return;
  }
  const MsExpr *receiver = callee->u.member.left;
  MsExpr *indexed_left = NULL;
  MsExpr *indexed_at = NULL;
  if (receiver->kind == MS_E_MEMBER || ms_expr_index(receiver, &indexed_left, &indexed_at)) {
    /* `pair.first.close()` on a `var` holder: the field would leave a record that stays in use with a hole in it.
     * An element never leaves its collection, whatever the binding. */
    bool element = false;
    const MsExpr *root = receiver;
    while (root->kind == MS_E_MEMBER || ms_expr_index(root, &indexed_left, &indexed_at)) {
      element = element || root->kind != MS_E_MEMBER;
      root = root->kind == MS_E_MEMBER ? root->u.member.left : indexed_left;
    }
    const MsTy field = ms_facts_type(pass->facts, receiver->id);
    if (root->kind == MS_E_NAME && ms_bind_of(pass->facts, root->id, &binding) &&
        (element || ms_binding_list_contains(&pass->vars, binding) || ms_binding_list_contains(&pass->varparams, binding)) && field != MS_TY_NONE &&
        ms_check_holds_resource(pass->program, field)) {
      MsStrBuild place = ms_strbuild_new();
      append_place_text(pass, &place, receiver);
      const MsSpan place_span = ms_strbuild_span(&place);
      const MsSpan root_name = ms_names_span(pass->program->names, root->u.sym);
      MsStrBuild moved = ms_strbuild_new();
      ms_strbuild_append_text(&moved, "cannot move the resource `");
      ms_strbuild_append(&moved, place_span);
      ms_strbuild_append_text(&moved, "` out of `");
      ms_strbuild_append(&moved, root_name);
      ms_strbuild_append_text(&moved, "`: a resource cannot be cloned, and it leaves `");
      ms_strbuild_append(&moved, root_name);
      ms_strbuild_append_text(&moved, "` only when `");
      ms_strbuild_append(&moved, root_name);
      ms_strbuild_append_text(&moved, "` is a local binding or a parameter and no type on the path has a `close` of its own; use `");
      ms_strbuild_append(&moved, place_span);
      ms_strbuild_append_text(&moved, "` in place, move the whole `");
      ms_strbuild_append(&moved, root_name);
      ms_strbuild_append_text(&moved, "`, or take it with `part := ");
      ms_strbuild_append(&moved, place_span);
      ms_strbuild_append_text(&moved, "` and refill `");
      ms_strbuild_append(&moved, place_span);
      ms_strbuild_append_text(&moved, " = ...` in the next statement");
      ms_check_report(pass->program, pass->module, receiver->pos, MS_CHECK_TYPE, ms_strbuild_finish(&moved));
      ms_strbuild_free(&place);
    }
    return;
  }
  if (receiver->kind != MS_E_NAME) {
    return;
  }
  const MsTy ty = ms_facts_type(pass->facts, receiver->id);
  if (!ms_bind_of(pass->facts, receiver->id, &binding) || !ms_binding_list_contains(&pass->plainparams, binding) || ty == MS_TY_NONE ||
      !ms_check_holds_resource(pass->program, ty)) {
    return;
  }
  const MsSpan name = ms_names_span(pass->program->names, receiver->u.sym);
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "cannot pass `");
  ms_strbuild_append(&text, name);
  ms_strbuild_append_text(&text, "` as a `move` receiver: it is not declared `move`, so the caller keeps it; write `move ");
  ms_strbuild_append(&text, name);
  ms_strbuild_append_text(&text, " <Type>` in the signature");
  ms_check_report(pass->program, pass->module, receiver->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
}

static void visit_expr(void *ctx, const MsExpr *expr) {
  Moves *pass = ctx;
  uint32_t binding = 0;
  if (expr->kind == MS_E_CALL) {
    check_move_receiver(pass, expr);
  }
  if (!pass->instance && expr->kind == MS_E_MEMBER && pass->facts->last != NULL) {
    note_last_field(pass, expr);
  }
  const MsCall *call = expr->kind == MS_E_CALL ? ms_facts_call(pass->facts, expr->id) : NULL;
  for (uint32_t index = 0; call != NULL && index < call->arg_count; index++) {
    if (call->args[index].source != MS_ARG_WRITTEN || (!call->constructor && (call->args[index].flags & MS_PARAM_MOVE) == 0) ||
        ms_own_look_field(pass->program, call, index) || ms_own_look_carrier(pass->program, call, index) ||
        (pass->ref_result && call->callee.kind == MS_REF_CASE)) {
      continue;
    }
    for (uint32_t at = 0; at < expr->u.call.args.len; at++) {
      if (expr->u.call.args.ptr[at].value->id == call->args[index].node.node) {
        check_new_owner(pass, expr->u.call.args.ptr[at].value);
      }
    }
  }
  if (expr->kind == MS_E_MATCH && expr->u.match.scrutinee->kind == MS_E_NAME &&
      ms_bind_of(pass->facts, expr->u.match.scrutinee->id, &binding) && ms_binding_list_contains(&pass->borrowed, binding)) {
    /* The payloads of a borrowed value are borrowed too. */
    for (uint32_t arm = 0; arm < expr->u.match.arms.len; arm++) {
      const MsArm *one = expr->u.match.arms.ptr[arm];
      ms_binding_list_push(&pass->borrowed, one->id);
    }
  }
  /* A list or map literal makes a new owner of every element it is given. */
  for (uint32_t at = 0; expr->kind == MS_E_LIST && at < expr->u.list.len; at++) {
    check_new_owner(pass, expr->u.list.ptr[at]);
  }
  for (uint32_t at = 0; expr->kind == MS_E_MAP && at < expr->u.map.len; at++) {
    check_new_owner(pass, expr->u.map.ptr[at].key);
    check_new_owner(pass, expr->u.map.ptr[at].value);
  }
  if (pass->instance) {
    return; /* an instance only reports a view or borrowed parameter that became a resource and moved on */
  }
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
    const MsTyParam *typed = ms_ty_params(&pass->program->types, ms_facts_type(pass->facts, expr->id));
    for (uint32_t at = 0; at < expr->u.lambda.params.len; at++) {
      if (typed != NULL && (typed[at].flags & MS_PARAM_MOVE) != 0) {
        ms_binding_list_push(&pass->moving, expr->u.lambda.params.ptr[at]->id); /* the function type hands it over */
      }
    }
    return;
  }
  if (expr->kind == MS_E_MATCH && expr->u.match.scrutinee->kind == MS_E_NAME &&
      ms_bind_of(pass->facts, expr->u.match.scrutinee->id, &binding) && ms_binding_list_contains(&pass->borrowed, binding)) {
    /* The payloads of a borrowed value are borrowed too. */
    for (uint32_t arm = 0; arm < expr->u.match.arms.len; arm++) {
      const MsArm *one = expr->u.match.arms.ptr[arm];
      ms_binding_list_push(&pass->borrowed, one->id);
    }
  }
  if (expr->kind == MS_E_NAME && ms_facts_use(pass->facts, expr->id) == MS_USE_BORROW) {
    (void)mark_last_use(pass, expr); /* an owner read for the last time is consumed by whatever takes it */
  }
  if (expr->kind != MS_E_NAME || ms_facts_use(pass->facts, expr->id) != MS_USE_MOVE || ms_binding_list_contains(&pass->reads, expr->id) ||
      !ms_bind_of(pass->facts, expr->id, &binding)) {
    return;
  }
  if (!pass->instance && pass->depth == 0 && binding != pass->assigning && ms_binding_list_contains(&pass->varparams, binding)) {
    const MsTy held = ms_facts_type(pass->facts, expr->id);
    const bool resource = held != MS_TY_NONE && ms_check_holds_resource(pass->program, held);
    if (held != MS_TY_NONE && ms_class_of(pass->classes, held) != MS_CLASS_COPY &&
        ms_ty_kind(&pass->program->types, held) != MS_TY_FUNCTION) {
      MsStrBuild text = ms_strbuild_new();
      const MsSpan name = ms_names_span(pass->program->names, expr->u.sym);
      ms_strbuild_append_text(&text, "cannot move `");
      ms_strbuild_append(&text, name);
      ms_strbuild_append_text(&text, "` out of the function: the caller keeps ownership of a var parameter");
      if (resource) {
        ms_strbuild_append_text(&text, " and closes it; a resource cannot be cloned, so change it in place");
      } else {
        ms_strbuild_append_text(&text, "; return `");
        ms_strbuild_append(&text, name);
        ms_strbuild_append_text(&text, ".clone()` or change the value in place");
      }
      ms_check_report(pass->program, pass->module, expr->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
      return;
    }
  }
  const MsUseLive *use = ms_live_map_get(&pass->live->uses, ms_live_key(expr->id, binding));
  if (use != NULL && !use->last) {
    const MsTy ty = ms_facts_type(pass->facts, expr->id);
    if (ty != MS_TY_NONE && ms_ty_kind(&pass->program->types, ty) == MS_TY_FUNCTION) {
      pass->facts->uses[expr->id] = MS_USE_BORROW; /* a function value never changes, so what takes it before its last use gets a copy */
      return;
    }
    report(pass, expr, use->next);
    return;
  }

}

/* Whether `name` is an owner read for the last time: whatever takes it may take it whole, with nothing left to read
 * afterwards. A view, a plain parameter and a name read inside a closure are not owners. A `var` record's fields stay in
 * the record the binding puts back, so only names (not fields) of `var`s count. */
static bool owner_at_last_use(Moves *pass, const MsExpr *name, bool allow_var) {
  uint32_t binding = 0;
  if (name->kind != MS_E_NAME || pass->facts->last == NULL || pass->instance || pass->live == NULL ||
      !ms_bind_of(pass->facts, name->id, &binding) || ms_binding_list_contains(&pass->outer, binding) || ms_binding_list_contains(&pass->borrowed, binding)) {
    return false;
  }
  const MsRef *ref = ms_facts_ref(pass->facts, name->id);
  const MsUseLive *use = ms_live_map_get(&pass->live->uses, ms_live_key(name->id, binding));
  const bool owner = ref != NULL && (ref->kind == MS_REF_PARAM ? ms_binding_list_contains(&pass->moving, binding) || ms_binding_list_contains(&pass->taking, binding)
                                                               : ref->kind == MS_REF_LOCAL &&
                                                                     (ms_binding_list_contains(&pass->owners, binding) ||
                                                                      (allow_var && ms_binding_list_contains(&pass->vars, binding))));
  return owner && use != NULL && use->last;
}

static bool mark_last_use(Moves *pass, const MsExpr *name) {
  if (!owner_at_last_use(pass, name, true)) {
    return false;
  }
  pass->facts->last[name->id] = 1;
  return true;
}

/* A call `x.get()` whose receiver is an owner at its last use consumes it: what the call returns is taken out of the
 * receiver rather than copied. The lowering reads the mark on the receiver name. */
static bool last_use_receiver(Moves *pass, const MsExpr *call) {
  const MsExpr *callee = call->u.call.callee;
  return callee->kind == MS_E_MEMBER && mark_last_use(pass, callee->u.member.left);
}

/* A name bound to a call result that borrows (`secure := outcome.get()`) holds a view, not an owner. */
static void note_view(Moves *pass, const MsStmt *stmt) {
  const MsExpr *value = stmt->u.bind.value;
  const MsCall *call = value != NULL && value->kind == MS_E_CALL ? ms_facts_call(pass->facts, value->id) : NULL;
  for (uint32_t position = 0; call != NULL && position < call->arg_count; position++) {
    if (ms_own_call_borrows(pass->program, call, position)) {
      if (position == 0 && last_use_receiver(pass, value)) {
        return; /* the receiver dies here, so the result is taken out of it and owns what it holds */
      }
      for (uint32_t arg = 0; arg < value->u.call.args.len; arg++) {
        if (value->u.call.args.ptr[arg].value->kind == MS_E_CALL) {
          return; /* what the call borrows from is a temporary, which moves into the result (`ok(Token(..))`) */
        }
      }
      ms_binding_list_push(&pass->borrowed, stmt->u.bind.pattern->id);
      return;
    }
  }
}

/* Whether an expression makes a value of its own: a call, a literal, or a call's result unwrapped. */
static bool fresh_value(const MsExpr *value) {
  while (value->kind == MS_E_UNARY && value->op == MS_U_TRY) {
    value = value->u.bin.left; /* a call's result unwrapped */
  }
  return value->kind == MS_E_CALL || value->kind == MS_E_LIST || value->kind == MS_E_MAP;
}

/* `var x = o.inner`, where `o` is a parameter: the caller keeps `o.inner`, and a `var` is a value of its own, so the copy
 * must be written. */
static void note_var_borrow(Moves *pass, const MsStmt *stmt) {
  const MsExpr *value = stmt->u.bind.value;
  const MsExpr *root = value;
  while (value != NULL && root->kind == MS_E_MEMBER) {
    root = root->u.member.left;
  }
  uint32_t binding = 0;
  const MsTy ty = value != NULL ? ms_facts_type(pass->facts, value->id) : MS_TY_NONE;
  if (pass->instance || pass->depth != 0 || value == NULL || value->kind != MS_E_MEMBER || root->kind != MS_E_NAME ||
      !ms_bind_of(pass->facts, root->id, &binding) || ty == MS_TY_NONE || ms_class_of(pass->classes, ty) == MS_CLASS_COPY ||
      ms_ty_kind(&pass->program->types, ty) == MS_TY_FUNCTION) {
    return;
  }
  if (ms_binding_list_contains(&pass->vars, binding) && ms_check_holds_resource(pass->program, ty)) {
    /* A resource field of a local `var` leaves it only as `part := holder.field`, refilled by the next statement. */
    MsStrBuild taken = ms_strbuild_new();
    ms_strbuild_append_text(&taken, "`var ");
    ms_strbuild_append(&taken, ms_names_span(pass->program->names, stmt->u.bind.pattern->u.name));
    ms_strbuild_append_text(&taken, "` cannot take the resource `");
    ms_strbuild_append(&taken, place_text(pass, value));
    ms_strbuild_append_text(&taken, "`: it would leave `");
    ms_strbuild_append(&taken, ms_names_span(pass->program->names, root->u.sym));
    ms_strbuild_append_text(&taken, "` with a hole; use it in place, or take it with `part := ");
    ms_strbuild_append(&taken, place_text(pass, value));
    ms_strbuild_append_text(&taken, "` and refill `");
    ms_strbuild_append(&taken, place_text(pass, value));
    ms_strbuild_append_text(&taken, " = ...` in the next statement");
    ms_check_report(pass->program, pass->module, value->pos, MS_CHECK_TYPE, ms_strbuild_finish(&taken));
    return;
  }
  if (!(ms_binding_list_contains(&pass->varparams, binding) || ms_binding_list_contains(&pass->plainparams, binding))) {
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "`var ");
  ms_strbuild_append(&text, ms_names_span(pass->program->names, stmt->u.bind.pattern->u.name));
  ms_strbuild_append_text(&text, "` cannot take `");
  ms_strbuild_append(&text, place_text(pass, value));
  ms_strbuild_append_text(&text, "`: the caller keeps it, and a `var` is a value of its own; copy it with `");
  ms_strbuild_append(&text, place_text(pass, value));
  ms_strbuild_append_text(&text, ".clone()`, or change it in place through `");
  ms_strbuild_append(&text, ms_names_span(pass->program->names, root->u.sym));
  ms_strbuild_append_text(&text, "`");
  ms_check_report(pass->program, pass->module, value->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
}

static void note_var(void *ctx, const MsStmt *stmt) {
  Moves *pass = ctx;
  if (stmt->kind == MS_S_BIND && !stmt->u.bind.is_mutable && stmt->u.bind.pattern->kind == MS_P_NAME) {
    note_view(pass, stmt);
    if (fresh_value(stmt->u.bind.value) && !ms_binding_list_contains(&pass->borrowed, stmt->u.bind.pattern->id)) {
      ms_binding_list_push(&pass->owners, stmt->u.bind.pattern->id);
    }
  }
  if (stmt->kind == MS_S_BIND && stmt->u.bind.is_mutable && stmt->u.bind.pattern->kind == MS_P_NAME) {
    ms_binding_list_push(&pass->vars, stmt->u.bind.pattern->id);
    note_var_borrow(pass, stmt);
  }
  if (stmt->kind == MS_S_IF && stmt->u.branch.binding != NULL && stmt->u.branch.cond->kind == MS_E_NAME &&
      stmt->u.branch.is_mutable && !pass->instance && !mark_last_use(pass, stmt->u.branch.cond)) {
    /* `if var x = name` moves `name` into `x` at its last use; anywhere else there is no entry in place to lend. */
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_append_text(&text, "`if var` borrows an entry written as `place[key]?` or `map.get(key)`, but `");
    ms_own_expr_text(&text, pass->program->names, stmt->u.branch.cond);
    ms_strbuild_append_text(&text, "` is not one; read the payload by testing `if value != null { ... }`, then use `var copy = x.clone()` for an "
                                   "independent mutable copy, or write the changed value back");
    ms_check_report(pass->program, pass->module, stmt->u.branch.binding->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  }
  if (stmt->kind == MS_S_IF && stmt->u.branch.binding != NULL && stmt->u.branch.cond->kind == MS_E_NAME &&
      !stmt->u.branch.is_mutable) {
    if (mark_last_use(pass, stmt->u.branch.cond) && stmt->u.branch.binding->kind == MS_P_NAME) {
      ms_binding_list_push(&pass->owners, stmt->u.branch.binding->id); /* the payload leaves the name whole */
    }
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
    if (!params.ptr[index]->moving && index < 32 && (pass->taken >> index & 1u) != 0) {
      ms_binding_list_push(&pass->taking, params.ptr[index]->id);
    }
    if (params.ptr[index]->moving) {
      ms_binding_list_push(&pass->moving, params.ptr[index]->id);
    } else if (params.ptr[index]->is_mutable) {
      ms_binding_list_push(&pass->varparams, params.ptr[index]->id);
    } else {
      ms_binding_list_push(&pass->plainparams, params.ptr[index]->id);
    }
  }
  MsLiveness live = ms_live_compute(pass->facts, pass->program->names, arena, body);
  pass->live = &live;
  ms_walk_callable(&(MsVisitor){.ctx = pass, .stmt = note_var}, params, body);
  ms_walk_callable(&(MsVisitor){.ctx = pass, .expr = note_spot}, params, body);
  ms_walk_callable(&(MsVisitor){.ctx = pass, .expr = visit_expr, .stmt = visit_stmt, .leave_expr = leave_expr}, params, body);
  spot_list_clear(&pass->spots);
  ms_binding_list_clear(&pass->vars);
  ms_binding_list_clear(&pass->owners);
  ms_binding_list_clear(&pass->reads);
  ms_binding_list_clear(&pass->moving);
  ms_binding_list_clear(&pass->taking);
  ms_binding_list_clear(&pass->varparams);
  ms_binding_list_clear(&pass->plainparams);
  ms_binding_list_clear(&pass->borrowed);
  ms_binding_list_clear(&pass->outer);
  pass->depth = 0;
  ms_liveness_free(&live);
}

static void check_decl(Moves *pass, MsArena *arena, const MsDecl *decl) {
  switch ((MsDeclKind)decl->kind) {
  case MS_D_FN:
    if (decl->u.fn.deferred) {
      return;
    }
    pass->taken = ms_own_taken_mask(pass->program, pass->module, decl->id);
    pass->ref_result = ms_own_result_is_borrowed(pass->program, pass->module, decl->id);
    check_body(pass, arena, decl->u.fn.body, decl->u.fn.params);
    return;
  case MS_D_TEST:
    check_body(pass, arena, decl->u.test.body, (MsParams){0});
    return;
  case MS_D_IMPL:
    for (uint32_t index = 0; index < decl->u.impl.methods.len; index++) {
      const MsFunc *func = &decl->u.impl.methods.ptr[index]->func;
      if (func->deferred) {
        continue;
      }
      pass->taken = ms_own_taken_mask(pass->program, pass->module, decl->u.impl.methods.ptr[index]->id);
      pass->ref_result = ms_own_result_is_borrowed(pass->program, pass->module, decl->u.impl.methods.ptr[index]->id);
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

bool ms_own_moves_instance(MsCheckProgram *program, uint32_t module, MsNode node, const MsFunc *func, const MsTy *vars,
                           const MsTy *args, uint32_t count, MsPos *at, MsName *who) {
  MsArena arena = ms_arena_new();
  MsClassifier classes = ms_class_new(program);
  Moves pass = {.program = program, .module = module, .facts = &program->modules.ptr[module].facts, .classes = &classes,
                .arena = &arena, .instance = true, .ref_result = ms_own_result_is_borrowed(program, module, node), .subst_vars = vars, .subst_args = args, .nsubst = count};
  for (uint32_t index = 0; index < func->params.len; index++) {
    if (!func->params.ptr[index]->moving && !func->params.ptr[index]->is_mutable) {
      ms_binding_list_push(&pass.borrowed, func->params.ptr[index]->id);
      ms_binding_list_push(&pass.plainparams, func->params.ptr[index]->id);
    }
  }
  ms_walk_callable(&(MsVisitor){.ctx = &pass, .stmt = note_var}, func->params, func->body);
  ms_walk_callable(&(MsVisitor){.ctx = &pass, .expr = visit_expr, .stmt = visit_stmt, .leave_expr = leave_expr}, func->params,
                   func->body);
  *at = pass.at;
  *who = pass.who;
  ms_binding_list_free(&pass.borrowed);
  ms_binding_list_free(&pass.reads);
  ms_binding_list_free(&pass.moving);
  ms_binding_list_free(&pass.outer);
  ms_binding_list_free(&pass.varparams);
  ms_binding_list_free(&pass.plainparams);
  ms_binding_list_free(&pass.vars);
  ms_binding_list_free(&pass.owners);
  spot_list_free(&pass.spots);
  ms_class_free(&classes);
  ms_arena_free(&arena);
  return pass.found;
}

void ms_own_moves(MsCheckProgram *program) {
  MsArena arena = ms_arena_new();
  MsClassifier classes = ms_class_new(program);
  for (uint32_t module = 0; module < program->modules.len; module++) {
    Moves pass = {.program = program, .module = module, .facts = &program->modules.ptr[module].facts,
                  .classes = &classes, .arena = &arena};
    const MsModule *tree = program->modules.ptr[module].tree;
    for (uint32_t index = 0; index < tree->ndecls; index++) {
      check_decl(&pass, &arena, tree->decls[index]);
    }
    spot_list_free(&pass.spots);
    ms_binding_list_free(&pass.vars);
    ms_binding_list_free(&pass.owners);
    ms_binding_list_free(&pass.reads);
    ms_binding_list_free(&pass.moving);
    ms_binding_list_free(&pass.taking);
    ms_binding_list_free(&pass.borrowed);
    ms_binding_list_free(&pass.outer);
    ms_binding_list_free(&pass.varparams);
    ms_binding_list_free(&pass.plainparams);
  }
  ms_class_free(&classes);
  ms_arena_free(&arena);
}
