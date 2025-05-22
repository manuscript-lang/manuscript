package visitor

import (
	"go/ast"
	"go/token"
	"manuscript-co/manuscript/internal/parser"
	"strconv"
)

// --- string literal visitors ---
func (v *ManuscriptAstVisitor) VisitLabelLiteralString(ctx *parser.LabelLiteralStringContext) interface{} {
	if ctx.StringLiteral() != nil {
		return v.Visit(ctx.StringLiteral())
	}
	v.addError("Unknown string literal type: "+ctx.GetText(), ctx.GetStart())
	return &ast.BadExpr{}
}

func (v *ManuscriptAstVisitor) VisitStringLiteral(ctx *parser.StringLiteralContext) interface{} {
	var parts []parser.IStringPartContext
	if ctx.SingleQuotedString() != nil {
		parts = ctx.SingleQuotedString().AllStringPart()
	} else if ctx.MultiQuotedString() != nil {
		parts = ctx.MultiQuotedString().AllStringPart()
	} else if ctx.DoubleQuotedString() != nil {
		parts = ctx.DoubleQuotedString().AllStringPart()
	} else if ctx.MultiDoubleQuotedString() != nil {
		parts = ctx.MultiDoubleQuotedString().AllStringPart()
	}
	return stringPartToLit(parts, v)
}

func (v *ManuscriptAstVisitor) VisitSingleQuotedString(ctx *parser.SingleQuotedStringContext) interface{} {
	return stringPartToLit(ctx.AllStringPart(), v)
}

func stringPartToLit(parts []parser.IStringPartContext, v *ManuscriptAstVisitor) interface{} {
	raw := ""
	for _, part := range parts {
		raw += v.Visit(part).(string)
	}
	return &ast.BasicLit{Kind: token.STRING, Value: strconv.Quote(raw)}
}

func (v *ManuscriptAstVisitor) VisitStringPart(ctx *parser.StringPartContext) interface{} {
	if ctx.SINGLE_STR_CONTENT() != nil {
		return ctx.SINGLE_STR_CONTENT().GetText()
	}
	if ctx.MULTI_STR_CONTENT() != nil {
		return ctx.MULTI_STR_CONTENT().GetText()
	}
	if ctx.DOUBLE_STR_CONTENT() != nil {
		return ctx.DOUBLE_STR_CONTENT().GetText()
	}
	if ctx.MULTI_DOUBLE_STR_CONTENT() != nil {
		return ctx.MULTI_DOUBLE_STR_CONTENT().GetText()
	}
	if ctx.Interpolation() != nil {
		return v.Visit(ctx.Interpolation())
	}
	return ""
}

// bool, null, void

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

// --- Fine-grained Number Literal Visitors ---
func (v *ManuscriptAstVisitor) VisitLabelLiteralNumber(ctx *parser.LabelLiteralNumberContext) interface{} {
	if ctx.NumberLiteral() != nil {
		return v.Visit(ctx.NumberLiteral())
	}
	v.addError("Unknown number literal type: "+ctx.GetText(), ctx.GetStart())
	return &ast.BadExpr{}
}

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
