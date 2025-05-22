package visitor

import (
	"manuscript-co/manuscript/internal/parser"
)

func (v *ManuscriptAstVisitor) VisitAwaitExpr(ctx *parser.AwaitExprContext) interface{} {
	if ctx.AWAIT() != nil {
		v.addError("Semantic translation for 'await' prefix in awaitExpr not fully implemented: "+ctx.GetText(), ctx.GetStart())
	}
	if ctx.ASYNC() != nil {
		v.addError("Semantic translation for 'async' prefix in awaitExpr not fully implemented: "+ctx.GetText(), ctx.GetStart())
	}
	return v.Visit(ctx.PostfixExpr())
}
