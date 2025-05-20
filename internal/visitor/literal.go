package visitor

import (
	"go/ast"
	"go/token"
	"manuscript-co/manuscript/internal/parser"
	"strconv"
)

func (v *ManuscriptAstVisitor) VisitLiteral(ctx *parser.LiteralContext) interface{} {
	switch {
	case ctx.NumberLiteral() != nil:
		return v.Visit(ctx.NumberLiteral())
	case ctx.StringLiteral() != nil:
		return v.Visit(ctx.StringLiteral())
	case ctx.BooleanLiteral() != nil:
		return v.Visit(ctx.BooleanLiteral())
	case ctx.VOID() != nil, ctx.NULL() != nil:
		return ast.NewIdent("nil")
	default:
		v.addError("Unhandled literal type: "+ctx.GetText(), ctx.GetStart())
		return &ast.BadExpr{}
	}
}

func (v *ManuscriptAstVisitor) VisitNumberLiteral(ctx *parser.NumberLiteralContext) interface{} {
	switch {
	case ctx.INTEGER() != nil:
		return &ast.BasicLit{Kind: token.INT, Value: ctx.INTEGER().GetText()}
	case ctx.FLOAT() != nil:
		return &ast.BasicLit{Kind: token.FLOAT, Value: ctx.FLOAT().GetText()}
	case ctx.HEX_LITERAL() != nil:
		return &ast.BasicLit{Kind: token.INT, Value: ctx.HEX_LITERAL().GetText()}
	case ctx.BINARY_LITERAL() != nil:
		return &ast.BasicLit{Kind: token.INT, Value: ctx.BINARY_LITERAL().GetText()}
	case ctx.OCTAL_LITERAL() != nil:
		return &ast.BasicLit{Kind: token.INT, Value: ctx.OCTAL_LITERAL().GetText()}
	}

	text := ctx.GetText()
	if text != "" {
		if _, err := strconv.ParseInt(text, 0, 64); err == nil {
			return &ast.BasicLit{Kind: token.INT, Value: text}
		} else if _, err := strconv.ParseFloat(text, 64); err == nil {
			return &ast.BasicLit{Kind: token.FLOAT, Value: text}
		}
	}
	v.addError("Unhandled or invalid number literal: "+ctx.GetText(), ctx.GetStart())
	return &ast.BadExpr{}
}

func (v *ManuscriptAstVisitor) VisitStringLiteral(ctx *parser.StringLiteralContext) interface{} {
	var parts []parser.IStringPartContext
	switch {
	case ctx.SingleQuotedString() != nil:
		parts = ctx.SingleQuotedString().AllStringPart()
	case ctx.MultiQuotedString() != nil:
		parts = ctx.MultiQuotedString().AllStringPart()
	case ctx.DoubleQuotedString() != nil:
		parts = ctx.DoubleQuotedString().AllStringPart()
	default:
		v.addError("No known string type found in string literal: "+ctx.GetText(), ctx.GetStart())
		return &ast.BadExpr{}
	}

	raw := ""
	for _, p := range parts {
		switch {
		case p.SINGLE_STR_CONTENT() != nil:
			raw += p.SINGLE_STR_CONTENT().GetText()
		case p.MULTI_STR_CONTENT() != nil:
			raw += p.MULTI_STR_CONTENT().GetText()
		case p.DOUBLE_STR_CONTENT() != nil:
			raw += p.DOUBLE_STR_CONTENT().GetText()
		case p.Interpolation() != nil:
			v.addError("String interpolation is not yet supported: "+p.Interpolation().GetText(), p.Interpolation().GetStart())
		}
	}
	return &ast.BasicLit{Kind: token.STRING, Value: strconv.Quote(raw)}
}

func (v *ManuscriptAstVisitor) VisitBooleanLiteral(ctx *parser.BooleanLiteralContext) interface{} {
	switch ctx.GetText() {
	case "true", "false":
		return ast.NewIdent(ctx.GetText())
	default:
		return &ast.BadExpr{}
	}
}
