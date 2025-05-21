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

// VisitMapLiteralEmpty handles map literal expressions like [:]
func (v *ManuscriptAstVisitor) VisitMapLiteralEmpty(ctx *parser.MapLiteralContext) interface{} {
	mapType := &ast.MapType{
		Key:   ast.NewIdent("interface{}"),
		Value: ast.NewIdent("interface{}"),
	}
	return &ast.CompositeLit{Type: mapType, Elts: nil}
}

// VisitMapLiteralNonEmpty handles map literal expressions like [key1: value1, key2: value2]
func (v *ManuscriptAstVisitor) VisitMapLiteralNonEmpty(ctx *parser.MapLiteralContext) interface{} {
	mapType := &ast.MapType{
		Key:   ast.NewIdent("interface{}"),
		Value: ast.NewIdent("interface{}"),
	}
	var elts []ast.Expr
	for _, f := range ctx.AllMapField() {
		fieldCtx, ok := f.(*parser.MapFieldContext)
		if !ok || fieldCtx == nil {
			continue
		}
		allExprs := fieldCtx.AllExpr()
		if len(allExprs) != 2 {
			v.addError("Map field must have exactly 2 expressions (key: value): "+fieldCtx.GetText(), fieldCtx.GetStart())
			continue
		}
		keyExpr, okKey := v.Visit(allExprs[0]).(ast.Expr)
		valExpr, okVal := v.Visit(allExprs[1]).(ast.Expr)
		if okKey && okVal {
			elts = append(elts, &ast.KeyValueExpr{Key: keyExpr, Value: valExpr})
		} else {
			if !okKey {
				v.addError("Map key is not a valid expression: "+allExprs[0].GetText(), allExprs[0].GetStart())
			}
			if !okVal {
				v.addError("Map value is not a valid expression: "+allExprs[1].GetText(), allExprs[1].GetStart())
			}
			// Optionally, append a BadExpr to keep the element count correct
			elts = append(elts, &ast.KeyValueExpr{
				Key:   &ast.BadExpr{},
				Value: &ast.BadExpr{},
			})
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
