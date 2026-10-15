package lower

import (
	"go/ast"
	"go/token"
	"strconv"
)

// These builders describe Go syntax, not snippets. Identifiers are checked
// IDs or compiler-owned names; source text enters only through quoted literals.
func ident(name string) *ast.Ident { return ast.NewIdent(name) }
func selector(value ast.Expr, name string) *ast.SelectorExpr {
	return &ast.SelectorExpr{X: value, Sel: ident(name)}
}
func rtName(name string) ast.Expr { return selector(ident("rt"), name) }
func textLiteral(value string) ast.Expr {
	return &ast.BasicLit{Kind: token.STRING, Value: strconv.Quote(value)}
}
func intLiteral(value int) ast.Expr {
	return &ast.BasicLit{Kind: token.INT, Value: strconv.Itoa(value)}
}
func call(fn ast.Expr, args ...ast.Expr) *ast.CallExpr   { return &ast.CallExpr{Fun: fn, Args: args} }
func rtCall(name string, args ...ast.Expr) *ast.CallExpr { return call(rtName(name), args...) }

// generic instantiates a generic function or type with explicit arguments.
func generic(fn ast.Expr, args ...ast.Expr) ast.Expr {
	if len(args) == 0 {
		return fn
	}
	if len(args) == 1 {
		return &ast.IndexExpr{X: fn, Index: args[0]}
	}
	return &ast.IndexListExpr{X: fn, Indices: args}
}
func composite(typ ast.Expr, elements ...ast.Expr) *ast.CompositeLit {
	return &ast.CompositeLit{Type: typ, Elts: elements}
}
func keyed(name string, value ast.Expr) ast.Expr {
	return &ast.KeyValueExpr{Key: ident(name), Value: value}
}
func sliceOf(typ ast.Expr) ast.Expr { return &ast.ArrayType{Elt: typ} }
func sliceLiteral(typ ast.Expr, values ...ast.Expr) ast.Expr {
	return composite(sliceOf(typ), values...)
}
func address(value ast.Expr) ast.Expr   { return &ast.UnaryExpr{Op: token.AND, X: value} }
func pointerTo(typ ast.Expr) ast.Expr   { return &ast.StarExpr{X: typ} }
func not(value ast.Expr) ast.Expr       { return &ast.UnaryExpr{Op: token.NOT, X: paren(value)} }
func paren(value ast.Expr) ast.Expr     { return &ast.ParenExpr{X: value} }
func index(value, at ast.Expr) ast.Expr { return &ast.IndexExpr{X: value, Index: at} }
func block(statements ...ast.Stmt) *ast.BlockStmt {
	return &ast.BlockStmt{List: statements}
}
func assign(left ast.Expr, op token.Token, right ast.Expr) ast.Stmt {
	return &ast.AssignStmt{Lhs: []ast.Expr{left}, Tok: op, Rhs: []ast.Expr{right}}
}
func define(name string, value ast.Expr) ast.Stmt { return assign(ident(name), token.DEFINE, value) }
func discard(value ast.Expr) ast.Stmt             { return assign(ident("_"), token.ASSIGN, value) }
func returned(values ...ast.Expr) ast.Stmt        { return &ast.ReturnStmt{Results: values} }
func evaluated(value ast.Expr) ast.Stmt           { return &ast.ExprStmt{X: value} }
func field(name string, typ ast.Expr) *ast.Field {
	return &ast.Field{Names: []*ast.Ident{ident(name)}, Type: typ}
}
func functionType(params []*ast.Field, result ast.Expr) *ast.FuncType {
	typ := &ast.FuncType{Params: &ast.FieldList{List: params}}
	if result != nil {
		typ.Results = &ast.FieldList{List: []*ast.Field{{Type: result}}}
	}
	return typ
}
func closure(params []*ast.Field, result ast.Expr, body ...ast.Stmt) *ast.FuncLit {
	return &ast.FuncLit{Type: functionType(params, result), Body: block(body...)}
}
func varDecl(name string, typ, value ast.Expr) ast.Stmt {
	spec := &ast.ValueSpec{Names: []*ast.Ident{ident(name)}, Type: typ}
	if value != nil {
		spec.Values = []ast.Expr{value}
	}
	return &ast.DeclStmt{Decl: &ast.GenDecl{Tok: token.VAR, Specs: []ast.Spec{spec}}}
}
func binary(left ast.Expr, op token.Token, right ast.Expr) ast.Expr {
	return &ast.BinaryExpr{X: left, Op: op, Y: right}
}
