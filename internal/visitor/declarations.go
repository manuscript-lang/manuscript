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

func (v *ManuscriptAstVisitor) VisitExternDecl(ctx *parser.ExternDeclContext) interface{} {
	modImport := ctx.ModuleImport()
	if modImport != nil {
		return v.Visit(modImport)
	}
	return nil
}
