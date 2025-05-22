package visitor

import (
	"go/ast"
	"go/token"
	"manuscript-co/manuscript/internal/parser"
	"strconv"
)

// --- Literal Visitors ---

func (v *ManuscriptAstVisitor) VisitLabelLiteralString(ctx *parser.LabelLiteralStringContext) interface{} {
	if ctx.StringLiteral() != nil {
		return v.Visit(ctx.StringLiteral())
	}
	v.addError("Unknown string literal type: "+ctx.GetText(), ctx.GetStart())
	return &ast.BadExpr{}
}

func (v *ManuscriptAstVisitor) VisitLabelLiteralNumber(ctx *parser.LabelLiteralNumberContext) interface{} {
	if ctx.NumberLiteral() != nil {
		return v.Visit(ctx.NumberLiteral())
	}
	v.addError("Unknown number literal type: "+ctx.GetText(), ctx.GetStart())
	return &ast.BadExpr{}
}

func (v *ManuscriptAstVisitor) VisitLabelLiteralBool(ctx *parser.LabelLiteralBoolContext) interface{} {
	if ctx.BooleanLiteral() != nil {
		return v.Visit(ctx.BooleanLiteral())
	}
	v.addError("Unknown boolean literal type: "+ctx.GetText(), ctx.GetStart())
	return &ast.BadExpr{}
}

func (v *ManuscriptAstVisitor) VisitLabelLiteralNull(ctx *parser.LabelLiteralNullContext) interface{} {
	return ast.NewIdent("nil")
}

func (v *ManuscriptAstVisitor) VisitLabelLiteralVoid(ctx *parser.LabelLiteralVoidContext) interface{} {
	return ast.NewIdent("nil")
}

// --- Fine-grained String Literal Visitors ---

func (v *ManuscriptAstVisitor) VisitLabelStringLiteralSingle(ctx *parser.LabelStringLiteralSingleContext) interface{} {
	if ctx.SingleQuotedString() != nil {
		return v.stringPartsToBasicLit(ctx.SingleQuotedString().AllStringPart())
	}
	v.addError("Malformed single-quoted string literal", ctx.GetStart())
	return &ast.BadExpr{}
}

func (v *ManuscriptAstVisitor) VisitLabelStringLiteralMulti(ctx *parser.LabelStringLiteralMultiContext) interface{} {
	if ctx.MultiQuotedString() != nil {
		return v.stringPartsToBasicLit(ctx.MultiQuotedString().AllStringPart())
	}
	v.addError("Malformed multi-quoted string literal", ctx.GetStart())
	return &ast.BadExpr{}
}

func (v *ManuscriptAstVisitor) VisitLabelStringLiteralDouble(ctx *parser.LabelStringLiteralDoubleContext) interface{} {
	if ctx.DoubleQuotedString() != nil {
		return v.stringPartsToBasicLit(ctx.DoubleQuotedString().AllStringPart())
	}
	v.addError("Malformed double-quoted string literal", ctx.GetStart())
	return &ast.BadExpr{}
}

func (v *ManuscriptAstVisitor) VisitLabelStringLiteralMultiDouble(ctx *parser.LabelStringLiteralMultiDoubleContext) interface{} {
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
		case *parser.LabelStringPartSingleContext:
			raw += part.GetText()
		case *parser.LabelStringPartMultiContext:
			raw += part.GetText()
		case *parser.LabelStringPartDoubleContext:
			raw += part.GetText()
		case *parser.LabelStringPartMultiDoubleContext:
			raw += part.GetText()
		case *parser.LabelStringPartInterpContext:
			v.addError("String interpolation is not yet supported: "+part.GetText(), part.GetStart())
		}
	}
	return &ast.BasicLit{Kind: token.STRING, Value: strconv.Quote(raw)}
}

// --- Fine-grained Number Literal Visitors ---

func (v *ManuscriptAstVisitor) VisitLabelNumberLiteralInt(ctx *parser.LabelNumberLiteralIntContext) interface{} {
	return &ast.BasicLit{Kind: token.INT, Value: ctx.GetText()}
}

func (v *ManuscriptAstVisitor) VisitLabelNumberLiteralFloat(ctx *parser.LabelNumberLiteralFloatContext) interface{} {
	return &ast.BasicLit{Kind: token.FLOAT, Value: ctx.GetText()}
}

func (v *ManuscriptAstVisitor) VisitLabelNumberLiteralHex(ctx *parser.LabelNumberLiteralHexContext) interface{} {
	return &ast.BasicLit{Kind: token.INT, Value: ctx.GetText()}
}

func (v *ManuscriptAstVisitor) VisitLabelNumberLiteralBin(ctx *parser.LabelNumberLiteralBinContext) interface{} {
	return &ast.BasicLit{Kind: token.INT, Value: ctx.GetText()}
}

func (v *ManuscriptAstVisitor) VisitLabelNumberLiteralOct(ctx *parser.LabelNumberLiteralOctContext) interface{} {
	return &ast.BasicLit{Kind: token.INT, Value: ctx.GetText()}
}

// --- Fine-grained Boolean Literal Visitors ---

func (v *ManuscriptAstVisitor) VisitLabelBoolLiteralTrue(ctx *parser.LabelBoolLiteralTrueContext) interface{} {
	return ast.NewIdent("true")
}

func (v *ManuscriptAstVisitor) VisitLabelBoolLiteralFalse(ctx *parser.LabelBoolLiteralFalseContext) interface{} {
	return ast.NewIdent("false")
}
