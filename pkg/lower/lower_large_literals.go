package lower

import (
	"go/ast"

	"github.com/manuscript-lang/manuscript/pkg/ir"
)

// The bound limits native compiler work on effectful literals. Scalar constant
// tables have no large executable initializer and do not use these helpers.
const listInitializationChunk = 64

func (g *generator) largeListLiteral(e ir.List) ast.Expr {
	typ := e.Type
	if g.debugLiterals || len(e.Items) <= largeListThreshold {
		return nil
	}
	if value := g.literalListData(e); value != nil {
		return value
	}
	constructor, initializer, extract := "NewSizedList", "InitListValue", ""
	if typ.ID == "@std/List" && len(typ.Args) == 1 && typ.Args[0].Kind == "primitive" {
		switch typ.Args[0].ID {
		case "Int":
			constructor, initializer, extract = "NewSizedIntList", "InitListInt", "IntValue"
		case "Float":
			constructor, initializer, extract = "NewSizedFloatList", "InitListFloat", "FloatValue"
		case "Bool":
			constructor, initializer, extract = "NewSizedBoolList", "InitListBool", "Bool"
		case "String":
			constructor, initializer, extract = "NewSizedStringList", "InitListString", "string"
		}
	}
	list := g.temp()
	body := []ast.Stmt{define(list, runtimeCall(constructor, g.key(typ), intLiteral(len(e.Items))))}
	g.expressionDepth++
	for start := 0; start < len(e.Items); start += listInitializationChunk {
		end := min(start+listInitializationChunk, len(e.Items))
		statements := make([]ast.Stmt, 0, end-start)
		for at := start; at < end; at++ {
			var value ast.Expr
			if extract != "" {
				constant, signedZero := g.literalDataScalar(e.Items[at], typ.Args[0].ID)
				if !signedZero {
					value = constant
				}
			}
			if value == nil {
				if item, ok := e.Items[at].(ir.Deferred); ok && extract != "" {
					// Use the scalar lane's native-consuming boundary for deferred
					// source operations; its implicit conversions remain authoritative.
					value = g.scalarValueAs(item.Source, typ.Args[0])
				} else if extract == "string" {
					value = g.irValue(e.Items[at])
					// Accept an already concrete String expression without adding
					// a second scalar lowering contract.
					value = &ast.TypeAssertExpr{X: call(runtimeName("Value"), value), Type: ident("string")}
				} else {
					value = g.irValue(e.Items[at])
					if extract != "" {
						value = runtimeCall(extract, value)
					}
				}
			}
			statements = append(statements, evaluated(runtimeCall(initializer, ident(list), intLiteral(at), value)))
		}
		// Source operations keep their ordinary checkpoints and fault sites.
		// Initialization setters add none. Statements capture each element before
		// a later match/call can mutate an earlier plain local or alias.
		body = append(body, evaluated(call(closure(nil, nil, statements...))))
	}
	g.expressionDepth--
	body = append(body, returned(runtimeCall("FinishListInitialization", ident(list))))
	return call(closure(nil, runtimeName("Value"), body...))
}
