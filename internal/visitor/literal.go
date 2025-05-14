package visitor

import (
	"go/ast"
	"go/token"
	"log"
	"manuscript-co/manuscript/internal/parser"
	"strconv"
)

// --- Literal Handling ---

// VisitLiteral dispatches to specific literal type visitors or handles terminals directly.
func (v *ManuscriptAstVisitor) VisitLiteral(ctx *parser.LiteralContext) interface{} {
	if ctx.NumberLiteral() != nil {
		return v.Visit(ctx.NumberLiteral())
	}
	if ctx.StringLiteral() != nil {
		return v.Visit(ctx.StringLiteral())
	}
	if ctx.BooleanLiteral() != nil {
		return v.Visit(ctx.BooleanLiteral())
	}
	if ctx.VOID() != nil {
		// Map Manuscript's `void` to Go's `nil`
		return ast.NewIdent("nil")
	}
	if ctx.NULL() != nil {
		// Map Manuscript's `null` to Go's `nil`
		return ast.NewIdent("nil")
	}
	// TODO: Handle ArrayLiteral and ObjectLiteral when implemented
	return nil
}

// VisitNumberLiteral converts a number literal context to an ast.BasicLit.
func (v *ManuscriptAstVisitor) VisitNumberLiteral(ctx *parser.NumberLiteralContext) interface{} {
	// Check explicit token types first
	if ctx.INTEGER() != nil {
		intText := ctx.INTEGER().GetText()
		return &ast.BasicLit{
			Kind:  token.INT,
			Value: intText,
		}
	}

	if ctx.FLOAT() != nil {
		floatText := ctx.FLOAT().GetText()
		return &ast.BasicLit{
			Kind:  token.FLOAT,
			Value: floatText,
		}
	}

	if ctx.HEX_LITERAL() != nil {
		hexText := ctx.HEX_LITERAL().GetText()
		return &ast.BasicLit{
			Kind:  token.INT,
			Value: hexText,
		}
	}

	if ctx.BINARY_LITERAL() != nil {
		binText := ctx.BINARY_LITERAL().GetText()
		return &ast.BasicLit{
			Kind:  token.INT,
			Value: binText,
		}
	}

	// If no specific token detected, try to infer the type from the text
	text := ctx.GetText()
	if text != "" {
		if _, err := strconv.ParseInt(text, 10, 64); err == nil {
			return &ast.BasicLit{
				Kind:  token.INT,
				Value: text,
			}
		} else if _, err := strconv.ParseFloat(text, 64); err == nil {
			return &ast.BasicLit{
				Kind:  token.FLOAT,
				Value: text,
			}
		}
	}

	// Default to 0 to avoid compiler errors
	return &ast.BasicLit{
		Kind:  token.INT,
		Value: "0",
	}
}

// VisitStringLiteral converts a string literal context to an ast.BasicLit.
func (v *ManuscriptAstVisitor) VisitStringLiteral(ctx *parser.StringLiteralContext) interface{} {
	var stringParts []parser.IStringPartContext
	var rawContent string

	if sqs := ctx.SingleQuotedString(); sqs != nil {
		stringParts = sqs.AllStringPart()
	} else if mqs := ctx.MultiQuotedString(); mqs != nil {
		stringParts = mqs.AllStringPart()
	} else if dqs := ctx.DoubleQuotedString(); dqs != nil {
		stringParts = dqs.AllStringPart()
	} else {
		log.Printf("VisitStringLiteral: No known string type found in StringLiteralContext: %s", ctx.GetText())
		return &ast.BadExpr{}
	}

	if stringParts != nil {
		for _, part := range stringParts {
			if sContent := part.SINGLE_STR_CONTENT(); sContent != nil {
				rawContent += sContent.GetText()
			} else if mContent := part.MULTI_STR_CONTENT(); mContent != nil {
				rawContent += mContent.GetText()
			} else if dContent := part.DOUBLE_STR_CONTENT(); dContent != nil {
				rawContent += dContent.GetText()
			} else if interpCtx := part.Interpolation(); interpCtx != nil {
				log.Printf("VisitStringLiteral: Interpolation encountered and ignored for now: %s", interpCtx.GetText())
			}
		}
	}

	goStr := strconv.Quote(rawContent)
	return &ast.BasicLit{
		Kind:  token.STRING,
		Value: goStr,
	}
}

// VisitBooleanLiteral converts a boolean literal context to an ast.Ident (true/false).
func (v *ManuscriptAstVisitor) VisitBooleanLiteral(ctx *parser.BooleanLiteralContext) interface{} {
	text := ctx.GetText()
	if text == "true" {
		return ast.NewIdent("true")
	} else if text == "false" {
		return ast.NewIdent("false")
	} else {
		// Go doesn't have a specific boolean literal node, `true` and `false` are identifiers.
		return &ast.BadExpr{}
	}
}
