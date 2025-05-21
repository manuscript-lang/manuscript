package visitor

import (
	"go/ast"
	"go/token"
	"manuscript-co/manuscript/internal/parser"
	"strconv"

	"github.com/antlr4-go/antlr/v4"
)

// VisitProgram handles the root of the parse tree (program rule).
// Converts the Manuscript program to a Go AST File.
func (v *ManuscriptAstVisitor) VisitProgram(ctx *parser.ProgramContext) interface{} {
	// Handle null context gracefully
	if ctx == nil {
		v.addError("Received nil program context", nil)
		return createEmptyMainFile()
	}

	// Create the Go AST file structure
	file := &ast.File{
		Name:  ast.NewIdent("main"),
		Decls: []ast.Decl{},
	}

	// Track if we found a main function
	mainFound := false

	// Collect top-level statements for inclusion in main if needed
	var topLevelStmts []ast.Stmt

	// Process all declarations
	for _, declCtx := range ctx.AllDeclaration() {
		if declCtx == nil {
			continue
		}

		// Visit the declaration
		node := v.VisitDeclaration(declCtx)
		if node == nil {
			continue
		}

		// Handle different return types
		switch typedNode := node.(type) {
		case []ast.Decl:
			file.Decls = append(file.Decls, typedNode...)

		case ast.Decl:
			// Check if this is a main function declaration
			if funcDecl, isFuncDecl := typedNode.(*ast.FuncDecl); isFuncDecl &&
				funcDecl.Name != nil && funcDecl.Name.Name == "main" {
				if mainFound {
					v.addError("Multiple main functions defined", declCtx.GetStart())
					continue
				}
				mainFound = true
			}
			file.Decls = append(file.Decls, typedNode)

		case *ast.TypeSpec:
			// Wrap type spec in a type declaration
			file.Decls = append(file.Decls, &ast.GenDecl{
				Tok:   token.TYPE,
				Specs: []ast.Spec{typedNode},
			})

		case *ast.BlockStmt:
			// Extract statements from block
			if typedNode != nil && len(typedNode.List) > 0 {
				topLevelStmts = append(topLevelStmts, typedNode.List...)
			}

		case ast.Stmt:
			// Add single statement
			if typedNode != nil {
				topLevelStmts = append(topLevelStmts, typedNode)
			}

		case []ast.Stmt:
			// Add multiple statements
			for _, stmt := range typedNode {
				if stmt != nil {
					topLevelStmts = append(topLevelStmts, stmt)
				}
			}
		}
	}

	// If no main function was defined but we have top-level statements,
	// create a synthetic main function
	if !mainFound && len(topLevelStmts) > 0 {
		file.Decls = append(file.Decls, &ast.FuncDecl{
			Name: ast.NewIdent("main"),
			Type: &ast.FuncType{
				Params:  &ast.FieldList{},
				Results: nil,
			},
			Body: &ast.BlockStmt{
				List: topLevelStmts,
			},
		})
	} else if !mainFound {
		// No main function and no top-level statements, create empty main
		file.Decls = append(file.Decls, &ast.FuncDecl{
			Name: ast.NewIdent("main"),
			Type: &ast.FuncType{
				Params:  &ast.FieldList{},
				Results: nil,
			},
			Body: &ast.BlockStmt{
				List: []ast.Stmt{},
			},
		})
	}

	// Add imports at the beginning of the file
	if len(v.goImports) > 0 {
		var importSpecs []ast.Spec
		for path, alias := range v.goImports {
			importSpec := &ast.ImportSpec{
				Path: &ast.BasicLit{
					Kind:  token.STRING,
					Value: strconv.Quote(path),
				},
			}

			if alias != "" {
				importSpec.Name = ast.NewIdent(alias)
			}

			importSpecs = append(importSpecs, importSpec)
		}

		importDecl := &ast.GenDecl{
			Tok:   token.IMPORT,
			Specs: importSpecs,
		}

		file.Decls = append([]ast.Decl{importDecl}, file.Decls...)
	}

	return file
}

// createEmptyMainFile creates a minimal valid Go program with an empty main function
func createEmptyMainFile() *ast.File {
	return &ast.File{
		Name: ast.NewIdent("main"),
		Decls: []ast.Decl{
			&ast.FuncDecl{
				Name: ast.NewIdent("main"),
				Type: &ast.FuncType{
					Params:  &ast.FieldList{},
					Results: nil,
				},
				Body: &ast.BlockStmt{
					List: []ast.Stmt{},
				},
			},
		},
	}
}

// VisitDeclaration handles the 'declaration' rule
func (v *ManuscriptAstVisitor) VisitDeclaration(ctx parser.IDeclarationContext) interface{} {
	if ctx == nil {
		v.addError("Received nil declaration context", nil)
		return nil
	}

	// Handle let declarations specially
	if letCtx, ok := ctx.(*parser.DeclLetContext); ok {
		letDecl := letCtx.LetDecl()
		if letDecl != nil {
			letResult := v.Visit(letDecl)
			return v.processLetDeclResult(letResult, ctx.GetStart())
		}
	}

	// Handle all other declarations
	if child, ok := ctx.GetChild(0).(antlr.ParseTree); ok {
		result := v.Visit(child)
		return v.processGenericDeclResult(result)
	}

	v.addError("Declaration child is not a ParseTree: "+ctx.GetText(), ctx.GetStart())
	return nil
}

// processLetDeclResult handles the result of visiting a let declaration
func (v *ManuscriptAstVisitor) processLetDeclResult(result interface{}, token antlr.Token) interface{} {
	switch typedResult := result.(type) {
	case []ast.Stmt:
		return typedResult
	case *ast.BlockStmt:
		return typedResult.List
	case ast.Stmt:
		return []ast.Stmt{typedResult}
	case nil:
		return nil
	default:
		v.addError("LetDecl did not return expected statement type", token)
		return nil
	}
}

// processGenericDeclResult handles the result of visiting non-let declarations
func (v *ManuscriptAstVisitor) processGenericDeclResult(result interface{}) interface{} {
	switch typedResult := result.(type) {
	case []ast.Stmt:
		return typedResult
	case *ast.BlockStmt:
		return typedResult.List
	case ast.Stmt:
		return []ast.Stmt{typedResult}
	case nil:
		return nil
	default:
		// For other types, pass through unchanged
		return result
	}
}
