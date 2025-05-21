package visitor

import (
	"go/ast"
	"go/token"
	"manuscript-co/manuscript/internal/parser"
	"strconv"

	"github.com/antlr4-go/antlr/v4"
)

// VisitProgram handles the root of the parse tree (program rule).
func (v *ManuscriptAstVisitor) VisitProgram(ctx *parser.ProgramContext) interface{} {
	if ctx == nil {
		v.addError("Received nil program context", nil)
		return createEmptyMainFile()
	}

	file := &ast.File{
		Name:  ast.NewIdent("main"),
		Decls: []ast.Decl{},
	}

	mainFound := false
	var mainFunc *ast.FuncDecl
	var topLevelStmts []ast.Stmt

	for _, decl := range ctx.AllDeclaration() {
		if decl == nil {
			continue
		}
		var node interface{}
		node = v.VisitDeclaration(decl)

		switch n := node.(type) {
		case []ast.Decl:
			file.Decls = append(file.Decls, n...)
		case ast.Decl:
			if n == nil {
				continue
			}
			if fn, ok := n.(*ast.FuncDecl); ok && fn.Name != nil && fn.Name.Name == "main" {
				if mainFound {
					v.addError("Multiple main functions defined.", decl.GetStart())
					continue
				}
				mainFound = true
				mainFunc = n.(*ast.FuncDecl)
			}
			file.Decls = append(file.Decls, n)
		case *ast.TypeSpec:
			file.Decls = append(file.Decls, &ast.GenDecl{Tok: token.TYPE, Specs: []ast.Spec{n}})
		case ast.Stmt:
			if n != nil {
				topLevelStmts = append(topLevelStmts, n)
			}
		case []ast.Stmt:
			for _, stmt := range n {
				if stmt != nil {
					topLevelStmts = append(topLevelStmts, stmt)
				}
			}
		case nil:
			// skip
		default:
			v.addError("Internal error: Unhandled node type for declaration", decl.GetStart())
		}
	}

	if !mainFound {
		file.Decls = append(file.Decls, &ast.FuncDecl{
			Name: ast.NewIdent("main"),
			Type: &ast.FuncType{Params: &ast.FieldList{}, Results: nil},
			Body: &ast.BlockStmt{List: topLevelStmts},
		})
	} else if mainFunc != nil && len(topLevelStmts) > 0 {
		mainFunc.Body.List = append(topLevelStmts, mainFunc.Body.List...)
	}

	if len(v.goImports) > 0 {
		var specs []ast.Spec
		for path := range v.goImports {
			specs = append(specs, &ast.ImportSpec{
				Path: &ast.BasicLit{
					Kind:  token.STRING,
					Value: strconv.Quote(path),
				},
			})
		}
		file.Decls = append([]ast.Decl{&ast.GenDecl{Tok: token.IMPORT, Specs: specs}}, file.Decls...)
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

// VisitDeclaration handles the 'declaration' rule using the ANTLR visitor pattern.
func (v *ManuscriptAstVisitor) VisitDeclaration(ctx parser.IDeclarationContext) interface{} {
	if ctx == nil {
		v.addError("Received nil declaration context", nil)
		return nil
	}
	// Only DeclLetContext has LetDecl method
	if letCtx, ok := ctx.(*parser.DeclLetContext); ok {
		letDecl := letCtx.LetDecl()
		if letDecl != nil {
			letResult := v.Visit(letDecl)
			switch stmts := letResult.(type) {
			case []ast.Stmt:
				return stmts
			case *ast.BlockStmt:
				return stmts
			case ast.Stmt:
				return []ast.Stmt{stmts}
			case nil:
				return nil
			default:
				v.addError("LetDecl did not return ast.Stmt or []ast.Stmt", ctx.GetStart())
				return nil
			}
		}
	}
	if child, ok := ctx.GetChild(0).(antlr.ParseTree); ok {
		return v.Visit(child)
	}
	v.addError("Declaration child is not a ParseTree: "+ctx.GetText(), ctx.GetStart())
	return nil
}
