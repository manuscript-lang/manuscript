package visitor

import (
	"go/ast"
	"manuscript-co/manuscript/internal/parser"
)

// VisitLetDeclSingle handles 'let typedID = expr' or 'let typedID'
func (v *ManuscriptAstVisitor) VisitLetDeclSingle(ctx *parser.LetDeclSingleContext) interface{} {
	letSingle := ctx.LetSingle()
	if letSingle == nil {
		v.addError("Missing letSingle in let declaration: "+ctx.GetText(), ctx.GetStart())
		return &ast.EmptyStmt{}
	}
	return v.Visit(letSingle)
}

// VisitLetDeclBlock handles 'let ( ... )'
func (v *ManuscriptAstVisitor) VisitLetDeclBlock(ctx *parser.LetDeclBlockContext) interface{} {
	if ctx == nil {
		v.addError("VisitLetBlock called with nil context", nil)
		return []ast.Stmt{&ast.BadStmt{}}
	}
	letBlock := ctx.LetBlock()
	if letBlock == nil {
		return []ast.Stmt{}
	}
	itemList := letBlock.LetBlockItemList()
	if itemList == nil {
		return []ast.Stmt{}
	}
	return v.Visit(itemList)
}

// VisitLetDeclDestructuredObj handles 'let {a, b} = expr'
func (v *ManuscriptAstVisitor) VisitLetDeclDestructuredObj(ctx *parser.LetDeclDestructuredObjContext) interface{} {
	letObj := ctx.LetDestructuredObj()
	if letObj == nil {
		v.addError("Missing LetDestructuredObj in let declaration: "+ctx.GetText(), ctx.GetStart())
		return &ast.EmptyStmt{}
	}
	return v.Visit(letObj)
}

// VisitLetDeclDestructuredArray handles 'let [a, b] = expr'
func (v *ManuscriptAstVisitor) VisitLetDeclDestructuredArray(ctx *parser.LetDeclDestructuredArrayContext) interface{} {
	letArr := ctx.LetDestructuredArray()
	if letArr == nil {
		v.addError("Missing LetDestructuredArray in let declaration: "+ctx.GetText(), ctx.GetStart())
		return &ast.EmptyStmt{}
	}
	return v.Visit(letArr)
}

// VisitImportDecl handles import declarations and lowers them to Go imports and variable assignments
func (v *ManuscriptAstVisitor) VisitImportDecl(ctx *parser.ImportDeclContext) interface{} {
	modImport := ctx.ModuleImport()
	if modImport == nil {
		return nil
	}

	switch t := modImport.(type) {
	case *parser.ModuleImportTargetContext:
		return v.VisitModuleImportTarget(t)
	case *parser.ModuleImportDestructuredContext:
		return v.VisitModuleImportDestructured(t)
	default:
		v.addError("Unknown module import type", ctx.GetStart())
		return nil
	}
}

// VisitDeclImport handles the DeclImport context and dispatches to VisitImportDecl
func (v *ManuscriptAstVisitor) VisitDeclImport(ctx *parser.DeclImportContext) interface{} {
	if ctx == nil {
		return nil
	}
	importDecl := ctx.ImportDecl()
	if importDecl != nil {
		if importDeclCtx, ok := importDecl.(*parser.ImportDeclContext); ok {
			return v.VisitImportDecl(importDeclCtx)
		}
	}
	return nil
}

// VisitDeclExport handles the DeclExport context and dispatches to VisitExportDecl, ensuring Go export naming
func (v *ManuscriptAstVisitor) VisitDeclExport(ctx *parser.DeclExportContext) interface{} {
	if ctx == nil {
		return nil
	}
	exportDecl := ctx.ExportDecl()
	if exportDecl != nil {
		if exportDeclCtx, ok := exportDecl.(*parser.ExportDeclContext); ok {
			return v.VisitExportDecl(exportDeclCtx)
		}
	}
	return nil
}

// VisitExportDecl handles export declarations and ensures Go export naming
func (v *ManuscriptAstVisitor) VisitExportDecl(ctx *parser.ExportDeclContext) interface{} {
	if ctx == nil || ctx.ExportedItem() == nil {
		v.addError("Export declaration is missing an exported item.", ctx.GetStart())
		return &ast.BadDecl{}
	}
	item := ctx.ExportedItem()
	var visitedNode interface{}
	switch t := item.(type) {
	case *parser.ExportedFnContext:
		if fn := t.FnDecl(); fn != nil {
			if fnCtx, ok := fn.(*parser.FnDeclContext); ok {
				visitedNode = v.VisitFnDecl(fnCtx)
			}
		}
	case *parser.ExportedLetContext:
		if let := t.LetDecl(); let != nil {
			if letCtx, ok := let.(*parser.LetDeclContext); ok {
				visitedNode = v.Visit(letCtx)
			}
		}
	case *parser.ExportedTypeContext:
		if typ := t.TypeDecl(); typ != nil {
			if typCtx, ok := typ.(*parser.TypeDeclContext); ok {
				visitedNode = v.VisitTypeDecl(typCtx)
			}
		}
	case *parser.ExportedInterfaceContext:
		if iface := t.InterfaceDecl(); iface != nil {
			if ifaceCtx, ok := iface.(*parser.InterfaceDeclContext); ok {
				visitedNode = v.VisitInterfaceDecl(ifaceCtx)
			}
		}
	default:
		v.addError("Exported item is not a recognized declaration.", ctx.GetStart())
		return &ast.BadDecl{}
	}
	// Capitalize identifiers for Go export
	if decl, ok := visitedNode.(*ast.FuncDecl); ok && decl.Name != nil {
		decl.Name = ast.NewIdent(capitalize(decl.Name.Name))
		return decl
	}
	if decl, ok := visitedNode.(*ast.GenDecl); ok && len(decl.Specs) > 0 {
		for _, spec := range decl.Specs {
			switch s := spec.(type) {
			case *ast.TypeSpec:
				s.Name = ast.NewIdent(capitalize(s.Name.Name))
			case *ast.ValueSpec:
				for i, n := range s.Names {
					s.Names[i] = ast.NewIdent(capitalize(n.Name))
				}
			}
		}
		return decl
	}
	return visitedNode
}

// capitalize returns the string with the first letter uppercased (for Go export)
func capitalize(s string) string {
	if len(s) == 0 {
		return s
	}
	r := []rune(s)
	r[0] = toUpper(r[0])
	return string(r)
}

// toUpper converts a rune to upper case if it's a lower case ASCII letter
func toUpper(r rune) rune {
	if r >= 'a' && r <= 'z' {
		return r - 'a' + 'A'
	}
	return r
}

func (v *ManuscriptAstVisitor) VisitExternDecl(ctx *parser.ExternDeclContext) interface{} {
	modImport := ctx.ModuleImport()
	if modImport != nil {
		return v.Visit(modImport)
	}
	return nil
}
