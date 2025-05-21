package visitor

import (
	"go/ast"
	"manuscript-co/manuscript/internal/parser"
)

func (v *ManuscriptAstVisitor) VisitStructInitExpr(ctx *parser.StructInitExprContext) interface{} {
	if ctx == nil {
		v.addError("VisitStructInitExpr called with nil context", nil)
		return &ast.BadExpr{}
	}
	if ctx.ID() == nil {
		v.addError("Struct initialization missing type name", ctx.GetStart())
		return &ast.BadExpr{}
	}
	structTypeName := ctx.ID().GetText()
	structTypeExpr := ast.NewIdent(structTypeName)
	keyValueElts := make([]ast.Expr, 0)
	if ctx.StructFieldList() != nil {
		for _, f := range ctx.StructFieldList().AllStructField() {
			keyNode := f.ID()
			valCtx := f.Expr()
			if keyNode == nil {
				v.addError("Struct field missing key", f.GetStart())
				continue
			}
			fieldName := keyNode.GetText()
			if valCtx == nil {
				v.addError("Struct field missing value", f.GetStart())
				continue
			}
			valueResult := v.Visit(valCtx)
			valueExpr, ok := valueResult.(ast.Expr)
			if !ok {
				v.addError("Struct field value did not resolve to a valid expression", valCtx.GetStart())
				continue
			}
			keyValueElts = append(keyValueElts, &ast.KeyValueExpr{
				Key:   ast.NewIdent(fieldName),
				Value: valueExpr,
			})
		}
	}
	return &ast.CompositeLit{
		Type: structTypeExpr,
		Elts: keyValueElts,
	}
}
