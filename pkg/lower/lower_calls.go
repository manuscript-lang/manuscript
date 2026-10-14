package lower

import (
	"go/ast"
	"strconv"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// A known nongeneric source declaration always holds a guarded source Function.
// Its Body includes cancellation, propagation, source returns, and profiling;
// the generated callback retains its cleanup and fault-frame defers. When every
// argument is already in declaration order, Invoke adds only redundant label
// preparation and a cancellation check. Keep other callable paths unchanged.
func (g *generator) preparedSourceCall(e *syntax.Expression, args []syntax.Argument) ast.Expr {
	x := g.ir.Expression(e).Call
	symbol := x.Symbol
	if symbol == nil || !x.Prepared {
		return nil
	}
	args = callSyntax(x)
	values := make([]ast.Expr, len(args))
	for i, arg := range args {
		// A later match argument can reassign a local used by an earlier
		// argument. Force each value's capture before evaluating the next.
		values[i] = sourceAt(arg.Pos, g.argumentValue(arg))
	}
	return g.locatedOperation(e, selector(&ast.TypeAssertExpr{X: ident(symbol.ID), Type: runtimeName("Function")}, "Body"), ident("ctx"), sliceLiteral(runtimeName("Value"), values...))
}

// A method call on a receiver whose static type is a concrete user record or
// alternative resolves its implementation once per call site and then runs the
// implementation's direct body, skipping the bound Function, argument labels,
// and Argument slice that Bind and Invoke build for every call. Arguments must
// already be in declaration order so the labels carry no information.
func (g *generator) preparedMethodCall(e *syntax.Expression, args []syntax.Argument) ast.Expr {
	x := g.ir.Expression(e).Call
	if x.Symbol != nil || x.Method == nil || !x.Prepared {
		return nil
	}
	args = callSyntax(x)
	receiverType := x.Receiver.Type
	values := make([]ast.Expr, len(args))
	for i, arg := range args {
		values[i] = sourceAt(arg.Pos, g.argumentValue(arg))
	}
	site := "method" + strconv.Itoa(len(g.sites)+1)
	g.sites = append(g.sites, site)
	receiver := sourceAt(e.Left.Left.Pos, g.expression(x.Receiver.Source))
	return g.locatedOperation(e, runtimeName("CallMethod"), ident("ctx"), address(ident(site)), receiver, g.key(x.Method.Contract), textLiteral(e.Left.Text), g.typeScope(receiverType), sliceLiteral(runtimeName("Value"), values...))
}
