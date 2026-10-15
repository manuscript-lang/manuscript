package lower

import (
	"go/ast"
	"strconv"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// A known nongeneric source declaration always holds a NewSourceFunction.
// Its Body includes cancellation, propagation, source returns, and profiling;
// the generated callback retains its cleanup and fault-frame defers. When every
// argument is already in declaration order, Invoke adds only redundant label
// preparation and a cancellation check. Keep other callable paths unchanged.
func (g *generator) preparedSourceCall(e *syntax.Expression, args []syntax.Argument) ast.Expr {
	info := g.program.Info(e)
	symbol := info.Symbol
	if symbol == nil || symbol.Native != "" || symbol.Decl == nil || symbol.Decl.Kind != syntax.KindFn {
		return nil
	}
	// A generic function is specialized once per program when its type
	// arguments are static; otherwise the call keeps ordinary dispatch.
	var callee ast.Expr = ident(symbol.ID)
	if len(symbol.Variables) != 0 {
		for _, arg := range info.TypeArgs {
			if hasTypeVariable(arg) {
				return nil
			}
		}
		callee = g.specialize(symbol, info.TypeArgs)
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
		values[i] = sequence(g.argumentValue(arg))
	}
	return orderedCall(selector(&ast.TypeAssertExpr{X: callee, Type: runtimeName("Function")}, "Body"), ident("ctx"), sliceLiteral(runtimeName("Value"), values...))
}

// A method call on a receiver whose static type is a concrete user record or
// alternative resolves its implementation once per call site and then runs the
// implementation's direct body, skipping the bound Function, argument labels,
// and Argument slice that Bind and Invoke build for every call. Arguments must
// already be in declaration order so the labels carry no information.
func (g *generator) preparedMethodCall(e *syntax.Expression, args []syntax.Argument) ast.Expr {
	callee := g.program.Info(e.Left)
	if value := g.standardContractCall(e, callee, args); value != nil {
		return value
	}
	if e.Left.Kind != syntax.KindMember || callee == nil || callee.Method == nil || callee.Method.Contract == nil || (callee.Method.Native != "" && callee.Method.Native != "contract") {
		return nil
	}
	receiverType := g.program.Info(e.Left.Left).Type
	viaInterface := receiverType.Kind == "contract"
	if callee.Method.Native == "contract" && !viaInterface {
		return nil
	}
	if (receiverType.Kind != syntax.KindRecord && receiverType.Kind != "alternative" && !viaInterface) || len(receiverType.Args) != 0 || hasTypeVariable(receiverType) || strings.HasPrefix(receiverType.ID, "@std/") {
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
		values[i] = sequence(g.argumentValue(arg))
	}
	site := "method" + strconv.Itoa(len(g.sites)+1)
	g.sites = append(g.sites, site)
	receiver := sequence(g.expression(e.Left.Left))
	entry := "CallMethod"
	if viaInterface {
		entry = "CallInterface"
	}
	return orderedCall(runtimeName(entry), ident("ctx"), address(ident(site)), receiver, g.key(callee.Method.Contract), textLiteral(e.Left.Text), g.typeScope(receiverType), sliceLiteral(runtimeName("Value"), values...))
}

// standardContractCall lowers a call of a standard contract method (Clock.now,
// WriteStream.write, ...) with every argument supplied in declaration order to
// rt.CallOperation. Calls that need prepared defaults keep ordinary dispatch.
func (g *generator) standardContractCall(e *syntax.Expression, callee *checker.Info, args []syntax.Argument) ast.Expr {
	if e.Left.Kind != syntax.KindMember || callee == nil || callee.Method == nil || callee.Method.Native != "contract" || callee.Method.Contract == nil {
		return nil
	}
	receiverType := g.program.Info(e.Left.Left).Type
	if receiverType.Kind != "contract" || !strings.HasPrefix(receiverType.ID, "@std/") || len(receiverType.Args) != 0 || hasTypeVariable(receiverType) {
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
	bound := runtimeCall("Bind", g.expression(e.Left.Left), g.key(callee.Method.Contract), textLiteral(e.Left.Text), g.typeScope(receiverType))
	if g.methodDefaults(callee.Method, bound, args) != ast.Expr(bound) {
		return nil
	}
	values := make([]ast.Expr, len(args))
	for i, arg := range args {
		values[i] = sequence(g.argumentValue(arg))
	}
	site := "method" + strconv.Itoa(len(g.sites)+1)
	g.sites = append(g.sites, site)
	receiver := sequence(g.expression(e.Left.Left))
	return orderedCall(runtimeName("CallOperation"), ident("ctx"), address(ident(site)), receiver, g.key(callee.Method.Contract), textLiteral(e.Left.Text), g.typeScope(receiverType), sliceLiteral(runtimeName("Value"), values...))
}
