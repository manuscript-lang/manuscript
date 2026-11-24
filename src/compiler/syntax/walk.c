/* Source-order walker (ms/walk.h). */
#include "compiler/syntax/walk.h"

static void walk_params(const MsVisitor *v, MsParams params) {
  for (uint32_t i = 0; i < params.len; i++) {
    if (params.ptr[i]->def != NULL) {
      ms_walk_expr(v, params.ptr[i]->def);
    }
  }
}

static void walk_methods(const MsVisitor *v, MsMethod *const *methods, uint32_t count) {
  for (uint32_t i = 0; i < count; i++) {
    ms_walk_callable(v, methods[i]->func.params, methods[i]->func.body);
  }
}

void ms_walk_decl(const MsVisitor *v, const MsDecl *d) {
  switch ((MsDeclKind)d->kind) {
  case MS_D_FN:
    ms_walk_callable(v, d->u.fn.params, d->u.fn.body);
    break;
  case MS_D_CONST:
    ms_walk_expr(v, d->u.konst.value);
    break;
  case MS_D_TYPE:
    walk_params(v, d->u.type.fields);
    break;
  case MS_D_ENUM:
  case MS_D_ALIAS:
    break;
  case MS_D_INTERFACE:
    walk_methods(v, d->u.iface.methods.ptr, d->u.iface.methods.len);
    break;
  case MS_D_IMPL:
    walk_methods(v, d->u.impl.methods.ptr, d->u.impl.methods.len);
    break;
  case MS_D_TEST:
    ms_walk_block(v, d->u.test.body);
    break;
  }
}

void ms_walk_callable(const MsVisitor *v, MsParams params, MsStmts body) {
  walk_params(v, params);
  ms_walk_block(v, body);
}

void ms_walk_block(const MsVisitor *v, MsStmts body) {
  if (body.len == 0) {
    return;
  }
  if (v->block != NULL) {
    v->block(v->ctx, body);
  }
  for (uint32_t i = 0; i < body.len; i++) {
    ms_walk_stmt(v, body.ptr[i]);
  }
}

void ms_walk_stmt(const MsVisitor *v, const MsStmt *s) {
  if (v->stmt != NULL) {
    v->stmt(v->ctx, s);
  }
  switch ((MsStmtKind)s->kind) {
  case MS_S_BIND:
    ms_walk_expr(v, s->u.bind.value);
    break;
  case MS_S_ASSIGN:
    if (s->u.assign.member_target) {
      ms_walk_expr(v, s->u.assign.target);
    }
    ms_walk_expr(v, s->u.assign.value);
    break;
  case MS_S_CALL:
    ms_walk_expr(v, s->u.expr);
    break;
  case MS_S_RETURN:
    if (s->u.expr != NULL) {
      ms_walk_expr(v, s->u.expr);
    }
    break;
  case MS_S_BREAK:
  case MS_S_CONTINUE:
    break;
  case MS_S_IF:
    ms_walk_expr(v, s->u.branch.cond);
    ms_walk_block(v, s->u.branch.body);
    ms_walk_block(v, s->u.branch.else_body);
    break;
  case MS_S_WHILE:
    ms_walk_expr(v, s->u.loop.cond);
    ms_walk_block(v, s->u.loop.body);
    break;
  case MS_S_FOR:
    ms_walk_expr(v, s->u.each.iter);
    ms_walk_block(v, s->u.each.body);
    break;
  }
}

static void walk_exprs(const MsVisitor *v, MsExpr *const *items, uint32_t count) {
  for (uint32_t i = 0; i < count; i++) {
    ms_walk_expr(v, items[i]);
  }
}

static void walk_text(const MsVisitor *v, const MsExpr *e) {
  for (uint32_t i = 0; i < e->u.text.len; i++) {
    if (e->u.text.ptr[i].expr != NULL) {
      ms_walk_expr(v, e->u.text.ptr[i].expr);
    }
  }
}

static void walk_children(const MsVisitor *v, const MsExpr *e) {
  switch ((MsExprKind)e->kind) {
  case MS_E_NUMBER:
  case MS_E_BOOL:
  case MS_E_VOID:
  case MS_E_NAME:
    break;
  case MS_E_TEXT:
    walk_text(v, e);
    break;
  case MS_E_MEMBER:
    ms_walk_expr(v, e->u.member.left);
    break;
  case MS_E_APPLY:
    ms_walk_expr(v, e->u.apply.left);
    if (e->u.apply.value != NULL) {
      ms_walk_expr(v, e->u.apply.value);
    }
    break;
  case MS_E_INDEX:
  case MS_E_BINARY:
    ms_walk_expr(v, e->u.bin.left);
    ms_walk_expr(v, e->u.bin.right);
    break;
  case MS_E_PROBE:
  case MS_E_UNARY:
    ms_walk_expr(v, e->u.bin.left);
    break;
  case MS_E_LIST:
    walk_exprs(v, e->u.list.ptr, e->u.list.len);
    break;
  case MS_E_MAP:
    for (uint32_t i = 0; i < e->u.map.len; i++) {
      ms_walk_expr(v, e->u.map.ptr[i].key);
      ms_walk_expr(v, e->u.map.ptr[i].value);
    }
    break;
  case MS_E_LAMBDA:
    ms_walk_callable(v, e->u.lambda.params, e->u.lambda.body);
    break;
  case MS_E_CALL:
    ms_walk_expr(v, e->u.call.callee);
    for (uint32_t i = 0; i < e->u.call.args.len; i++) {
      ms_walk_expr(v, e->u.call.args.ptr[i].value);
    }
    break;
  case MS_E_MATCH:
    ms_walk_expr(v, e->u.match.scrutinee);
    for (uint32_t i = 0; i < e->u.match.arms.len; i++) {
      const MsArm *arm = e->u.match.arms.ptr[i];
      ms_walk_block(v, arm->body);
      if (arm->value != NULL) {
        ms_walk_expr(v, arm->value);
      }
    }
    break;
  }
}

void ms_walk_expr(const MsVisitor *v, const MsExpr *e) {
  if (v->expr != NULL) {
    v->expr(v->ctx, e);
  }
  walk_children(v, e);
  if (v->leave_expr != NULL) {
    v->leave_expr(v->ctx, e);
  }
}

MsPos ms_expr_start(const MsExpr *e) {
  switch ((MsExprKind)e->kind) {
  case MS_E_MEMBER:
    return ms_expr_start(e->u.member.left);
  case MS_E_APPLY:
    return ms_expr_start(e->u.apply.left);
  case MS_E_INDEX:
  case MS_E_BINARY:
  case MS_E_PROBE:
    return ms_expr_start(e->u.bin.left);
  case MS_E_CALL:
    return ms_expr_start(e->u.call.callee);
  case MS_E_UNARY:
    if (e->op == MS_U_TRY) {
      return ms_expr_start(e->u.bin.left); /* a postfix `?` starts where its operand does */
    }
    break;
  case MS_E_NUMBER:
  case MS_E_BOOL:
  case MS_E_VOID:
  case MS_E_TEXT:
  case MS_E_NAME:
  case MS_E_LIST:
  case MS_E_MAP:
  case MS_E_LAMBDA:
  case MS_E_MATCH:
    break;
  }
  return e->pos;
}
