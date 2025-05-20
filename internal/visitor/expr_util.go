package visitor

import (
	"go/ast"
	"manuscript-co/manuscript/internal/parser"
	"strings"
)

func isValidIdentifier(s string) bool {
	if len(s) == 0 {
		return false
	}
	firstChar := rune(s[0])
	if !isLetter(firstChar) && firstChar != '_' {
		return false
	}
	for _, c := range s[1:] {
		if !isLetter(c) && !isDigit(c) && c != '_' {
			return false
		}
	}
	return true
}

func isLetter(r rune) bool {
	return (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z')
}

func isDigit(r rune) bool {
	return r >= '0' && r <= '9'
}

func (v *ManuscriptAstVisitor) extractValueAfterColon(exprCtx parser.IExprContext) ast.Expr {
	exprText := exprCtx.GetText()
	colonPos := strings.Index(exprText, ":")
	if colonPos < 0 {
		return nil
	}
	visitedExpr := v.Visit(exprCtx)
	if expr, ok := visitedExpr.(ast.Expr); ok {
		return expr
	}
	if ctx, ok := exprCtx.(*parser.ExprContext); ok {
		if assignExpr, ok := ctx.AssignmentExpr().(*parser.AssignmentExprContext); ok {
			if assignExpr.AssignmentExpr() != nil {
				valueResult := v.Visit(assignExpr.AssignmentExpr())
				if valueExpr, ok := valueResult.(ast.Expr); ok {
					return valueExpr
				}
			}
		}
	}
	return &ast.BadExpr{
		From: v.pos(exprCtx.GetStart()),
		To:   v.pos(exprCtx.GetStop()),
	}
}
