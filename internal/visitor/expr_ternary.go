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
		if ctx.GetCondition() == nil {
			v.addError("TernaryExprContext has no Condition (LogicalOrExpr) child when QUESTION is missing", ctx.GetStart())
			return &ast.BadExpr{}
		}
		return v.Visit(ctx.GetCondition())
	}
	if ctx.GetCondition() == nil || ctx.GetTrueExpr() == nil || ctx.GetFalseExpr() == nil || ctx.COLON() == nil {
		v.addError("Incomplete ternary expression", ctx.GetStart())
		return &ast.BadExpr{}
	}
	condNode := v.Visit(ctx.GetCondition())
	condExpr, ok := condNode.(ast.Expr)
	if !ok {
		v.addError("Condition in ternary expression did not resolve to an ast.Expr", ctx.GetCondition().GetStart())
		return &ast.BadExpr{}
	}
	trueNode := v.Visit(ctx.GetTrueExpr())
	trueExpr, ok := trueNode.(ast.Expr)
	if !ok {
		v.addError("True expression in ternary did not resolve to an ast.Expr", ctx.GetTrueExpr().GetStart())
		return &ast.BadExpr{}
	}
	falseNode := v.Visit(ctx.GetFalseExpr())
	falseExpr, ok := falseNode.(ast.Expr)
	if !ok {
		v.addError("False expression in ternary did not resolve to an ast.Expr", ctx.GetFalseExpr().GetStart())
		return &ast.BadExpr{}
	}
	ifStmt := &ast.IfStmt{
		Cond: condExpr,
		Body: &ast.BlockStmt{
			List: []ast.Stmt{
				&ast.ReturnStmt{Results: []ast.Expr{trueExpr}},
			},
		},
		Else: &ast.BlockStmt{
			List: []ast.Stmt{
				&ast.ReturnStmt{Results: []ast.Expr{falseExpr}},
			},
		},
	}
	returnType := ast.NewIdent("interface{}")
	funcLit := &ast.FuncLit{
		Type: &ast.FuncType{
			Params:  &ast.FieldList{},
			Results: &ast.FieldList{List: []*ast.Field{{Type: returnType}}},
		},
		Body: &ast.BlockStmt{List: []ast.Stmt{ifStmt}},
	}
	return &ast.CallExpr{Fun: funcLit}
}
