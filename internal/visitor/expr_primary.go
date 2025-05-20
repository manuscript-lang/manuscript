package visitor

import (
	"go/ast"
	"manuscript-co/manuscript/internal/parser"
)

func (v *ManuscriptAstVisitor) VisitPrimaryExpr(ctx *parser.PrimaryExprContext) interface{} {
	if ctx.Literal() != nil {
		return v.Visit(ctx.Literal())
	}
	if ctx.ID() != nil {
		identName := ctx.ID().GetText()
		return ast.NewIdent(identName)
	}
	if ctx.GetParenExpr() != nil {
		return v.Visit(ctx.GetParenExpr())
	}
	if ctx.ArrayLiteral() != nil {
		return v.Visit(ctx.ArrayLiteral())
	}
	if ctx.ObjectLiteral() != nil {
		return v.Visit(ctx.ObjectLiteral())
	}
	if ctx.FnExpr() != nil {
		return v.Visit(ctx.FnExpr())
	}
	if ctx.MapLiteral() != nil {
		return v.Visit(ctx.MapLiteral())
	}
	if ctx.SetLiteral() != nil {
		return v.Visit(ctx.SetLiteral())
	}
	if ctx.TaggedBlockString() != nil {
		return v.Visit(ctx.TaggedBlockString())
	}
	if ctx.StructInitExpr() != nil {
		return v.Visit(ctx.StructInitExpr())
	}
	if ctx.MatchExpr() != nil {
		return v.Visit(ctx.MatchExpr())
	}
	v.addError("Unhandled primary expression type: "+ctx.GetText(), ctx.GetStart())
	return &ast.BadExpr{}
}
