package visitor

import (
	"go/ast"
	"go/token"
	"manuscript-co/manuscript/internal/parser"
	"strconv"

	antlr "github.com/antlr4-go/antlr/v4"
)

// VisitProgram handles the root of the parse tree (program rule).
func (v *ManuscriptAstVisitor) VisitProgram(ctx *parser.ProgramContext) interface{} {
	if ctx == nil {
		v.addError("Received nil program context", nil)
		return createEmptyMainFile()
	}

	file := &ast.File{
		Name:  ast.NewIdent("main"), // Default to main package
		Decls: []ast.Decl{},         // Declarations will be added here
	}
	var mainFunctionFound bool = false
	var mainFuncBody *ast.BlockStmt // To store the body if main is found

	// Placeholder for statements that might need to go into main if not part of any explicit func
	// This slice will remain empty given current grammar where ProgramItem are declarations.
	var topLevelStatements []ast.Stmt

	for _, itemCtx := range ctx.AllProgramItem() {
		if itemCtx == nil {
			continue
		}

		var visitedItem interface{}

		// Check for specific program item types based on the grammar rule for programItem
		if importStmtCtx := itemCtx.ImportStmt(); importStmtCtx != nil {
			visitedItem = v.Visit(importStmtCtx)
		} else if exportStmtCtx := itemCtx.ExportStmt(); exportStmtCtx != nil {
			visitedItem = v.Visit(exportStmtCtx)
		} else if externStmtCtx := itemCtx.ExternStmt(); externStmtCtx != nil {
			visitedItem = v.Visit(externStmtCtx)
		} else if letDeclCtx := itemCtx.LetDecl(); letDeclCtx != nil {
			visitedItem = v.Visit(letDeclCtx)
		} else if typeDeclCtx := itemCtx.TypeDecl(); typeDeclCtx != nil {
			visitedItem = v.Visit(typeDeclCtx)
		} else if ifaceDeclCtx := itemCtx.InterfaceDecl(); ifaceDeclCtx != nil {
			visitedItem = v.Visit(ifaceDeclCtx)
		} else if fnDeclCtx := itemCtx.FnDecl(); fnDeclCtx != nil {
			visitedItem = v.Visit(fnDeclCtx)
		} else if methodsDeclCtx := itemCtx.MethodsDecl(); methodsDeclCtx != nil {
			visitedItem = v.Visit(methodsDeclCtx)
		} else {
			text := itemCtx.GetText()
			if text != "" && text != "<EOF>" {
				v.addError("VisitProgram: Unhandled program item alternative: "+text, itemCtx.GetStart())
			}
		}

		switch node := visitedItem.(type) {
		case ast.Stmt: // Should not be hit if programItem only yields Decls
			if stmt, ok := node.(*ast.EmptyStmt); ok && stmt == nil {
				// Skip nil empty statements
				continue
			} else if _, isEmpty := node.(*ast.EmptyStmt); isEmpty {
				// Skip empty statements but log it
				continue
			} else {
				// This logic path should ideally not be hit with current grammar
				// as ProgramItems are expected to be declarations or module statements.
				// If a ProgramItem somehow yields a Stmt, it would be added to topLevelStatements.
				topLevelStatements = append(topLevelStatements, node)
			}
		case []ast.Stmt: // Should not be hit if programItem only yields Decls
			for _, stmt := range node {
				if _, isEmpty := stmt.(*ast.EmptyStmt); isEmpty {
					continue
				} else if stmt != nil {
					topLevelStatements = append(topLevelStatements, stmt)
				}
			}
		case ast.Decl:
			if node == nil {
				continue
			}

			if funcDecl, ok := node.(*ast.FuncDecl); ok && funcDecl.Name != nil && funcDecl.Name.Name == "main" {
				if mainFunctionFound {
					// Multiple main functions defined, this is an error in Go.
					// Find the original token for the function name for error reporting.
					var errorToken antlr.Token
					if specificFnDeclCtx := itemCtx.FnDecl(); specificFnDeclCtx != nil &&
						specificFnDeclCtx.FnSignature() != nil &&
						specificFnDeclCtx.FnSignature().NamedID() != nil &&
						specificFnDeclCtx.FnSignature().NamedID().ID() != nil {
						errorToken = specificFnDeclCtx.FnSignature().NamedID().ID().GetSymbol()
					} else {
						errorToken = itemCtx.GetStart() // Fallback to the start of the program item
					}
					v.addError("Multiple main functions defined.", errorToken)
				} else {
					file.Decls = append(file.Decls, node) // Add the user-defined main function
					mainFunctionFound = true
					mainFuncBody = funcDecl.Body // Store its body
				}
			} else {
				file.Decls = append(file.Decls, node) // Add other declarations
			}
		case nil:
			// Log an error if we unexpectedly get nil from a child visit
			text := itemCtx.GetText()
			if text != "" && text != "<EOF>" {
				v.addError("VisitProgram: Child visit returned nil for: "+text, itemCtx.GetStart())
			}
		default:
			v.addError("Internal error: Unhandled node type returned from program item processing for: "+itemCtx.GetText(), itemCtx.GetStart())
			if expr, ok := node.(ast.Expr); ok { // Should not happen with current grammar
				topLevelStatements = append(topLevelStatements, &ast.ExprStmt{X: expr})
			}
		}
	}

	// If there were top-level statements and no explicit main func body was found to put them in,
	// this indicates an issue if the grammar was supposed to prevent this scenario.
	// For now, if a main was found, and we also collected topLevelStatements (which shouldn't happen with decl-only programItems),
	// we could try to merge them, but this suggests a grammar vs visitor logic mismatch.
	if len(topLevelStatements) > 0 {
		if mainFunctionFound && mainFuncBody != nil {
			// Prepend topLevelStatements to the user-defined main's body
			// This case is less likely with current grammar where programItem is only declarations.
			mainFuncBody.List = append(topLevelStatements, mainFuncBody.List...)
		} else if !mainFunctionFound {
			// No main function found, and we have top-level statements.
			// Create a main function for them.
			defaultMain := &ast.FuncDecl{
				Name: ast.NewIdent("main"),
				Type: &ast.FuncType{Params: &ast.FieldList{}, Results: nil},
				Body: &ast.BlockStmt{List: topLevelStatements},
			}
			file.Decls = append(file.Decls, defaultMain)
			mainFunctionFound = true // We just created one.
		}
	}

	// If no main function was found (neither user-defined nor created for top-level statements), add a default empty one.
	if !mainFunctionFound {
		defaultMain := &ast.FuncDecl{
			Name: ast.NewIdent("main"),
			Type: &ast.FuncType{Params: &ast.FieldList{}, Results: nil},
			Body: &ast.BlockStmt{List: []ast.Stmt{}}, // Empty body
		}
		file.Decls = append(file.Decls, defaultMain)
	}

	// Add collected imports (ensure this happens after all other Decls are potentially added)
	if len(v.goImports) > 0 {
		var importSpecs []ast.Spec
		for impPath := range v.goImports {
			importSpec := &ast.ImportSpec{
				Path: &ast.BasicLit{
					Kind:  token.STRING,
					Value: strconv.Quote(impPath),
				},
			}
			importSpecs = append(importSpecs, importSpec)
		}

		importDecl := &ast.GenDecl{
			Tok:   token.IMPORT,
			Specs: importSpecs,
		}
		// Prepend imports to other declarations for conventional Go style.
		file.Decls = append([]ast.Decl{importDecl}, file.Decls...)
	}

	// Double check that we have a valid file to return
	if file == nil {
		v.addError("VisitProgram: Failed to produce a valid file", ctx.GetStart())
		return createEmptyMainFile()
	}

	return file
}

// Helper function to create an empty main file
func createEmptyMainFile() *ast.File {
	return &ast.File{
		Name: ast.NewIdent("main"),
		Decls: []ast.Decl{
			&ast.GenDecl{
				Tok: token.IMPORT,
				Specs: []ast.Spec{
					&ast.ImportSpec{
						Path: &ast.BasicLit{
							Kind:  token.STRING,
							Value: "\"fmt\"",
						},
					},
				},
			},
			&ast.FuncDecl{
				Name: ast.NewIdent("main"),
				Type: &ast.FuncType{Params: &ast.FieldList{}, Results: nil},
				Body: &ast.BlockStmt{List: []ast.Stmt{}},
			},
		},
	}
}
