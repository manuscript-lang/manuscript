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

	// Track whether we found a main function in the manuscript code
	mainFound := false
	hasStatements := false

	// Process all declarations
	for _, decl := range node.Declarations {
		if decl == nil {
			continue
		}

		result := t.Visit(decl)
		if result == nil {
			continue
		}

		// Handle different types of results
		switch goNode := result.(type) {
		case *MultipleDeclarations:
			t.currentFile.Decls = append(t.currentFile.Decls, goNode.Decls...)
		case *ast.FuncDecl:
			// Check if this is a main function
			if goNode.Name != nil && goNode.Name.Name == "main" {
				mainFound = true
			}
			t.currentFile.Decls = append(t.currentFile.Decls, goNode)
		case *ast.GenDecl:
			t.currentFile.Decls = append(t.currentFile.Decls, goNode)
		case ast.Decl:
			t.currentFile.Decls = append(t.currentFile.Decls, goNode)
		case ast.Stmt:
			// Top-level statements need to be wrapped in a main function or init
			t.addToMainOrInit(goNode)
			hasStatements = true
		default:
			// For any other type, try to handle as interface{} and extract what we can
			t.handleUnknownResult(result)
		}
	}

	// If no main function was found in the manuscript code AND no statements were added to an implicit main,
	// create an empty one
	if !mainFound && !hasStatements {
		mainFunc := &ast.FuncDecl{
			Name: &ast.Ident{Name: "main"},
			Type: &ast.FuncType{
				Params: &ast.FieldList{},
			},
			Body: &ast.BlockStmt{
				List: []ast.Stmt{},
			},
		}
		t.currentFile.Decls = append(t.currentFile.Decls, mainFunc)
	}

	// Add imports if any were collected
	if len(t.Imports) > 0 {
		t.addImports()
	}

	return t.currentFile
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

// addToMainOrInit adds a statement to the main function, creating it if necessary
func (t *GoTranspiler) addToMainOrInit(stmt ast.Stmt) {
	if stmt == nil {
		return
	}

	// Find existing main function or create one
	mainFunc := t.findOrCreateMainFunc()
	if mainFunc != nil && mainFunc.Body != nil {
		// Check for special block types that should be preserved
		switch s := stmt.(type) {
		case *DestructuringBlockStmt:
			// Preserve destructuring blocks as-is
			mainFunc.Body.List = append(mainFunc.Body.List, s.BlockStmt)
		case *PipelineBlockStmt:
			// Preserve pipeline blocks as-is
			mainFunc.Body.List = append(mainFunc.Body.List, s.BlockStmt)
		case *ast.BlockStmt:
			// Flatten regular block statements
			for _, innerStmt := range s.List {
				if innerStmt != nil {
					mainFunc.Body.List = append(mainFunc.Body.List, innerStmt)
				}
			}
		default:
			// Add the statement directly
			mainFunc.Body.List = append(mainFunc.Body.List, stmt)
		}
	}
}

// findOrCreateMainFunc finds the main function or creates it if it doesn't exist
func (t *GoTranspiler) findOrCreateMainFunc() *ast.FuncDecl {
	// Look for existing main function
	for _, decl := range t.currentFile.Decls {
		if funcDecl, ok := decl.(*ast.FuncDecl); ok {
			if funcDecl.Name != nil && funcDecl.Name.Name == "main" {
				return funcDecl
			}
		}
	}

	// Create new main function
	mainFunc := &ast.FuncDecl{
		Name: &ast.Ident{Name: "main"},
		Type: &ast.FuncType{
			Params: &ast.FieldList{},
		},
		Body: &ast.BlockStmt{
			List: []ast.Stmt{},
		},
	}

	t.currentFile.Decls = append(t.currentFile.Decls, mainFunc)
	return mainFunc
}

// addImports adds collected imports to the file
func (t *GoTranspiler) addImports() {
	if len(t.Imports) == 0 {
		return
	}

	// Create import declaration
	importDecl := &ast.GenDecl{
		Tok:   token.IMPORT,
		Specs: make([]ast.Spec, len(t.Imports)),
	}

	// Convert ImportSpec slice to Spec slice
	for i, importSpec := range t.Imports {
		importDecl.Specs[i] = importSpec
	}

	// Add import declaration to the beginning of the file
	t.currentFile.Decls = append([]ast.Decl{importDecl}, t.currentFile.Decls...)
}

// handleUnknownResult tries to extract useful Go AST nodes from unknown result types
func (t *GoTranspiler) handleUnknownResult(result ast.Node) {
	// This is a fallback for handling results that don't match our expected types
	// We can extend this as needed for specific cases
	if result == nil {
		return
	}

	// If it's some other ast.Node that implements ast.Decl or ast.Stmt,
	// we might want to handle it, but for now, just ignore unknown types
}
