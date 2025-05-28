package transpiler

import (
	"go/ast"
	"go/token"

	mast "manuscript-lang/manuscript/internal/ast"
)

// VisitProgram transpiles the root Program node to a Go file
func (t *GoTranspiler) VisitProgram(node *mast.Program) ast.Node {
	if node == nil {
		t.addError("received nil program node", nil)
		return t.createEmptyGoFile()
	}

	t.currentFile = &ast.File{
		Name:    &ast.Ident{Name: t.PackageName},
		Decls:   []ast.Decl{},
		Package: token.NoPos,
	}

	t.registerNodeMapping(t.currentFile, node)

	mainFound := false
	var topLevelStmts []ast.Stmt

	// Process all declarations
	for _, decl := range node.Declarations {
		if decl == nil {
			continue
		}

		result := t.Visit(decl)
		if result == nil {
			continue
		}

		mainFound = t.processDeclarationResult(result, &topLevelStmts) || mainFound
	}

	// Handle main function and top-level statements
	t.handleMainFunction(mainFound, topLevelStmts)

	// Add imports
	t.addImportsToFile()

	return t.currentFile
}

// processDeclarationResult processes a single declaration result and returns true if main function was found
func (t *GoTranspiler) processDeclarationResult(result ast.Node, topLevelStmts *[]ast.Stmt) bool {
	switch goNode := result.(type) {
	case *MultipleDeclarations:
		t.currentFile.Decls = append(t.currentFile.Decls, goNode.Decls...)
	case *ast.BlockStmt:
		*topLevelStmts = append(*topLevelStmts, goNode.List...)
	case *ast.FuncDecl:
		if goNode.Name != nil && goNode.Name.Name == "main" {
			t.currentFile.Decls = append(t.currentFile.Decls, goNode)
			return true
		}
		t.currentFile.Decls = append(t.currentFile.Decls, goNode)
	case *ast.GenDecl:
		t.currentFile.Decls = append(t.currentFile.Decls, goNode)
	case ast.Decl:
		t.currentFile.Decls = append(t.currentFile.Decls, goNode)
	case ast.Stmt:
		*topLevelStmts = append(*topLevelStmts, goNode)
	}
	return false
}

// handleMainFunction handles main function creation and top-level statement integration
func (t *GoTranspiler) handleMainFunction(mainFound bool, topLevelStmts []ast.Stmt) {
	if len(topLevelStmts) == 0 && mainFound {
		return
	}

	if mainFound {
		t.addStatementsToExistingMain(topLevelStmts)
	} else {
		t.createMainFunction(topLevelStmts)
	}
}

// addStatementsToExistingMain adds top-level statements to existing main function
func (t *GoTranspiler) addStatementsToExistingMain(stmts []ast.Stmt) {
	for _, decl := range t.currentFile.Decls {
		if funcDecl, ok := decl.(*ast.FuncDecl); ok {
			if funcDecl.Name != nil && funcDecl.Name.Name == "main" {
				if funcDecl.Body == nil {
					funcDecl.Body = &ast.BlockStmt{List: []ast.Stmt{}}
				}
				funcDecl.Body.List = append(stmts, funcDecl.Body.List...)
				return
			}
		}
	}
}

// createMainFunction creates a new main function with the given statements
func (t *GoTranspiler) createMainFunction(stmts []ast.Stmt) {
	mainFunc := &ast.FuncDecl{
		Name: &ast.Ident{Name: "main"},
		Type: &ast.FuncType{
			Params: &ast.FieldList{},
		},
		Body: &ast.BlockStmt{
			List: stmts,
		},
	}
	t.currentFile.Decls = append(t.currentFile.Decls, mainFunc)
}

// addImportsToFile adds import declarations to the file
func (t *GoTranspiler) addImportsToFile() {
	if len(t.Imports) == 0 {
		return
	}

	importDecl := &ast.GenDecl{
		Tok:   token.IMPORT,
		Specs: make([]ast.Spec, len(t.Imports)),
	}
	for i, imp := range t.Imports {
		importDecl.Specs[i] = imp
	}
	t.currentFile.Decls = append([]ast.Decl{importDecl}, t.currentFile.Decls...)
}

// createEmptyGoFile creates a minimal valid Go file
func (t *GoTranspiler) createEmptyGoFile() *ast.File {
	return &ast.File{
		Name: &ast.Ident{Name: t.PackageName},
		Decls: []ast.Decl{
			&ast.FuncDecl{
				Name: &ast.Ident{Name: "main"},
				Type: &ast.FuncType{
					Params: &ast.FieldList{},
				},
				Body: &ast.BlockStmt{
					List: []ast.Stmt{},
				},
			},
		},
		Package: token.NoPos,
	}
}
