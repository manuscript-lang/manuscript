package visitor

import (
	"go/ast"
	"manuscript-co/manuscript/internal/parser"
)

// VisitPrimaryLiteral handles literal primary expressions.
func (v *ManuscriptAstVisitor) VisitPrimaryLiteral(ctx *parser.PrimaryLiteralContext) interface{} {
	return v.Visit(ctx.Literal())
}

// VisitPrimaryID handles identifier primary expressions.
func (v *ManuscriptAstVisitor) VisitPrimaryID(ctx *parser.PrimaryIDContext) interface{} {
	if ctx.ID() != nil {
		return ast.NewIdent(ctx.ID().GetText())
	}
	v.addError("PrimaryID missing ID", ctx.GetStart())
	return &ast.BadExpr{}
}

// VisitPrimaryParen handles parenthesized expressions.
func (v *ManuscriptAstVisitor) VisitPrimaryParen(ctx *parser.PrimaryParenContext) interface{} {
	if ctx.Expr() != nil {
		return v.Visit(ctx.Expr())
	}
	v.addError("PrimaryParen missing Expr", ctx.GetStart())
	return &ast.BadExpr{}
}

// VisitPrimaryArray handles array literals.
func (v *ManuscriptAstVisitor) VisitPrimaryArray(ctx *parser.PrimaryArrayContext) interface{} {
	return v.Visit(ctx.ArrayLiteral())
}

// VisitPrimaryObject handles object literals.
func (v *ManuscriptAstVisitor) VisitPrimaryObject(ctx *parser.PrimaryObjectContext) interface{} {
	return v.Visit(ctx.ObjectLiteral())
}

// VisitPrimaryMap handles map literals.
func (v *ManuscriptAstVisitor) VisitPrimaryMap(ctx *parser.PrimaryMapContext) interface{} {
	return v.Visit(ctx.MapLiteral())
}

// VisitPrimarySet handles set literals.
func (v *ManuscriptAstVisitor) VisitPrimarySet(ctx *parser.PrimarySetContext) interface{} {
	return v.Visit(ctx.SetLiteral())
}

// VisitPrimaryFn handles function expressions.
func (v *ManuscriptAstVisitor) VisitPrimaryFn(ctx *parser.PrimaryFnContext) interface{} {
	return v.Visit(ctx.FnExpr())
}

// VisitPrimaryMatch handles match expressions.
func (v *ManuscriptAstVisitor) VisitPrimaryMatch(ctx *parser.PrimaryMatchContext) interface{} {
	return v.Visit(ctx.MatchExpr())
}

// VisitPrimaryVoid handles the void literal.
func (v *ManuscriptAstVisitor) VisitPrimaryVoid(ctx *parser.PrimaryVoidContext) interface{} {
	return ast.NewIdent("nil")
}

// VisitPrimaryNull handles the null literal.
func (v *ManuscriptAstVisitor) VisitPrimaryNull(ctx *parser.PrimaryNullContext) interface{} {
	return ast.NewIdent("nil")
}

// VisitPrimaryTaggedBlock handles tagged block strings.
func (v *ManuscriptAstVisitor) VisitPrimaryTaggedBlock(ctx *parser.PrimaryTaggedBlockContext) interface{} {
	return v.Visit(ctx.TaggedBlockString())
}

// VisitPrimaryStructInit handles struct initialization expressions.
func (v *ManuscriptAstVisitor) VisitPrimaryStructInit(ctx *parser.PrimaryStructInitContext) interface{} {
	return v.Visit(ctx.StructInitExpr())
}
