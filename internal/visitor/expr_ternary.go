package visitor

import (
	"go/ast"
	"manuscript-co/manuscript/internal/parser"
)

func (v *ManuscriptAstVisitor) VisitTernaryExpr(ctx *parser.TernaryExprContext) interface{} {
	if ctx == nil {
		v.addError("VisitTernaryExpr called with nil context", nil)
		return &ast.BadExpr{}
	}
	if ctx.QUESTION() == nil {
		if ctx.LogicalOrExpr() == nil {
			v.addError("TernaryExprContext has no Condition (LogicalOrExpr) child when QUESTION is missing", ctx.GetStart())
			return &ast.BadExpr{}
		}
		return v.Visit(ctx.LogicalOrExpr())
	}
	if ctx.LogicalOrExpr() == nil || ctx.Expr() == nil || ctx.TernaryExpr() == nil || ctx.COLON() == nil {
		v.addError("Incomplete ternary expression", ctx.GetStart())
		return &ast.BadExpr{}
	}
	condNode := v.Visit(ctx.LogicalOrExpr())
	condExpr, ok := condNode.(ast.Expr)
	if !ok {
		v.addError("Ternary condition did not resolve to ast.Expr", ctx.LogicalOrExpr().GetStart())
		return &ast.BadExpr{}
	}
	trueNode := v.Visit(ctx.Expr())
	trueExpr, ok := trueNode.(ast.Expr)
	if !ok {
		v.addError("Ternary true branch did not resolve to ast.Expr", ctx.Expr().GetStart())
		return &ast.BadExpr{}
	}
	falseNode := v.Visit(ctx.TernaryExpr())
	falseExpr, ok := falseNode.(ast.Expr)
	if !ok {
		v.addError("Ternary false branch did not resolve to ast.Expr", ctx.TernaryExpr().GetStart())
		return &ast.BadExpr{}
	}
	// Lower to an IIFE (function literal) that returns the correct value
	return &ast.CallExpr{
		Fun: &ast.FuncLit{
			Type: &ast.FuncType{
				Params:  &ast.FieldList{},
				Results: &ast.FieldList{List: []*ast.Field{{Type: ast.NewIdent("interface{}")}}},
			},
			Body: &ast.BlockStmt{List: []ast.Stmt{
				&ast.IfStmt{
					Cond: condExpr,
					Body: &ast.BlockStmt{List: []ast.Stmt{
						&ast.ReturnStmt{Results: []ast.Expr{trueExpr}},
					}},
					Else: &ast.BlockStmt{List: []ast.Stmt{
						&ast.ReturnStmt{Results: []ast.Expr{falseExpr}},
					}},
				},
			}},
		},
		Args: []ast.Expr{},
	}
}
