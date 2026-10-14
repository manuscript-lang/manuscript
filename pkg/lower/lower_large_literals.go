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
	suffix := ir.ListSuffix(typ)
	constructor, initializer := "NewSizedList", "InitListValue"
	if suffix != "" {
		constructor = "NewSized" + suffix + "List"
		initializer = "InitList" + suffix
	}
	list := g.temp()
	body := []ast.Stmt{define(list, runtimeCall(constructor, g.key(typ), intLiteral(len(e.Items))))}
	g.expressionDepth++
	for start := 0; start < len(e.Items); start += listInitializationChunk {
		end := min(start+listInitializationChunk, len(e.Items))
		statements := make([]ast.Stmt, 0, end-start)
		for at := start; at < end; at++ {
			var value ast.Expr
			if suffix != "" {
				constant, signedZero := g.literalDataScalar(e.Items[at], typ.Args[0].ID)
				if !signedZero {
					value = constant
				}
			}
			if value == nil {
				if suffix != "" {
					value = g.scalarEdge(e.Elements[at])
				} else {
					value = g.irValue(e.Items[at])
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
