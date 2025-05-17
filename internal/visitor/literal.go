package visitor

import (
	"go/ast"
	"go/token"
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
	v.addError("Unhandled literal type: "+ctx.GetText(), ctx.GetStart())
	return &ast.BadExpr{}
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
		// Ensure Go compatibility for float literals (e.g., no suffix 'f')
		// strconv.ParseFloat will handle this appropriately.
		// The raw text is usually fine for ast.BasicLit if it's a valid Go float.
		return &ast.BasicLit{
			Kind:  token.FLOAT,
			Value: floatText,
		}
	}

	if ctx.HEX_LITERAL() != nil {
		hexText := ctx.HEX_LITERAL().GetText()
		return &ast.BasicLit{
			Kind:  token.INT, // Go handles hex literals as ints
			Value: hexText,
		}
	}

	if ctx.BINARY_LITERAL() != nil {
		binText := ctx.BINARY_LITERAL().GetText()
		return &ast.BasicLit{
			Kind:  token.INT, // Go handles binary literals as ints
			Value: binText,
		}
	}

	if ctx.OCTAL_LITERAL() != nil {
		octText := ctx.OCTAL_LITERAL().GetText()
		// Go's octal representation is 0o prefix (Go 1.13+) or 0 prefix.
		// ANTLR token already includes 0o.
		return &ast.BasicLit{
			Kind:  token.INT,
			Value: octText,
		}
	}

	// Fallback: if no specific token type was hit (should be rare if grammar is correct)
	// or if GetText() is needed for some other reason.
	text := ctx.GetText()
	if text != "" {
		// Try to infer, primarily for robustness or unexpected cases.
		// Standard integer (base 10)
		if _, err := strconv.ParseInt(text, 0, 64); err == nil { // base 0 for auto-detection (0x, 0o, 0b)
			// This path might be redundant if specific literal tokens are always caught.
			// However, ensuring it handles plain decimal numbers correctly if they somehow miss INTEGER().
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

	v.addError("Unhandled or invalid number literal: "+ctx.GetText(), ctx.GetStart())
	return &ast.BadExpr{}
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
		v.addError("No known string type found in string literal: "+ctx.GetText(), ctx.GetStart())
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
				v.addError("String interpolation is not yet supported: "+interpCtx.GetText(), interpCtx.GetStart())
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
