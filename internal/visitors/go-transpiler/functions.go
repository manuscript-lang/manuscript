package transpiler

import (
	"go/ast"

	mast "manuscript-lang/manuscript/internal/ast"
)

// VisitFnDecl transpiles function declarations
func (t *GoTranspiler) VisitFnDecl(node *mast.FnDecl) ast.Node {
	if node == nil || node.Name == "" {
		t.addError("invalid function declaration", node)
		return nil
	}

	params, paramExtractionStmts := t.buildFunctionParams(node.Parameters)
	results := t.buildReturnType(node.ReturnType, node.CanThrow)
	body := t.buildFunctionBody(node.Body, paramExtractionStmts)

	if t.manuscriptBodyContainsYield(node.Body) {
		return t.buildGeneratorFunction(node.Name, params, body)
	}

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
func (t *GoTranspiler) buildFunctionParams(parameters []mast.Parameter) ([]*ast.Field, []ast.Stmt) {
	for _, param := range parameters {
		if param.DefaultValue != nil {
			return t.buildVariadicParams(parameters)
		}
	}

	var params []*ast.Field
	for i := range parameters {
		if field := t.Visit(&parameters[i]); field != nil {
			if astField, ok := field.(*ast.Field); ok {
				params = append(params, astField)
			}
		}
	}
	return params, nil
}

// buildVariadicParams builds variadic parameters for functions with default values
func (t *GoTranspiler) buildVariadicParams(parameters []mast.Parameter) ([]*ast.Field, []ast.Stmt) {
	params := []*ast.Field{{
		Names: []*ast.Ident{{Name: "args"}},
		Type:  &ast.Ellipsis{Elt: &ast.Ident{Name: "interface{}"}},
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

// getParameterType gets the Go type expression for a parameter
func (t *GoTranspiler) getParameterType(paramType mast.Node) ast.Expr {
	if paramType != nil {
		if typeExpr, ok := t.Visit(paramType).(ast.Expr); ok {
			return typeExpr
		}
	}
	return &ast.Ident{Name: "interface{}"}
}

// buildReturnType builds the return type field list
func (t *GoTranspiler) buildReturnType(returnType mast.Node, canThrow bool) *ast.FieldList {
	var results *ast.FieldList

	if returnType != nil {
		if returnExpr, ok := t.Visit(returnType).(ast.Expr); ok {
			results = &ast.FieldList{List: []*ast.Field{{Type: returnExpr}}}
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
func (t *GoTranspiler) buildFunctionBody(bodyNode mast.Node, paramExtractionStmts []ast.Stmt) *ast.BlockStmt {
	body := &ast.BlockStmt{List: []ast.Stmt{}}

	if bodyNode != nil {
		if blockStmt, ok := t.Visit(bodyNode).(*ast.BlockStmt); ok {
			body = blockStmt
		}
	}

	if len(paramExtractionStmts) > 0 {
		body.List = append(paramExtractionStmts, body.List...)
	}

	return body
}

// handleImplicitReturn adds implicit return for functions with explicit non-void return types
func (t *GoTranspiler) handleImplicitReturn(body *ast.BlockStmt, returnType mast.Node) {
	if returnType != nil {
		// Check if the return type is void
		if typeSpec, ok := returnType.(*mast.TypeSpec); ok && typeSpec.Kind == mast.VoidType {
			return // Do not add implicit return for void functions
		}
		t.ensureLastExprIsReturn(body)
	} else {
		t.ensureLastExprIsReturn(body)
	}
}

// VisitMethodsDecl transpiles methods declarations
func (t *GoTranspiler) VisitMethodsDecl(node *mast.MethodsDecl) ast.Node {
	if node == nil {
		t.addError("invalid methods declaration", node)
		return nil
	}

	receiver := &ast.Field{
		Names: []*ast.Ident{{Name: node.Interface}},
		Type:  &ast.StarExpr{X: &ast.Ident{Name: t.generateVarName(node.TypeName)}},
	}

	var decls []ast.Decl
	for i := range node.Methods {
		if funcDecl, ok := t.Visit(&node.Methods[i]).(*ast.FuncDecl); ok {
			funcDecl.Recv = &ast.FieldList{List: []*ast.Field{receiver}}
			decls = append(decls, funcDecl)
		}
	}

	if t.currentFile != nil {
		t.currentFile.Decls = append(t.currentFile.Decls, decls...)
	}

	return nil
}

// VisitFieldDecl transpiles field declarations
func (t *GoTranspiler) VisitFieldDecl(node *mast.FieldDecl) ast.Node {
	if node == nil {
		return &ast.Field{
			Names: []*ast.Ident{{Name: "unknown"}},
			Type:  &ast.Ident{Name: "interface{}"},
		}
	}

	fieldType := ast.Expr(&ast.Ident{Name: "interface{}"})
	if node.Type != nil {
		if typeExpr, ok := t.Visit(node.Type).(ast.Expr); ok {
			fieldType = typeExpr
		}
	}

	if node.Optional {
		fieldType = &ast.StarExpr{X: fieldType}
	}

	return &ast.Field{
		Names: []*ast.Ident{{Name: t.generateVarName(node.Name)}},
		Type:  fieldType,
	}
}

func (t *GoTranspiler) ensureLastExprIsReturn(body *ast.BlockStmt) {
	if body == nil || len(body.List) == 0 {
		return
	}

	lastIdx := len(body.List) - 1
	if exprStmt, ok := body.List[lastIdx].(*ast.ExprStmt); ok && exprStmt.X != nil {
		body.List[lastIdx] = &ast.ReturnStmt{Results: []ast.Expr{exprStmt.X}}
	}
}
