package visitor

import (
	"go/ast"
	"manuscript-co/manuscript/internal/parser"
)

// VisitLetDeclSingle handles 'let typedID = expr' or 'let typedID'
func (v *ManuscriptAstVisitor) VisitLabelLetDeclSingle(ctx *parser.LabelLetDeclSingleContext) interface{} {
	letSingle := ctx.LetSingle()
	if letSingle == nil {
		v.addError("Missing letSingle in let declaration: "+ctx.GetText(), ctx.GetStart())
		return &ast.EmptyStmt{}
	}
	return v.Visit(letSingle)
}

// VisitLetDeclBlock handles 'let ( ... )'
func (v *ManuscriptAstVisitor) VisitLabelLetDeclBlock(ctx *parser.LabelLetDeclBlockContext) interface{} {
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
func (v *ManuscriptAstVisitor) VisitLabelLetDeclDestructuredObj(ctx *parser.LabelLetDeclDestructuredObjContext) interface{} {
	letObj := ctx.LetDestructuredObj()
	if letObj == nil {
		v.addError("Missing LetDestructuredObj in let declaration: "+ctx.GetText(), ctx.GetStart())
		return &ast.EmptyStmt{}
	}
	return v.Visit(letObj)
}

// VisitLetDeclDestructuredArray handles 'let [a, b] = expr'
func (v *ManuscriptAstVisitor) VisitLabelLetDeclDestructuredArray(ctx *parser.LabelLetDeclDestructuredArrayContext) interface{} {
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
	case *parser.LabelModuleImportTargetContext:
		return v.VisitLabelModuleImportTarget(t)
	case *parser.LabelModuleImportDestructuredContext:
		return v.VisitLabelModuleImportDestructured(t)
	default:
		v.addError("Unknown module import type", ctx.GetStart())
		return nil
	}
}

// VisitExportDecl expects the exported item visitor methods to be implemented and return Go AST nodes.
func (v *ManuscriptAstVisitor) VisitExportDecl(ctx *parser.ExportDeclContext) interface{} {
	if ctx == nil || ctx.ExportedItem() == nil {
		v.addError("Export declaration is missing an exported item.", ctx.GetStart())
		return &ast.BadDecl{}
	}
	// Use Accept to visit the exported item, leveraging the grammar structure
	visitedNode := ctx.ExportedItem().Accept(v)
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

// VisitExportedFn delegates to VisitFnDecl
func (v *ManuscriptAstVisitor) VisitLabelExportedFn(ctx *parser.LabelExportedFnContext) interface{} {
	if ctx == nil || ctx.FnDecl() == nil {
		return nil
	}
	if fnCtx, ok := ctx.FnDecl().(*parser.FnDeclContext); ok {
		return v.VisitFnDecl(fnCtx)
	}
	return nil
}

// VisitExportedLet delegates to VisitLetDecl
func (v *ManuscriptAstVisitor) VisitLabelExportedLet(ctx *parser.LabelExportedLetContext) interface{} {
	if ctx == nil || ctx.LetDecl() == nil {
		return nil
	}
	if letCtx, ok := ctx.LetDecl().(*parser.LetDeclContext); ok {
		return v.Visit(letCtx)
	}
	return nil
}

// VisitExportedType delegates to VisitTypeDecl
func (v *ManuscriptAstVisitor) VisitLabelExportedType(ctx *parser.LabelExportedTypeContext) interface{} {
	if ctx == nil || ctx.TypeDecl() == nil {
		return nil
	}
	if typeCtx, ok := ctx.TypeDecl().(*parser.TypeDeclContext); ok {
		return v.VisitTypeDecl(typeCtx)
	}
	return nil
}

// VisitExportedInterface delegates to VisitInterfaceDecl
func (v *ManuscriptAstVisitor) VisitLabelExportedInterface(ctx *parser.LabelExportedInterfaceContext) interface{} {
	if ctx == nil || ctx.InterfaceDecl() == nil {
		return nil
	}
	if ifaceCtx, ok := ctx.InterfaceDecl().(*parser.InterfaceDeclContext); ok {
		return v.VisitInterfaceDecl(ifaceCtx)
	}
	return nil
}
