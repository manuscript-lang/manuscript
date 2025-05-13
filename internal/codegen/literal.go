package codegen

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
	// VOID and NULL are likely terminals within LiteralContext
	if ctx.VOID() != nil {
		// Map Manuscript's `void` to Go's `nil`
		return ast.NewIdent("nil")
	}
	if ctx.NULL() != nil {
		// Map Manuscript's `null` to Go's `nil`
		return ast.NewIdent("nil")
	}
	// TODO: Handle ArrayLiteral and ObjectLiteral when implemented

	log.Printf("Warning: Unhandled literal type in VisitLiteral: %s", ctx.GetText())
	return nil
}

// VisitNumberLiteral converts a number literal context to an ast.BasicLit.
func (v *ManuscriptAstVisitor) VisitNumberLiteral(ctx *parser.NumberLiteralContext) interface{} {
	text := ctx.GetText()
	log.Printf("VisitNumberLiteral: Processing '%s'", text)

	// Check explicit token types first
	if ctx.INTEGER() != nil {
		intText := ctx.INTEGER().GetText()
		log.Printf("VisitNumberLiteral: Found INTEGER token with value '%s'", intText)
		return &ast.BasicLit{
			Kind:  token.INT,
			Value: intText,
		}
	}

	if ctx.FLOAT() != nil {
		floatText := ctx.FLOAT().GetText()
		log.Printf("VisitNumberLiteral: Found FLOAT token with value '%s'", floatText)
		return &ast.BasicLit{
			Kind:  token.FLOAT,
			Value: floatText,
		}
	}

	if ctx.HEX_LITERAL() != nil {
		hexText := ctx.HEX_LITERAL().GetText()
		log.Printf("VisitNumberLiteral: Found HEX_LITERAL token with value '%s'", hexText)
		return &ast.BasicLit{
			Kind:  token.INT,
			Value: hexText,
		}
	}

	if ctx.BINARY_LITERAL() != nil {
		binText := ctx.BINARY_LITERAL().GetText()
		log.Printf("VisitNumberLiteral: Found BINARY_LITERAL token with value '%s'", binText)
		return &ast.BasicLit{
			Kind:  token.INT,
			Value: binText,
		}
	}

	// If no specific token detected, try to infer the type from the text
	// This is a fallback mechanism in case the lexer doesn't properly tokenize
	if text != "" {
		log.Printf("VisitNumberLiteral: No specific token found, inferring type from text '%s'", text)
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

	log.Printf("Error: Failed to parse number literal: %s", text)
	return &ast.BasicLit{
		Kind:  token.INT,
		Value: "0", // Default to 0 to avoid compiler errors
	}
}

// VisitStringLiteral converts a string literal context to an ast.BasicLit.
func (v *ManuscriptAstVisitor) VisitStringLiteral(ctx *parser.StringLiteralContext) interface{} {
	text := ctx.GetText()
	log.Printf("VisitStringLiteral: Processing '%s'", text)

	// Extract string content regardless of quote style
	if ctx.SingleQuotedString() != nil {
		// Handle single-quoted string - need to convert to double-quoted for Go
		content := ""

		// Extract content between the quotes
		if parts := ctx.SingleQuotedString().AllStringPart(); len(parts) > 0 {
			for _, part := range parts {
				if strContent := part.SINGLE_STR_CONTENT(); strContent != nil {
					content += strContent.GetText()
				}
			}
		}

		// Convert to Go string with double quotes
		goStr := strconv.Quote(content)
		log.Printf("VisitStringLiteral: Converted single-quoted '%s' to double-quoted %s", text, goStr)
		return &ast.BasicLit{
			Kind:  token.STRING,
			Value: goStr,
		}
	} else if ctx.MultiQuotedString() != nil {
		// Handle multi-quoted string (similar approach)
		content := ""

		// Extract content between triple quotes
		if parts := ctx.MultiQuotedString().AllStringPart(); len(parts) > 0 {
			for _, part := range parts {
				if strContent := part.MULTI_STR_CONTENT(); strContent != nil {
					content += strContent.GetText()
				}
			}
		}

		// Convert to Go string with double quotes
		goStr := strconv.Quote(content)
		log.Printf("VisitStringLiteral: Converted multi-quoted '%s' to double-quoted %s", text, goStr)
		return &ast.BasicLit{
			Kind:  token.STRING,
			Value: goStr,
		}
	}

	log.Printf("Warning: Malformed string literal detected: %s", text)
	return &ast.BadExpr{}
}

// VisitBooleanLiteral converts a boolean literal context to an ast.Ident (true/false).
func (v *ManuscriptAstVisitor) VisitBooleanLiteral(ctx *parser.BooleanLiteralContext) interface{} {
	text := ctx.GetText()
	if text == "true" {
		return ast.NewIdent("true")
	} else if text == "false" {
		return ast.NewIdent("false")
	} else {
		log.Printf("Warning: Unrecognized boolean literal: %s", text)
		// Go doesn't have a specific boolean literal node, `true` and `false` are identifiers.
		// Return BadExpr on error
		return &ast.BadExpr{}
	}
}
