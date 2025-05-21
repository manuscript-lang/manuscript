package visitor

import (
	"go/ast"
	"manuscript-co/manuscript/internal/parser"
)

// VisitStructInitExpr handles struct initialization expressions.
// In Manuscript: Point(x: 1, y: 2)
// In Go: Point{x: 1, y: 2}
func (v *ManuscriptAstVisitor) VisitStructInitExpr(ctx *parser.StructInitExprContext) interface{} {
	// Validate context
	if ctx == nil {
		v.addError("VisitStructInitExpr called with nil context", nil)
		return &ast.BadExpr{}
	}

	// Get struct type name
	if ctx.ID() == nil {
		v.addError("Struct initialization missing type name", ctx.GetStart())
		return &ast.BadExpr{}
	}
	structTypeName := ctx.ID().GetText()
	structTypeExpr := ast.NewIdent(structTypeName)

	// Process field initializers
	keyValueElts := make([]ast.Expr, 0, len(ctx.AllStructField()))

	for _, fieldCtx := range ctx.AllStructField() {
		// Get field name (key)
		keyNode := fieldCtx.ID()
		if keyNode == nil {
			v.addError("Struct field missing key", fieldCtx.GetStart())
			continue
		}
		fieldName := keyNode.GetText()

		// Get field value expression
		valueCtx := fieldCtx.Expr()
		if valueCtx == nil {
			v.addError("Struct field missing value", fieldCtx.GetStart())
			continue
		}

		// Visit the value expression
		valueResult := v.Visit(valueCtx)
		valueExpr, ok := valueResult.(ast.Expr)
		if !ok {
			v.addError("Struct field value did not resolve to a valid expression", valueCtx.GetStart())
			continue
		}

		// Create key-value pair for this field
		keyValueElts = append(keyValueElts, &ast.KeyValueExpr{
			Key:   ast.NewIdent(fieldName),
			Value: valueExpr,
		})
	}

	// Return the Go AST composite literal for the struct
	return &ast.CompositeLit{
		Type: structTypeExpr,
		Elts: keyValueElts,
	}
}
