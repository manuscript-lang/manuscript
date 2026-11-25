/* compiler/own/relays.c: borrowed results that would leave as owned ones (see relays.h). */
#include "compiler/own/relays.h"

#include "compiler/own/bind.h"
#include "compiler/own/class.h"
#include "compiler/own/expr_text.h"
#include "compiler/own/result_borrows.h"
#include "compiler/syntax/walk.h"

typedef struct Relays {
  MsCheckProgram *program;
  MsClassifier *classes;
  uint32_t module;
  const MsFacts *facts;
  const MsExpr *callee; /* the name of the call just entered: written as a callee, not used as a value */
  const MsExpr *applied; /* the name of the type application just entered, which checks as a whole */
  MsBindingList views;   /* locals bound to a borrowed part of a parameter: they borrow it too */
} Relays;

static bool owns_memory(const Relays *pass, MsTy ty) {
  return ty != MS_TY_NONE && ms_class_of(pass->classes, ty) != MS_CLASS_COPY;
}

/* A parameter, a field of one, or a local bound to one, that the function only borrows. */
static bool is_borrowed_param_place(const Relays *pass, const MsExpr *place) {
  const MsExpr *root = place;
  while (root->kind == MS_E_MEMBER) {
    root = root->u.member.left;
  }
  const MsRef *ref = root->kind == MS_E_NAME ? ms_facts_ref(pass->facts, root->id) : NULL;
  if (ref == NULL) {
    return false;
  }
  if (ref->kind == MS_REF_LOCAL) {
    uint32_t binding = 0;
    for (size_t index = 0; ms_bind_of(pass->facts, root->id, &binding) && index < pass->views.len; index++) {
      if (pass->views.ptr[index] == binding) {
        return true;
      }
    }
    return false;
  }
  return ref->kind == MS_REF_PARAM && ms_facts_use(pass->facts, root->id) == MS_USE_BORROW;
}

/* Whether a call's result borrows an argument that is a place someone else owns: a borrowed result of a temporary the
 * caller made leaves as that temporary's owner. */
static bool borrows_a_place(const Relays *pass, const MsExpr *call_expr) {
  const MsCall *call = ms_facts_call(pass->facts, call_expr->id);
  if (call == NULL || call->callee.kind != MS_REF_FUNCTION) {
    return false;
  }
  const uint32_t mask = ms_own_result_borrow_mask(pass->program, call->callee.decl.module, call->callee.decl.node);
  for (uint32_t index = 0; index < call->arg_count && index < 31; index++) {
    if ((mask & (UINT32_C(1) << index)) == 0 || call->args[index].source != MS_ARG_WRITTEN) {
      continue;
    }
    for (uint32_t at = 0; at < call_expr->u.call.args.len; at++) {
      const MsExpr *written = call_expr->u.call.args.ptr[at].value;
      if (written->id == call->args[index].node.node &&
          is_borrowed_param_place(pass, written)) {
        return true;
      }
    }
  }
  return false;
}

/* The error type of a `Result` operand that would hand a borrowed error out as an owned one, or MS_TY_NONE. */
static bool relays_borrowed_error(const Relays *pass, const MsExpr *operand) {
  const MsTyTable *types = &pass->program->types;
  const MsTy ty = ms_facts_type(pass->facts, operand->id);
  if (ty == MS_TY_NONE || !ms_ty_is(types, ty, MS_BUILTIN_Result) || ms_ty_arg_count(types, ty) != 2 ||
      !owns_memory(pass, ms_ty_args(types, ty)[1])) {
    return false;
  }
  if (operand->kind == MS_E_CALL) {
    return borrows_a_place(pass, operand);
  }
  return is_borrowed_param_place(pass, operand);
}

static void report_try(Relays *pass, const MsExpr *try_expr, const MsExpr *operand) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, operand->kind == MS_E_CALL ? "the result of `" : "`");
  ms_own_expr_text(&text, pass->program->names, operand);
  ms_strbuild_append_text(&text, operand->kind == MS_E_CALL ? "` is a borrow of its arguments, so `?` cannot move its error out; write `"
                                                             : "` is a borrow, so `?` cannot move its error out; write `");
  ms_own_expr_text(&text, pass->program->names, operand);
  ms_strbuild_append_text(&text, ".clone()?` to relay a copy, or take it from an owner");
  ms_check_report(pass->program, pass->module, try_expr->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
}

/* A function that returns a borrow of its arguments, named as a value: the function type's result is owned. */
static void check_function_value(Relays *pass, const MsExpr *name, const MsExpr *value) {
  const MsRef *ref = ms_facts_ref(pass->facts, name->id);
  if (ref == NULL || ref->kind != MS_REF_FUNCTION || !ms_own_result_is_borrowed(pass->program, ref->decl.module, ref->decl.node)) {
    return;
  }
  const MsTy ty = ms_facts_type(pass->facts, value->id);
  const MsTyTable *types = &pass->program->types;
  if (ty == MS_TY_NONE || ms_ty_kind(types, ty) != MS_TY_FUNCTION || !owns_memory(pass, ms_ty_result(types, ty))) {
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "`");
  ms_own_expr_text(&text, pass->program->names, name);
  ms_strbuild_append_text(&text, "` returns a borrow of its arguments, so as a function value its result would be a hidden copy; "
                                 "wrap it in a closure that returns `.clone()` of the call");
  ms_check_report(pass->program, pass->module, name->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
}

static void visit_stmt(void *ctx, const MsStmt *stmt) {
  Relays *pass = ctx;
  uint32_t binding = 0;
  if (stmt->kind == MS_S_BIND && !stmt->u.bind.is_mutable && stmt->u.bind.pattern->kind == MS_P_NAME && stmt->u.bind.value != NULL &&
      (stmt->u.bind.value->kind == MS_E_NAME || stmt->u.bind.value->kind == MS_E_MEMBER) &&
      is_borrowed_param_place(pass, stmt->u.bind.value) && ms_bind_of(pass->facts, stmt->u.bind.pattern->id, &binding)) {
    ms_binding_list_push(&pass->views, binding);
  }
}

static void visit_expr(void *ctx, const MsExpr *expr) {
  Relays *pass = ctx;
  if (expr->kind == MS_E_CALL) {
    const MsExpr *callee = expr->u.call.callee;
    pass->callee = callee->kind == MS_E_APPLY ? callee->u.apply.left : callee;
  }
  if (expr->kind == MS_E_UNARY && expr->op == MS_U_TRY && relays_borrowed_error(pass, expr->u.bin.left)) {
    report_try(pass, expr, expr->u.bin.left);
  }
  if (expr->kind == MS_E_APPLY && expr->u.apply.left->kind == MS_E_NAME && expr->u.apply.left != pass->callee) {
    pass->applied = expr->u.apply.left;
    check_function_value(pass, expr->u.apply.left, expr);
  }
  if (expr->kind == MS_E_NAME && expr != pass->callee && expr != pass->applied) {
    check_function_value(pass, expr, expr);
  }
}

void ms_own_relays(MsCheckProgram *program) {
  MsClassifier classes = ms_class_new(program);
  for (uint32_t module = 0; module < program->user_modules && module < (uint32_t)program->modules.len; module++) {
    if (!ms_check_is_user_module(program, module)) {
      continue;
    }
    Relays pass = {.program = program, .classes = &classes, .module = module, .facts = &program->modules.ptr[module].facts};
    const MsModule *tree = program->modules.ptr[module].tree;
    const MsVisitor visitor = {.ctx = &pass, .expr = visit_expr, .stmt = visit_stmt};
    for (uint32_t index = 0; index < tree->ndecls; index++) {
      ms_walk_decl(&visitor, tree->decls[index]);
    }
    ms_binding_list_free(&pass.views);
  }
  ms_class_free(&classes);
}
