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
			statements = append(statements, v.List...)
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

	params, paramExtractionStmts := t.buildFunctionParams(node.Parameters)
	results := t.buildReturnType(node.ReturnType, node.CanThrow)
	body := t.buildFunctionBody(node.Body, paramExtractionStmts)
	t.handleImplicitReturn(body, node.ReturnType)

	return &ast.FuncDecl{
		Name: &ast.Ident{Name: t.generateVarName(node.Name)},
		Type: &ast.FuncType{
			Params:  &ast.FieldList{List: params},
			Results: results,
		},
		Body: body,
	}
}

// buildFunctionParams builds parameter list and extraction statements for functions
func (t *GoTranspiler) buildFunctionParams(parameters []msast.Parameter) ([]*ast.Field, []ast.Stmt) {
	hasDefaultParams := t.hasDefaultParameters(parameters)

	if hasDefaultParams {
		return t.buildVariadicParams(parameters)
	}
	return t.buildRegularParams(parameters), nil
}

// hasDefaultParameters checks if any parameters have default values
func (t *GoTranspiler) hasDefaultParameters(parameters []msast.Parameter) bool {
	for i := range parameters {
		if parameters[i].DefaultValue != nil {
			return true
		}
	}
	return false
}

// buildVariadicParams builds variadic parameters for functions with default values
func (t *GoTranspiler) buildVariadicParams(parameters []msast.Parameter) ([]*ast.Field, []ast.Stmt) {
	params := []*ast.Field{{
		Names: []*ast.Ident{{Name: "args"}},
		Type: &ast.Ellipsis{
			Elt: &ast.Ident{Name: "interface{}"},
		},
	}}

	var paramExtractionStmts []ast.Stmt
	for i, param := range parameters {
		paramName := t.generateVarName(param.Name)
		paramType := t.getParameterType(param.Type)
		extractionStmts := t.generateParameterExtraction(&param, i, paramName, paramType)
		paramExtractionStmts = append(paramExtractionStmts, extractionStmts...)
	}

	return params, paramExtractionStmts
}

// buildRegularParams builds regular parameters (no defaults)
func (t *GoTranspiler) buildRegularParams(parameters []msast.Parameter) []*ast.Field {
	var params []*ast.Field
	for i := range parameters {
		param := &parameters[i]
		field := t.Visit(param)
		if astField, ok := field.(*ast.Field); ok {
			params = append(params, astField)
		}
	}
	return params
}

// getParameterType gets the Go type expression for a parameter
func (t *GoTranspiler) getParameterType(paramType msast.Node) ast.Expr {
	if paramType != nil {
		typeResult := t.Visit(paramType)
		if typeExpr, ok := typeResult.(ast.Expr); ok {
			return typeExpr
		}
	}
	return &ast.Ident{Name: "interface{}"}
}

// buildReturnType builds the return type field list
func (t *GoTranspiler) buildReturnType(returnType msast.Node, canThrow bool) *ast.FieldList {
	var results *ast.FieldList

	if returnType != nil {
		returnTypeExpr := t.Visit(returnType)
		if returnExpr, ok := returnTypeExpr.(ast.Expr); ok {
			results = &ast.FieldList{
				List: []*ast.Field{{Type: returnExpr}},
			}
		}
	}

	if canThrow {
		errorField := &ast.Field{Type: &ast.Ident{Name: "error"}}
		if results == nil {
			results = &ast.FieldList{List: []*ast.Field{errorField}}
		} else {
			results.List = append(results.List, errorField)
		}
	}

	return results
}

// buildFunctionBody builds the function body with optional parameter extraction statements
func (t *GoTranspiler) buildFunctionBody(bodyNode msast.Node, paramExtractionStmts []ast.Stmt) *ast.BlockStmt {
	var body *ast.BlockStmt

	if bodyNode != nil {
		bodyResult := t.Visit(bodyNode)
		if blockStmt, ok := bodyResult.(*ast.BlockStmt); ok {
			body = blockStmt
		} else {
			body = &ast.BlockStmt{List: []ast.Stmt{}}
		}
	} else {
		body = &ast.BlockStmt{List: []ast.Stmt{}}
	}

	// Prepend parameter extraction statements
	if len(paramExtractionStmts) > 0 {
		newBodyList := append([]ast.Stmt{}, paramExtractionStmts...)
		newBodyList = append(newBodyList, body.List...)
		body.List = newBodyList
	}

	return body
}

// handleImplicitReturn adds implicit return for functions with explicit non-void return types
func (t *GoTranspiler) handleImplicitReturn(body *ast.BlockStmt, returnType msast.Node) {
	if returnType != nil {
		// Check if the return type is void
		if typeSpec, ok := returnType.(*msast.TypeSpec); ok && typeSpec.Kind == msast.VoidType {
			return // Do not add implicit return for void functions
		}
		t.ensureLastExprIsReturn(body)
	} else {
		t.ensureLastExprIsReturn(body)
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
		// Use the standard visitor pattern
		methodResult := t.Visit(method)
		if funcDecl, ok := methodResult.(*ast.FuncDecl); ok {
			// Add receiver to the function declaration
			receiverType := &ast.StarExpr{X: &ast.Ident{Name: t.generateVarName(node.TypeName)}}
			receiver := &ast.Field{
				Names: []*ast.Ident{{Name: node.Interface}},
				Type:  receiverType,
			}
			funcDecl.Recv = &ast.FieldList{List: []*ast.Field{receiver}}
			decls = append(decls, funcDecl)
		}
	}

	// Since we can't return multiple declarations directly,
	// we'll add them to the current file and return nil
	if t.currentFile != nil {
		t.currentFile.Decls = append(t.currentFile.Decls, decls...)
	}

	return nil
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

// generateParameterExtraction creates parameter extraction statements for functions with default parameters
func (t *GoTranspiler) generateParameterExtraction(param *msast.Parameter, paramIndex int, paramName string, paramType ast.Expr) []ast.Stmt {
	if param.DefaultValue != nil {
		return t.createDefaultParameterStmts(param, paramIndex, paramName, paramType)
	}
	return t.createRequiredParameterStmts(paramIndex, paramName, paramType)
}

// createDefaultParameterStmts creates statements for parameters with default values
func (t *GoTranspiler) createDefaultParameterStmts(param *msast.Parameter, paramIndex int, paramName string, paramType ast.Expr) []ast.Stmt {
	defaultExpr := t.Visit(param.DefaultValue)
	defaultValue, ok := defaultExpr.(ast.Expr)
	if !ok {
		return nil
	}

	// Variable declaration with default value
	varDecl := t.createVarDecl(paramName, paramType, defaultValue)

	// Conditional assignment: if len(args) > i { name = args[i].(Type) }
	ifStmt := t.createConditionalAssignment(paramIndex, paramName, paramType)

	return []ast.Stmt{varDecl, ifStmt}
}

// createRequiredParameterStmts creates statements for required parameters
func (t *GoTranspiler) createRequiredParameterStmts(paramIndex int, paramName string, paramType ast.Expr) []ast.Stmt {
	// Parameter without default value: name := args[i].(Type)
	assignStmt := &ast.AssignStmt{
		Lhs: []ast.Expr{&ast.Ident{Name: paramName}},
		Tok: token.DEFINE,
		Rhs: []ast.Expr{t.createArgsTypeAssertion(paramIndex, paramType)},
	}
	return []ast.Stmt{assignStmt}
}

// createVarDecl creates a variable declaration statement
func (t *GoTranspiler) createVarDecl(paramName string, paramType ast.Expr, defaultValue ast.Expr) *ast.DeclStmt {
	return &ast.DeclStmt{
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
}

// createConditionalAssignment creates an if statement for conditional parameter assignment
func (t *GoTranspiler) createConditionalAssignment(paramIndex int, paramName string, paramType ast.Expr) *ast.IfStmt {
	return &ast.IfStmt{
		Cond: &ast.BinaryExpr{
			X: &ast.CallExpr{
				Fun:  &ast.Ident{Name: "len"},
				Args: []ast.Expr{&ast.Ident{Name: "args"}},
			},
			Op: token.GTR,
			Y:  &ast.BasicLit{Kind: token.INT, Value: fmt.Sprintf("%d", paramIndex)},
		},
		Body: &ast.BlockStmt{
			List: []ast.Stmt{
				&ast.AssignStmt{
					Lhs: []ast.Expr{&ast.Ident{Name: paramName}},
					Tok: token.ASSIGN,
					Rhs: []ast.Expr{t.createArgsTypeAssertion(paramIndex, paramType)},
				},
			},
		},
	}
}

// createArgsTypeAssertion creates a type assertion expression for args[i].(Type)
func (t *GoTranspiler) createArgsTypeAssertion(paramIndex int, paramType ast.Expr) *ast.TypeAssertExpr {
	return &ast.TypeAssertExpr{
		X: &ast.IndexExpr{
			X:     &ast.Ident{Name: "args"},
			Index: &ast.BasicLit{Kind: token.INT, Value: fmt.Sprintf("%d", paramIndex)},
		},
		Type: paramType,
	}
}
