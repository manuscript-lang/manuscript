package visitor

import (
	"go/ast"
	"go/token"
	"log"
	"manuscript-co/manuscript/internal/parser"
	"strconv"
)

// VisitProgram handles the root of the parse tree (program rule).
func (v *ManuscriptAstVisitor) VisitProgram(ctx *parser.ProgramContext) interface{} {
	log.Println("SUCCESS: ManuscriptAstVisitor.VisitProgram in program.go is being executed.") // Diagnostic log
	file := &ast.File{
		Name:  ast.NewIdent("main"), // Default to main package
		Decls: []ast.Decl{},         // Declarations will be added here
	}
	mainFunc := &ast.FuncDecl{
		Name: ast.NewIdent("main"),
		Type: &ast.FuncType{Params: &ast.FieldList{}, Results: nil},
		Body: &ast.BlockStmt{List: []ast.Stmt{}},
	}
	file.Decls = append(file.Decls, mainFunc)
	mainBody := &mainFunc.Body.List

	for _, itemCtx := range ctx.AllProgramItem() {
		var visitedItem interface{}
		if stmtCtx := itemCtx.Stmt(); stmtCtx != nil {
			if concreteStmtCtx, ok := stmtCtx.(*parser.StmtContext); ok {
				visitedItem = v.VisitStmt(concreteStmtCtx)
			} else {
				log.Printf("Warning: Could not assert StmtContext type for %s", itemCtx.GetText())
			}
		} else if fnDeclCtx := itemCtx.FnDecl(); fnDeclCtx != nil {
			if concreteFnDeclCtx, ok := fnDeclCtx.(*parser.FnDeclContext); ok {
				visitedItem = v.Visit(concreteFnDeclCtx)
			} else {
				log.Printf("Warning: Could not assert FnDeclContext type for %s", itemCtx.GetText())
			}
		} else {
			// Log only if it's not one of the types we explicitly check for above
			if itemCtx.Stmt() == nil && itemCtx.FnDecl() == nil /* && other checked types == nil */ {
				log.Printf("Warning: Unhandled ProgramItem type in VisitProgram loop: %s", itemCtx.GetText())
			}
		}

		switch node := visitedItem.(type) {
		case ast.Stmt:
			if stmt, ok := node.(*ast.EmptyStmt); ok && stmt == nil { // Should not happen with current logic, but good check
				// Do nothing for a truly nil ast.Stmt if it somehow gets here
			} else if _, isEmpty := node.(*ast.EmptyStmt); isEmpty {
				// Do not append *ast.EmptyStmt to avoid empty lines or unwanted semicolons
				log.Printf("VisitProgram: Skipping *ast.EmptyStmt for item: %s", itemCtx.GetText())
			} else {
				*mainBody = append(*mainBody, node)
			}
		case []ast.Stmt: // New case to handle a slice of statements
			for _, stmt := range node {
				if _, isEmpty := stmt.(*ast.EmptyStmt); isEmpty {
					// Do not append *ast.EmptyStmt from the slice
					log.Printf("VisitProgram: Skipping *ast.EmptyStmt from slice for item: %s", itemCtx.GetText())
				} else if stmt != nil {
					*mainBody = append(*mainBody, stmt)
				}
			}
		case ast.Decl:
			if funcDecl, ok := node.(*ast.FuncDecl); !ok || funcDecl.Name.Name != "main" {
				file.Decls = append(file.Decls, node)
			}
		case nil:
			// Expected if an unhandled/unassertable ProgramItem type was encountered
		default:
			log.Printf("Warning: Unhandled node type (%T) returned from ProgramItem processing for item: %s", node, itemCtx.GetText())
			if expr, ok := node.(ast.Expr); ok {
				log.Printf("Treating returned expression as statement in main func.")
				*mainBody = append(*mainBody, &ast.ExprStmt{X: expr})
			}
		}
	}

	// Add collected imports
	if len(v.ProgramImports) > 0 {
		var importSpecs []ast.Spec
		for impPath := range v.ProgramImports {
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
		// Ensure mainFunc is still correctly part of Decls if it was the only one.
		updatedDecls := []ast.Decl{importDecl}
		file.Decls = append(updatedDecls, file.Decls...)
	}

	return file
}
