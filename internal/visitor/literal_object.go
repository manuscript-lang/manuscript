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

	for _, fieldInterface := range ctx.ObjectFieldList().AllObjectField() {
		fieldCtx, ok := fieldInterface.(*parser.ObjectFieldContext)
		if !ok {

			continue
		}

		var keyStringValue string
		var valueAstExpr ast.Expr
		var keyErrorToken antlr.Token

		keyNameCtx := fieldCtx.ObjectFieldName()
		if keyNameCtx == nil {
			v.addError("Object field is missing a name/key part", fieldCtx.GetStart())
			continue
		}

		if idNode := keyNameCtx.ID(); idNode != nil {
			keyStringValue = idNode.GetText()
			keyErrorToken = idNode.GetSymbol()
		} else if strLitCtx := keyNameCtx.StringLiteral(); strLitCtx != nil {
			rawStrKey := strLitCtx.GetText()
			unquotedKey, err := strconv.Unquote(rawStrKey)
			if err != nil {
				v.addError("Invalid string literal for object key: "+rawStrKey, strLitCtx.GetStart())
				keyStringValue = rawStrKey // Fallback
			} else {
				keyStringValue = unquotedKey
			}
			keyErrorToken = strLitCtx.GetStart()
		} else {
			v.addError("Object field key is neither an ID nor a String: "+keyNameCtx.GetText(), keyNameCtx.GetStart())
			continue
		}

		// Check for shorthand { key } vs. explicit { key value }
		if fieldCtx.Expr() != nil { // Explicit key: value
			valResult := v.Visit(fieldCtx.Expr())
			if valExpr, okVal := valResult.(ast.Expr); okVal {
				valueAstExpr = valExpr
			} else {
				v.addError("Object field value is not a valid expression: "+fieldCtx.Expr().GetText(), fieldCtx.Expr().GetStart())
				valueAstExpr = &ast.BadExpr{From: v.pos(fieldCtx.Expr().GetStart()), To: v.pos(fieldCtx.Expr().GetStop())}
			}
		} else { // Shorthand: { key }
			// Value is the identifier itself if the key was a simple ID
			if keyNameCtx.ID() != nil { // Ensure key was an ID for shorthand value
				valueAstExpr = ast.NewIdent(keyStringValue)
			} else {
				// Shorthand like { "string-key" } is not valid, value cannot be derived.
				v.addError(fmt.Sprintf("Object shorthand field key '%s' must be a simple identifier, not a string, to automatically derive its value.", keyStringValue), keyErrorToken)
				valueAstExpr = &ast.BadExpr{From: v.pos(keyErrorToken), To: v.pos(keyErrorToken)}
			}
		}

		astKey := &ast.BasicLit{
			Kind:  token.STRING,
			Value: strconv.Quote(keyStringValue),
		}

		elements = append(elements, &ast.KeyValueExpr{
			Key:   astKey,
			Value: valueAstExpr,
		})
	}

	return &ast.CompositeLit{
		Type:   mapType,
		Lbrace: v.pos(startToken.GetSymbol()),
		Elts:   elements,
		Rbrace: v.pos(stopToken.GetSymbol()),
	}
}
