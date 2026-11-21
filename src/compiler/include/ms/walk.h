/* Source-order walker over executable syntax: the port of crates/ms-syntax/src/visit.rs. Fill an
 * MsVisitor with the hooks you need (the rest stay NULL) and call ms_walk_decl; the walk goes
 * through parameter defaults, interpolation, closures, branches and match arms. Types and
 * patterns are not executable and are not visited.
 *
 * Order: for a statement, `stmt`, then the assignment target, the value, the body, the else body.
 * For an expression, `expr`, then left/right, arguments, list/map elements, text interpolations,
 * lambda parameter defaults and body, arms (body, then value), and finally `leave_expr`. */
#ifndef MS_WALK_H
#define MS_WALK_H

#include "ms/ast.h"

typedef struct MsVisitor {
    void *ctx;
    void (*block)(void *ctx, MsStmts body); /* every non-empty statement list, before its statements */
    void (*stmt)(void *ctx, const MsStmt *stmt);
    void (*expr)(void *ctx, const MsExpr *expr);
    void (*leave_expr)(void *ctx, const MsExpr *expr); /* after the children, arm bodies included */
} MsVisitor;

void ms_walk_decl(const MsVisitor *v, const MsDecl *decl);
void ms_walk_callable(const MsVisitor *v, MsParams params, MsStmts body);
void ms_walk_block(const MsVisitor *v, MsStmts body);
void ms_walk_stmt(const MsVisitor *v, const MsStmt *stmt);
void ms_walk_expr(const MsVisitor *v, const MsExpr *expr);

#endif
