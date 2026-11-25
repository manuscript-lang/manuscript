/* compiler/own/result_borrows.c: see borrows.h. */
#include "compiler/own/result_borrows.h"

#include "base/alloc.h"
#include "compiler/check/properties.h"
#include "compiler/natives/native_sigs.h"
#include "compiler/own/class.h"
#include "compiler/syntax/walk.h"

typedef struct Returns {
  const MsExpr *values[16];
  uint32_t len;
  uint32_t lambdas; /* open closures: what they return is theirs */
  bool overflow;
} Returns;

static void collect_return(void *ctx, const MsStmt *stmt) {
  Returns *returns = ctx;
  if (stmt->kind != MS_S_RETURN || stmt->u.expr == NULL || returns->lambdas != 0) {
    return;
  }
  if (returns->len == MS_COUNT_OF(returns->values)) {
    returns->overflow = true;
    return;
  }
  returns->values[returns->len++] = stmt->u.expr;
}

static void enter_lambda(void *ctx, const MsExpr *expr) {
  Returns *returns = ctx;
  returns->lambdas += expr->kind == MS_E_LAMBDA ? 1u : 0u;
}

static void leave_lambda(void *ctx, const MsExpr *expr) {
  Returns *returns = ctx;
  returns->lambdas -= expr->kind == MS_E_LAMBDA ? 1u : 0u;
}

/* What a returned expression carries: the positions it borrows, or that it is something the callable owns. */
typedef struct Reach {
  uint32_t mask;
  bool owned;
} Reach;

/* A local that views another expression: an arm or `if` binding of a scrutinee, or `x := place`. */
typedef struct View {
  uint32_t local;
  const MsExpr *source;
} View;

typedef struct Pass {
  View views[48];
  uint32_t view_count;
  uint32_t depth;
  MsCheckProgram *program;
  MsClassifier *classes;
  const MsFacts *facts;
  MsNode self_node;
  uint32_t self_module;
  bool method;
  MsName self_name;
  const MsTy *written; /* by node of this module: the type a written type resolved to (MS_TY_NONE, which is 0, if none) */
} Pass;

static Reach join(Reach left, Reach right) {
  return (Reach){.mask = left.mask | right.mask, .owned = left.owned || right.owned};
}

static const Reach NEUTRAL = {0, false};
static const Reach OWNED = {0, true};

static Reach classify(Pass *pass, const MsExpr *expr);

/* The position of a name that is the receiver or a parameter, or -1. */
static int position_of(const Pass *pass, const MsExpr *name) {
  const MsRef *ref = ms_facts_ref(pass->facts, name->id);
  if (ref == NULL || ref->kind != MS_REF_PARAM) {
    return -1;
  }
  if (pass->method && name->u.sym == pass->self_name) {
    return 0;
  }
  const uint32_t position = ref->local + (pass->method ? 1u : 0u);
  return position < 31 ? (int)position : -1;
}

static void add_view(Pass *pass, uint32_t local, const MsExpr *source) {
  if (pass->view_count < MS_COUNT_OF(pass->views)) {
    pass->views[pass->view_count++] = (View){local, source};
  }
}

static void view_stmt(void *ctx, const MsStmt *stmt) {
  Pass *pass = ctx;
  if (stmt->kind == MS_S_IF && stmt->u.branch.binding != NULL && stmt->u.branch.binding->kind == MS_P_NAME) {
    const MsRef *ref = ms_facts_ref(pass->facts, stmt->u.branch.binding->id);
    if (ref != NULL && ref->kind == MS_REF_LOCAL) {
      add_view(pass, ref->local, stmt->u.branch.cond);
    }
  } else if (stmt->kind == MS_S_FOR && (stmt->u.each.iter->kind == MS_E_NAME || stmt->u.each.iter->kind == MS_E_MEMBER)) {
    /* The loop variable of a walk over a place views one element of it. */
    const MsRef *ref = ms_facts_ref(pass->facts, stmt->id);
    if (ref != NULL && ref->kind == MS_REF_LOCAL) {
      add_view(pass, ref->local, stmt->u.each.iter);
    }
  } else if (stmt->kind == MS_S_BIND && !stmt->u.bind.is_mutable && stmt->u.bind.pattern->kind == MS_P_NAME &&
             (stmt->u.bind.value->kind == MS_E_NAME || stmt->u.bind.value->kind == MS_E_MEMBER) &&
             /* a field read the callable moves out (`old := self.f; self.f = g`) is owned by the name, not viewed */
             !(stmt->u.bind.value->kind == MS_E_MEMBER && ms_facts_use(pass->facts, stmt->u.bind.value->id) == MS_USE_MOVE)) {
    const MsRef *ref = ms_facts_ref(pass->facts, stmt->u.bind.pattern->id);
    if (ref != NULL && ref->kind == MS_REF_LOCAL) {
      add_view(pass, ref->local, stmt->u.bind.value);
    }
  }
}

static void view_expr(void *ctx, const MsExpr *expr) {
  Pass *pass = ctx;
  for (uint32_t arm = 0; expr->kind == MS_E_MATCH && arm < expr->u.match.arms.len; arm++) {
    const MsArm *one = expr->u.match.arms.ptr[arm];
    const MsRef *bound = ms_facts_ref(pass->facts, one->id);
    for (uint32_t at = 0; bound != NULL && bound->kind == MS_REF_CASE && at < one->bindings.len; at++) {
      add_view(pass, bound->local + at, expr->u.match.scrutinee);
    }
  }
}

static Reach classify_place(Pass *pass, const MsExpr *expr) {
  const MsExpr *root = expr;
  while (root->kind == MS_E_MEMBER) {
    root = root->u.member.left;
  }
  if (root->kind != MS_E_NAME) {
    return OWNED;
  }
  const MsRef *ref = ms_facts_ref(pass->facts, root->id);
  if (ref != NULL && ref->kind != MS_REF_PARAM && ref->kind != MS_REF_LOCAL) {
    return NEUTRAL; /* a constant or a case such as `none` owns nothing */
  }
  if (ref != NULL && ref->kind == MS_REF_LOCAL) {
    for (uint32_t index = 0; index < pass->view_count; index++) {
      if (pass->views[index].local == ref->local && pass->depth < 8) {
        pass->depth++;
        const Reach borrow = classify(pass, pass->views[index].source);
        pass->depth--;
        return borrow;
      }
    }
    return OWNED;
  }
  const int position = position_of(pass, root);
  return position < 0 ? OWNED : (Reach){.mask = UINT32_C(1) << position, .owned = false};
}

static Reach classify_call(Pass *pass, const MsExpr *call) {
  const MsCall *fact = ms_facts_call(pass->facts, call->id);
  if (fact == NULL) {
    return OWNED;
  }
  const MsRefKind kind = fact->callee.kind;
  if (kind == MS_REF_CASE) {
    const MsTyTable *types = &pass->program->types;
    const MsTy made = ms_facts_type(pass->facts, call->id);
    if (made == MS_TY_NONE || (!ms_ty_is(types, made, MS_BUILTIN_Optional) && !ms_ty_is(types, made, MS_BUILTIN_Result))) {
      return OWNED; /* a case of a user enum stores its payload: new storage */
    }
  }
  const MsFunc *func = kind == MS_REF_CASE ? NULL : ms_own_find_func(pass->program, &fact->callee);
  if (kind != MS_REF_CASE && kind != MS_REF_FUNCTION && kind != MS_REF_METHOD && kind != MS_REF_NATIVE) {
    return OWNED;
  }
  if (func != NULL && func->result_moves) {
    return OWNED;
  }
  const MsExpr *callee = call->u.call.callee;
  const bool receiver = callee->kind == MS_E_MEMBER && kind != MS_REF_FUNCTION && kind != MS_REF_CASE;
  Reach out = NEUTRAL;
  uint32_t position = 0;
  if (receiver) {
    if (kind == MS_REF_CASE || ms_own_call_borrows(pass->program, fact, 0)) {
      out = join(out, classify(pass, callee->u.member.left));
    }
    position = 1;
  }
  for (uint32_t index = 0; index < call->u.call.args.len; index++, position++) {
    if (kind == MS_REF_CASE || ms_own_call_borrows(pass->program, fact, position)) {
      out = join(out, classify(pass, call->u.call.args.ptr[index].value));
    }
  }
  return out;
}

static Reach classify(Pass *pass, const MsExpr *expr) {
  if (!ms_class_owns_memory(pass->facts, pass->classes, expr)) {
    return NEUTRAL;
  }
  if (expr->kind == MS_E_NAME || expr->kind == MS_E_MEMBER) {
    return classify_place(pass, expr);
  }
  if (expr->kind == MS_E_UNARY && expr->op == MS_U_TRY) {
    return classify(pass, expr->u.bin.left);
  }
  if (expr->kind == MS_E_BINARY && expr->op == MS_B_OR &&
      ms_ty_is(&pass->program->types, ms_facts_type(pass->facts, expr->u.bin.left->id), MS_BUILTIN_Optional)) {
    return classify(pass, expr->u.bin.left); /* `x or d` hands out the payload of `x`, which stays where `x` keeps it */
  }
  MsExpr *container = NULL;
  MsExpr *position = NULL;
  if (ms_expr_index(expr, &container, &position) &&
      ms_ty_is(&pass->program->types, ms_facts_type(pass->facts, container->id), MS_BUILTIN_List)) {
    return classify(pass, container); /* an element of a list is a part of it */
  }
  return expr->kind == MS_E_CALL ? classify_call(pass, expr) : OWNED;
}

/* What a callable's returns carry: the joined reach, and the first pair of returns that hand out the same case of the
 * result as a part of an argument and as a new value. A `Result` or an Optional keeps its cases apart, so
 * `ok(part)` beside `error(new)` is not a mix. */
typedef struct Reached {
  Reach all;
  const MsExpr *borrowed;
  const MsExpr *fresh;
  bool known;
} Reached;

enum { CASE_OK = 1, CASE_ERROR = 2, CASE_ALL = 3 };

static uint32_t case_of(const Pass *pass, const MsExpr *value) {
  const MsExpr *callee = value->kind == MS_E_CALL ? value->u.call.callee : NULL;
  if (callee == NULL || callee->kind != MS_E_NAME) {
    return CASE_ALL;
  }
  const MsSpan name = ms_names_span(pass->program->names, callee->u.sym);
  return ms_span_is_text(name, "ok") ? CASE_OK : ms_span_is_text(name, "error") ? CASE_ERROR : CASE_ALL;
}

/* The bit of every `move` parameter: what it holds is the callable's own, not a borrow. */
static uint32_t moved_positions(const Pass *pass, MsParams params) {
  uint32_t mask = 0;
  for (uint32_t index = 0; index < params.len; index++) {
    const uint32_t position = index + (pass->method ? 1u : 0u);
    if (params.ptr[index]->moving && position < 31) {
      mask |= UINT32_C(1) << position;
    }
  }
  return mask;
}

static Reached reached_by(Pass *pass, MsParams params, MsStmts body, MsTy result) {
  pass->view_count = 0;
  pass->depth = 0;
  ms_walk_callable(&(MsVisitor){.ctx = pass, .stmt = view_stmt, .expr = view_expr}, params, body);
  Returns returns = {.len = 0};
  const MsVisitor visitor = {.ctx = &returns, .stmt = collect_return, .expr = enter_lambda, .leave_expr = leave_lambda};
  ms_walk_block(&visitor, body);
  Reached out = {.all = NEUTRAL, .known = !returns.overflow && returns.len != 0};
  Reach reaches[16];
  for (uint32_t index = 0; out.known && index < returns.len; index++) {
    reaches[index] = classify(pass, returns.values[index]);
    out.all = join(out.all, reaches[index]);
  }
  const uint32_t owned_params = moved_positions(pass, params);
  /* An interface result is a view every path builds; a value converted on the way out (a type as its interface, a value as
   * its Optional) is a new value, not a reference. */
  const bool view_result = result != MS_TY_NONE && ms_ty_kind(&pass->program->types, result) == MS_TY_CONTRACT;
  for (uint32_t fresh = 0; out.known && !view_result && fresh < returns.len && out.fresh == NULL; fresh++) {
    if (!reaches[fresh].owned || reaches[fresh].mask != 0) {
      continue;
    }
    for (uint32_t borrowed = 0; borrowed < returns.len; borrowed++) {
      const MsTy shown = ms_facts_type(pass->facts, returns.values[borrowed]->id);
      if (result != MS_TY_NONE && shown != result) {
        continue;
      }
      if ((reaches[borrowed].mask & ~owned_params) != 0 && (case_of(pass, returns.values[fresh]) & case_of(pass, returns.values[borrowed])) != 0) {
        out.fresh = returns.values[fresh];
        out.borrowed = returns.values[borrowed];
        break;
      }
    }
  }
  return out;
}

static uint32_t mask_of(Pass *pass, MsParams params, MsStmts body) {
  const Reached reached = reached_by(pass, params, body, MS_TY_NONE);
  if (!reached.known) {
    return 0;
  }
  /* A `move` parameter is the callable's own: what it hands on is the result's, not a borrow of the caller's argument. */
  const uint32_t borrowed = reached.all.mask & ~moved_positions(pass, params);
  return borrowed | (reached.all.owned || reached.all.mask == 0 ? 0 : MS_RESULT_BORROWED);
}

static bool named_as(const Pass *pass, const MsTypeRef *t, const char *text) {
  return t->kind == MS_TYPE_NAMED && ms_span_is_text(ms_names_span(pass->program->names, t->name), text);
}

/* Whether a written type has a `&` anywhere inside it. */
static bool has_ref(const MsTypeRef *t) {
  if (t == NULL) {
    return false;
  }
  if (t->is_ref) {
    return true;
  }
  for (uint32_t index = 0; t->kind == MS_TYPE_NAMED && index < t->args.len; index++) {
    if (has_ref(t->args.ptr[index])) {
      return true;
    }
  }
  return false;
}

/* Whether the result itself is a reference: `&T`, or the payload of `&T?` and `&T!`. */
static bool ref_result(const Pass *pass, const MsTypeRef *t) {
  if (t == NULL) {
    return false;
  }
  if (t->is_ref) {
    return true;
  }
  return t->args.len >= 1 && (named_as(pass, t, "Optional") || named_as(pass, t, "Result")) && ref_result(pass, t->args.ptr[0]);
}

/* A signature that writes `hold` or `&` states the mask itself: the positions it holds, and the borrowed-result bit when
 * the result is a reference. Returns false for a signature that writes neither, which still gets the inferred mask. */
static bool declared_mask(const Pass *pass, bool receiver_holds, MsParams params, const MsTypeRef *result, uint32_t *out) {
  uint32_t mask = receiver_holds && pass->method ? 1u : 0u;
  bool declared = receiver_holds;
  for (uint32_t index = 0; index < params.len; index++) {
    const uint32_t position = index + (pass->method ? 1u : 0u);
    if (params.ptr[index]->holding && position < 31) {
      mask |= UINT32_C(1) << position;
      declared = true;
    }
  }
  if (has_ref(result)) {
    declared = true;
    mask |= ref_result(pass, result) ? MS_RESULT_BORROWED : 0;
  }
  *out = mask;
  return declared;
}

/* A signature's `hold` and `&` against its body: the body may return a part of a held argument only, and a `&` result
 * must be a part of one. */
static void report_declared(Pass *pass, uint32_t module, MsPos pos, bool receiver_holds, MsParams params, MsStmts body,
                            const MsTypeRef *result) {
  uint32_t declared = 0;
  if (!declared_mask(pass, receiver_holds, params, result, &declared)) {
    return;
  }
  const uint32_t holds = declared & ~MS_RESULT_BORROWED;
  if ((declared & MS_RESULT_BORROWED) != 0 && holds == 0) {
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_append_text(&text, "a `&` result points into an argument; mark that argument `hold`, or return an owned value");
    ms_check_report(pass->program, module, pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
    return;
  }
  const Reached reached = reached_by(pass, params, body, MS_TY_NONE);
  if (!reached.known) {
    return;
  }
  const uint32_t moved = moved_positions(pass, params);
  const uint32_t used = reached.all.mask & ~moved & ~MS_RESULT_BORROWED;
  for (uint32_t position = 0; position < 31; position++) {
    const uint32_t bit = UINT32_C(1) << position;
    if ((used & bit) == 0 || (holds & bit) != 0) {
      continue;
    }
    const bool is_self = pass->method && position == 0;
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_append_text(&text, "the result is a part of `");
    ms_strbuild_append_text(&text, is_self ? "self" : "");
    if (!is_self) {
      const uint32_t index = position - (pass->method ? 1u : 0u);
      ms_strbuild_append(&text, ms_names_span(pass->program->names, params.ptr[index]->name));
    }
    ms_strbuild_append_text(&text, "`, so the signature must say `hold` for it; write `hold` before it, or return a `.clone()`");
    ms_check_report(pass->program, module, pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
    return;
  }
  if ((declared & MS_RESULT_BORROWED) != 0 && used == 0 && !reached.all.owned) {
    return;
  }
  if ((declared & MS_RESULT_BORROWED) != 0 && (used & holds) == 0) {
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_append_text(&text, "a `&` result must be a part of a `hold` argument, but this body returns a new value; "
                                   "remove the `&` or return a part of the held argument");
    ms_check_report(pass->program, module, pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  }
}

/* A callable that returns a part of its arguments on one path and a new value on another cannot say who owns its result. */
static MsTy written_type(const Pass *pass, const MsTypeRef *ref) {
  return ref != NULL && ref->id < pass->facts->node_count ? pass->written[ref->id] : MS_TY_NONE;
}

/* The resolved types of a module's written types, by node: one pass over the records, not one scan per function. */
static MsTy *written_types(const MsCheckProgram *program, uint32_t module, uint32_t node_count) {
  MsTy *written = ms_alloc_zeroed(((size_t)node_count + 1) * sizeof *written);
  for (size_t index = 0; index < program->type_refs.len; index++) {
    const MsTypeRefRecord *record = &program->type_refs.ptr[index];
    if (record->module == module && record->node < node_count) {
      written[record->node] = record->ty;
    }
  }
  return written;
}

static void report_mixed(Pass *pass, uint32_t module, MsNode node, MsParams params, MsStmts body, const MsTypeRef *result_ref) {
  const MsTy result = written_type(pass, result_ref);
  const Reached reached = reached_by(pass, params, body, result);
  if (!reached.known || reached.borrowed == NULL || reached.fresh == NULL) {
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "this function returns a reference into its arguments at ");
  ms_strbuild_append_u64(&text, reached.borrowed->pos.line);
  ms_strbuild_append_text(&text, ":");
  ms_strbuild_append_u64(&text, reached.borrowed->pos.column);
  ms_strbuild_append_text(&text, " but a new value here; return `.clone()` of the part there, or build a new value on every path");
  ms_check_report(pass->program, module, reached.fresh->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  if (node < pass->facts->node_count) {
    pass->facts->result_borrows[node] = 0; /* callers see an owner, so one mistake is reported once */
  }
}

void ms_own_mixed_returns(MsCheckProgram *program) {
  MsClassifier classes = ms_class_new(program);
  for (uint32_t module = 0; module < program->user_modules && module < program->modules.len; module++) {
    MsFacts *facts = &program->modules.ptr[module].facts;
    const MsModule *tree = program->modules.ptr[module].tree;
    MsTy *written = written_types(program, module, facts->node_count);
    Pass pass = {.program = program, .classes = &classes, .facts = facts, .self_module = module,
                 .self_name = ms_names_intern(program->names, ms_span_of_text("self")), .written = written};
    for (uint32_t index = 0; facts->result_borrows != NULL && index < tree->ndecls; index++) {
      const MsDecl *decl = tree->decls[index];
      if (decl->kind == MS_D_FN) {
        pass.method = false;
        pass.self_node = decl->id;
        report_mixed(&pass, module, decl->id, decl->u.fn.params, decl->u.fn.body, decl->u.fn.result);
        report_declared(&pass, module, decl->pos, false, decl->u.fn.params, decl->u.fn.body, decl->u.fn.result);
      }
      for (uint32_t at = 0; decl->kind == MS_D_IMPL && at < decl->u.impl.methods.len; at++) {
        const MsMethod *method = decl->u.impl.methods.ptr[at];
        pass.method = true;
        pass.self_node = method->id;
        report_mixed(&pass, module, method->id, method->func.params, method->func.body, method->func.result);
        report_declared(&pass, module, method->pos, method->holding, method->func.params, method->func.body,
                        method->func.result);
      }
    }
    ms_free(written);
  }
}

static bool store(MsFacts *facts, MsNode node, uint32_t mask) {
  const bool changed = node < facts->node_count && facts->result_borrows[node] != mask;
  if (node < facts->node_count) {
    facts->result_borrows[node] = mask;
  }
  return changed;
}

static bool round_of(MsCheckProgram *program, MsClassifier *classes) {
  bool changed = false;
  for (uint32_t module = 0; module < program->modules.len; module++) {
    MsFacts *facts = &program->modules.ptr[module].facts;
    const MsModule *tree = program->modules.ptr[module].tree;
    Pass pass = {.program = program, .classes = classes, .facts = facts, .self_module = module,
                 .self_name = ms_names_intern(program->names, ms_span_of_text("self"))};
    for (uint32_t index = 0; facts->result_borrows != NULL && index < tree->ndecls; index++) {
      const MsDecl *decl = tree->decls[index];
      if (decl->kind == MS_D_FN) {
        pass.method = false;
        pass.self_node = decl->id;
        uint32_t declared = 0;
        changed |= store(facts, decl->id,
                         declared_mask(&pass, false, decl->u.fn.params, decl->u.fn.result, &declared)
                             ? declared
                             : mask_of(&pass, decl->u.fn.params, decl->u.fn.body));
      }
      for (uint32_t at = 0; decl->kind == MS_D_IMPL && at < decl->u.impl.methods.len; at++) {
        const MsMethod *method = decl->u.impl.methods.ptr[at];
        pass.method = true;
        pass.self_node = method->id;
        uint32_t declared = 0;
        changed |= store(facts, method->id,
                         declared_mask(&pass, method->holding, method->func.params, method->func.result, &declared)
                             ? declared
                             : mask_of(&pass, method->func.params, method->func.body));
      }
    }
  }
  return changed;
}

void ms_own_result_borrows(MsCheckProgram *program) {
  MsClassifier classes = ms_class_new(program);
  for (int round = 0; round < 8 && round_of(program, &classes); round++) {
  }
}

uint32_t ms_own_result_borrow_mask(const MsCheckProgram *program, uint32_t module, MsNode node) {
  if (module >= program->modules.len) {
    return 0;
  }
  const MsFacts *facts = &program->modules.ptr[module].facts;
  return facts->result_borrows != NULL && node < facts->node_count ? facts->result_borrows[node] : 0;
}

/* Whether an argument is flat data: a scalar, a String or Bytes holds no part another value could share. */
static bool flat_argument(const MsCheckProgram *program, MsTy ty) {
  const MsTyTable *types = &program->types;
  return ty != MS_TY_NONE && (ms_ty_is(types, ty, MS_BUILTIN_String) || ms_ty_is(types, ty, MS_BUILTIN_Bytes) ||
                              ms_ty_is(types, ty, MS_BUILTIN_Int) || ms_ty_is(types, ty, MS_BUILTIN_Bool) ||
                              ms_ty_is(types, ty, MS_BUILTIN_Float));
}

/* A free function the runtime provides (`msstd_fs_create_directory`): its result is fresh when its signature
 * does not say `@borrows` and every argument is flat. */
static bool external_function_is_fresh(const MsCheckProgram *program, const MsCall *call, const MsFunc *func) {
  const MsNativeSig *sig = ms_native_sig_find(ms_names_span(program->names, func->name));
  /* A result that holds only plain data (`Void!`, `Int`) cannot hold a part of an argument. */
  const MsTyTable *types = &program->types;
  MsTy result = ms_ty_result(types, call->callee_ty);
  if (result != MS_TY_NONE && ms_ty_is(types, result, MS_BUILTIN_Result) && ms_ty_arg_count(types, result) == 2) {
    result = ms_ty_args(types, result)[0];
  }
  if (sig != NULL && !sig->borrows && result != MS_TY_NONE &&
      (ms_ty_is(types, result, MS_BUILTIN_Void) || ms_ty_is(types, result, MS_BUILTIN_Int) ||
       ms_ty_is(types, result, MS_BUILTIN_Bool) || ms_ty_is(types, result, MS_BUILTIN_Float))) {
    return true;
  }
  for (uint32_t index = 0; sig != NULL && index < call->arg_count; index++) {
    const MsCallArg *arg = &call->args[index];
    const bool known = arg->node.node != 0 && arg->node.module < program->modules.len;
    if (!known || !flat_argument(program, ms_facts_type(&program->modules.ptr[arg->node.module].facts, arg->node.node))) {
      return false;
    }
  }
  return sig != NULL && !sig->borrows;
}

/* The natives whose result points into their receiver, the one place a method name decides ownership (the rule the
 * Rust checker's `native_borrow` states): `get` on a Map, the payload `get()` of an Optional or Result, the
 * views of text and bytes, the keys and values of a Map, and a slice of a list of plain data. Every other native
 * answers a value of its own. */
static bool native_result_borrows(const MsCheckProgram *program, MsTy receiver, MsSpan operation, uint32_t args) {
  const MsTyTable *types = &program->types;
  const bool text = ms_ty_is(types, receiver, MS_BUILTIN_String);
  const bool bytes = ms_ty_is(types, receiver, MS_BUILTIN_Bytes);
  const bool list = ms_ty_is(types, receiver, MS_BUILTIN_List);
  const bool map = ms_ty_is(types, receiver, MS_BUILTIN_Map);
  const bool payload = ms_ty_is(types, receiver, MS_BUILTIN_Optional) || ms_ty_is(types, receiver, MS_BUILTIN_Result);
  if (ms_span_is_text(operation, "get")) {
    return (args == 1 && map) || (args == 0 && payload);
  }
  if (ms_span_is_text(operation, "view")) {
    return args == 2 && (text || bytes);
  }
  if (ms_span_is_text(operation, "view_bytes")) {
    return args == 0 && text;
  }
  if (ms_span_is_text(operation, "split")) {
    return (args == 1 || args == 2) && text;
  }
  if (ms_span_is_text(operation, "lines") || ms_span_is_text(operation, "chars")) {
    return args == 0 && text;
  }
  if (ms_span_is_text(operation, "keys") || ms_span_is_text(operation, "values")) {
    return args == 0 && map;
  }
  if (ms_span_is_text(operation, "slice") && args == 2 && list && ms_ty_arg_count(types, receiver) == 1) {
    const MsTy elem = ms_ty_args(types, receiver)[0]; /* only elements that own nothing */
    return ms_ty_is(types, elem, MS_BUILTIN_Int) || ms_ty_is(types, elem, MS_BUILTIN_Float) || ms_ty_is(types, elem, MS_BUILTIN_Bool);
  }
  return false;
}

/* Whether the runtime native behind a bodiless declaration says its result is a fresh owner (no `@borrows`): a copy,
 * not a view into an argument. False when the table does not know the native. */
static bool native_result_is_fresh(const MsCheckProgram *program, const MsCall *call) {
  MsTy receiver = MS_TY_NONE;
  MsName name = 0;
  const MsFunc *func = ms_own_find_func(program, &call->callee);
  const MsMethodEntry *method = ms_check_method_at(program, call->callee.decl.module, call->callee.decl.node);
  if (method != NULL) {
    receiver = method->receiver;
    name = method->name;
  }
  if (func != NULL && receiver == MS_TY_NONE && func->external) {
    return external_function_is_fresh(program, call, func);
  }
  if (func != NULL && receiver == MS_TY_NONE) { /* an operation of an interface: the receiver is the first argument */
    const MsCallArg *first = call->arg_count > 0 ? &call->args[0] : NULL;
    if (first != NULL && first->node.node != 0 && first->node.module < program->modules.len) {
      receiver = ms_facts_type(&program->modules.ptr[first->node.module].facts, first->node.node);
      name = func->name;
    }
  }
  if (receiver == MS_TY_NONE) {
    return false;
  }
  /* The declaration's receiver names type variables (`List[T]`); the call's own receiver says the element. */
  const MsCallArg *first = call->arg_count > 0 ? &call->args[0] : NULL;
  if (first != NULL && first->source == MS_ARG_WRITTEN && first->node.node != 0 && first->node.module < program->modules.len) {
    const MsTy actual = ms_facts_type(&program->modules.ptr[first->node.module].facts, first->node.node);
    receiver = actual != MS_TY_NONE ? actual : receiver;
  }
  const char *type_name = ms_builtin_name(ms_ty_builtin(&program->types, receiver));
  const MsSpan operation = ms_names_span(program->names, name);
  if (native_result_borrows(program, receiver, operation, call->arg_count > 0 ? call->arg_count - 1 : 0)) {
    return false;
  }
  const MsNativeSig *sig = ms_native_sig_find_method(ms_span_of_text(type_name), operation);
  return sig == NULL || !sig->borrows; /* a runtime native that says `@borrows` is a view too */
}

bool ms_own_call_borrows(const MsCheckProgram *program, const MsCall *call, uint32_t position) {
  const MsRefKind kind = call->callee.kind;
  if (kind == MS_REF_OPERATION) {
    return false; /* an interface operation answers the clone its implementation writes */
  }
  if (kind != MS_REF_FUNCTION && kind != MS_REF_METHOD && kind != MS_REF_NATIVE) {
    return kind == MS_REF_CASE;
  }
  const MsFunc *declared = ms_own_find_func(program, &call->callee);
  if (declared != NULL && declared->result_moves) {
    return false; /* the declaration says the result is new memory, whatever the arguments */
  }
  if (kind == MS_REF_NATIVE) {
    return !native_result_is_fresh(program, call);
  }
  const MsFunc *func = declared;
  if (func == NULL || func->bodiless || func->external) {
    /* the runtime provides it: its result may be any part of its arguments unless the table says it builds a new one */
    return !native_result_is_fresh(program, call);
  }
  return position < 31 && (ms_own_result_borrow_mask(program, call->callee.decl.module, call->callee.decl.node) >> position & 1u) != 0;
}

bool ms_own_result_is_borrowed(const MsCheckProgram *program, uint32_t module, MsNode node) {
  return (ms_own_result_borrow_mask(program, module, node) & MS_RESULT_BORROWED) != 0;
}

const MsFunc *ms_own_find_func(const MsCheckProgram *program, const MsRef *ref) {
  const MsMethodEntry *entry = ms_check_method_at(program, ref->decl.module, ref->decl.node);
  if (entry != NULL) {
    return &entry->source->func;
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

MsNativeGet ms_own_native_get(const MsCheckProgram *program, const MsFacts *facts, const MsExpr *call) {
  const MsExpr *callee = call->kind == MS_E_CALL ? call->u.call.callee : NULL;
  const MsCall *fact = callee != NULL ? ms_facts_call(facts, call->id) : NULL;
  if (fact == NULL || callee->kind != MS_E_MEMBER || !ms_span_is_text(ms_names_span(program->names, callee->u.member.name), "get")) {
    return MS_NATIVE_GET_NONE;
  }
  const MsTyTable *types = &program->types;
  const MsTy held = ms_facts_type(facts, callee->u.member.left->id);
  if (held == MS_TY_NONE) {
    return MS_NATIVE_GET_NONE;
  }
  if (call->u.call.args.len == 1) {
    return ms_ty_is(types, held, MS_BUILTIN_Map) ? MS_NATIVE_GET_MAP
           : ms_ty_is(types, held, MS_BUILTIN_List) ? MS_NATIVE_GET_LIST
                                                    : MS_NATIVE_GET_NONE;
  }
  return call->u.call.args.len == 0 && (ms_ty_is(types, held, MS_BUILTIN_Optional) || ms_ty_is(types, held, MS_BUILTIN_Result))
             ? MS_NATIVE_GET_PAYLOAD
             : MS_NATIVE_GET_NONE;
}
