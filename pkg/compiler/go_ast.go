package compiler

import (
	"go/ast"
	"go/token"
	"strconv"
)

// These builders describe Go syntax, not snippets. Identifiers are checked IDs
// or compiler-owned names; source text enters only through quoted literals.
func ident(name string) *ast.Ident { return ast.NewIdent(name) }
func selector(value ast.Expr, name string) *ast.SelectorExpr {
	return &ast.SelectorExpr{X: value, Sel: ident(name)}
}
func runtimeName(name string) ast.Expr { return selector(ident("rt"), name) }
func textLiteral(value string) ast.Expr {
	return &ast.BasicLit{Kind: token.STRING, Value: strconv.Quote(value)}
}
func intLiteral(value int) ast.Expr {
	return &ast.BasicLit{Kind: token.INT, Value: strconv.Itoa(value)}
}
func call(fn ast.Expr, args ...ast.Expr) *ast.CallExpr { return &ast.CallExpr{Fun: fn, Args: args} }
func runtimeCall(name string, args ...ast.Expr) *ast.CallExpr {
	return call(runtimeName(name), args...)
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
func stringSlice(values []string) ast.Expr {
	elements := make([]ast.Expr, len(values))
	for i, v := range values {
		elements[i] = textLiteral(v)
	}
	return sliceLiteral(ident("string"), elements...)
}
func address(value ast.Expr) ast.Expr             { return &ast.UnaryExpr{Op: token.AND, X: value} }
func index(value, at ast.Expr) ast.Expr           { return &ast.IndexExpr{X: value, Index: at} }
func block(statements ...ast.Stmt) *ast.BlockStmt { return &ast.BlockStmt{List: statements} }
func assign(left ast.Expr, op token.Token, right ast.Expr) ast.Stmt {
	return &ast.AssignStmt{Lhs: []ast.Expr{left}, Tok: op, Rhs: []ast.Expr{right}}
}
func define(name string, value ast.Expr) ast.Stmt { return assign(ident(name), token.DEFINE, value) }
func discard(value ast.Expr) ast.Stmt             { return assign(ident("_"), token.ASSIGN, value) }
func returned(value ast.Expr) ast.Stmt            { return &ast.ReturnStmt{Results: []ast.Expr{value}} }
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
func variable(name string, typ, value ast.Expr) *ast.GenDecl {
	spec := &ast.ValueSpec{Names: []*ast.Ident{ident(name)}, Type: typ}
	if value != nil {
		spec.Values = []ast.Expr{value}
	}
	return &ast.GenDecl{Tok: token.VAR, Specs: []ast.Spec{spec}}
}
func unit() ast.Expr          { return composite(runtimeName("Unit")) }
func typeArguments() ast.Expr { return &ast.MapType{Key: ident("string"), Value: ident("string")} }
func typeScopes() ast.Expr {
	return &ast.MapType{Key: ident("string"), Value: runtimeName("TypeScope")}
}
func buildParameters(receiver bool) []*ast.Field {
	var fields []*ast.Field
	if receiver {
		fields = append(fields, field("receiver", runtimeName("Value")))
	}
	return append(fields, field("typeArgs", typeArguments()), field("typeScopes", typeScopes()))
}
func concreteFunction(fn ast.Expr) ast.Expr {
	return call(closure(nil, runtimeName("Function"), define("typeArgs", composite(typeArguments())), discard(ident("typeArgs")), returned(fn)))
}
