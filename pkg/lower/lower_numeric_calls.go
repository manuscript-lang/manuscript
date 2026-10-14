package lower

import (
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"go/ast"
)

// Resolve intrinsics by checked native identity, not the visible source name.
// Bound methods and first-class references retain the ordinary callable ABI.

func (g *generator) numericCall(e *syntax.Expression) ast.Expr {
	name := g.numericCallName(e)
	if name == "" {
		return nil
	}
	x := g.ir.Expression(e).Call
	edge := x.Receiver
	if len(x.Arguments) == 1 {
		edge = x.Arguments[0].Value
	}
	return g.locatedOperation(e, runtimeName(name), ident("ctx"), g.scalarEdge(edge))
}
