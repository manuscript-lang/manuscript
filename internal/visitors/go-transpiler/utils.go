package transpiler

import (
	"fmt"
	"go/ast"

	mast "manuscript-lang/manuscript/internal/ast"
)

// VisitParameter transpiles function parameters
func (t *GoTranspiler) VisitParameter(node *mast.Parameter) ast.Node {
	if node == nil || node.Name == "" {
		t.addError("invalid parameter", node)
		return nil
	}

	var paramType ast.Expr
	if node.Type != nil {
		typeResult := t.Visit(node.Type)
		if typeExpr, ok := typeResult.(ast.Expr); ok {
			paramType = typeExpr
		} else {
			paramType = &ast.Ident{Name: "interface{}"}
		}
	} else {
		paramType = &ast.Ident{Name: "interface{}"}
	}

	field := &ast.Field{
		Names: []*ast.Ident{{Name: t.generateVarName(node.Name)}},
		Type:  paramType,
	}

	t.registerNodeMapping(field, node)
	return field
}

// VisitInterfaceMethod transpiles interface method declarations
func (t *GoTranspiler) VisitInterfaceMethod(node *mast.InterfaceMethod) ast.Node {
	if node == nil || node.Name == "" {
		t.addError("invalid interface method", node)
		return nil
	}

	// Build parameter list
	var params []*ast.Field
	for i := range node.Parameters {
		param := &node.Parameters[i]
		field := t.Visit(param)
		if astField, ok := field.(*ast.Field); ok {
			params = append(params, astField)
		}
	}

	// Build return type
	var results *ast.FieldList
	if node.ReturnType != nil {
		// Check if the return type is void
		if typeSpec, ok := node.ReturnType.(*mast.TypeSpec); ok && typeSpec.Kind == mast.VoidType {
			// For void return types, don't set any return type (results remains nil)
		} else {
			returnType := t.Visit(node.ReturnType)
			if returnExpr, ok := returnType.(ast.Expr); ok {
				results = &ast.FieldList{
					List: []*ast.Field{{Type: returnExpr}},
				}
			}
		}
	}

	// Handle error return if method can throw
	if node.CanThrow {
		errorField := &ast.Field{
			Type: &ast.Ident{Name: "error"},
		}
		if results == nil {
			results = &ast.FieldList{List: []*ast.Field{errorField}}
		} else {
			results.List = append(results.List, errorField)
		}
	}

	field := &ast.Field{
		Names: []*ast.Ident{{Name: t.generateVarName(node.Name)}},
		Type: &ast.FuncType{
			Params:  &ast.FieldList{List: params},
			Results: results,
		},
	}

	t.registerNodeMapping(field, node)
	return field
}

// VisitTypedID transpiles typed identifiers
func (t *GoTranspiler) VisitTypedID(node *mast.TypedID) ast.Node {
	if node == nil {
		return nil
	}

	// This is typically used in parameter/variable contexts
	// Return the identifier name for now
	ident := &ast.Ident{Name: t.generateVarName(node.Name)}

	t.registerNodeMapping(ident, node)
	return ident
}

// VisitTypeSpec transpiles type specifications
func (t *GoTranspiler) VisitTypeSpec(node *mast.TypeSpec) ast.Node {
	if node == nil {
		return &ast.Ident{Name: "interface{}"}
	}

	switch node.Kind {
	case mast.SimpleType:
		// Map manuscript types to Go types
		switch node.Name {
		case "int":
			return &ast.Ident{Name: "int"}
		case "float":
			return &ast.Ident{Name: "float64"}
		case "string":
			return &ast.Ident{Name: "string"}
		case "bool":
			return &ast.Ident{Name: "bool"}
		case "void":
			// Void type doesn't exist in Go, but we shouldn't hit this in a type context
			return &ast.Ident{Name: "interface{}"}
		default:
			// User-defined types or unknown types
			return &ast.Ident{Name: t.generateVarName(node.Name)}
		}

	case mast.ArrayType:
		// Handle array types
		if node.ElementType != nil {
			elemTypeResult := t.Visit(node.ElementType)
			if elemType, ok := elemTypeResult.(ast.Expr); ok {
				return &ast.ArrayType{
					Elt: elemType,
				}
			}
		}
		return &ast.ArrayType{
			Elt: &ast.Ident{Name: "interface{}"},
		}

	case mast.FunctionType:
		// Handle function types
		var params []*ast.Field
		for i := range node.Parameters {
			param := &node.Parameters[i]
			paramResult := t.Visit(param)
			if field, ok := paramResult.(*ast.Field); ok {
				params = append(params, field)
			}
		}

		var results *ast.FieldList
		if node.ReturnType != nil {
			returnTypeResult := t.Visit(node.ReturnType)
			if returnType, ok := returnTypeResult.(ast.Expr); ok {
				results = &ast.FieldList{
					List: []*ast.Field{{Type: returnType}},
				}
			}
		}

		return &ast.FuncType{
			Params:  &ast.FieldList{List: params},
			Results: results,
		}

	case mast.TupleType:
		// Handle tuple types - in Go, we use structs with numbered fields
		var fields []*ast.Field
		for i, elemType := range node.ElementTypes {
			elemTypeResult := t.Visit(elemType)
			if goType, ok := elemTypeResult.(ast.Expr); ok {
				fieldName := fmt.Sprintf("Field%d", i+1)
				fields = append(fields, &ast.Field{
					Names: []*ast.Ident{{Name: fieldName}},
					Type:  goType,
				})
			}
		}

		return &ast.StructType{
			Fields: &ast.FieldList{List: fields},
		}

	case mast.VoidType:
		// Void type in Go is represented as no return type
		return &ast.Ident{Name: "interface{}"}

	default:
		return &ast.Ident{Name: "interface{}"}
	}
}

// VisitTypeDefBody transpiles type definition bodies
func (t *GoTranspiler) VisitTypeDefBody(node *mast.TypeDefBody) ast.Node {
	if node == nil {
		return &ast.StructType{Fields: &ast.FieldList{}}
	}

	var fields []*ast.Field
	for _, fieldDecl := range node.Fields {
		fieldResult := t.Visit(&fieldDecl)
		if field, ok := fieldResult.(*ast.Field); ok {
			fields = append(fields, field)
		}
	}

	return &ast.StructType{
		Fields: &ast.FieldList{List: fields},
	}
}

// VisitTypeAlias transpiles type aliases
func (t *GoTranspiler) VisitTypeAlias(node *mast.TypeAlias) ast.Node {
	if node == nil {
		return &ast.Ident{Name: "interface{}"}
	}

	if node.Type != nil {
		return t.Visit(node.Type)
	}

	return &ast.Ident{Name: "interface{}"}
}

// VisitMethodImpl transpiles method implementations
func (t *GoTranspiler) VisitMethodImpl(node *mast.MethodImpl) ast.Node {
	if node == nil || node.Name == "" {
		t.addError("invalid method implementation", node)
		return nil
	}

	// Build parameter list
	var params []*ast.Field
	for i := range node.Parameters {
		param := &node.Parameters[i]
		field := t.Visit(param)
		if astField, ok := field.(*ast.Field); ok {
			params = append(params, astField)
		}
	}

	// Build return type
	var results *ast.FieldList
	if node.ReturnType != nil {
		returnType := t.Visit(node.ReturnType)
		if returnExpr, ok := returnType.(ast.Expr); ok {
			results = &ast.FieldList{
				List: []*ast.Field{{Type: returnExpr}},
			}
		}
	}

	// Handle error return if method can throw
	if node.CanThrow {
		errorField := &ast.Field{
			Type: &ast.Ident{Name: "error"},
		}
		if results == nil {
			results = &ast.FieldList{List: []*ast.Field{errorField}}
		} else {
			results.List = append(results.List, errorField)
		}
	}

	// Build method body
	var body *ast.BlockStmt
	if node.Body != nil {
		bodyResult := t.Visit(node.Body)
		if blockStmt, ok := bodyResult.(*ast.BlockStmt); ok {
			body = blockStmt
		} else {
			body = &ast.BlockStmt{List: []ast.Stmt{}}
		}
	} else {
		body = &ast.BlockStmt{List: []ast.Stmt{}}
	}

	// Methods should always have implicit returns for last expressions
	t.ensureLastExprIsReturn(body)

	// For method implementations, we return a function declaration
	// The receiver will be handled by the parent MethodsDecl
	return &ast.FuncDecl{
		Name: &ast.Ident{Name: t.generateVarName(node.Name)},
		Type: &ast.FuncType{
			Params:  &ast.FieldList{List: params},
			Results: results,
		},
		Body: body,
	}
}
