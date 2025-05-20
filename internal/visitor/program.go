package visitor

import (
	"go/ast"
	"go/token"
	"manuscript-co/manuscript/internal/parser"
	"strconv"
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
		if concreteDecl, ok := decl.(*parser.DeclarationContext); ok {
			node = v.VisitDeclaration(concreteDecl)
		} else {
			v.addError("Internal error: Declaration is not *parser.DeclarationContext", decl.GetStart())
			continue
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

// VisitDeclaration handles the 'declaration' rule and dispatches to the correct declaration type.
func (v *ManuscriptAstVisitor) VisitDeclaration(ctx *parser.DeclarationContext) interface{} {
	if ctx == nil {
		v.addError("Received nil declaration context", nil)
		return nil
	}

	if importDecl := ctx.ImportDecl(); importDecl != nil {
		if concreteImportDecl, ok := importDecl.(*parser.ImportDeclContext); ok {
			return v.VisitImportDecl(concreteImportDecl)
		}
		v.addError("Internal error: ImportDecl is not *parser.ImportDeclContext", importDecl.GetStart())
		return nil
	}
	if exportDecl := ctx.ExportDecl(); exportDecl != nil {
		if concreteExportDecl, ok := exportDecl.(*parser.ExportDeclContext); ok {
			return v.VisitExportDecl(concreteExportDecl)
		}
		v.addError("Internal error: ExportDecl is not *parser.ExportDeclContext", exportDecl.GetStart())
		return nil
	}
	if externDecl := ctx.ExternDecl(); externDecl != nil {
		if concreteExternDecl, ok := externDecl.(*parser.ExternDeclContext); ok {
			return v.VisitExternDecl(concreteExternDecl)
		}
		v.addError("Internal error: ExternDecl is not *parser.ExternDeclContext", externDecl.GetStart())
		return nil
	}
	if letDecl := ctx.LetDecl(); letDecl != nil {
		return v.Visit(letDecl)
	}
	if typeDecl := ctx.TypeDecl(); typeDecl != nil {
		return v.Visit(typeDecl)
	}
	if interfaceDecl := ctx.InterfaceDecl(); interfaceDecl != nil {
		return v.Visit(interfaceDecl)
	}
	if fnDecl := ctx.FnDecl(); fnDecl != nil {
		return v.Visit(fnDecl)
	}
	if methodsDecl := ctx.MethodsDecl(); methodsDecl != nil {
		return v.Visit(methodsDecl)
	}

	v.addError("Unhandled declaration type in VisitDeclaration: "+ctx.GetText(), ctx.GetStart())
	return nil
}
