package visitor

import (
	"go/ast"
	"manuscript-co/manuscript/internal/parser"
)

// VisitArrayLiteral handles array literal expressions: [expr, ...]
func (v *ManuscriptAstVisitor) VisitArrayLiteral(ctx *parser.ArrayLiteralContext) interface{} {
	var elts []ast.Expr
	if ctx.ExprList() != nil {
		if exprListCtx, ok := ctx.ExprList().(*parser.ExprListContext); ok {
			if exprs, ok := v.VisitExprList(exprListCtx).([]ast.Expr); ok {
				elts = exprs
			}
		}
	}
	return &ast.CompositeLit{
		Type: &ast.ArrayType{Elt: ast.NewIdent("interface{}")},
		Elts: elts,
	}
}

// VisitMapLiteralEmpty handles map literal expressions: [:]
func (v *ManuscriptAstVisitor) VisitMapLiteralEmpty(ctx *parser.MapLiteralEmptyContext) interface{} {
	return &ast.CompositeLit{
		Type: &ast.MapType{
			Key:   ast.NewIdent("interface{}"),
			Value: ast.NewIdent("interface{}"),
		},
		Elts: nil,
	}
}

// VisitMapLiteralNonEmpty handles map literal expressions: [key: value, ...]
func (v *ManuscriptAstVisitor) VisitMapLiteralNonEmpty(ctx *parser.MapLiteralNonEmptyContext) interface{} {
	var elts []ast.Expr
	if mfl := ctx.MapFieldList(); mfl != nil {
		for _, f := range mfl.AllMapField() {
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
			}
		}
	}
	return &ast.CompositeLit{
		Type: &ast.MapType{
			Key:   ast.NewIdent("interface{}"),
			Value: ast.NewIdent("interface{}"),
		},
		Elts: elts,
	}
}

// VisitSetLiteral handles set literal expressions: <expr, ...>
// Sets are translated to map[interface{}]bool in Go.
func (v *ManuscriptAstVisitor) VisitSetLiteral(ctx *parser.SetLiteralContext) interface{} {
	var elts []ast.Expr
	for _, e := range ctx.AllExpr() {
		if expr, ok := v.Visit(e).(ast.Expr); ok {
			elts = append(elts, &ast.KeyValueExpr{Key: expr, Value: ast.NewIdent("true")})
		} else {
			v.addError("Set element is not a valid expression: "+e.GetText(), e.GetStart())
		}
	}
	return &ast.CompositeLit{
		Type: &ast.MapType{
			Key:   ast.NewIdent("interface{}"),
			Value: ast.NewIdent("bool"),
		},
		Elts: elts,
	}
}
