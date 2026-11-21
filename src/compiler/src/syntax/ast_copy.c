/* Copies a method with fresh node ids, so the per-node tables of two copies never collide.
 * Mirrors crates/ms-syntax/src/renumber.rs: ids are drawn in the same order, each node before its
 * children. The tree's depth is bounded by the parser's nesting limit, which bounds the recursion. */
#include <string.h>

#include "ms/desugar.h"

typedef struct Freshener {
    MsArena *arena;
    uint32_t next_id;
} Freshener;

static uint32_t next_fresh_id(Freshener *c) { return c->next_id++; }

static MsExpr *fresh_expr(Freshener *c, const MsExpr *old);
static MsStmts fresh_stmts(Freshener *c, MsStmts old);
static MsTypeRef *fresh_type(Freshener *c, const MsTypeRef *old);

/* A copy of `count` elements of type `T`, for the caller to fill in. */
#define FRESH_ARRAY(c, T, old, count) ((T *)fresh_elements((c), (old), (count), sizeof(T)))

static void *fresh_elements(Freshener *c, const void *old, uint32_t count, size_t size) {
    if (count == 0) {
        return NULL;
    }
    size_t bytes = 0;
    if (!ms_size_mul(count, size, &bytes)) {
        ms_oom();
    }
    void *items = ms_alloc(c->arena, bytes, _Alignof(max_align_t));
    memcpy(items, old, bytes);
    return items;
}

static MsTypeRef *fresh_optional_type(Freshener *c, const MsTypeRef *old) {
    return old == NULL ? NULL : fresh_type(c, old);
}

static MsExpr *fresh_optional_expr(Freshener *c, const MsExpr *old) {
    return old == NULL ? NULL : fresh_expr(c, old);
}

static MsParam *fresh_param(Freshener *c, const MsParam *old) {
    MsParam *param = MS_NEW(c->arena, MsParam);
    *param = *old;
    param->id = next_fresh_id(c);
    param->ty = fresh_optional_type(c, old->ty);
    param->def = fresh_optional_expr(c, old->def);
    return param;
}

static MsParams fresh_params(Freshener *c, MsParams old) {
    MsParams params = {FRESH_ARRAY(c, MsParam *, old.ptr, old.len), old.len};
    for (uint32_t i = 0; i < old.len; i++) {
        params.ptr[i] = fresh_param(c, old.ptr[i]);
    }
    return params;
}

static MsTypeRef *fresh_type(Freshener *c, const MsTypeRef *old) {
    MsTypeRef *type = MS_NEW(c->arena, MsTypeRef);
    *type = *old;
    type->id = next_fresh_id(c);
    switch ((MsTypeKind)old->kind) {
    case MS_TYPE_NAMED:
        type->args.ptr = FRESH_ARRAY(c, MsTypeRef *, old->args.ptr, old->args.len);
        for (uint32_t i = 0; i < old->args.len; i++) {
            type->args.ptr[i] = fresh_type(c, old->args.ptr[i]);
        }
        return type;
    case MS_TYPE_FN:
        type->params = fresh_params(c, old->params);
        type->result = fresh_optional_type(c, old->result);
        return type;
    }
    return type;
}

static MsTypeRefs fresh_types(Freshener *c, MsTypeRefs old) {
    MsTypeRefs types = {FRESH_ARRAY(c, MsTypeRef *, old.ptr, old.len), old.len};
    for (uint32_t i = 0; i < old.len; i++) {
        types.ptr[i] = fresh_type(c, old.ptr[i]);
    }
    return types;
}

static MsTypeParams fresh_type_params(Freshener *c, MsTypeParams old) {
    MsTypeParams params = {FRESH_ARRAY(c, MsTypeParam *, old.ptr, old.len), old.len};
    for (uint32_t i = 0; i < old.len; i++) {
        MsTypeParam *param = MS_NEW(c->arena, MsTypeParam);
        *param = *old.ptr[i];
        param->id = next_fresh_id(c);
        param->bounds = fresh_types(c, old.ptr[i]->bounds);
        param->def = fresh_optional_type(c, old.ptr[i]->def);
        params.ptr[i] = param;
    }
    return params;
}

static MsPattern *fresh_pattern(Freshener *c, const MsPattern *old) {
    MsPattern *pattern = MS_NEW(c->arena, MsPattern);
    *pattern = *old;
    pattern->id = next_fresh_id(c);
    switch ((MsPatternKind)old->kind) {
    case MS_P_NAME:
        return pattern;
    case MS_P_LIST:
        pattern->u.list.ptr = FRESH_ARRAY(c, MsPattern *, old->u.list.ptr, old->u.list.len);
        for (uint32_t i = 0; i < old->u.list.len; i++) {
            pattern->u.list.ptr[i] = fresh_pattern(c, old->u.list.ptr[i]);
        }
        return pattern;
    case MS_P_TYPE:
        pattern->u.fields.ptr = FRESH_ARRAY(c, MsPatternField, old->u.fields.ptr, old->u.fields.len);
        for (uint32_t i = 0; i < old->u.fields.len; i++) {
            pattern->u.fields.ptr[i].pattern = fresh_pattern(c, old->u.fields.ptr[i].pattern);
        }
        return pattern;
    }
    return pattern;
}

static MsExprs fresh_exprs(Freshener *c, MsExprs old) {
    MsExprs exprs = {FRESH_ARRAY(c, MsExpr *, old.ptr, old.len), old.len};
    for (uint32_t i = 0; i < old.len; i++) {
        exprs.ptr[i] = fresh_expr(c, old.ptr[i]);
    }
    return exprs;
}

static void fresh_text(Freshener *c, MsExpr *expr, const MsExpr *old) {
    expr->u.text.ptr = FRESH_ARRAY(c, MsTextPart, old->u.text.ptr, old->u.text.len);
    for (uint32_t i = 0; i < old->u.text.len; i++) {
        expr->u.text.ptr[i].expr = fresh_optional_expr(c, old->u.text.ptr[i].expr);
    }
}

static void fresh_map(Freshener *c, MsExpr *expr, const MsExpr *old) {
    expr->u.map.ptr = FRESH_ARRAY(c, MsMapEntry, old->u.map.ptr, old->u.map.len);
    for (uint32_t i = 0; i < old->u.map.len; i++) {
        expr->u.map.ptr[i].key = fresh_expr(c, old->u.map.ptr[i].key);
        expr->u.map.ptr[i].value = fresh_expr(c, old->u.map.ptr[i].value);
    }
}

static void fresh_call(Freshener *c, MsExpr *expr, const MsExpr *old) {
    expr->u.call.callee = fresh_expr(c, old->u.call.callee);
    expr->u.call.args.ptr = FRESH_ARRAY(c, MsArg, old->u.call.args.ptr, old->u.call.args.len);
    for (uint32_t i = 0; i < old->u.call.args.len; i++) {
        expr->u.call.args.ptr[i].value = fresh_expr(c, old->u.call.args.ptr[i].value);
    }
}

static void fresh_match(Freshener *c, MsExpr *expr, const MsExpr *old) {
    expr->u.match.scrutinee = fresh_expr(c, old->u.match.scrutinee);
    expr->u.match.arms.ptr = FRESH_ARRAY(c, MsArm *, old->u.match.arms.ptr, old->u.match.arms.len);
    for (uint32_t i = 0; i < old->u.match.arms.len; i++) {
        const MsArm *old_arm = old->u.match.arms.ptr[i];
        MsArm *arm = MS_NEW(c->arena, MsArm);
        *arm = *old_arm;
        arm->id = next_fresh_id(c);
        arm->path = fresh_expr(c, old_arm->path);
        arm->body = fresh_stmts(c, old_arm->body);
        arm->value = fresh_optional_expr(c, old_arm->value);
        expr->u.match.arms.ptr[i] = arm;
    }
}

static void fresh_lambda(Freshener *c, MsExpr *expr, const MsExpr *old) {
    expr->u.lambda.params = fresh_params(c, old->u.lambda.params);
    expr->u.lambda.result = fresh_optional_type(c, old->u.lambda.result);
    expr->u.lambda.body = fresh_stmts(c, old->u.lambda.body);
}

static MsExpr *fresh_expr(Freshener *c, const MsExpr *old) {
    MsExpr *expr = MS_NEW(c->arena, MsExpr);
    *expr = *old;
    expr->id = next_fresh_id(c);
    switch ((MsExprKind)old->kind) {
    case MS_E_NUMBER:
    case MS_E_BOOL:
    case MS_E_VOID:
    case MS_E_NAME:
        break;
    case MS_E_TEXT: fresh_text(c, expr, old); break;
    case MS_E_MEMBER: expr->u.member.left = fresh_expr(c, old->u.member.left); break;
    case MS_E_APPLY:
        expr->u.apply.left = fresh_expr(c, old->u.apply.left);
        expr->u.apply.types = fresh_types(c, old->u.apply.types);
        expr->u.apply.value = fresh_optional_expr(c, old->u.apply.value);
        break;
    case MS_E_INDEX:
    case MS_E_BINARY:
        expr->u.bin.left = fresh_expr(c, old->u.bin.left);
        expr->u.bin.right = fresh_expr(c, old->u.bin.right);
        break;
    case MS_E_PROBE:
    case MS_E_UNARY:
        expr->u.bin.left = fresh_expr(c, old->u.bin.left);
        break;
    case MS_E_LIST: expr->u.list = fresh_exprs(c, old->u.list); break;
    case MS_E_MAP: fresh_map(c, expr, old); break;
    case MS_E_LAMBDA: fresh_lambda(c, expr, old); break;
    case MS_E_CALL: fresh_call(c, expr, old); break;
    case MS_E_MATCH: fresh_match(c, expr, old); break;
    }
    return expr;
}

static void fresh_assign(Freshener *c, MsStmt *stmt, const MsStmt *old) {
    if (old->u.assign.member_target) {
        stmt->u.assign.target = fresh_expr(c, old->u.assign.target);
    }
    stmt->u.assign.value = fresh_expr(c, old->u.assign.value);
}

static void fresh_branch(Freshener *c, MsStmt *stmt, const MsStmt *old) {
    if (old->u.branch.binding != NULL) {
        stmt->u.branch.binding = fresh_pattern(c, old->u.branch.binding);
    }
    stmt->u.branch.cond = fresh_expr(c, old->u.branch.cond);
    stmt->u.branch.body = fresh_stmts(c, old->u.branch.body);
    stmt->u.branch.else_body = fresh_stmts(c, old->u.branch.else_body);
}

static MsStmt *fresh_stmt(Freshener *c, const MsStmt *old) {
    MsStmt *stmt = MS_NEW(c->arena, MsStmt);
    *stmt = *old;
    stmt->id = next_fresh_id(c);
    switch ((MsStmtKind)old->kind) {
    case MS_S_BIND:
        stmt->u.bind.pattern = fresh_pattern(c, old->u.bind.pattern);
        stmt->u.bind.ty = fresh_optional_type(c, old->u.bind.ty);
        stmt->u.bind.value = fresh_expr(c, old->u.bind.value);
        break;
    case MS_S_ASSIGN: fresh_assign(c, stmt, old); break;
    case MS_S_CALL:
    case MS_S_RETURN:
        stmt->u.expr = fresh_optional_expr(c, old->u.expr);
        break;
    case MS_S_BREAK:
    case MS_S_CONTINUE:
        break;
    case MS_S_IF: fresh_branch(c, stmt, old); break;
    case MS_S_WHILE:
        stmt->u.loop.cond = fresh_expr(c, old->u.loop.cond);
        stmt->u.loop.body = fresh_stmts(c, old->u.loop.body);
        break;
    case MS_S_FOR:
        stmt->u.each.iter = fresh_expr(c, old->u.each.iter);
        stmt->u.each.body = fresh_stmts(c, old->u.each.body);
        break;
    }
    return stmt;
}

static MsStmts fresh_stmts(Freshener *c, MsStmts old) {
    MsStmts stmts = {FRESH_ARRAY(c, MsStmt *, old.ptr, old.len), old.len};
    for (uint32_t i = 0; i < old.len; i++) {
        stmts.ptr[i] = fresh_stmt(c, old.ptr[i]);
    }
    return stmts;
}

MsMethod *ms_method_copy_fresh(MsArena *arena, uint32_t *next_id, const MsMethod *old) {
    Freshener c = {arena, *next_id};
    MsMethod *method = MS_NEW(arena, MsMethod);
    *method = *old;
    method->id = next_fresh_id(&c);
    method->func.type_params = fresh_type_params(&c, old->func.type_params);
    method->func.params = fresh_params(&c, old->func.params);
    method->func.result = fresh_optional_type(&c, old->func.result);
    method->func.body = fresh_stmts(&c, old->func.body);
    method->receiver_args = fresh_types(&c, old->receiver_args);
    *next_id = c.next_id;
    return method;
}
