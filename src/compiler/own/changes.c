/* compiler/own/changes.c: changing a value its owner did not declare changeable (see changes.h). */
#include "compiler/own/changes.h"

#include "compiler/check/mutate_fix.h"
#include "compiler/check/scope_walk.h"

typedef struct Changes {
  MsCheckProgram *program;
  uint32_t module;
  MsSpan source;
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
static void report(Changes *pass, const MsExpr *place, const MsBinding *binding) {
  const size_t length = place->end.offset > place->pos.offset ? place->end.offset - place->pos.offset : 0;
  if (place->end.offset > pass->source.len) {
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "cannot change `");
  ms_strbuild_append(&text, (MsSpan){pass->source.ptr + place->pos.offset, length});
  ms_strbuild_append_text(&text, "`: ");
  const bool parameter = binding->kind == MS_BK_PARAM;
  if (parameter) {
    ms_strbuild_append_text(&text, "parameter `");
    append_name(pass, &text, binding->name);
    ms_strbuild_append_text(&text, "` is not declared var; write `var ");
    append_name(pass, &text, binding->name);
    ms_strbuild_append_text(&text, ": <Type>` in the signature");
  } else {
    ms_strbuild_append_text(&text, "`");
    append_name(pass, &text, binding->name);
    ms_strbuild_append_text(&text, "` is an immutable binding, immutable including its contents; declare it `var ");
    append_name(pass, &text, binding->name);
    ms_strbuild_append_text(&text, "` to change it");
  }
  MsVarFix fix = {0};
  const bool has_fix = parameter ? parameter_fix(binding->decl, &fix) : ms_var_fix(pass->source, binding->decl, &fix);
  ms_check_report(pass->program, pass->module, place->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  if (has_fix) {
    ms_check_attach_fix(pass->program, fix.pos, fix.end, fix.replacement);
  }
}

/* A parameter, `:=` local or loop variable that is not `var` cannot be changed in place. */
static bool refuses_change(const MsBinding *binding) {
  if (binding->mutable_ || binding->invalid) {
    return false;
  }
  return binding->kind == MS_BK_PARAM || binding->kind == MS_BK_LOOP ||
         (binding->kind == MS_BK_OTHER && binding->origin == MS_BIND_LOCAL);
}

static void check_place(Changes *pass, const MsExpr *place, const MsBindingList *scope) {
  const MsExpr *root = NULL;
  if (!place_root(place, &root)) {
    return;
  }
  const MsBinding *binding = ms_scope_lookup(scope, root->u.sym);
  if (binding != NULL && refuses_change(binding)) {
    report(pass, place, binding);
  }
}

static void visit_expr(void *context, const MsExpr *expr, const MsBindingList *scope, const MsScopeSite *site) {
  (void)site;
  Changes *pass = context;
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
      check_place(pass, callee->u.member.left, scope);
      continue;
    }
    for (uint32_t at = 0; at < expr->u.call.args.len; at++) {
      if (expr->u.call.args.ptr[at].value->id == arg->node.node) {
        check_place(pass, expr->u.call.args.ptr[at].value, scope);
      }
    }
  }
}

void ms_own_changes(MsCheckProgram *program) {
  if (program->diagnostics.len != 0) {
    return;
  }
  for (uint32_t module = 0; module < program->modules.len; module++) {
    Changes pass = {.program = program, .module = module, .source = program->modules.ptr[module].source};
    const MsScopeVisitor visitor = {.context = &pass, .expr = visit_expr};
    ms_scope_walk_module(program->modules.ptr[module].tree, &visitor, program->names);
  }
}
