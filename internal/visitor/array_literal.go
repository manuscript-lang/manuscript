package visitor

import (
	"go/ast"
	"manuscript-co/manuscript/internal/parser"
)

// VisitArrayLiteral handles array literal expressions like [1, 2, 3]
func (v *ManuscriptAstVisitor) VisitArrayLiteral(ctx *parser.ArrayLiteralContext) interface{} {
	// Get all the element expressions
	elements := make([]ast.Expr, 0)

	for _, elemCtx := range ctx.AllExpr() {
		elemResult := v.Visit(elemCtx)
		if elemExpr, ok := elemResult.(ast.Expr); ok {
			elements = append(elements, elemExpr)
		} else {
			v.addError("Array element is not a valid expression: "+elemCtx.GetText(), elemCtx.GetStart())
			// Add a nil for placeholder
			elements = append(elements, &ast.BadExpr{})
		}
	}

	// Create a composite literal for the array
	// In Go, this will be a slice literal without a type
	return &ast.CompositeLit{
		Type: nil, // Type will be inferred from the elements
		Elts: elements,
	}
}

// VisitMapLiteral handles map literal expressions like [:] or [key1: value1, key2: value2]
func (v *ManuscriptAstVisitor) VisitMapLiteral(ctx *parser.MapLiteralContext) interface{} {
	// Create a map type
	mapType := &ast.MapType{
		Key:   ast.NewIdent("interface{}"), // Use interface{} as the generic key type
		Value: ast.NewIdent("interface{}"), // Use interface{} as the generic value type
	}

	// Handle empty map case
	if len(ctx.AllMapField()) == 0 {
		// Empty map literal
		return &ast.CompositeLit{
			Type: mapType,
			Elts: []ast.Expr{},
		}
	}

	// Process each map field
	elements := make([]ast.Expr, 0, len(ctx.AllMapField()))

	for _, fieldCtx := range ctx.AllMapField() {
		mapField := fieldCtx.(*parser.MapFieldContext)

		// Visit the key and value expressions
		keyResult := v.Visit(mapField.GetKey())
		keyExpr, keyOk := keyResult.(ast.Expr)

		valueResult := v.Visit(mapField.GetValue())
		valueExpr, valueOk := valueResult.(ast.Expr)

		if !keyOk || !valueOk {
			if !keyOk {
				v.addError("Map key is not a valid expression: "+mapField.GetKey().GetText(), mapField.GetKey().GetStart())
			}
			if !valueOk {
				v.addError("Map value is not a valid expression: "+mapField.GetValue().GetText(), mapField.GetValue().GetStart())
			}
			continue
		}

		// Create a key-value expression for this field
		kvExpr := &ast.KeyValueExpr{
			Key:   keyExpr,
			Value: valueExpr,
		}

		elements = append(elements, kvExpr)
	}

	// Create the map composite literal
	return &ast.CompositeLit{
		Type: mapType,
		Elts: elements,
	}
}

// VisitSetLiteral handles set literal expressions like <1, 2, 3>
// Sets don't exist natively in Go, so we'll translate them to maps with bool values
func (v *ManuscriptAstVisitor) VisitSetLiteral(ctx *parser.SetLiteralContext) interface{} {
	// Create a map[interface{}]bool type for the set
	setType := &ast.MapType{
		Key:   ast.NewIdent("interface{}"),
		Value: ast.NewIdent("bool"),
	}

	// Handle empty set case
	if len(ctx.AllExpr()) == 0 {
		// Empty set literal
		return &ast.CompositeLit{
			Type: setType,
			Elts: []ast.Expr{},
		}
	}

	// Process each set element
	elements := make([]ast.Expr, 0, len(ctx.AllExpr()))

	for _, elemCtx := range ctx.AllExpr() {
		elemResult := v.Visit(elemCtx)
		if elemExpr, ok := elemResult.(ast.Expr); ok {
			// Create a key-value pair where the key is the element and the value is true
			kvExpr := &ast.KeyValueExpr{
				Key:   elemExpr,
				Value: ast.NewIdent("true"),
			}

			elements = append(elements, kvExpr)
		} else {
			v.addError("Set element is not a valid expression: "+elemCtx.GetText(), elemCtx.GetStart())
		}
	}

	// Create the set composite literal (as a map)
	return &ast.CompositeLit{
		Type: setType,
		Elts: elements,
	}
}

// VisitTupleLiteral handles tuple literal expressions like (1, "hello", true)
// Tuples don't exist natively in Go, so we'll translate them to slices of interface{}
func (v *ManuscriptAstVisitor) VisitTupleLiteral(ctx *parser.TupleLiteralContext) interface{} {
	// Create a []interface{} type for the tuple
	tupleType := &ast.ArrayType{
		Elt: ast.NewIdent("interface{}"),
	}

	// Process each tuple element
	elements := make([]ast.Expr, 0, len(ctx.AllExpr()))

	for _, elemCtx := range ctx.AllExpr() {
		elemResult := v.Visit(elemCtx)
		if elemExpr, ok := elemResult.(ast.Expr); ok {
			elements = append(elements, elemExpr)
		} else {
			v.addError("Tuple element is not a valid expression: "+elemCtx.GetText(), elemCtx.GetStart())
			// Add a nil for placeholder
			elements = append(elements, &ast.BadExpr{})
		}
	}

	// Create the tuple composite literal (as a slice)
	return &ast.CompositeLit{
		Type: tupleType,
		Elts: elements,
	}
}
