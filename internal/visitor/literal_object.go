package visitor

import (
	"fmt"
	"go/ast"
	"go/token"
	"manuscript-co/manuscript/internal/parser"
	"strconv"

	"github.com/antlr4-go/antlr/v4"
)

// VisitObjectLiteral handles object literal expressions like { key1: value1, key2, "string-key": value3 }
// It translates them to Go's `map[string]interface{}`.
func (v *ManuscriptAstVisitor) VisitObjectLiteral(ctx *parser.ObjectLiteralContext) interface{} {
	mapType := &ast.MapType{
		Key:   ast.NewIdent("string"),
		Value: ast.NewIdent("interface{}"),
	}

	elements := make([]ast.Expr, 0)
	startToken := ctx.LBRACE()
	stopToken := ctx.RBRACE()

	if startToken == nil || stopToken == nil {
		v.addError("Object literal is missing braces", ctx.GetStart())
		return &ast.BadExpr{From: v.pos(ctx.GetStart()), To: v.pos(ctx.GetStop())}
	}

	fieldList := ctx.ObjectFieldList()
	if fieldList != nil {
		for _, fieldInterface := range fieldList.AllObjectField() {
			fieldCtx, ok := fieldInterface.(*parser.ObjectFieldContext)
			if !ok || fieldCtx == nil {
				continue
			}

			key, keyToken, keyIsIdent := v.extractObjectFieldKey(fieldCtx.ObjectFieldName())
			if key == "" {
				// Error already reported in extractObjectFieldKey
				continue
			}

			var valueAstExpr ast.Expr
			if fieldCtx.Expr() != nil { // Explicit key: value
				valResult := v.Visit(fieldCtx.Expr())
				if valExpr, okVal := valResult.(ast.Expr); okVal {
					valueAstExpr = valExpr
				} else {
					v.addError("Object field value is not a valid expression: "+fieldCtx.Expr().GetText(), fieldCtx.Expr().GetStart())
					valueAstExpr = &ast.BadExpr{From: v.pos(fieldCtx.Expr().GetStart()), To: v.pos(fieldCtx.Expr().GetStop())}
				}
			} else if keyIsIdent {
				// Shorthand: { key }
				valueAstExpr = ast.NewIdent(key)
			} else {
				// Shorthand like { "string-key" } is not valid
				v.addError(fmt.Sprintf("Object shorthand field key '%s' must be a simple identifier, not a string, to automatically derive its value.", key), keyToken)
				valueAstExpr = &ast.BadExpr{From: v.pos(keyToken), To: v.pos(keyToken)}
			}

			astKey := &ast.BasicLit{
				Kind:  token.STRING,
				Value: strconv.Quote(key),
			}
			elements = append(elements, &ast.KeyValueExpr{
				Key:   astKey,
				Value: valueAstExpr,
			})
		}
	}

	return &ast.CompositeLit{
		Type:   mapType,
		Lbrace: v.pos(startToken.GetSymbol()),
		Elts:   elements,
		Rbrace: v.pos(stopToken.GetSymbol()),
	}
}

// extractObjectFieldKey extracts the key string and token from an ObjectFieldName context using the visitor pattern.
// Returns (key, token, isIdent) where isIdent is true if the key is an identifier.
func (v *ManuscriptAstVisitor) extractObjectFieldKey(ctx parser.IObjectFieldNameContext) (string, antlr.Token, bool) {
	switch c := ctx.(type) {
	case *parser.LabelObjectFieldNameIDContext:
		if c.ID() != nil {
			return c.ID().GetText(), c.ID().GetSymbol(), true
		}
		v.addError("Object field ID is missing", c.GetStart())
		return "", c.GetStart(), false
	case *parser.LabelObjectFieldNameStrContext:
		if c.StringLiteral() != nil {
			// Use the string literal visitor to get the Go string value
			val := v.Visit(c.StringLiteral())
			if basicLit, ok := val.(*ast.BasicLit); ok {
				unquoted, err := strconv.Unquote(basicLit.Value)
				if err != nil {
					v.addError("Invalid string literal for object key: "+basicLit.Value, c.StringLiteral().GetStart())
					return basicLit.Value, c.StringLiteral().GetStart(), false
				}
				return unquoted, c.StringLiteral().GetStart(), false
			}
			v.addError("String literal did not resolve to a Go string", c.StringLiteral().GetStart())
			return c.StringLiteral().GetText(), c.StringLiteral().GetStart(), false
		}
		v.addError("Object field string literal is missing", c.GetStart())
		return "", c.GetStart(), false
	default:
		v.addError("Unknown object field name context type", ctx.GetStart())
		return "", ctx.GetStart(), false
	}
}
