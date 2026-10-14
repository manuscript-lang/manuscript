package lower

import (
	"go/ast"
	"strconv"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// A known nongeneric source declaration always holds a guarded source Function.
// Its Body includes cancellation, propagation, source returns, and profiling;
// the generated callback retains its cleanup and fault-frame defers. When every
// argument is already in declaration order, Invoke adds only redundant label
// preparation and a cancellation check. Keep other callable paths unchanged.
func (g *generator) preparedSourceCall(e *syntax.Expression, args []syntax.Argument) ast.Expr {
	symbol := g.program.Info(e).Symbol
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

// A method call on a receiver whose static type is a concrete user record or
// alternative resolves its implementation once per call site and then runs the
// implementation's direct body, skipping the bound Function, argument labels,
// and Argument slice that Bind and Invoke build for every call. Arguments must
// already be in declaration order so the labels carry no information.
func (g *generator) preparedMethodCall(e *syntax.Expression, args []syntax.Argument) ast.Expr {
	callee := g.program.Info(e.Left)
	if e.Left.Kind != syntax.KindMember || callee == nil || callee.Method == nil || callee.Method.Contract == nil || callee.Method.Native != "" {
		return nil
	}
	receiverType := g.program.Info(e.Left.Left).Type
	if (receiverType.Kind != syntax.KindRecord && receiverType.Kind != "alternative") || len(receiverType.Args) != 0 || hasTypeVariable(receiverType) || strings.HasPrefix(receiverType.ID, "@std/") {
		return nil
	}
	params := callee.Method.Type.Params
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
		values[i] = sourceAt(arg.Pos, g.argumentValue(arg))
	}
	site := "method" + strconv.Itoa(len(g.sites)+1)
	g.sites = append(g.sites, site)
	receiver := sourceAt(e.Left.Left.Pos, g.expression(e.Left.Left))
	return g.locatedOperation(e, runtimeName("CallMethod"), ident("ctx"), address(ident(site)), receiver, g.key(callee.Method.Contract), textLiteral(e.Left.Text), g.typeScope(receiverType), sliceLiteral(runtimeName("Value"), values...))
}
