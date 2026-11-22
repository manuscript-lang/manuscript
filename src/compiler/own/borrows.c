/* compiler/own/borrows.c: a source changed while a binding borrowing it is still used (see borrows.h). */
#include "compiler/own/borrows.h"

#include "compiler/check/methods.h"
#include "compiler/own/bind.h"
#include "compiler/own/class.h"
#include "compiler/own/uses.h"
#include "compiler/syntax/walk.h"

typedef struct Borrow {
  uint32_t binding; /* the borrowing binding */
  MsName name;
  MsPos at; /* where it is bound */
  uint32_t after; /* the offset its initializer ends at */
  bool mutable_;
  uint32_t root; /* the binding it borrows from */
} Borrow;

typedef struct Change {
  uint32_t root;
  MsPos pos;     /* where the changed place starts */
  uint32_t end;  /* the offset it ends at */
  bool assign;
} Change;

typedef struct Use {
  uint32_t binding;
  uint32_t offset;
} Use;

/* A source range: a branch's two arms exclude each other; a loop body runs again after its end. */
typedef struct Range {
  uint32_t lo, split, hi; /* an if: [lo, split) is the then arm and [split, hi] the else arm; a loop: [lo, hi] */
  bool loop;
} Range;

/* What a borrowing expression was computed from: the place it reads and the innermost call applied to it. */
typedef struct Source {
  uint32_t root;
  const MsExpr *place;
  const MsExpr *call;
} Source;

/* A borrowing call in a position that keeps its result. */
typedef struct Keep {
  const MsExpr *kept;
  Source source;
} Keep;

MS_LIST_DEFINE(RangeList, range_list, Range)
MS_LIST_DEFINE(KeepList, keep_list, Keep)
MS_LIST_DEFINE(BorrowList, borrow_list, Borrow)
MS_LIST_DEFINE(ChangeList, change_list, Change)
MS_LIST_DEFINE(UseList, use_list, Use)

typedef struct Borrows {
  MsCheckProgram *program;
  MsClassifier *classes;
  uint32_t module;
  MsFacts *facts;
  MsSpan source;
  BorrowList borrows;
  ChangeList changes;
  UseList uses;
  RangeList ranges;
  KeepList keeps;
  uint32_t depth; /* nesting of callee bodies being read */
  uint32_t high; /* the furthest end offset seen by the current measuring walk */
} Borrows;

/* The function-wide id of the local or parameter `node` names: the checker numbers locals densely and gives
 * parameters their own index space. */
static bool local_of(const MsFacts *facts, MsNode node, uint32_t *id) {
  const MsRef *ref = ms_facts_ref(facts, node);
  if (ref == NULL || (ref->kind != MS_REF_LOCAL && ref->kind != MS_REF_PARAM)) {
    return false;
  }
  *id = ref->kind == MS_REF_PARAM ? ref->local | 0x80000000u : ref->local;
  return true;
}

/* The function a callee ref names, or NULL when no declaration is found. */
static const MsFunc *find_func(const MsCheckProgram *program, const MsRef *ref) {
  for (size_t index = 0; index < program->methods.len; index++) {
    const MsMethodEntry *entry = &program->methods.ptr[index];
    if (entry->module == ref->decl.module && entry->source->id == ref->decl.node) {
      return &entry->source->func;
    }
  }
  const MsModule *tree = program->modules.ptr[ref->decl.module].tree;
  for (uint32_t index = 0; index < tree->ndecls; index++) {
    const MsDecl *decl = tree->decls[index];
    if (decl->kind == MS_D_FN && decl->id == ref->decl.node) {
      return &decl->u.fn;
    }
    if (decl->kind != MS_D_INTERFACE) {
      continue;
    }
    for (uint32_t at = 0; at < decl->u.iface.methods.len; at++) {
      if (decl->u.iface.methods.ptr[at]->id == ref->decl.node) {
        return &decl->u.iface.methods.ptr[at]->func;
      }
    }
  }
  return NULL;
}

/* Whether the declaration `ref` names declares its result `move`. */
static bool declares_move(const MsCheckProgram *program, const MsRef *ref) {
  const MsFunc *func = find_func(program, ref);
  return func != NULL && func->result_moves;
}

static bool is_value_ref(MsRefKind kind) {
  return kind == MS_REF_FUNCTION || kind == MS_REF_METHOD || kind == MS_REF_NATIVE || kind == MS_REF_OPERATION;
}

static bool owns_memory(Borrows *pass, const MsExpr *expr) {
  const MsTy ty = ms_facts_type(pass->facts, expr->id);
  return ty != MS_TY_NONE && ms_class_of(pass->classes, ty) != MS_CLASS_COPY;
}

static bool origin_of_call(Borrows *pass, const MsExpr *call, Source *out);

/* The local an argument expression borrows from: a local, a field of one, or a borrowing call on one. */
static bool origin_of_arg(Borrows *pass, const MsExpr *arg, Source *out) {
  const MsExpr *at = arg;
  while (at->kind == MS_E_MEMBER) {
    at = at->u.member.left;
  }
  if (at->kind == MS_E_NAME && owns_memory(pass, arg)) {
    out->place = arg;
    out->call = NULL;
    return local_of(pass->facts, at->id, &out->root);
  }
  if (arg->kind == MS_E_UNARY && arg->op == MS_U_TRY) {
    return origin_of_arg(pass, arg->u.bin.left, out);
  }
  return arg->kind == MS_E_CALL && origin_of_call(pass, arg, out);
}

/* The names a written type mentions, appended to `out` (at most `cap`). */
static void type_names(const MsTypeRef *ty, MsName *out, uint32_t *len, uint32_t cap) {
  if (ty == NULL) {
    return;
  }
  if (ty->kind == MS_TYPE_NAMED && *len < cap) {
    out[(*len)++] = ty->name;
  }
  for (uint32_t index = 0; index < ty->args.len; index++) {
    type_names(ty->args.ptr[index], out, len, cap);
  }
  for (uint32_t index = 0; index < ty->params.len; index++) {
    type_names(ty->params.ptr[index]->ty, out, len, cap);
  }
  type_names(ty->result, out, len, cap);
}

enum { NAME_CAP = 24 };

/* The names the declared parameter `position` of `func` mentions; the receiver is position 0 of a method. */
static uint32_t parameter_names(const MsFunc *func, bool method, uint32_t position, MsName *out) {
  uint32_t len = 0;
  if (method && position == 0) {
    const MsMethod *owner = ms_method_of_func(func);
    for (uint32_t index = 0; index < owner->receiver_args.len; index++) {
      type_names(owner->receiver_args.ptr[index], out, &len, NAME_CAP);
    }
  } else if (position - (method ? 1u : 0u) < func->params.len) {
    type_names(func->params.ptr[position - (method ? 1u : 0u)]->ty, out, &len, NAME_CAP);
  }
  return len;
}

static bool name_in(const MsName *names, uint32_t len, MsName name) {
  for (uint32_t index = 0; index < len; index++) {
    if (names[index] == name) {
      return true;
    }
  }
  return false;
}

/* The type variables `func` declares: its own and, for a method, its receiver's. */
static uint32_t declared_variables(const MsFunc *func, bool method, MsName *out) {
  uint32_t len = 0;
  for (uint32_t index = 0; index < func->type_params.len && len < NAME_CAP; index++) {
    out[len++] = func->type_params.ptr[index]->name;
  }
  if (method) {
    const MsMethod *owner = ms_method_of_func(func);
    for (uint32_t index = 0; index < owner->receiver_args.len; index++) {
      type_names(owner->receiver_args.ptr[index], out, &len, NAME_CAP);
    }
  }
  return len;
}

typedef struct Returns {
  const MsExpr *values[16];
  uint32_t len;
} Returns;

static void collect_return(void *ctx, const MsStmt *stmt) {
  Returns *returns = ctx;
  if (stmt->kind == MS_S_RETURN && stmt->u.expr != NULL && returns->len < MS_COUNT_OF(returns->values)) {
    returns->values[returns->len++] = stmt->u.expr;
  }
}

/* The name a source place is rooted at. */
static MsName root_name(const MsExpr *place) {
  while (place->kind == MS_E_MEMBER) {
    place = place->u.member.left;
  }
  return place->kind == MS_E_NAME ? place->u.sym : MS_NAME_EMPTY;
}

/* Whether a function without type variables returns something computed from its parameter number `position`:
 * the walk of its own returned values, read in the module that declares it. */
static bool returns_part_of(Borrows *pass, const MsCall *fact, const MsFunc *func, uint32_t position) {
  if (pass->depth >= 4) {
    return false;
  }
  const bool method = fact->callee.kind == MS_REF_METHOD;
  const MsName wanted = method && position == 0 ? ms_names_intern(pass->program->names, ms_span_of_text("self"))
                                                 : position - (method ? 1u : 0u) < func->params.len
                                                       ? func->params.ptr[position - (method ? 1u : 0u)]->name
                                                       : MS_NAME_EMPTY;
  Returns returns = {.len = 0};
  const MsVisitor visitor = {.ctx = &returns, .stmt = collect_return};
  ms_walk_block(&visitor, func->body);
  MsFacts *saved = pass->facts;
  pass->facts = &pass->program->modules.ptr[fact->callee.decl.module].facts;
  pass->depth++;
  bool lends = false;
  for (uint32_t index = 0; !lends && index < returns.len; index++) {
    Source source = {0};
    lends = origin_of_arg(pass, returns.values[index], &source) && root_name(source.place) == wanted;
  }
  pass->depth--;
  pass->facts = saved;
  return lends;
}

/* Whether the callee's declared result can hold what its argument number `position` carries: a declaration
 * with a body lends only through a type variable its parameter and its result both mention; one the runtime provides
 * lends from any argument. */
static bool lends_from(Borrows *pass, const MsCall *fact, uint32_t position, const MsExpr *arg, const MsExpr *call) {
  const MsRef *callee = &fact->callee;
  const MsFunc *func = find_func(pass->program, callee);
  if ((callee->kind != MS_REF_METHOD && callee->kind != MS_REF_FUNCTION) || func == NULL) {
    return true;
  }
  MsName result[NAME_CAP];
  MsName mine[NAME_CAP];
  uint32_t result_len = 0;
  type_names(func->result, result, &result_len, NAME_CAP);
  MsName variables[NAME_CAP];
  const uint32_t variable_len = declared_variables(func, callee->kind == MS_REF_METHOD, variables);
  (void)arg;
  (void)call;
  if (variable_len == 0) {
    return returns_part_of(pass, fact, func, position);
  }
  const uint32_t mine_len = parameter_names(func, callee->kind == MS_REF_METHOD, position, mine);
  for (uint32_t at = 0; at < mine_len; at++) {
    for (uint32_t index = 0; index < result_len; index++) {
      if (mine[at] == result[index] && name_in(variables, variable_len, mine[at])) {
        return true;
      }
    }
  }
  return false;
}

/* Whether `call` takes the payload out of an optional or result held in a place: its result is the receiver's
 * first type argument. An owned `T?` owns its payload or nothing, so the payload leaves with the value. */
static bool takes_payload(Borrows *pass, const MsExpr *call) {
  const MsExpr *callee = call->u.call.callee;
  if (callee->kind != MS_E_MEMBER) {
    return false;
  }
  const MsExpr *receiver = callee->u.member.left;
  const MsTyTable *types = &pass->program->types;
  const MsTy held = ms_facts_type(pass->facts, receiver->id);
  if (held == MS_TY_NONE || ms_ty_arg_count(types, held) == 0 ||
      (!ms_ty_is(types, held, MS_BUILTIN_Optional) && !ms_ty_is(types, held, MS_BUILTIN_Result))) {
    return false;
  }
  return ms_facts_type(pass->facts, call->id) == ms_ty_args(types, held)[0];
}

/* A call whose result is not declared `move` borrows from its first argument that has an origin. */
static bool origin_of_call(Borrows *pass, const MsExpr *call, Source *out) {
  const MsCall *fact = ms_facts_call(pass->facts, call->id);
  if (fact == NULL || !is_value_ref(fact->callee.kind) || declares_move(pass->program, &fact->callee) ||
      !owns_memory(pass, call)) {
    return false;
  }
  const MsExpr *callee = call->u.call.callee;
  const bool receiver = callee->kind == MS_E_MEMBER && fact->callee.kind != MS_REF_FUNCTION;
  if (receiver && takes_payload(pass, call) && callee->u.member.left->kind != MS_E_CALL) {
    return false;
  }
  bool found = receiver && lends_from(pass, fact, 0, callee->u.member.left, call) && origin_of_arg(pass, callee->u.member.left, out);
  for (uint32_t index = 0; !found && index < call->u.call.args.len; index++) {
    found = lends_from(pass, fact, index + (receiver ? 1u : 0u), call->u.call.args.ptr[index].value, call) &&
            origin_of_arg(pass, call->u.call.args.ptr[index].value, out);
  }
  if (found && out->call == NULL) {
    out->call = call;
  }
  return found;
}

static void note_bind(Borrows *pass, const MsStmt *stmt) {
  const MsPattern *pattern = stmt->u.bind.pattern;
  const MsExpr *value = stmt->u.bind.value;
  Source source = {0};
  uint32_t binding = 0;
  if (pattern == NULL || pattern->kind != MS_P_NAME || value == NULL || !origin_of_arg(pass, value, &source) ||
      value->kind == MS_E_NAME || value->kind == MS_E_MEMBER || !local_of(pass->facts, pattern->id, &binding)) {
    return;
  }
  borrow_list_push(&pass->borrows, (Borrow){.binding = binding, .name = pattern->u.name, .at = pattern->pos, .after = value->end.offset,
                                            .mutable_ = stmt->u.bind.is_mutable, .root = source.root});
}

/* Records the place a store or `var` argument changes. */
static void note_change(Borrows *pass, const MsExpr *place, bool assign) {
  if (place == NULL) {
    return;
  }
  const MsExpr *at = place;
  for (;;) {
    MsExpr *left = NULL;
    MsExpr *index = NULL;
    if (at->kind == MS_E_MEMBER) {
      at = at->u.member.left;
    } else if (ms_expr_index(at, &left, &index)) {
      at = left;
    } else {
      break;
    }
  }
  uint32_t root = 0;
  if (at->kind == MS_E_NAME && local_of(pass->facts, at->id, &root)) {
    change_list_push(&pass->changes, (Change){.root = root, .pos = ms_expr_start(place), .end = place->end.offset, .assign = assign});
  }
}

static void measure_expr(void *ctx, const MsExpr *expr) {
  Borrows *pass = ctx;
  if (expr->end.offset > pass->high) {
    pass->high = expr->end.offset;
  }
}

/* The furthest offset any expression of `body` ends at. */
static uint32_t body_end(Borrows *pass, MsStmts body) {
  pass->high = 0;
  const MsVisitor measure = {.ctx = pass, .expr = measure_expr};
  ms_walk_block(&measure, body);
  return pass->high;
}

static void note_ranges(Borrows *pass, const MsStmt *stmt) {
  if (stmt->kind == MS_S_IF && stmt->u.branch.else_body.len != 0 && stmt->u.branch.body.len != 0) {
    const uint32_t split = stmt->u.branch.else_body.ptr[0]->pos.offset;
    range_list_push(&pass->ranges, (Range){.lo = stmt->pos.offset, .split = split,
                                           .hi = body_end(pass, stmt->u.branch.else_body)});
  } else if (stmt->kind == MS_S_WHILE || stmt->kind == MS_S_FOR) {
    const MsStmts body = stmt->kind == MS_S_WHILE ? stmt->u.loop.body : stmt->u.each.body;
    if (body.len != 0) {
      range_list_push(&pass->ranges, (Range){.lo = stmt->pos.offset, .hi = body_end(pass, body), .loop = true});
    }
  }
}

/* The call an expression keeps once `?` is peeled, or NULL. */
static const MsExpr *kept_call(const MsExpr *expr) {
  while (expr->kind == MS_E_UNARY && expr->op == MS_U_TRY) {
    expr = expr->u.bin.left;
  }
  return expr->kind == MS_E_CALL ? expr : NULL;
}

static void note_keep(Borrows *pass, const MsExpr *kept) {
  const MsExpr *call = kept_call(kept);
  Keep keep = {.kept = call};
  if (call != NULL && origin_of_arg(pass, call, &keep.source)) {
    keep_list_push(&pass->keeps, keep);
  }
}

static bool is_constructor(const Borrows *pass, const MsExpr *call) {
  const MsRef *ref = ms_facts_ref(pass->facts, call->u.call.callee->id);
  return ref != NULL && (ref->kind == MS_REF_TYPE || ref->kind == MS_REF_CASE);
}

/* The arguments of `call` that a new owner keeps: constructor arguments, `move` parameters, a taken receiver. */
static void note_call_keeps(Borrows *pass, const MsExpr *call) {
  const MsCall *fact = ms_facts_call(pass->facts, call->id);
  const MsExpr *callee = call->u.call.callee;
  const bool constructor = is_constructor(pass, call);
  for (uint32_t index = 0; index < call->u.call.args.len; index++) {
    const MsExpr *value = call->u.call.args.ptr[index].value;
    bool moves = constructor;
    for (uint32_t at = 0; fact != NULL && at < fact->arg_count; at++) {
      moves = moves || (fact->args[at].source == MS_ARG_WRITTEN && fact->args[at].node.node == value->id &&
                        (fact->args[at].flags & MS_PARAM_MOVE) != 0);
    }
    if (moves) {
      note_keep(pass, value);
    }
  }
  if (fact != NULL && fact->arg_count != 0 && callee->kind == MS_E_MEMBER && fact->args[0].source == MS_ARG_WRITTEN &&
      fact->args[0].node.node == callee->u.member.left->id &&
      ((fact->args[0].flags & MS_PARAM_MOVE) != 0 || ms_own_consuming_method(pass->program, &fact->callee))) {
    note_keep(pass, callee->u.member.left);
  }
}

static void note_keeps(Borrows *pass, const MsExpr *expr) {
  if (expr->kind == MS_E_CALL) {
    note_call_keeps(pass, expr);
  } else if (expr->kind == MS_E_LIST) {
    for (uint32_t index = 0; index < expr->u.list.len; index++) {
      note_keep(pass, expr->u.list.ptr[index]);
    }
  } else if (expr->kind == MS_E_MAP) {
    for (uint32_t index = 0; index < expr->u.map.len; index++) {
      note_keep(pass, expr->u.map.ptr[index].key);
      note_keep(pass, expr->u.map.ptr[index].value);
    }
  }
}

static void visit_stmt(void *ctx, const MsStmt *stmt) {
  Borrows *pass = ctx;
  note_ranges(pass, stmt);
  if (stmt->kind == MS_S_BIND) {
    note_bind(pass, stmt);
  } else if (stmt->kind == MS_S_ASSIGN) {
    note_change(pass, stmt->u.assign.target, true);
    uint32_t root = 0;
    if (!stmt->u.assign.member_target && local_of(pass->facts, stmt->id, &root)) {
      const uint32_t length = (uint32_t)ms_names_span(pass->program->names, stmt->u.assign.name).len;
      change_list_push(&pass->changes, (Change){.root = root, .pos = stmt->pos, .end = stmt->pos.offset + length,
                                                .assign = true});
    }
  }
}

static void visit_expr(void *ctx, const MsExpr *expr) {
  Borrows *pass = ctx;
  uint32_t binding = 0;
  note_keeps(pass, expr);
  if (expr->kind == MS_E_NAME && local_of(pass->facts, expr->id, &binding)) {
    use_list_push(&pass->uses, (Use){.binding = binding, .offset = expr->pos.offset});
    return;
  }
  const MsCall *fact = expr->kind == MS_E_CALL ? ms_facts_call(pass->facts, expr->id) : NULL;
  for (uint32_t index = 0; fact != NULL && index < fact->arg_count; index++) {
    const MsCallArg *arg = &fact->args[index];
    if (arg->source != MS_ARG_WRITTEN || (arg->flags & MS_PARAM_VAR) == 0) {
      continue;
    }
    const MsExpr *callee = expr->u.call.callee;
    if (callee->kind == MS_E_MEMBER && arg->node.node == callee->u.member.left->id) {
      note_change(pass, callee->u.member.left, false);
      continue;
    }
    for (uint32_t at = 0; at < expr->u.call.args.len; at++) {
      if (expr->u.call.args.ptr[at].value->id == arg->node.node) {
        note_change(pass, expr->u.call.args.ptr[at].value, false);
      }
    }
  }
}

/* Whether a use at `use` can run after a change at `change`: later in the source, unless the two sit in
 * different arms of one branch; or anywhere in a loop that holds the change and not the borrow's binding. */
static bool runs_after(const Borrows *pass, const Borrow *borrow, uint32_t change, uint32_t use) {
  for (size_t index = 0; index < pass->ranges.len; index++) {
    const Range *range = &pass->ranges.ptr[index];
    if (range->loop) {
      if (change >= range->lo && change <= range->hi && use >= range->lo && use <= range->hi &&
          borrow->after < range->lo) {
        return true;
      }
      continue;
    }
    const bool change_then = change >= range->lo && change < range->split;
    const bool change_else = change >= range->split && change <= range->hi;
    const bool use_then = use >= range->lo && use < range->split;
    const bool use_else = use >= range->split && use <= range->hi;
    if ((change_then && use_else) || (change_else && use_then)) {
      return false;
    }
  }
  return use > change;
}

static bool used_after(const Borrows *pass, const Borrow *borrow, uint32_t offset) {
  for (size_t index = 0; index < pass->uses.len; index++) {
    if (pass->uses.ptr[index].binding == borrow->binding && runs_after(pass, borrow, offset, pass->uses.ptr[index].offset)) {
      return true;
    }
  }
  return false;
}

static void append_name(const Borrows *pass, MsStrBuild *text, MsName name) {
  ms_strbuild_append(text, ms_names_span(pass->program->names, name));
}

static MsSpan source_text(const Borrows *pass, const MsExpr *expr) {
  const MsPos start = ms_expr_start(expr);
  return (MsSpan){pass->source.ptr + start.offset, expr->end.offset - start.offset};
}

/* The name a call is written with. */
static MsName call_name(const MsExpr *call) {
  const MsExpr *callee = call->u.call.callee;
  return callee->kind == MS_E_MEMBER ? callee->u.member.name : callee->u.sym;
}

static void report_keep(Borrows *pass, const Keep *keep) {
  const MsExpr *base = keep->source.call;
  const MsCall *fact = ms_facts_call(pass->facts, base->id);
  const bool native = fact != NULL && fact->callee.kind != MS_REF_METHOD && fact->callee.kind != MS_REF_FUNCTION;
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "`");
  append_name(pass, &text, native ? call_name(base) : call_name(keep->kept));
  ms_strbuild_append_text(&text, native ? "` borrows `" : "` returns a reference into `");
  ms_strbuild_append(&text, source_text(pass, keep->source.place));
  ms_strbuild_append_text(&text, "`, which this position would keep; store `.clone()` of it, or use it in place");
  ms_check_report(pass->program, pass->module, keep->kept->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
}

static void report(Borrows *pass, const Borrow *borrow, const Change *change) {
  const MsPos start = change->pos;
  if (change->end <= start.offset || change->end > pass->source.len) {
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, change->assign ? "cannot reassign `" : "cannot change `");
  ms_strbuild_append(&text, (MsSpan){pass->source.ptr + start.offset, change->end - start.offset});
  ms_strbuild_append_text(&text, "` while `");
  append_name(pass, &text, borrow->name);
  ms_strbuild_append_text(&text, borrow->mutable_ ? "` borrows it (mutable borrow, at " : "` borrows it (binding of a part of it, at ");
  ms_strbuild_append_u64(&text, borrow->at.line);
  ms_strbuild_append_text(&text, ":");
  ms_strbuild_append_u64(&text, borrow->at.column);
  ms_strbuild_append_text(&text, "); finish using `");
  append_name(pass, &text, borrow->name);
  ms_strbuild_append_text(&text, "` before this, or give `");
  append_name(pass, &text, borrow->name);
  ms_strbuild_append_text(&text, "` its own value by ending its initializer with `.clone()`");
  ms_check_report(pass->program, pass->module, start, MS_CHECK_TYPE, ms_strbuild_finish(&text));
}

/* Each borrow reports its first later change of the source when the borrower is still used after it. */
static void judge(Borrows *pass) {
  for (size_t at = 0; at < pass->keeps.len; at++) {
    report_keep(pass, &pass->keeps.ptr[at]);
  }
  for (size_t at = 0; at < pass->borrows.len; at++) {
    const Borrow *borrow = &pass->borrows.ptr[at];
    for (size_t index = 0; index < pass->changes.len; index++) {
      const Change *change = &pass->changes.ptr[index];
      const uint32_t offset = change->pos.offset;
      if (change->root == borrow->root && offset >= borrow->after && used_after(pass, borrow, offset)) {
        report(pass, borrow, change);
        break;
      }
    }
  }
  borrow_list_clear(&pass->borrows);
  change_list_clear(&pass->changes);
  use_list_clear(&pass->uses);
  range_list_clear(&pass->ranges);
  keep_list_clear(&pass->keeps);
}

void ms_own_borrows(MsCheckProgram *program) {
  if (program->diagnostics.len != 0) {
    return;
  }
  MsClassifier classes = ms_class_new(program);
  for (uint32_t module = 0; module < program->user_modules; module++) {
    Borrows pass = {.program = program, .classes = &classes, .module = module,
                    .facts = &program->modules.ptr[module].facts, .source = program->modules.ptr[module].source};
    const MsModule *tree = program->modules.ptr[module].tree;
    const MsVisitor visitor = {.ctx = &pass, .stmt = visit_stmt, .expr = visit_expr};
    for (uint32_t index = 0; index < tree->ndecls; index++) {
      ms_walk_decl(&visitor, tree->decls[index]);
      judge(&pass);
    }
    borrow_list_free(&pass.borrows);
    change_list_free(&pass.changes);
    use_list_free(&pass.uses);
    range_list_free(&pass.ranges);
    keep_list_free(&pass.keeps);
  }
  ms_class_free(&classes);
}
