package lower

import (
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"go/ast"
)

func (g *generator) typedListAt(e *syntax.Expression) ast.Expr {
	suffix := g.typedListAtSuffix(e)
	if suffix == "" {
		return nil
	}
	call := g.ir.Expression(e).Call
	receiver := sourceAt(call.Receiver.Source.Pos, g.expression(call.Receiver.Source))
	return g.locatedOperation(e, runtimeName("ListAt"+suffix), ident("ctx"), receiver, g.scalarEdge(call.Arguments[0].Value))
}
