package visitor

import (
	"go/ast"
	"go/token"
	"manuscript-co/manuscript/internal/parser"
	"strconv"
)

// --- Literal Visitors ---

func (v *ManuscriptAstVisitor) VisitLiteralString(ctx *parser.LiteralStringContext) interface{} {
	if ctx.StringLiteral() != nil {
		return v.Visit(ctx.StringLiteral())
	}
	v.addError("Unknown string literal type: "+ctx.GetText(), ctx.GetStart())
	return &ast.BadExpr{}
}

func (v *ManuscriptAstVisitor) VisitLiteralNumber(ctx *parser.LiteralNumberContext) interface{} {
	if ctx.NumberLiteral() != nil {
		return v.Visit(ctx.NumberLiteral())
	}
	v.addError("Unknown number literal type: "+ctx.GetText(), ctx.GetStart())
	return &ast.BadExpr{}
}

func (v *ManuscriptAstVisitor) VisitLiteralBool(ctx *parser.LiteralBoolContext) interface{} {
	if ctx.BooleanLiteral() != nil {
		return v.Visit(ctx.BooleanLiteral())
	}
	v.addError("Unknown boolean literal type: "+ctx.GetText(), ctx.GetStart())
	return &ast.BadExpr{}
}

func (v *ManuscriptAstVisitor) VisitLiteralNull(ctx *parser.LiteralNullContext) interface{} {
	return ast.NewIdent("nil")
}

func (v *ManuscriptAstVisitor) VisitLiteralVoid(ctx *parser.LiteralVoidContext) interface{} {
	return ast.NewIdent("nil")
}

// --- Fine-grained String Literal Visitors ---

func (v *ManuscriptAstVisitor) VisitStringLiteralSingle(ctx *parser.StringLiteralSingleContext) interface{} {
	if ctx.SingleQuotedString() != nil {
		return v.stringPartsToBasicLit(ctx.SingleQuotedString().AllStringPart())
	}
	v.addError("Malformed single-quoted string literal", ctx.GetStart())
	return &ast.BadExpr{}
}

func (v *ManuscriptAstVisitor) VisitStringLiteralMulti(ctx *parser.StringLiteralMultiContext) interface{} {
	if ctx.MultiQuotedString() != nil {
		return v.stringPartsToBasicLit(ctx.MultiQuotedString().AllStringPart())
	}
	v.addError("Malformed multi-quoted string literal", ctx.GetStart())
	return &ast.BadExpr{}
}

func (v *ManuscriptAstVisitor) VisitStringLiteralDouble(ctx *parser.StringLiteralDoubleContext) interface{} {
	if ctx.DoubleQuotedString() != nil {
		return v.stringPartsToBasicLit(ctx.DoubleQuotedString().AllStringPart())
	}
	v.addError("Malformed double-quoted string literal", ctx.GetStart())
	return &ast.BadExpr{}
}

func (v *ManuscriptAstVisitor) VisitStringLiteralMultiDouble(ctx *parser.StringLiteralMultiDoubleContext) interface{} {
	if ctx.MultiDoubleQuotedString() != nil {
		return v.stringPartsToBasicLit(ctx.MultiDoubleQuotedString().AllStringPart())
	}
	v.addError("Malformed multi-double-quoted string literal", ctx.GetStart())
	return &ast.BadExpr{}
}

func (v *ManuscriptAstVisitor) stringPartsToBasicLit(parts []parser.IStringPartContext) ast.Expr {
	raw := ""
	for _, p := range parts {
		switch part := p.(type) {
		case *parser.StringPartSingleContext:
			raw += part.GetText()
		case *parser.StringPartMultiContext:
			raw += part.GetText()
		case *parser.StringPartDoubleContext:
			raw += part.GetText()
		case *parser.StringPartMultiDoubleContext:
			raw += part.GetText()
		case *parser.StringPartInterpContext:
			v.addError("String interpolation is not yet supported: "+part.GetText(), part.GetStart())
		}
	}
	return &ast.BasicLit{Kind: token.STRING, Value: strconv.Quote(raw)}
}

// --- Fine-grained Number Literal Visitors ---

func (v *ManuscriptAstVisitor) VisitNumberLiteralInt(ctx *parser.NumberLiteralIntContext) interface{} {
	return &ast.BasicLit{Kind: token.INT, Value: ctx.GetText()}
}

func (v *ManuscriptAstVisitor) VisitNumberLiteralFloat(ctx *parser.NumberLiteralFloatContext) interface{} {
	return &ast.BasicLit{Kind: token.FLOAT, Value: ctx.GetText()}
}

func (v *ManuscriptAstVisitor) VisitNumberLiteralHex(ctx *parser.NumberLiteralHexContext) interface{} {
	return &ast.BasicLit{Kind: token.INT, Value: ctx.GetText()}
}

func (v *ManuscriptAstVisitor) VisitNumberLiteralBin(ctx *parser.NumberLiteralBinContext) interface{} {
	return &ast.BasicLit{Kind: token.INT, Value: ctx.GetText()}
}

func (v *ManuscriptAstVisitor) VisitNumberLiteralOct(ctx *parser.NumberLiteralOctContext) interface{} {
	return &ast.BasicLit{Kind: token.INT, Value: ctx.GetText()}
}

// --- Fine-grained Boolean Literal Visitors ---

func (v *ManuscriptAstVisitor) VisitBoolLiteralTrue(ctx *parser.BoolLiteralTrueContext) interface{} {
	return ast.NewIdent("true")
}

func (v *ManuscriptAstVisitor) VisitBoolLiteralFalse(ctx *parser.BoolLiteralFalseContext) interface{} {
	return ast.NewIdent("false")
}
