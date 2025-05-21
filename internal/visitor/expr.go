package visitor

import (
	"fmt"
	"go/ast"
	"manuscript-co/manuscript/internal/parser"
)

func (v *ManuscriptAstVisitor) VisitExpr(ctx *parser.ExprContext) interface{} {
	if ctx == nil {
		v.addError("VisitExpr called with nil context", nil)
		return &ast.BadExpr{}
	}
	if ctx.AssignmentExpr() == nil {
		v.addError("ExprContext has no AssignmentExpr child", ctx.GetStart())
		return &ast.BadExpr{}
	}
	return v.Visit(ctx.AssignmentExpr())
}

func (v *ManuscriptAstVisitor) VisitExprList(ctx *parser.ExprListContext) interface{} {
	if ctx == nil {
		v.addError("VisitExprList called with nil context", nil)
		return nil
	}
	allExprs := ctx.AllExpr()
	if len(allExprs) == 0 {
		return nil
	}
	if len(allExprs) > 1 {
		v.addError(
			fmt.Sprintf("ExprList with multiple (%d) expressions encountered in a context expecting a single statement; processing only the first: %s", len(allExprs), ctx.GetText()),
			ctx.GetStart(),
		)
	}
	firstExprCtx := allExprs[0]
	if firstExprCtx == nil {
		v.addError("First expression in ExprList is nil", ctx.GetStart())
		return nil
	}
	visitedNode := v.Visit(firstExprCtx)
	if stmt, ok := visitedNode.(ast.Stmt); ok {
		return stmt
	}
	if expr, ok := visitedNode.(ast.Expr); ok {
		return &ast.ExprStmt{X: expr}
	}
	if visitedNode == nil {
		v.addError(fmt.Sprintf("Visiting first expression in ExprList returned nil: %s", firstExprCtx.GetText()), firstExprCtx.GetStart())
	} else {
		v.addError(fmt.Sprintf("Expression in ExprList resolved to unexpected type %T: %s", visitedNode, firstExprCtx.GetText()), firstExprCtx.GetStart())
	}
	return &ast.BadStmt{From: v.pos(firstExprCtx.GetStart()), To: v.pos(firstExprCtx.GetStop())}
}
