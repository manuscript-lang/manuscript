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

	var exprs []ast.Expr
	for i, exprCtx := range allExprs {
		if exprCtx == nil {
			v.addError(fmt.Sprintf("Expression %d in ExprList is nil", i), ctx.GetStart())
			continue
		}
		visitedNode := v.Visit(exprCtx)
		if expr, ok := visitedNode.(ast.Expr); ok {
			exprs = append(exprs, expr)
		} else if visitedNode == nil {
			v.addError(fmt.Sprintf("Visiting expression %d in ExprList returned nil: %s", i, exprCtx.GetText()), exprCtx.GetStart())
			exprs = append(exprs, &ast.BadExpr{})
		} else {
			v.addError(fmt.Sprintf("Expression %d in ExprList resolved to unexpected type %T: %s", i, visitedNode, exprCtx.GetText()), exprCtx.GetStart())
			exprs = append(exprs, &ast.BadExpr{})
		}
	}
	return exprs
}
