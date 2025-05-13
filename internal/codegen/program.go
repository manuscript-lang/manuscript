package codegen

import (
	"go/ast"
	"log"
	"manuscript-co/manuscript/internal/parser"
)

// VisitProgram handles the root of the parse tree (program rule).
func (v *ManuscriptAstVisitor) VisitProgram(ctx *parser.ProgramContext) interface{} {
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
			*mainBody = append(*mainBody, node)
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

	return file
}
