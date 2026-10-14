package lower

import (
	"go/ast"
	"strconv"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// A known nongeneric source declaration owns its guarded Body. Resolve
// argument slots once, capturing supplied values in written order; omitted
// slots remain nil so the callee evaluates its checked defaults after admission.
// Dynamic callables and generic dispatch retain ordinary Invoke.
func (g *generator) preparedSourceCall(e *syntax.Expression, args []syntax.Argument) ast.Expr {
	symbol := g.program.Info(e).Symbol
	if symbol == nil || symbol.Native != "" || len(symbol.Variables) != 0 || symbol.Decl == nil || symbol.Decl.Kind != syntax.KindFn {
		return nil
	}
	params := symbol.Type.Params
	if len(args) > len(params) {
		return nil
	}
	slots := make(map[string]int, len(params))
	for i, p := range params {
		slots[p.Name] = i
	}
	values := make([]ast.Expr, len(params))
	for i := range values {
		values[i] = ident("nil")
	}
	var captures []ast.Stmt
	for _, arg := range args {
		slot, ok := slots[arg.Name]
		if !ok {
			return nil
		}
		tmp := g.temp()
		captures = append(captures, define(tmp, sourceAt(arg.Pos, g.argumentValue(arg))))
		values[slot] = ident(tmp)
	}
	operation := g.locatedOperation(e, selector(&ast.TypeAssertExpr{X: ident(symbol.ID), Type: runtimeName("Function")}, "Body"), ident("ctx"), sliceLiteral(runtimeName("Value"), values...))
	captures = append(captures, returned(operation))
	return call(closure(nil, runtimeName("Value"), captures...))

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
