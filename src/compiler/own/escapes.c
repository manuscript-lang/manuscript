/* compiler/own/escapes.c: which closures escape (see escapes.h). */
#include "compiler/own/escapes.h"

#include "base/map.h"
#include "compiler/own/bind.h"
#include "compiler/syntax/walk.h"

typedef struct Callable {
  MsParams params;
  MsStmts body;
  MsNode id;      /* the declaration node a call's callee names */
  uint32_t first; /* the index of the first written parameter (1 after a receiver) */
} Callable;

MS_LIST_DEFINE(CallableList, callable_list, Callable)
typedef struct Tie {
  MsNode lambda; /* a closure passed to a parameter that holds it in what the callee returns ... */
  MsNode call;   /* ... so it escapes when this call's result does */
} Tie;

MS_LIST_DEFINE(TieList, tie_list, Tie)
MS_MAP_DEFINE(KeptMap, kept_map, uint64_t, bool, ms_hash_u64_key, ms_equal_u64_key)

typedef struct Module {
  CallableList callables;
  uint8_t *ok;  /* per node: a name or lambda consumed in place (called, or passed to a parameter not kept) */
  uint8_t *bad; /* per binding site: used where it may be kept, or captured by an escaping closure */
  uint8_t *kept; /* per binding site: used where it may be kept */
  uint8_t *held; /* per binding site: captured by an escaping closure, or handed to a parameter that holds it */
  uint8_t *moved; /* per binding site: read where ownership leaves it */
  uint8_t *holdn; /* per node: a name passed to a parameter that holds it */
  uint8_t *kept_result; /* per node: a call whose result is returned, stored, or passed to a keeping parameter */
  TieList ties;
} Module;

typedef struct Escapes {
  MsCheckProgram *program;
  Module *modules;
  KeptMap kept;
  KeptMap held; /* parameters a callee captures in a closure it keeps: the argument lives as long as the result */
  uint32_t module; /* the module being walked */
  bool changed;
} Escapes;

static uint64_t kept_key(uint32_t module, MsNode node, uint32_t index) {
  return ((uint64_t)module << 48) | ((uint64_t)node << 8) | (index & 0xffu);
}

static bool is_kept(const Escapes *pass, uint32_t module, MsNode node, uint32_t index) {
  const bool *kept = kept_map_get(&pass->kept, kept_key(module, node, index));
  return kept != NULL && *kept;
}

static bool is_held(const Escapes *pass, uint32_t module, MsNode node, uint32_t index) {
  const bool *held = kept_map_get(&pass->held, kept_key(module, node, index));
  return held != NULL && *held;
}

/* ---- collecting the callables ---- */

static void collect(Escapes *pass, uint32_t module) {
  const MsModule *tree = pass->program->modules.ptr[module].tree;
  CallableList *list = &pass->modules[module].callables;
  for (uint32_t index = 0; index < tree->ndecls; index++) {
    const MsDecl *decl = tree->decls[index];
    if (decl->kind == MS_D_FN) {
      callable_list_push(list, (Callable){decl->u.fn.params, decl->u.fn.body, decl->id, 0});
    } else if (decl->kind == MS_D_TEST) {
      callable_list_push(list, (Callable){(MsParams){0}, decl->u.test.body, decl->id, 0});
    } else if (decl->kind == MS_D_IMPL) {
      for (uint32_t at = 0; at < decl->u.impl.methods.len; at++) {
        const MsMethod *method = decl->u.impl.methods.ptr[at];
        callable_list_push(list, (Callable){method->func.params, method->func.body, method->id, 1});
      }
    }
  }
}

/* ---- roles: what a call does with its operands ---- */

static const MsCallArg *arg_for(const MsCall *call, const MsExpr *value, uint32_t *index) {
  for (uint32_t at = 0; at < call->arg_count; at++) {
    if (call->args[at].source == MS_ARG_WRITTEN && call->args[at].node.node == value->id) {
      *index = at;
      return &call->args[at];
    }
  }
  return NULL;
}

/* Whether the callee keeps its parameter `index`: declared `move`, or a function that does keep it. A callee the
 * call does not name (a function value, an interface operation) is taken to keep everything. */
static bool keeps(const Escapes *pass, const MsCall *call, const MsCallArg *arg, uint32_t index) {
  if ((arg->flags & MS_PARAM_MOVE) != 0) {
    return true;
  }
  const MsRefKind kind = call->callee.kind;
  if (kind == MS_REF_NATIVE) {
    return false;
  }
  if (kind == MS_REF_LOCAL || kind == MS_REF_PARAM) {
    return false; /* a function type carries no `move` */
  }
  if (kind != MS_REF_FUNCTION && kind != MS_REF_METHOD) {
    return true;
  }
  return is_kept(pass, call->callee.decl.module, call->callee.decl.node, index);
}

/* Whether the callee holds its parameter `index` in the value it returns: the argument must outlive the result. */
static bool holds(const Escapes *pass, const MsCall *call, uint32_t index) {
  const MsRefKind kind = call->callee.kind;
  return (kind == MS_REF_FUNCTION || kind == MS_REF_METHOD) &&
         is_held(pass, call->callee.decl.module, call->callee.decl.node, index);
}

static void mark_ok(Escapes *pass, const MsExpr *expr) {
  if (expr->id < pass->program->modules.ptr[pass->module].facts.node_count) {
    pass->modules[pass->module].ok[expr->id] = 1;
  }
}

/* A call (or the calls in a list) in a position that keeps its result. */
static void mark_result_kept(Escapes *pass, const MsExpr *expr) {
  const MsFacts *facts = &pass->program->modules.ptr[pass->module].facts;
  if (expr->kind == MS_E_CALL && expr->id < facts->node_count) {
    pass->modules[pass->module].kept_result[expr->id] = 1;
  }
  for (uint32_t at = 0; expr->kind == MS_E_LIST && at < expr->u.list.len; at++) {
    mark_result_kept(pass, expr->u.list.ptr[at]);
  }
}

static void roles_stmt(void *ctx, const MsStmt *stmt) {
  Escapes *pass = ctx;
  if (stmt->kind == MS_S_RETURN && stmt->u.expr != NULL) {
    mark_result_kept(pass, stmt->u.expr);
  } else if (stmt->kind == MS_S_BIND && stmt->u.bind.value != NULL &&
             (stmt->u.bind.is_mutable || stmt->u.bind.value->kind == MS_E_LIST)) {
    mark_result_kept(pass, stmt->u.bind.value);
  } else if (stmt->kind == MS_S_ASSIGN && stmt->u.assign.value != NULL) {
    mark_result_kept(pass, stmt->u.assign.value);
  }
}

static void mark_elements_ok(Escapes *pass, const MsExpr *list) {
  for (uint32_t at = 0; at < list->u.list.len; at++) {
    const MsExpr *element = list->u.list.ptr[at];
    if (element->kind == MS_E_CALL || element->kind == MS_E_LAMBDA || element->kind == MS_E_NAME) {
      mark_ok(pass, element);
    }
  }
}

static void visit_call(Escapes *pass, const MsExpr *call) {
  const MsExpr *callee = call->u.call.callee;
  if (callee->kind == MS_E_NAME || callee->kind == MS_E_LAMBDA) {
    mark_ok(pass, callee);
  }
  const MsFacts *facts = &pass->program->modules.ptr[pass->module].facts;
  Module *module = &pass->modules[pass->module];
  const MsCall *fact = ms_facts_call(facts, call->id);
  for (uint32_t at = 0; at < call->u.call.args.len; at++) {
    const MsExpr *value = call->u.call.args.ptr[at].value;
    uint32_t index = 0;
    const MsCallArg *arg = fact == NULL ? NULL : arg_for(fact, value, &index);
    if (arg == NULL || keeps(pass, fact, arg, index)) {
      mark_result_kept(pass, value);
      continue;
    }
    const bool holding = holds(pass, fact, index);
    if (value->kind == MS_E_LIST && !holding) {
      mark_elements_ok(pass, value); /* a list that is only read does not keep its elements */
    } else if (holding && value->kind == MS_E_LAMBDA) {
      tie_list_push(&module->ties, (Tie){value->id, call->id});
    } else if (holding && value->kind == MS_E_NAME && value->id < facts->node_count) {
      module->holdn[value->id] = 1;
    } else if (value->kind == MS_E_NAME || value->kind == MS_E_LAMBDA) {
      mark_ok(pass, value);
    }
  }
}

static void roles_expr(void *ctx, const MsExpr *expr) {
  if (expr->kind == MS_E_CALL) {
    visit_call(ctx, expr);
  }
}

/* ---- uses of bindings ---- */

static void uses_expr(void *ctx, const MsExpr *expr) {
  Escapes *pass = ctx;
  Module *module = &pass->modules[pass->module];
  const MsFacts *facts = &pass->program->modules.ptr[pass->module].facts;
  uint32_t binding = 0;
  if (expr->kind != MS_E_NAME || !ms_bind_of(facts, expr->id, &binding) || binding >= facts->node_count ||
      expr->id >= facts->node_count) {
    return;
  }
  if (facts->uses[expr->id] == MS_USE_MOVE) {
    module->moved[binding] = 1;
  }
  if (module->holdn[expr->id]) {
    module->held[binding] = 1;
  } else if (!module->ok[expr->id]) {
    module->bad[binding] = 1;
    module->kept[binding] = 1;
  }
}

/* The binding a lambda is bound to: `f := fn ...`. */
typedef struct Bound {
  const MsExpr *lambda;
  MsNode binding;
} Bound;

MS_LIST_DEFINE(BoundList, bound_list, Bound)

MS_LIST_DEFINE(LambdaList, lambda_list, const MsExpr *)

MS_LIST_DEFINE(CallBindList, call_bind_list, Bound)

typedef struct Pass {
  BoundList bound;
  CallBindList call_bound; /* `p := f(...)`: the call (in `lambda`) and the binding that holds its result */
  LambdaList lambdas;
} Pass;

static void scan_stmt(void *ctx, const MsStmt *stmt) {
  Pass *pass = ctx;
  if (stmt->kind == MS_S_BIND && stmt->u.bind.pattern->kind == MS_P_NAME && stmt->u.bind.value != NULL &&
      stmt->u.bind.value->kind == MS_E_LAMBDA) {
    bound_list_push(&pass->bound, (Bound){stmt->u.bind.value, stmt->u.bind.pattern->id});
  }
  if (stmt->kind == MS_S_BIND && stmt->u.bind.pattern->kind == MS_P_NAME && stmt->u.bind.value != NULL &&
      stmt->u.bind.value->kind == MS_E_CALL) {
    call_bind_list_push(&pass->call_bound, (Bound){stmt->u.bind.value, stmt->u.bind.pattern->id});
  }
}

static void scan_expr(void *ctx, const MsExpr *expr) {
  Pass *pass = ctx;
  if (expr->kind == MS_E_LAMBDA) {
    lambda_list_push(&pass->lambdas, expr);
  }
}

static MsNode bound_binding(const Pass *pass, const MsExpr *lambda) {
  for (size_t index = 0; index < pass->bound.len; index++) {
    if (pass->bound.ptr[index].lambda == lambda) {
      return pass->bound.ptr[index].binding;
    }
  }
  return MS_NO_NODE;
}

static MsFacts *facts_of(Escapes *pass, uint32_t module) {
  return &pass->program->modules.ptr[module].facts;
}

/* Whether the result of `call` is kept: returned or stored, or bound to a name that is. */
static bool result_escapes(const Module *state, const MsFacts *facts, const Pass *scan, MsNode call) {
  if (call >= facts->node_count || state->ok[call]) {
    return false;
  }
  if (state->kept_result[call]) {
    return true;
  }
  for (size_t index = 0; index < scan->call_bound.len; index++) {
    if (scan->call_bound.ptr[index].lambda->id == call) {
      return state->moved[scan->call_bound.ptr[index].binding] != 0;
    }
  }
  return false;
}

static const Tie *tie_of(const Module *state, MsNode lambda) {
  for (size_t index = 0; index < state->ties.len; index++) {
    if (state->ties.ptr[index].lambda == lambda) {
      return &state->ties.ptr[index];
    }
  }
  return NULL;
}

static bool escaping(const MsFacts *facts, const MsExpr *lambda) {
  return lambda->id < facts->node_count && facts->uses[lambda->id] == MS_USE_MOVE;
}

/* One module: the escape of every lambda and the keeping of every parameter, until nothing moves. */
static void settle(Escapes *pass, uint32_t module, Pass *scan) {
  Module *state = &pass->modules[module];
  MsFacts *facts = facts_of(pass, module);
  pass->module = module;
  for (uint32_t node = 0; node < facts->node_count; node++) {
    state->ok[node] = 0;
    state->holdn[node] = 0;
    state->kept_result[node] = 0;
  }
  tie_list_clear(&state->ties);
  for (size_t at = 0; at < state->callables.len; at++) {
    const Callable *callable = &state->callables.ptr[at];
    ms_walk_callable(&(MsVisitor){.ctx = pass, .expr = roles_expr, .stmt = roles_stmt}, callable->params, callable->body);
  }
  for (bool again = true; again;) {
    again = false;
    for (uint32_t node = 0; node < facts->node_count; node++) {
      state->bad[node] = 0;
      state->kept[node] = 0;
      state->held[node] = 0;
      state->moved[node] = 0;
    }
    for (size_t at = 0; at < state->callables.len; at++) {
      const Callable *callable = &state->callables.ptr[at];
      ms_walk_callable(&(MsVisitor){.ctx = pass, .expr = uses_expr}, callable->params, callable->body);
    }
    for (size_t at = 0; at < scan->lambdas.len; at++) { /* what an escaping closure captures is kept */
      if (!escaping(facts, scan->lambdas.ptr[at])) {
        continue;
      }
      MsBindingList captures = ms_bind_captures(facts, scan->lambdas.ptr[at]);
      for (size_t index = 0; index < captures.len; index++) {
        if (captures.ptr[index] < facts->node_count) {
          state->bad[captures.ptr[index]] = 1;
          state->held[captures.ptr[index]] = 1;
        }
      }
      ms_binding_list_free(&captures);
    }
    for (size_t at = 0; at < scan->lambdas.len; at++) {
      const MsExpr *lambda = scan->lambdas.ptr[at];
      const MsNode binding = bound_binding(scan, lambda);
      const Tie *tie = tie_of(state, lambda->id);
      const bool escapes = tie != NULL ? result_escapes(state, facts, scan, tie->call)
                                       : !state->ok[lambda->id] && (binding == MS_NO_NODE || state->bad[binding]);
      const uint8_t use = escapes ? MS_USE_MOVE : MS_USE_BORROW;
      if (facts->uses[lambda->id] != use && !(escapes == false && facts->uses[lambda->id] == MS_USE_MOVE)) {
        facts->uses[lambda->id] = use;
        again = true;
        pass->changed = true;
      }
    }
  }
  for (size_t at = 0; at < state->callables.len; at++) {
    const Callable *callable = &state->callables.ptr[at];
    for (uint32_t index = 0; index < callable->params.len; index++) {
      const MsParam *param = callable->params.ptr[index];
      const MsTy ty = ms_facts_type(facts, param->id);
      if (param->id >= facts->node_count || ty == MS_TY_NONE ||
          ms_ty_kind(&pass->program->types, ty) != MS_TY_FUNCTION) {
        continue;
      }
      const uint64_t key = kept_key(module, callable->id, callable->first + index);
      if (state->kept[param->id] && !is_kept(pass, module, callable->id, callable->first + index)) {
        kept_map_put(&pass->kept, key, true);
        pass->changed = true;
      }
      if (state->held[param->id] && !is_held(pass, module, callable->id, callable->first + index)) {
        kept_map_put(&pass->held, key, true);
        pass->changed = true;
      }
      if (state->held[param->id] && index < 32 && facts->taken != NULL && callable->id < facts->node_count) {
        facts->taken[callable->id] |= 1u << index; /* a closure the body keeps owns the parameter: the caller hands it over */
      }
    }
  }
}

void ms_own_escapes(MsCheckProgram *program) {
  const size_t count = program->modules.len;
  MsArena arena = ms_arena_new();
  Escapes pass = {.program = program, .modules = MS_ARENA_NEW_ARRAY(&arena, Module, count + 1)};
  Pass *scans = MS_ARENA_NEW_ARRAY(&arena, Pass, count + 1);
  for (size_t module = 0; module < count; module++) {
    MsFacts *facts = facts_of(&pass, (uint32_t)module);
    pass.modules[module] = (Module){0};
    scans[module] = (Pass){0};
    if (facts->uses == NULL) {
      continue;
    }
    pass.modules[module].ok = MS_ARENA_NEW_ARRAY(&arena, uint8_t, facts->node_count + 1);
    pass.modules[module].bad = MS_ARENA_NEW_ARRAY(&arena, uint8_t, facts->node_count + 1);
    pass.modules[module].kept = MS_ARENA_NEW_ARRAY(&arena, uint8_t, facts->node_count + 1);
    pass.modules[module].held = MS_ARENA_NEW_ARRAY(&arena, uint8_t, facts->node_count + 1);
    pass.modules[module].moved = MS_ARENA_NEW_ARRAY(&arena, uint8_t, facts->node_count + 1);
    pass.modules[module].holdn = MS_ARENA_NEW_ARRAY(&arena, uint8_t, facts->node_count + 1);
    pass.modules[module].kept_result = MS_ARENA_NEW_ARRAY(&arena, uint8_t, facts->node_count + 1);
    collect(&pass, (uint32_t)module);
    for (size_t at = 0; at < pass.modules[module].callables.len; at++) {
      const Callable *callable = &pass.modules[module].callables.ptr[at];
      ms_walk_callable(&(MsVisitor){.ctx = &scans[module], .stmt = scan_stmt, .expr = scan_expr}, callable->params,
                       callable->body);
    }
  }
  for (int round = 0; round < 12; round++) {
    pass.changed = false;
    for (size_t module = 0; module < count; module++) {
      if (pass.modules[module].ok != NULL) {
        settle(&pass, (uint32_t)module, &scans[module]);
      }
    }
    if (!pass.changed) {
      break;
    }
  }
  for (size_t module = 0; module < count; module++) {
    callable_list_free(&pass.modules[module].callables);
    tie_list_free(&pass.modules[module].ties);
    call_bind_list_free(&scans[module].call_bound);
    bound_list_free(&scans[module].bound);
    lambda_list_free(&scans[module].lambdas);
  }
  kept_map_free(&pass.kept);
  kept_map_free(&pass.held);
  ms_arena_free(&arena);
}
