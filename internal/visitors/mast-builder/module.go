package mastb

import (
	"manuscript-lang/manuscript/internal/ast"
	"manuscript-lang/manuscript/internal/parser"
)

func (v *ParseTreeToAST) VisitImportDecl(ctx *parser.ImportDeclContext) interface{} {
	importDecl := &ast.ImportDecl{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if ctx.ModuleImport() != nil {
		if moduleImport := ctx.ModuleImport().Accept(v); moduleImport != nil {
			importDecl.Import = moduleImport.(ast.ModuleImport)
		}
	}

	return importDecl
}

func (v *ParseTreeToAST) VisitExportDecl(ctx *parser.ExportDeclContext) interface{} {
	exportDecl := &ast.ExportDecl{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if ctx.ExportedItem() != nil {
		if item := ctx.ExportedItem().Accept(v); item != nil {
			exportDecl.Item = item.(ast.Declaration)
		}
	}

	return exportDecl
}

func (v *ParseTreeToAST) VisitExternDecl(ctx *parser.ExternDeclContext) interface{} {
	externDecl := &ast.ExternDecl{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if ctx.ModuleImport() != nil {
		if moduleImport := ctx.ModuleImport().Accept(v); moduleImport != nil {
			externDecl.Import = moduleImport.(ast.ModuleImport)
		}
	}

	return externDecl
}

func (v *ParseTreeToAST) VisitExportedItem(ctx *parser.ExportedItemContext) interface{} {
	// Delegate to the specific exported item type
	if ctx.FnDecl() != nil {
		return ctx.FnDecl().Accept(v)
	}
	if ctx.LetDecl() != nil {
		return ctx.LetDecl().Accept(v)
	}
	if ctx.TypeDecl() != nil {
		return ctx.TypeDecl().Accept(v)
	}
	if ctx.InterfaceDecl() != nil {
		return ctx.InterfaceDecl().Accept(v)
	}
	return nil
}

func (v *ParseTreeToAST) VisitModuleImport(ctx *parser.ModuleImportContext) interface{} {
	if ctx.DestructuredImport() != nil {
		return ctx.DestructuredImport().Accept(v)
	}
	if ctx.TargetImport() != nil {
		return ctx.TargetImport().Accept(v)
	}
	return nil
}

func (v *ParseTreeToAST) VisitDestructuredImport(ctx *parser.DestructuredImportContext) interface{} {
	destructuredImport := &ast.DestructuredImport{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	// Extract module path from single quoted string
	if ctx.SingleQuotedString() != nil {
		if strLit := ctx.SingleQuotedString().Accept(v); strLit != nil {
			// Extract the actual string value from the string literal
			if stringLiteral, ok := strLit.(*ast.StringLiteral); ok {
				destructuredImport.Module = v.extractStringValue(stringLiteral)
			}
		}
	}

	// Extract import items
	if ctx.ImportItemList() != nil {
		if itemList := ctx.ImportItemList().Accept(v); itemList != nil {
			destructuredImport.Items = itemList.([]ast.ImportItem)
		}
	}

	return destructuredImport
}

func (v *ParseTreeToAST) VisitTargetImport(ctx *parser.TargetImportContext) interface{} {
	targetImport := &ast.TargetImport{
		NamedNode: ast.NamedNode{
			BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
			Name:     ctx.ID().GetText(),
		},
	}

	// Extract module path from single quoted string
	if ctx.SingleQuotedString() != nil {
		if strLit := ctx.SingleQuotedString().Accept(v); strLit != nil {
			if stringLiteral, ok := strLit.(*ast.StringLiteral); ok {
				targetImport.Module = v.extractStringValue(stringLiteral)
			}
		}
	}

	return targetImport
}

func (v *ParseTreeToAST) VisitImportItemList(ctx *parser.ImportItemListContext) interface{} {
	var items []ast.ImportItem
	for _, itemCtx := range ctx.AllImportItem() {
		if item := itemCtx.Accept(v); item != nil {
			items = append(items, item.(ast.ImportItem))
		}
	}
	return items
}

func (v *ParseTreeToAST) VisitImportItem(ctx *parser.ImportItemContext) interface{} {
	// Use the first ID token for more precise positioning
	idToken := ctx.AllID()[0].GetSymbol()
	item := ast.ImportItem{
		NamedNode: ast.NamedNode{
			BaseNode: ast.BaseNode{Position: v.getPositionFromToken(idToken)},
			Name:     ctx.AllID()[0].GetText(),
		},
	}

	if len(ctx.AllID()) > 1 {
		item.Alias = ctx.AllID()[1].GetText()
	}

	return item
}
