package compiler

import (
	"go/ast"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// A known nongeneric source declaration always holds a NewSourceFunction.
// Its Body includes cancellation, propagation, source returns, and profiling;
// the generated callback retains its cleanup and fault-frame defers. When every
// argument is already in declaration order, Invoke adds only redundant label
// preparation and a cancellation check. Keep other callable paths unchanged.
func (g *generator) preparedSourceCall(e *syntax.Expression, args []syntax.Argument) ast.Expr {
	symbol := g.program.Expressions[e].Symbol
	if symbol == nil || symbol.Native != "" || len(symbol.Variables) != 0 || symbol.Decl == nil || symbol.Decl.Kind != syntax.KindFn {
		return nil
	}
	params := symbol.Type.Params
	if len(args) != len(params) {
		return nil
	}
	for i, arg := range args {
		if arg.Name != params[i].Name {
			return nil
		}
	}
	values := make([]ast.Expr, len(args))
	for i, arg := range args {
		// A later match argument can reassign a local used by an earlier
		// argument. Force each value's capture before evaluating the next.
		values[i] = sourceAt(arg.Pos, g.argumentValue(arg))
	}
	return g.locatedOperation(e, selector(&ast.TypeAssertExpr{X: ident(symbol.ID), Type: runtimeName("Function")}, "Body"), ident("ctx"), sliceLiteral(runtimeName("Value"), values...))
}
