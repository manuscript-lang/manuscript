package visitor

import (
	"go/ast"
	"manuscript-co/manuscript/internal/parser"
)

// VisitArrayLiteral handles array literal expressions like [1, 2, 3]
func (v *ManuscriptAstVisitor) VisitArrayLiteral(ctx *parser.ArrayLiteralContext) interface{} {
	var elts []ast.Expr
	if exprList := ctx.ExprList(); exprList != nil {
		for _, e := range exprList.AllExpr() {
			if expr, ok := v.Visit(e).(ast.Expr); ok {
				elts = append(elts, expr)
			} else {
				v.addError("Array element is not a valid expression: "+e.GetText(), e.GetStart())
				elts = append(elts, &ast.BadExpr{})
			}
		}
	}
	return &ast.CompositeLit{
		Type: &ast.ArrayType{Elt: ast.NewIdent("interface{}")},
		Elts: elts,
	}
}

// VisitMapLiteral handles map literal expressions like [:] or [key1: value1, key2: value2]
func (v *ManuscriptAstVisitor) VisitMapLiteral(ctx *parser.MapLiteralContext) interface{} {
	mapType := &ast.MapType{
		Key:   ast.NewIdent("interface{}"),
		Value: ast.NewIdent("interface{}"),
	}
	var elts []ast.Expr
	for _, f := range ctx.AllMapField() {
		field := f.(*parser.MapFieldContext)
		k, okk := v.Visit(field.GetKey()).(ast.Expr)
		v_, okv := v.Visit(field.GetValue()).(ast.Expr)
		if okk && okv {
			elts = append(elts, &ast.KeyValueExpr{Key: k, Value: v_})
		} else {
			if !okk {
				v.addError("Map key is not a valid expression: "+field.GetKey().GetText(), field.GetKey().GetStart())
			}
			if !okv {
				v.addError("Map value is not a valid expression: "+field.GetValue().GetText(), field.GetValue().GetStart())
			}
		}
	}
	return &ast.CompositeLit{Type: mapType, Elts: elts}
}

// VisitSetLiteral handles set literal expressions like <1, 2, 3>
// Sets don't exist natively in Go, so we'll translate them to maps with bool values
func (v *ManuscriptAstVisitor) VisitSetLiteral(ctx *parser.SetLiteralContext) interface{} {
	setType := &ast.MapType{
		Key:   ast.NewIdent("interface{}"),
		Value: ast.NewIdent("bool"),
	}
	var elts []ast.Expr
	for _, e := range ctx.AllExpr() {
		if expr, ok := v.Visit(e).(ast.Expr); ok {
			elts = append(elts, &ast.KeyValueExpr{Key: expr, Value: ast.NewIdent("true")})
		} else {
			v.addError("Set element is not a valid expression: "+e.GetText(), e.GetStart())
		}
	}
	return &ast.CompositeLit{Type: setType, Elts: elts}
}
