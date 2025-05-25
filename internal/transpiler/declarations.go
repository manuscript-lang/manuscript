package transpiler

import (
	"fmt"
	"go/ast"
	"go/token"
	"strings"

	msast "manuscript-co/manuscript/internal/ast"
)

// VisitImportDecl transpiles import declarations
func (t *GoTranspiler) VisitImportDecl(node *msast.ImportDecl) ast.Node {
	if node == nil || node.Import == nil {
		t.addError("invalid import declaration", nil)
		return nil
	}

	// Visit the import node
	result := t.Visit(node.Import)

	return result
}

// VisitExportDecl transpiles export declarations
func (t *GoTranspiler) VisitExportDecl(node *msast.ExportDecl) ast.Node {
	if node == nil || node.Item == nil {
		t.addError("invalid export declaration", node)
		return nil
	}

	// Visit the exported item
	result := t.Visit(node.Item)
	if result == nil {
		return nil
	}

	// Make the exported item public by capitalizing the name
	switch decl := result.(type) {
	case *ast.FuncDecl:
		if decl.Name != nil {
			decl.Name.Name = t.capitalizeForExport(decl.Name.Name)
		}
		return decl
	case *ast.GenDecl:
		// Handle type and variable declarations
		for _, spec := range decl.Specs {
			switch s := spec.(type) {
			case *ast.TypeSpec:
				if s.Name != nil {
					s.Name.Name = t.capitalizeForExport(s.Name.Name)
				}
			case *ast.ValueSpec:
				for _, name := range s.Names {
					if name != nil {
						name.Name = t.capitalizeForExport(name.Name)
					}
				}
			}
		}
		return decl
	default:
		return result
	}
}

// VisitExternDecl transpiles extern declarations (similar to imports)
func (t *GoTranspiler) VisitExternDecl(node *msast.ExternDecl) ast.Node {
	if node == nil || node.Import == nil {
		t.addError("invalid extern declaration", node)
		return nil
	}

	// Visit the module import
	t.Visit(node.Import)

	// Extern declarations are typically handled as imports in Go
	return nil
}

// VisitLetDecl transpiles let declarations to Go variable declarations or assignment statements
func (t *GoTranspiler) VisitLetDecl(node *msast.LetDecl) ast.Node {
	if node == nil {
		t.addError("received nil let declaration", nil)
		return nil
	}

	// Process all items in the let declaration
	var statements []ast.Stmt

	for _, item := range node.Items {
		result := t.Visit(item)

		// Handle different result types
		switch v := result.(type) {
		case *DestructuringBlockStmt:
			// Standalone destructuring - preserve the wrapper as a statement
			statements = append(statements, v)
		case *ast.BlockStmt:
			// Check if this is from a let block
			switch item.(type) {
			case *msast.LetBlock:
				// Let block - flatten the statements
				statements = append(statements, v.List...)
			default:
				// Other block statements - flatten
				statements = append(statements, v.List...)
			}
		case ast.Stmt:
			statements = append(statements, v)
		case nil:
			// Skip nil results
			continue
		default:
			t.addError(fmt.Sprintf("unexpected result type from let item: %T", result), item)
		}
	}

	// If we have multiple statements, return as a block
	if len(statements) > 1 {
		return &ast.BlockStmt{List: statements}
	} else if len(statements) == 1 {
		return statements[0]
	}

	return nil
}

// VisitTypeDecl transpiles type declarations
func (t *GoTranspiler) VisitTypeDecl(node *msast.TypeDecl) ast.Node {
	if node == nil || node.Name == "" {
		t.addError("invalid type declaration", node)
		return nil
	}

	// Visit the type body
	typeExpr := t.Visit(node.Body)
	if typeExpr == nil {
		t.addError("failed to transpile type body", node)
		return nil
	}

	// Convert to Go type
	var goType ast.Expr
	if expr, ok := typeExpr.(ast.Expr); ok {
		goType = expr
	} else {
		t.addError("type body did not produce valid Go type expression", node)
		return nil
	}

	typeSpec := &ast.TypeSpec{
		Name: &ast.Ident{Name: t.generateVarName(node.Name)},
		Type: goType,
	}

	return &ast.GenDecl{
		Tok:   token.TYPE,
		Specs: []ast.Spec{typeSpec},
	}
}

// VisitInterfaceDecl transpiles interface declarations
func (t *GoTranspiler) VisitInterfaceDecl(node *msast.InterfaceDecl) ast.Node {
	if node == nil || node.Name == "" {
		t.addError("invalid interface declaration", node)
		return nil
	}

	var methods []*ast.Field

	// Process interface methods
	for i := range node.Methods {
		method := &node.Methods[i]
		field := t.Visit(method)
		if astField, ok := field.(*ast.Field); ok {
			methods = append(methods, astField)
		}
	}

	interfaceType := &ast.InterfaceType{
		Methods: &ast.FieldList{List: methods},
	}

	typeSpec := &ast.TypeSpec{
		Name: &ast.Ident{Name: t.generateVarName(node.Name)},
		Type: interfaceType,
	}

	return &ast.GenDecl{
		Tok:   token.TYPE,
		Specs: []ast.Spec{typeSpec},
	}
}

// VisitFnDecl transpiles function declarations
func (t *GoTranspiler) VisitFnDecl(node *msast.FnDecl) ast.Node {
	if node == nil || node.Name == "" {
		t.addError("invalid function declaration", node)
		return nil
	}

	// Check if any parameters have default values
	hasDefaultParams := false
	for i := range node.Parameters {
		param := &node.Parameters[i]
		if param.DefaultValue != nil {
			hasDefaultParams = true
			break
		}
	}

	// Build parameter list and parameter extraction logic
	var params []*ast.Field
	var paramExtractionStmts []ast.Stmt

	if hasDefaultParams {
		// Use variadic approach for functions with default parameters
		params = []*ast.Field{{
			Names: []*ast.Ident{{Name: "args"}},
			Type: &ast.Ellipsis{
				Elt: &ast.Ident{Name: "interface{}"},
			},
		}}

		// Generate parameter extraction statements
		for i, param := range node.Parameters {
			paramName := t.generateVarName(param.Name)

			// Get parameter type
			var paramType ast.Expr
			if param.Type != nil {
				typeResult := t.Visit(param.Type)
				if typeExpr, ok := typeResult.(ast.Expr); ok {
					paramType = typeExpr
				} else {
					paramType = &ast.Ident{Name: "interface{}"}
				}
			} else {
				paramType = &ast.Ident{Name: "interface{}"}
			}

			if param.DefaultValue != nil {
				// Parameter with default value: var name Type = defaultValue
				defaultExpr := t.Visit(param.DefaultValue)
				if defaultValue, ok := defaultExpr.(ast.Expr); ok {
					// Variable declaration with default value
					varDecl := &ast.DeclStmt{
						Decl: &ast.GenDecl{
							Tok: token.VAR,
							Specs: []ast.Spec{
								&ast.ValueSpec{
									Names:  []*ast.Ident{{Name: paramName}},
									Type:   paramType,
									Values: []ast.Expr{defaultValue},
								},
							},
						},
					}
					paramExtractionStmts = append(paramExtractionStmts, varDecl)

					// Conditional assignment: if len(args) > i { name = args[i].(Type) }
					ifStmt := &ast.IfStmt{
						Cond: &ast.BinaryExpr{
							X: &ast.CallExpr{
								Fun:  &ast.Ident{Name: "len"},
								Args: []ast.Expr{&ast.Ident{Name: "args"}},
							},
							Op: token.GTR,
							Y:  &ast.BasicLit{Kind: token.INT, Value: fmt.Sprintf("%d", i)},
						},
						Body: &ast.BlockStmt{
							List: []ast.Stmt{
								&ast.AssignStmt{
									Lhs: []ast.Expr{&ast.Ident{Name: paramName}},
									Tok: token.ASSIGN,
									Rhs: []ast.Expr{
										&ast.TypeAssertExpr{
											X: &ast.IndexExpr{
												X:     &ast.Ident{Name: "args"},
												Index: &ast.BasicLit{Kind: token.INT, Value: fmt.Sprintf("%d", i)},
											},
											Type: paramType,
										},
									},
								},
							},
						},
					}
					paramExtractionStmts = append(paramExtractionStmts, ifStmt)
				}
			} else {
				// Parameter without default value: name := args[i].(Type)
				assignStmt := &ast.AssignStmt{
					Lhs: []ast.Expr{&ast.Ident{Name: paramName}},
					Tok: token.DEFINE,
					Rhs: []ast.Expr{
						&ast.TypeAssertExpr{
							X: &ast.IndexExpr{
								X:     &ast.Ident{Name: "args"},
								Index: &ast.BasicLit{Kind: token.INT, Value: fmt.Sprintf("%d", i)},
							},
							Type: paramType,
						},
					},
				}
				paramExtractionStmts = append(paramExtractionStmts, assignStmt)
			}
		}
	} else {
		// Regular parameters (no defaults)
		for i := range node.Parameters {
			param := &node.Parameters[i]
			field := t.Visit(param)
			if astField, ok := field.(*ast.Field); ok {
				params = append(params, astField)
			}
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

	// Handle error return if function can throw
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

	// Build function body
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

	// Prepend parameter extraction statements to the function body
	if len(paramExtractionStmts) > 0 {
		newBodyList := append([]ast.Stmt{}, paramExtractionStmts...)
		newBodyList = append(newBodyList, body.List...)
		body.List = newBodyList
	}

	// Add implicit return for functions with explicit non-void return types
	if node.ReturnType != nil {
		// Check if the return type is void
		if typeSpec, ok := node.ReturnType.(*msast.TypeSpec); ok && typeSpec.Kind == msast.VoidType {
			// Do not add implicit return for void functions
		} else {
			// Add implicit return for functions with actual return types
			t.ensureLastExprIsReturn(body)
		}
	} else {
		// Add implicit return for functions with actual return types
		t.ensureLastExprIsReturn(body)
	}

	return &ast.FuncDecl{
		Name: &ast.Ident{Name: t.generateVarName(node.Name)},
		Type: &ast.FuncType{
			Params:  &ast.FieldList{List: params},
			Results: results,
		},
		Body: body,
	}
}

// VisitMethodsDecl transpiles methods declarations
func (t *GoTranspiler) VisitMethodsDecl(node *msast.MethodsDecl) ast.Node {
	if node == nil {
		t.addError("invalid methods declaration", node)
		return nil
	}

	// In Go, methods are individual function declarations with receivers
	// We'll need to create separate function declarations for each method
	var decls []ast.Decl

	for i := range node.Methods {
		method := &node.Methods[i]
		// Pass both the type name and the receiver alias (stored in Interface field)
		methodDecl := t.visitMethodImpl(method, node.TypeName, node.Interface)
		if methodDecl != nil {
			decls = append(decls, methodDecl)
		}
	}

	// Since we can't return multiple declarations directly,
	// we'll add them to the current file and return nil
	if t.currentFile != nil {
		t.currentFile.Decls = append(t.currentFile.Decls, decls...)
	}

	return nil
}

// visitMethodImpl helper to transpile a method implementation
func (t *GoTranspiler) visitMethodImpl(method *msast.MethodImpl, typeName string, receiverAlias string) *ast.FuncDecl {
	if method == nil || method.Name == "" {
		return nil
	}

	// Build parameter list (including receiver)
	var params []*ast.Field

	// Add receiver parameter using the specified alias name
	receiverType := &ast.StarExpr{X: &ast.Ident{Name: t.generateVarName(typeName)}}
	receiver := &ast.Field{
		Names: []*ast.Ident{{Name: receiverAlias}},
		Type:  receiverType,
	}

	// Build other parameters
	for i := range method.Parameters {
		param := &method.Parameters[i]
		field := t.Visit(param)
		if astField, ok := field.(*ast.Field); ok {
			params = append(params, astField)
		}
	}

	// Build return type
	var results *ast.FieldList
	if method.ReturnType != nil {
		returnType := t.Visit(method.ReturnType)
		if returnExpr, ok := returnType.(ast.Expr); ok {
			results = &ast.FieldList{
				List: []*ast.Field{{Type: returnExpr}},
			}
		}
	}

	// Handle error return if method can throw
	if method.CanThrow {
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
	if method.Body != nil {
		bodyResult := t.Visit(method.Body)
		if blockStmt, ok := bodyResult.(*ast.BlockStmt); ok {
			body = blockStmt
		} else {
			body = &ast.BlockStmt{List: []ast.Stmt{}}
		}
	} else {
		body = &ast.BlockStmt{List: []ast.Stmt{}}
	}

	// Add implicit return for methods with explicit return types (same as functions)
	if method.ReturnType != nil {
		// Check if the return type is void
		if typeSpec, ok := method.ReturnType.(*msast.TypeSpec); ok && typeSpec.Kind == msast.VoidType {
			// Do not add implicit return for void methods
		} else {
			// Add implicit return for methods with actual return types
			t.ensureLastExprIsReturn(body)
		}
	}

	return &ast.FuncDecl{
		Name: &ast.Ident{Name: t.generateVarName(method.Name)},
		Recv: &ast.FieldList{List: []*ast.Field{receiver}},
		Type: &ast.FuncType{
			Params:  &ast.FieldList{List: params},
			Results: results,
		},
		Body: body,
	}
}

// capitalizeForExport capitalizes the first letter for Go exports
func (t *GoTranspiler) capitalizeForExport(name string) string {
	if name == "" {
		return name
	}

	// Convert first character to uppercase
	if len(name) == 1 {
		return strings.ToUpper(name)
	}

	return strings.ToUpper(name[:1]) + name[1:]
}

// ensureLastExprIsReturn converts the last statement to a return if it's an expression statement.
// This should only be called for functions with explicit return types.
func (t *GoTranspiler) ensureLastExprIsReturn(body *ast.BlockStmt) {

	if body == nil || len(body.List) == 0 {
		return
	}

	lastIdx := len(body.List) - 1
	lastStmt := body.List[lastIdx]

	// Check if the last statement is an expression statement
	if exprStmt, ok := lastStmt.(*ast.ExprStmt); ok && exprStmt.X != nil {

		// Convert expression statement to return statement
		body.List[lastIdx] = &ast.ReturnStmt{Results: []ast.Expr{exprStmt.X}}
	}
}

// VisitFieldDecl transpiles field declarations
func (t *GoTranspiler) VisitFieldDecl(node *msast.FieldDecl) ast.Node {
	if node == nil {
		return &ast.Field{
			Names: []*ast.Ident{{Name: "unknown"}},
			Type:  &ast.Ident{Name: "interface{}"},
		}
	}

	var fieldType ast.Expr
	if node.Type != nil {
		typeResult := t.Visit(node.Type)
		if typeExpr, ok := typeResult.(ast.Expr); ok {
			fieldType = typeExpr
		} else {
			fieldType = &ast.Ident{Name: "interface{}"}
		}
	} else {
		fieldType = &ast.Ident{Name: "interface{}"}
	}

	fieldName := t.generateVarName(node.Name)

	// Handle optional fields by using pointer types
	if node.Optional {
		fieldType = &ast.StarExpr{X: fieldType}
	}

	return &ast.Field{
		Names: []*ast.Ident{{Name: fieldName}},
		Type:  fieldType,
	}
}
