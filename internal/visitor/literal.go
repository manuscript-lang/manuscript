package visitor

import (
	"go/ast"
	"go/token"
	"manuscript-co/manuscript/internal/parser"
	"strconv"
)

// --- Literal Visitors ---

func (v *ManuscriptAstVisitor) VisitLiteral(ctx *parser.LiteralContext) interface{} {
	if ctx.StringLiteral() != nil {
		return v.Visit(ctx.StringLiteral())
	}
	if ctx.NumberLiteral() != nil {
		return v.Visit(ctx.NumberLiteral())
	}
	if ctx.BooleanLiteral() != nil {
		return v.Visit(ctx.BooleanLiteral())
	}
	if ctx.NULL() != nil {
		return ast.NewIdent("nil")
	}
	if ctx.VOID() != nil {
		return ast.NewIdent("nil")
	}
	v.addError("Unknown literal type: "+ctx.GetText(), ctx.GetStart())
	return &ast.BadExpr{}
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
		// Only handle plain text parts for now
		text := p.GetText()
		if text != "" {
			raw += text
		} else {
			v.addError("Unknown or unsupported string part: "+p.GetText(), p.GetStart())
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
