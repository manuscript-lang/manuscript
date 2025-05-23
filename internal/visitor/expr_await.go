package visitor

import (
	"manuscript-co/manuscript/internal/parser"
)

func (v *ManuscriptAstVisitor) VisitAwaitExpr(ctx *parser.AwaitExprContext) interface{} {
	return v.Visit(ctx.PostfixExpr())
}
