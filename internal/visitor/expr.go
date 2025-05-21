package visitor

import (
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
	for _, exprCtx := range allExprs {
		if exprCtx == nil {
			continue
		}
		visited := v.Visit(exprCtx)
		if expr, ok := visited.(ast.Expr); ok {
			exprs = append(exprs, expr)
		} else if visited != nil {
			v.addError("Expression in ExprList did not resolve to ast.Expr: "+exprCtx.GetText(), exprCtx.GetStart())
			exprs = append(exprs, &ast.BadExpr{From: v.pos(exprCtx.GetStart()), To: v.pos(exprCtx.GetStop())})
		}
	}
	return exprs
}
