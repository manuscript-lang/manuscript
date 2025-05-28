package transpiler

import (
	"go/ast"
	"go/token"
	mast "manuscript-lang/manuscript/internal/ast"
	"strconv"
	"strings"
)

// VisitObjectField transpiles object field declarations
func (t *GoTranspiler) VisitObjectField(node *mast.ObjectField) ast.Node {
	if node == nil {
		return nil
	}

	// Get the field name
	var keyExpr ast.Expr
	if node.Name != nil {
		nameResult := t.Visit(node.Name)
		if ident, ok := nameResult.(*ast.Ident); ok {
			keyExpr = &ast.BasicLit{
				Kind:  token.STRING,
				Value: strconv.Quote(ident.Name),
			}
		} else if str, ok := nameResult.(*ast.BasicLit); ok && str.Kind == token.STRING {
			keyExpr = str
		} else {
			keyExpr = &ast.BasicLit{
				Kind:  token.STRING,
				Value: `"unknown"`,
			}
		}
	} else {
		keyExpr = &ast.BasicLit{
			Kind:  token.STRING,
			Value: `"unknown"`,
		}
	}

	// Get the field value
	var valueExpr ast.Expr
	if node.Value != nil {
		valueResult := t.Visit(node.Value)
		if expr, ok := valueResult.(ast.Expr); ok {
			valueExpr = expr
		} else {
			valueExpr = &ast.Ident{Name: "nil"}
		}
	} else {
		// Shorthand property - use the key name as value
		if basicLit, ok := keyExpr.(*ast.BasicLit); ok {
			if unquoted, err := strconv.Unquote(basicLit.Value); err == nil {
				valueExpr = &ast.Ident{Name: t.generateVarName(unquoted)}
			} else {
				valueExpr = &ast.Ident{Name: "nil"}
			}
		} else {
			valueExpr = &ast.Ident{Name: "nil"}
		}
	}

	return &ast.KeyValueExpr{
		Key:   keyExpr,
		Value: valueExpr,
	}
}

// VisitMapField transpiles map field declarations
func (t *GoTranspiler) VisitMapField(node *mast.MapField) ast.Node {
	if node == nil {
		return nil
	}

	var keyExpr, valueExpr ast.Expr

	if node.Key != nil {
		keyResult := t.Visit(node.Key)
		if expr, ok := keyResult.(ast.Expr); ok {
			keyExpr = expr
		} else {
			keyExpr = &ast.Ident{Name: "nil"}
		}
	} else {
		keyExpr = &ast.Ident{Name: "nil"}
	}

	if node.Value != nil {
		valueResult := t.Visit(node.Value)
		if expr, ok := valueResult.(ast.Expr); ok {
			valueExpr = expr
		} else {
			valueExpr = &ast.Ident{Name: "nil"}
		}
	} else {
		valueExpr = &ast.Ident{Name: "nil"}
	}

	return &ast.KeyValueExpr{
		Key:   keyExpr,
		Value: valueExpr,
	}
}

// VisitObjectFieldID transpiles object field IDs
func (t *GoTranspiler) VisitObjectFieldID(node *mast.ObjectFieldID) ast.Node {
	if node == nil || node.Name == "" {
		return &ast.Ident{Name: "unknown"}
	}

	return &ast.Ident{Name: t.generateVarName(node.Name)}
}

// VisitObjectFieldString transpiles object field string declarations
func (t *GoTranspiler) VisitObjectFieldString(node *mast.ObjectFieldString) ast.Node {
	if node == nil {
		return nil
	}

	// Visit the string literal and return it
	if node.Literal != nil {
		return t.Visit(node.Literal)
	}

	// Fallback to empty string
	return &ast.BasicLit{
		Kind:  token.STRING,
		Value: `""`,
	}
}

// VisitStructField transpiles struct fields
func (t *GoTranspiler) VisitStructField(node *mast.StructField) ast.Node {
	if node == nil {
		return &ast.KeyValueExpr{
			Key:   &ast.Ident{Name: "unknown"},
			Value: &ast.Ident{Name: "nil"},
		}
	}

	// Get field name
	var keyExpr ast.Expr
	if node.Name != "" {
		keyExpr = &ast.Ident{Name: t.generateVarName(node.Name)}
	} else {
		keyExpr = &ast.Ident{Name: "unknown"}
	}

	// Get field value
	var valueExpr ast.Expr
	if node.Value != nil {
		valueResult := t.Visit(node.Value)
		if expr, ok := valueResult.(ast.Expr); ok {
			valueExpr = expr
		} else {
			valueExpr = &ast.Ident{Name: "nil"}
		}
	} else {
		valueExpr = &ast.Ident{Name: "nil"}
	}

	return &ast.KeyValueExpr{
		Key:   keyExpr,
		Value: valueExpr,
	}
}

// VisitStructInitExpr transpiles struct initialization expressions
func (t *GoTranspiler) VisitStructInitExpr(node *mast.StructInitExpr) ast.Node {
	if node == nil {
		return &ast.Ident{Name: "nil"}
	}

	// Get the struct type from the name
	var structType ast.Expr
	if node.Name != "" {
		structType = &ast.Ident{Name: t.generateVarName(node.Name)}
	} else {
		structType = &ast.Ident{Name: "interface{}"}
	}

	// Build field list
	var fields []ast.Expr
	for _, field := range node.Fields {
		fieldResult := t.Visit(&field)
		if keyValueExpr, ok := fieldResult.(*ast.KeyValueExpr); ok {
			fields = append(fields, keyValueExpr)
		}
	}

	return &ast.CompositeLit{
		Type: structType,
		Elts: fields,
	}
}

// VisitTypedObjectLiteral transpiles typed object literals to Go pointer assignments
func (t *GoTranspiler) VisitTypedObjectLiteral(node *mast.TypedObjectLiteral) ast.Node {
	if node == nil {
		return &ast.Ident{Name: "nil"}
	}

	structType := t.getStructType(node.Name)
	fields := t.buildStructFields(node.Fields)

	return &ast.UnaryExpr{
		Op: token.AND,
		X: &ast.CompositeLit{
			Type: structType,
			Elts: fields,
		},
	}
}

// getStructType returns the struct type expression for the given name
func (t *GoTranspiler) getStructType(name string) ast.Expr {
	if name != "" {
		return &ast.Ident{Name: t.generateVarName(name)}
	}
	return &ast.Ident{Name: "interface{}"}
}

// buildStructFields converts object fields to struct field expressions
func (t *GoTranspiler) buildStructFields(fields []mast.ObjectField) []ast.Expr {
	var result []ast.Expr
	for _, field := range fields {
		keyExpr := t.getFieldKey(field.Name)
		valueExpr := t.getFieldValue(field.Value, keyExpr)

		result = append(result, &ast.KeyValueExpr{
			Key:   keyExpr,
			Value: valueExpr,
		})
	}
	return result
}

// getFieldKey extracts the field key as an unquoted identifier
func (t *GoTranspiler) getFieldKey(name mast.Node) ast.Expr {
	if name == nil {
		return &ast.Ident{Name: "unknown"}
	}

	nameResult := t.Visit(name)

	if ident, ok := nameResult.(*ast.Ident); ok {
		return &ast.Ident{Name: ident.Name}
	}

	if str, ok := nameResult.(*ast.BasicLit); ok && str.Kind == token.STRING {
		if unquoted, err := strconv.Unquote(str.Value); err == nil {
			return &ast.Ident{Name: unquoted}
		}
	}

	return &ast.Ident{Name: "unknown"}
}

// getFieldValue gets the field value expression, handling shorthand properties
func (t *GoTranspiler) getFieldValue(value mast.Node, keyExpr ast.Expr) ast.Expr {
	if value != nil {
		if valueResult := t.Visit(value); valueResult != nil {
			if expr, ok := valueResult.(ast.Expr); ok {
				return expr
			}
		}
		return &ast.Ident{Name: "nil"}
	}

	// Shorthand property - use the key name as value
	if ident, ok := keyExpr.(*ast.Ident); ok {
		return &ast.Ident{Name: t.generateVarName(ident.Name)}
	}

	return &ast.Ident{Name: "nil"}
}

// VisitStringContent transpiles string content
func (t *GoTranspiler) VisitStringContent(node *mast.StringContent) ast.Node {
	if node == nil || node.Content == "" {
		return &ast.BasicLit{Kind: token.STRING, Value: `""`}
	}

	return &ast.BasicLit{
		Kind:  token.STRING,
		Value: strconv.Quote(node.Content),
	}
}

// VisitStringInterpolation transpiles string interpolation
func (t *GoTranspiler) VisitStringInterpolation(node *mast.StringInterpolation) ast.Node {
	if node == nil {
		return &ast.BasicLit{Kind: token.STRING, Value: `""`}
	}

	// Convert string interpolation to fmt.Sprintf call with the expression
	if node.Expr != nil {
		exprResult := t.Visit(node.Expr)
		if goExpr, ok := exprResult.(ast.Expr); ok {
			// Create fmt.Sprintf("%v", expr)
			return &ast.CallExpr{
				Fun: &ast.SelectorExpr{
					X:   &ast.Ident{Name: "fmt"},
					Sel: &ast.Ident{Name: "Sprintf"},
				},
				Args: []ast.Expr{
					&ast.BasicLit{Kind: token.STRING, Value: `"%v"`},
					goExpr,
				},
			}
		}
	}

	return &ast.BasicLit{Kind: token.STRING, Value: `""`}
}

// VisitStringLiteral transpiles string literals
func (t *GoTranspiler) VisitStringLiteral(node *mast.StringLiteral) ast.Node {
	if node == nil {
		return &ast.BasicLit{Kind: token.STRING, Value: `""`}
	}

	// For simple strings, concatenate all parts
	var parts []string
	for _, part := range node.Parts {
		if content, ok := part.(*mast.StringContent); ok {
			parts = append(parts, content.Content)
		}
	}

	result := strings.Join(parts, "")
	literal := &ast.BasicLit{
		Kind:     token.STRING,
		Value:    strconv.Quote(result),
		ValuePos: t.pos(node),
	}

	t.registerNodeMapping(literal, node)
	return literal
}

// VisitNumberLiteral transpiles number literals
func (t *GoTranspiler) VisitNumberLiteral(node *mast.NumberLiteral) ast.Node {
	if node == nil {
		return &ast.BasicLit{Kind: token.INT, Value: "0"}
	}

	// Determine the kind based on the string value
	kind := token.INT
	if node.Kind == mast.Float {
		kind = token.FLOAT
	}

	literal := &ast.BasicLit{
		Kind:     kind,
		Value:    node.Value,
		ValuePos: t.pos(node),
	}

	t.registerNodeMapping(literal, node)
	return literal
}

// VisitBooleanLiteral transpiles boolean literals
func (t *GoTranspiler) VisitBooleanLiteral(node *mast.BooleanLiteral) ast.Node {
	if node == nil {
		return &ast.Ident{Name: "false"}
	}

	name := "false"
	if node.Value {
		name = "true"
	}

	ident := &ast.Ident{
		Name:    name,
		NamePos: t.pos(node),
	}

	t.registerNodeMapping(ident, node)
	return ident
}

// VisitNullLiteral transpiles null literals
func (t *GoTranspiler) VisitNullLiteral(node *mast.NullLiteral) ast.Node {
	ident := &ast.Ident{
		Name:    "nil",
		NamePos: t.pos(node),
	}

	t.registerNodeMapping(ident, node)
	return ident
}

// VisitVoidLiteral transpiles void literals
func (t *GoTranspiler) VisitVoidLiteral(node *mast.VoidLiteral) ast.Node {
	ident := &ast.Ident{
		Name:    "nil",
		NamePos: t.pos(node),
	}

	t.registerNodeMapping(ident, node)
	return ident
}

// VisitArrayLiteral transpiles array literals
func (t *GoTranspiler) VisitArrayLiteral(node *mast.ArrayLiteral) ast.Node {
	if node == nil {
		return &ast.CompositeLit{
			Type: &ast.ArrayType{Elt: &ast.Ident{Name: "interface{}"}},
		}
	}

	var elements []ast.Expr
	for _, elem := range node.Elements {
		if elem == nil {
			continue
		}

		elemResult := t.Visit(elem)
		if elemExpr, ok := elemResult.(ast.Expr); ok {
			elements = append(elements, elemExpr)
		}
	}

	literal := &ast.CompositeLit{
		Type: &ast.ArrayType{
			Elt: &ast.Ident{Name: "interface{}"},
		},
		Lbrace: t.pos(node),
		Elts:   elements,
	}

	t.registerNodeMapping(literal, node)
	return literal
}

// VisitObjectLiteral transpiles object literals to Go structs
func (t *GoTranspiler) VisitObjectLiteral(node *mast.ObjectLiteral) ast.Node {
	if node == nil {
		return &ast.CompositeLit{
			Type: &ast.MapType{
				Key:   &ast.Ident{Name: "string"},
				Value: &ast.Ident{Name: "interface{}"},
			},
		}
	}

	var fields []ast.Expr
	for _, prop := range node.Fields {
		propResult := t.Visit(&prop)
		if propExpr, ok := propResult.(ast.Expr); ok {
			fields = append(fields, propExpr)
		}
	}

	literal := &ast.CompositeLit{
		Type: &ast.MapType{
			Key:   &ast.Ident{Name: "string"},
			Value: &ast.Ident{Name: "interface{}"},
		},
		Lbrace: t.pos(node),
		Elts:   fields,
	}

	t.registerNodeMapping(literal, node)
	return literal
}

// VisitMapLiteral transpiles map literals
func (t *GoTranspiler) VisitMapLiteral(node *mast.MapLiteral) ast.Node {
	if node == nil {
		return &ast.CompositeLit{
			Type: &ast.MapType{
				Key:   &ast.Ident{Name: "interface{}"},
				Value: &ast.Ident{Name: "interface{}"},
			},
		}
	}

	var elements []ast.Expr
	for _, pair := range node.Fields {
		pairResult := t.Visit(&pair)
		if pairExpr, ok := pairResult.(ast.Expr); ok {
			elements = append(elements, pairExpr)
		}
	}

	literal := &ast.CompositeLit{
		Type: &ast.MapType{
			Key:   &ast.Ident{Name: "interface{}"},
			Value: &ast.Ident{Name: "interface{}"},
		},
		Elts: elements,
	}

	t.registerNodeMapping(literal, node)
	return literal
}

// VisitSetLiteral transpiles set literals to Go maps
func (t *GoTranspiler) VisitSetLiteral(node *mast.SetLiteral) ast.Node {
	if node == nil {
		return &ast.CompositeLit{
			Type: &ast.MapType{
				Key:   &ast.Ident{Name: "interface{}"},
				Value: &ast.Ident{Name: "bool"},
			},
		}
	}

	var elements []ast.Expr
	for _, elem := range node.Elements {
		if elem == nil {
			continue
		}

		elemResult := t.Visit(elem)
		if elemExpr, ok := elemResult.(ast.Expr); ok {
			// For sets, create key-value pairs where value is true
			elements = append(elements, &ast.KeyValueExpr{
				Key:   elemExpr,
				Value: &ast.Ident{Name: "true"},
			})
		}
	}

	literal := &ast.CompositeLit{
		Type: &ast.MapType{
			Key:   &ast.Ident{Name: "interface{}"},
			Value: &ast.Ident{Name: "bool"},
		},
		Elts: elements,
	}

	t.registerNodeMapping(literal, node)
	return literal
}
