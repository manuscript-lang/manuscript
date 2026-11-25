/* compiler/own/changes.c: changing a value its owner did not declare changeable (see changes.h). */
#include "compiler/own/changes.h"

#include "compiler/check/mutate_fix.h"
#include "compiler/check/scope_walk.h"

typedef struct Changes {
  MsCheckProgram *program;
  uint32_t module;
  MsSpan source;
  const MsScopeSite *site; /* where the visited node sits */
  const MsExpr *closure;      /* the last lambda reported as changing a capture */
  const MsBinding *captured;  /* ... and the binding it changed */
} Changes;

/* The local name a place expression (`b`, `b.f`, `b.xs[i]`) is rooted at, or false. */
static bool place_root(const MsExpr *expr, const MsExpr **root) {
  const MsExpr *at = expr;
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
  *root = at;
  return at->kind == MS_E_NAME;
}

static void append_name(const Changes *pass, MsStrBuild *text, MsName name) {
  ms_strbuild_append(text, ms_names_span(pass->program->names, name));
}

/* A parameter gains the keyword in front of it: `var ` inserted where it is written. */
static bool parameter_fix(MsPos decl, MsVarFix *fix) {
  fix->pos = decl;
  fix->end = decl;
  fix->replacement = ms_string_from_span(ms_span_of_text("var "));
  return true;
}

/* Reports `place` changed through a binding that does not allow it; the first line of the oracle's wording. */
static void report(Changes *pass, const MsExpr *place, const MsExpr *root, const MsBinding *binding, MsPos at) {
  const size_t start = root->pos.offset < place->pos.offset ? root->pos.offset : place->pos.offset; /* the written place */
  const size_t length = place->end.offset > start ? place->end.offset - start : 0;
  if (place->end.offset > pass->source.len) {
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "cannot change `");
  ms_strbuild_append(&text, (MsSpan){pass->source.ptr + start, length});
  ms_strbuild_append_text(&text, "`: ");
  const bool parameter = binding->kind == MS_BK_PARAM;
  const bool receiver = binding->kind == MS_BK_SELF;
  const MsMethod *method = NULL; /* the method whose receiver it is */
  for (uint32_t each = 0; receiver && pass->site != NULL && pass->site->impl != NULL && each < pass->site->impl->u.impl.methods.len; each++) {
    const MsMethod *candidate = pass->site->impl->u.impl.methods.ptr[each];
    method = candidate->pos.offset == binding->decl.offset ? candidate : method;
  }
  if (receiver) {
    ms_strbuild_append_text(&text, "this method does not change its receiver; write `fn var` in its declaration to allow that");
  } else if (parameter) {
    ms_strbuild_append_text(&text, "parameter `");
    append_name(pass, &text, binding->name);
    ms_strbuild_append_text(&text, "` is not declared var; write `var ");
    append_name(pass, &text, binding->name);
    ms_strbuild_append_text(&text, " <Type>` in the signature");
  } else {
    ms_strbuild_append_text(&text, "`");
    append_name(pass, &text, binding->name);
    ms_strbuild_append_text(&text, "` is an immutable binding, immutable including its contents; declare it `var ");
    append_name(pass, &text, binding->name);
    ms_strbuild_append_text(&text, "` to change it");
  }
  MsVarFix fix = {0};
  const bool has_fix = receiver ? (method != NULL && parameter_fix(method->var_at, &fix))
                       : parameter ? parameter_fix(binding->decl, &fix) : ms_var_fix(pass->source, binding->decl, &fix);
  ms_check_report(pass->program, pass->module, at, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  if (has_fix) {
    ms_check_attach_fix(pass->program, fix.pos, fix.end, fix.replacement);
  }
}

/* A parameter, `:=` local or loop variable that is not `var` cannot be changed in place. */
static bool refuses_change(const MsBinding *binding, bool by_argument) {
  if (binding->mutable_ || binding->invalid) {
    return false;
  }
  return binding->kind == MS_BK_PARAM || (binding->kind == MS_BK_SELF && !by_argument) || binding->kind == MS_BK_LOOP ||
         (binding->kind == MS_BK_OTHER && binding->origin == MS_BIND_LOCAL);
}

/* `by_argument`: the place is passed as a `var` argument, which a method may do with its own receiver. */
static void check_place(Changes *pass, const MsExpr *place, const MsBindingList *scope, bool by_argument) {
  const MsExpr *root = NULL;
  if (!place_root(place, &root)) {
    return;
  }
  const MsBinding *binding = ms_scope_lookup(scope, root->u.sym);
  if (binding != NULL && refuses_change(binding, by_argument)) {
    report(pass, place, root, binding, place->pos);
    const MsExpr *lambda = pass->site != NULL ? pass->site->lambda : NULL;
    const bool captured = lambda != NULL && (size_t)(binding - scope->ptr) < pass->site->lambda_scope;
    if (captured && binding->kind == MS_BK_PARAM && (pass->closure != lambda || pass->captured != binding)) {
      pass->closure = lambda; /* the closure itself changes what it captured */
      pass->captured = binding;
      report(pass, root, root, binding, lambda->pos);
    }
  }
}

static void visit_expr(void *context, const MsExpr *expr, const MsBindingList *scope, const MsScopeSite *site) {
  Changes *pass = context;
  pass->site = site;
  if (expr->kind != MS_E_CALL) {
    return;
  }
  const MsCall *fact = ms_facts_call(&pass->program->modules.ptr[pass->module].facts, expr->id);
  if (fact == NULL) {
    return;
  }
  const MsExpr *callee = expr->u.call.callee;
  for (uint32_t index = 0; index < fact->arg_count; index++) {
    const MsCallArg *arg = &fact->args[index];
    if (arg->source != MS_ARG_WRITTEN || (arg->flags & MS_PARAM_VAR) == 0) {
      continue;
    }
    if (callee->kind == MS_E_MEMBER && arg->node.node == callee->u.member.left->id) {
      check_place(pass, callee->u.member.left, scope, false);
      continue;
    }
    for (uint32_t at = 0; at < expr->u.call.args.len; at++) {
      if (expr->u.call.args.ptr[at].value->id == arg->node.node) {
        check_place(pass, expr->u.call.args.ptr[at].value, scope, true);
      }
    }
  }
}

static void visit_store(void *context, const MsStmt *stmt, const MsBindingList *scope, const MsScopeSite *site) {
  Changes *pass = context;
  pass->site = site;
  check_place(pass, stmt->u.assign.target, scope, false);
}

void ms_own_changes(MsCheckProgram *program) {
  if (program->diagnostics.len != 0) {
    return;
  }
  for (uint32_t module = 0; module < program->modules.len; module++) {
    if (module >= program->user_modules && !program->check_std) {
      continue; /* a bundled module reports only when asked to */
    }
    Changes pass = {.program = program, .module = module, .source = program->modules.ptr[module].source};
    const MsScopeVisitor visitor = {.context = &pass, .expr = visit_expr, .store = visit_store};
    ms_scope_walk_module(program->modules.ptr[module].tree, &visitor, program->names);
  }
}
