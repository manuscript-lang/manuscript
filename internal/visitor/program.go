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
		Name:  ast.NewIdent("main"),
		Decls: []ast.Decl{},
	}
	mainFound := false
	var mainFunc *ast.FuncDecl
	var topLevelStmts []ast.Stmt

	for _, item := range ctx.AllProgramItem() {
		if item == nil {
			continue
		}
		var node interface{}
		switch {
		case item.ImportStmt() != nil:
			node = v.Visit(item.ImportStmt())
		case item.ExportStmt() != nil:
			node = v.Visit(item.ExportStmt())
		case item.ExternStmt() != nil:
			node = v.Visit(item.ExternStmt())
		case item.LetDecl() != nil:
			node = v.Visit(item.LetDecl())
		case item.TypeDecl() != nil:
			node = v.Visit(item.TypeDecl())
		case item.InterfaceDecl() != nil:
			node = v.Visit(item.InterfaceDecl())
		case item.FnDecl() != nil:
			node = v.Visit(item.FnDecl())
		case item.MethodsDecl() != nil:
			node = v.Visit(item.MethodsDecl())
		default:
			text := item.GetText()
			if text != "" && text != "<EOF>" {
				v.addError("VisitProgram: Unhandled program item: "+text, item.GetStart())
			}
		}

		switch n := node.(type) {
		case []ast.Decl:
			file.Decls = append(file.Decls, n...)
		case ast.Decl:
			if n == nil {
				continue
			}
			if fn, ok := n.(*ast.FuncDecl); ok && fn.Name != nil && fn.Name.Name == "main" {
				if mainFound {
					var tok antlr.Token
					if fnDecl := item.FnDecl(); fnDecl != nil &&
						fnDecl.FnSignature() != nil &&
						fnDecl.FnSignature().NamedID() != nil &&
						fnDecl.FnSignature().NamedID().ID() != nil {
						tok = fnDecl.FnSignature().NamedID().ID().GetSymbol()
					} else {
						tok = item.GetStart()
					}
					v.addError("Multiple main functions defined.", tok)
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
			text := item.GetText()
			if text != "" && text != "<EOF>" {
				v.addError("VisitProgram: Child visit returned nil for: "+text, item.GetStart())
			}
		default:
			v.addError("Internal error: Unhandled node type for: "+item.GetText(), item.GetStart())
		}
	}

	if !mainFound {
		file.Decls = append(file.Decls, &ast.FuncDecl{
			Name: ast.NewIdent("main"),
			Type: &ast.FuncType{Params: &ast.FieldList{}},
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
