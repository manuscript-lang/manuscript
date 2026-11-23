/* compiler/own/result_borrows.c: see borrows.h. */
#include "compiler/own/result_borrows.h"

#include "compiler/check/properties.h"
#include "compiler/natives/native_sigs.h"
#include "compiler/own/class.h"
#include "compiler/syntax/walk.h"

typedef struct Returns {
  const MsExpr *values[16];
  uint32_t len;
  bool overflow;
} Returns;

static void collect_return(void *ctx, const MsStmt *stmt) {
  Returns *returns = ctx;
  if (stmt->kind != MS_S_RETURN || stmt->u.expr == NULL) {
    return;
  }
  if (returns->len == MS_COUNT_OF(returns->values)) {
    returns->overflow = true;
    return;
  }
  returns->values[returns->len++] = stmt->u.expr;
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
} Pass;

static Reach join(Reach left, Reach right) {
  return (Reach){.mask = left.mask | right.mask, .owned = left.owned || right.owned};
}

static bool owns_memory(const Pass *pass, const MsExpr *expr) {
  const MsTy ty = ms_facts_type(pass->facts, expr->id);
  return ty != MS_TY_NONE && ms_class_of(pass->classes, ty) != MS_CLASS_COPY;
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
             (stmt->u.bind.value->kind == MS_E_NAME || stmt->u.bind.value->kind == MS_E_MEMBER)) {
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
  if (!owns_memory(pass, expr)) {
    return NEUTRAL;
  }
  if (expr->kind == MS_E_NAME || expr->kind == MS_E_MEMBER) {
    return classify_place(pass, expr);
  }
  if (expr->kind == MS_E_UNARY && expr->op == MS_U_TRY) {
    return classify(pass, expr->u.bin.left);
  }
  MsExpr *container = NULL;
  MsExpr *position = NULL;
  if (ms_expr_index(expr, &container, &position) &&
      ms_ty_is(&pass->program->types, ms_facts_type(pass->facts, container->id), MS_BUILTIN_List)) {
    return classify(pass, container); /* an element of a list is a part of it */
  }
  return expr->kind == MS_E_CALL ? classify_call(pass, expr) : OWNED;
}

static uint32_t mask_of(Pass *pass, MsParams params, MsStmts body) {
  pass->view_count = 0;
  pass->depth = 0;
  ms_walk_callable(&(MsVisitor){.ctx = pass, .stmt = view_stmt, .expr = view_expr}, params, body);
  Returns returns = {.len = 0};
  const MsVisitor visitor = {.ctx = &returns, .stmt = collect_return};
  ms_walk_block(&visitor, body);
  if (returns.overflow || returns.len == 0) {
    return 0;
  }
  Reach all = NEUTRAL;
  for (uint32_t index = 0; index < returns.len; index++) {
    all = join(all, classify(pass, returns.values[index]));
  }
  return all.mask | (all.owned || all.mask == 0 ? 0 : MS_RESULT_BORROWED);
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
        changed |= store(facts, decl->id, mask_of(&pass, decl->u.fn.params, decl->u.fn.body));
      }
      for (uint32_t at = 0; decl->kind == MS_D_IMPL && at < decl->u.impl.methods.len; at++) {
        const MsMethod *method = decl->u.impl.methods.ptr[at];
        pass.method = true;
        pass.self_node = method->id;
        changed |= store(facts, method->id, mask_of(&pass, method->func.params, method->func.body));
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
 * Rust checker's `native_borrow` states): `get` on a List or Map, the payload `get()` of an Optional or Result, the
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
    return (args == 1 && (list || map)) || (args == 0 && payload);
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
  for (size_t index = 0; index < program->methods.len; index++) {
    const MsMethodEntry *at = &program->methods.ptr[index];
    if (at->module == call->callee.decl.module && at->source->id == call->callee.decl.node) {
      receiver = at->receiver;
      name = at->name;
    }
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
  if (kind == MS_REF_NATIVE) {
    return !native_result_is_fresh(program, call);
  }
  if (kind != MS_REF_FUNCTION && kind != MS_REF_METHOD) {
    return kind == MS_REF_CASE;
  }
  const MsFunc *func = ms_own_find_func(program, &call->callee);
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
