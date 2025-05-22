package visitor

import (
	"go/ast"
	"manuscript-co/manuscript/internal/parser"
)

// VisitPrimaryLiteral handles literal primary expressions.
func (v *ManuscriptAstVisitor) VisitLabelPrimaryLiteral(ctx *parser.LabelPrimaryLiteralContext) interface{} {
	return v.Visit(ctx.Literal())
}

// VisitPrimaryID handles identifier primary expressions.
func (v *ManuscriptAstVisitor) VisitLabelPrimaryID(ctx *parser.LabelPrimaryIDContext) interface{} {
	if ctx.ID() != nil {
		return ast.NewIdent(ctx.ID().GetText())
	}
	v.addError("PrimaryID missing ID", ctx.GetStart())
	return &ast.BadExpr{}
}

// VisitPrimaryParen handles parenthesized expressions.
func (v *ManuscriptAstVisitor) VisitLabelPrimaryParen(ctx *parser.LabelPrimaryParenContext) interface{} {
	if ctx.Expr() != nil {
		return v.Visit(ctx.Expr())
	}
	v.addError("PrimaryParen missing Expr", ctx.GetStart())
	return &ast.BadExpr{}
}

// VisitPrimaryArray handles array literals.
func (v *ManuscriptAstVisitor) VisitLabelPrimaryArray(ctx *parser.LabelPrimaryArrayContext) interface{} {
	return v.Visit(ctx.ArrayLiteral())
}

// VisitPrimaryObject handles object literals.
func (v *ManuscriptAstVisitor) VisitLabelPrimaryObject(ctx *parser.LabelPrimaryObjectContext) interface{} {
	return v.Visit(ctx.ObjectLiteral())
}

// VisitPrimaryMap handles map literals.
func (v *ManuscriptAstVisitor) VisitLabelPrimaryMap(ctx *parser.LabelPrimaryMapContext) interface{} {
	return v.Visit(ctx.MapLiteral())
}

// VisitPrimarySet handles set literals.
func (v *ManuscriptAstVisitor) VisitLabelPrimarySet(ctx *parser.LabelPrimarySetContext) interface{} {
	return v.Visit(ctx.SetLiteral())
}

// VisitPrimaryFn handles function expressions.
func (v *ManuscriptAstVisitor) VisitLabelPrimaryFn(ctx *parser.LabelPrimaryFnContext) interface{} {
	return v.Visit(ctx.FnExpr())
}

// VisitPrimaryMatch handles match expressions.
func (v *ManuscriptAstVisitor) VisitLabelPrimaryMatch(ctx *parser.LabelPrimaryMatchContext) interface{} {
	return v.Visit(ctx.MatchExpr())
}

// VisitPrimaryVoid handles the void literal.
func (v *ManuscriptAstVisitor) VisitLabelPrimaryVoid(ctx *parser.LabelPrimaryVoidContext) interface{} {
	return ast.NewIdent("nil")
}

// VisitPrimaryNull handles the null literal.
func (v *ManuscriptAstVisitor) VisitLabelPrimaryNull(ctx *parser.LabelPrimaryNullContext) interface{} {
	return ast.NewIdent("nil")
}

// VisitPrimaryTaggedBlock handles tagged block strings.
func (v *ManuscriptAstVisitor) VisitLabelPrimaryTaggedBlock(ctx *parser.LabelPrimaryTaggedBlockContext) interface{} {
	return v.Visit(ctx.TaggedBlockString())
}

// VisitPrimaryStructInit handles struct initialization expressions.
func (v *ManuscriptAstVisitor) VisitLabelPrimaryStructInit(ctx *parser.LabelPrimaryStructInitContext) interface{} {
	return v.Visit(ctx.StructInitExpr())
}
