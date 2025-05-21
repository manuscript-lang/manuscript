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
