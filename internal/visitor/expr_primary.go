package visitor

import (
	"go/ast"
	"manuscript-co/manuscript/internal/parser"
)

// VisitPrimaryExpr handles all primary expressions.
func (v *ManuscriptAstVisitor) VisitPrimaryExpr(ctx *parser.PrimaryExprContext) interface{} {
	if ctx.Literal() != nil {
		return v.Visit(ctx.Literal())
	}
	if ctx.ID() != nil {
		return ast.NewIdent(ctx.ID().GetText())
	}
	if ctx.LPAREN() != nil && ctx.Expr() != nil && ctx.RPAREN() != nil {
		return v.Visit(ctx.Expr())
	}
	if ctx.ArrayLiteral() != nil {
		return v.Visit(ctx.ArrayLiteral())
	}
	if ctx.ObjectLiteral() != nil {
		return v.Visit(ctx.ObjectLiteral())
	}
	if ctx.MapLiteral() != nil {
		return v.Visit(ctx.MapLiteral())
	}
	if ctx.SetLiteral() != nil {
		return v.Visit(ctx.SetLiteral())
	}
	if ctx.FnExpr() != nil {
		return v.Visit(ctx.FnExpr())
	}
	if ctx.MatchExpr() != nil {
		return v.Visit(ctx.MatchExpr())
	}
	if ctx.VOID() != nil {
		return ast.NewIdent("nil")
	}
	if ctx.NULL() != nil {
		return ast.NewIdent("nil")
	}
	if ctx.TaggedBlockString() != nil {
		return v.Visit(ctx.TaggedBlockString())
	}
	if ctx.StructInitExpr() != nil {
		return v.Visit(ctx.StructInitExpr())
	}
	v.addError("Unknown or unsupported primary expression", ctx.GetStart())
	return &ast.BadExpr{}
}
