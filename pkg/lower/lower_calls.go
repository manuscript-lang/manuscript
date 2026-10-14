package lower

import (
	"go/ast"
	"strconv"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/ir"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// calleeMember is the member a call invokes, when its callee is one.
func calleeMember(x ir.Call) (ir.Member, bool) {
	m, ok := x.Callee.(ir.Member)
	return m, ok
}

// argsInOrder reports whether every argument is labelled with the parameter
// at its position, so the labels carry no information.
func argsInOrder(args []ir.Argument, params []checker.Param) bool {
	if len(args) != len(params) {
		return false
	}
	for i, arg := range args {
		if arg.Name != params[i].Name {
			return false
		}
	}
	return true
}

// A known nongeneric source declaration always holds a NewSourceFunction.
// Its Body includes cancellation, propagation, source returns, and profiling;
// the generated callback retains its cleanup and fault-frame defers. When every
// argument is already in declaration order, Invoke adds only redundant label
// preparation and a cancellation check. Keep other callable paths unchanged.
func (g *generator) preparedSourceCall(x ir.Call) ast.Expr {
	symbol := x.Info.Symbol
	if symbol == nil || symbol.Native != "" || len(symbol.Variables) != 0 || symbol.Decl == nil || symbol.Decl.Kind != syntax.KindFn {
		return nil
	}
	if !argsInOrder(x.Args, symbol.Type.Params) {
		return nil
	}
	values := make([]ast.Expr, len(x.Args))
	for i, arg := range x.Args {
		// A later match argument can reassign a local used by an earlier
		// argument. Force each value's capture before evaluating the next.
		values[i] = sourceAt(arg.Pos, g.argumentValue(arg))
	}
	return locatedAt(x.Pos, selector(&ast.TypeAssertExpr{X: ident(symbol.ID), Type: runtimeName("Function")}, "Body"), ident("ctx"), sliceLiteral(runtimeName("Value"), values...))
}

// A method call on a receiver whose static type is a concrete user record or
// alternative resolves its implementation once per call site and then runs the
// implementation's direct body, skipping the bound Function, argument labels,
// and Argument slice that Bind and Invoke build for every call. Arguments must
// already be in declaration order so the labels carry no information.
func (g *generator) preparedMethodCall(x ir.Call) ast.Expr {
	m, ok := calleeMember(x)
	if !ok || m.Info.Method == nil || m.Info.Method.Contract == nil || m.Info.Method.Native != "" {
		return nil
	}
	receiverType := m.ReceiverType
	if (receiverType.Kind != syntax.KindRecord && receiverType.Kind != "alternative") || len(receiverType.Args) != 0 || hasTypeVariable(receiverType) || strings.HasPrefix(receiverType.ID, "@std/") {
		return nil
	}
	if !argsInOrder(x.Args, m.Info.Method.Type.Params) {
		return nil
	}
	values := make([]ast.Expr, len(x.Args))
	for i, arg := range x.Args {
		values[i] = sourceAt(arg.Pos, g.argumentValue(arg))
	}
	site := "method" + strconv.Itoa(len(g.sites)+1)
	g.sites = append(g.sites, site)
	receiver := sourceAt(m.ReceiverPos, g.irValue(m.Receiver))
	return locatedAt(x.Pos, runtimeName("CallMethod"), ident("ctx"), address(ident(site)), receiver, g.key(m.Info.Method.Contract), textLiteral(m.Name), g.typeScope(receiverType), sliceLiteral(runtimeName("Value"), values...))
}

// view converts a receiver to a contract view of its static type.
func (g *generator) view(x ir.View) ast.Expr {
	return runtimeCall("ViewOf", g.key(x.Type), g.irValue(x.Receiver), g.typeScope(x.ReceiverType))
}

// call lowers an invocation. Direct and prepared forms are tried from the most
// specific, then constructors, then the generic Invoke over a callable.
func (g *generator) call(x ir.Call) ast.Expr {
	info := x.Info
	arguments := x.Args
	if value := g.directCollectionCall(x); value != nil {
		return value
	}
	if value := g.directCall(x); value != nil {
		return value
	}
	if value := g.preparedSourceCall(x); value != nil {
		return value
	}
	if value := g.preparedMethodCall(x); value != nil {
		return value
	}
	if info.Constructor != nil && info.Native != "view" && info.Case != "" {
		labels := g.caseLabels(info)
		if fields := g.alternativeFields(labels, arguments); fields != nil {
			return composite(runtimeName("Alternative"), keyed("Type", g.key(info.Type)), keyed("Tag", textLiteral(info.Case)), keyed("Fields", sliceLiteral(runtimeName("Value"), fields...)))
		}
	}
	if info.Constructor != nil && info.Native != "view" && info.Case == "" {
		if st := g.structFor(info.Constructor); st != nil && !recordDefaults(info.Constructor.Def.Symbol.Decl) {
			if value := g.constructStruct(st, arguments); value != nil {
				return value
			}
		}
	}
	args := g.arguments(arguments)
	if info.Constructor != nil {
		if info.Case != "" {
			return runtimeCall("NewAlternative", g.key(info.Type), textLiteral(info.Case), stringSlice(g.caseLabels(info)), args)
		}
		if symbol := info.Constructor.Def.Symbol; recordDefaults(symbol.Decl) && (symbol.Native == "" || g.program.ParameterBindings(symbol.Decl) != nil) {
			if symbol.Native != "" {
				if len(arguments) == len(symbol.Decl.Fields) {
					return locatedAt(x.Pos, runtimeName("ConstructWithContext"), ident("ctx"), g.key(info.Type), args)
				}
				callable := g.lazyValue("native constructor/"+symbol.ID, g.declaredFunction(symbol))
				return locatedAt(x.Pos, runtimeName("Invoke"), ident("ctx"), callable, args)
			}
			var callable ast.Expr = ident(symbol.ID)
			if len(symbol.Variables) > 0 {
				callable = g.specialize(symbol, info.Constructor.Args)
			}
			return locatedAt(x.Pos, runtimeName("Invoke"), ident("ctx"), callable, args)
		}
		return locatedAt(x.Pos, runtimeName("ConstructWithContext"), ident("ctx"), g.key(info.Type), args)
	}
	var callable ast.Expr
	if info.Symbol != nil {
		if info.Symbol.Native != "" {
			callable = g.nativeDefaults(info.Symbol.Decl, x.CalleeType, runtimeCall("StandardFunction", textLiteral(info.Symbol.Native), g.key(info.Type)), arguments)
		} else {
			callable = ident(info.Symbol.ID)
			if len(info.Symbol.Variables) > 0 {
				callable = g.specialize(info.Symbol, info.TypeArgs)
			}
		}
	} else {
		// Capture a dynamic callable before arguments that may replace it.
		callable = runtimeCall("SourceAt", address(ident("sourcePosition")), textLiteral(x.CalleePos.String()), g.methodCallable(x))
	}
	return locatedAt(x.Pos, runtimeName("Invoke"), ident("ctx"), callable, args)
}
