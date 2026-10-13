package lower

import (
	"go/ast"
	"go/token"
	"sort"
	"strconv"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/ir"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func (g *generator) arguments(args []syntax.Argument) ast.Expr {
	var values []ast.Expr
	for _, a := range args {
		// Go orders calls, but a later argument can mutate a plain local value.
		// Capture each supplied value before evaluating the next argument.
		value := runtimeCall("SourceAt", address(ident("sourcePosition")), textLiteral(a.Pos.String()), g.argumentValue(a))
		values = append(values, composite(nil, keyed("Name", textLiteral(a.Name)), keyed("Value", value)))
	}
	return sliceLiteral(runtimeName("Argument"), values...)
}
func (g *generator) argumentValue(a syntax.Argument) ast.Expr {
	value := g.expression(a.Value)
	if target := g.program.Info(a.Value).OptionalArgument; target != nil {
		value = runtimeCall("NewAlternative", g.key(target), textLiteral("some"), stringSlice([]string{"value"}), sliceLiteral(runtimeName("Argument"), composite(nil, keyed("Name", textLiteral("value")), keyed("Value", value))))
	}
	return value
}
func (g *generator) expression(e *syntax.Expression) ast.Expr {
	if value, ok := g.booleans[e]; ok {
		return ident(strconv.FormatBool(value))
	}
	info := g.program.Info(e)
	if info.ErrorSource == nil {
		return g.expressionValue(e, info)
	}
	original := *info
	original.Type = info.ErrorSource
	value := g.expressionValue(e, &original)
	cause := info.ErrorSource
	if cause.ID == "@std/Result" {
		cause = cause.Args[1]
		args := []ast.Expr{value, g.key(info.Type)}
		if info.ScopedError {
			args = append(args, g.typeScope(cause))
		}
		return runtimeCall("ErrorResult", args...)
	}
	if info.ScopedError {
		return runtimeCall("ViewOf", textLiteral("@std/Error"), value, g.typeScope(cause))
	}
	return value
}
func (g *generator) expressionValue(e *syntax.Expression, info *checker.Info) ast.Expr {
	if info.Native == "index" {
		return g.locatedOperation(e, runtimeName("Index"), g.expression(e.Left), g.expression(e.Right))
	}
	if value := ir.Value(g.program, e, info); value != nil {
		return g.irValue(value)
	}
	switch e.Kind {
	case syntax.KindIndex:
		return g.locatedOperation(e, runtimeName("Index"), g.expression(e.Left), g.expression(e.Right))
	case syntax.KindMatch:
		native := g.wantScalar > 0 && primitiveEqualityType(info.Type) != ""
		oldExpressionResult := g.expressionResult
		if native {
			g.expressionResult = info.Type
		} else {
			g.expressionResult = nil
		}
		g.expressionDepth++
		body := g.match(e.Left, e.Arms, func(a *syntax.Arm) []ast.Stmt {
			body := g.body(a.Body)
			value := unit()
			if a.Value != nil {
				if native {
					value = g.scalarValue(a.Value)
				} else {
					value = g.expression(a.Value)
				}
			}
			if native && a.Value == nil {
				value = scalarExtract(info.Type, runtimeCall("Panic", textLiteral("runtime invariant: match arm fell through")))
			}
			return append(body, returned(value))
		})
		g.expressionDepth--
		g.expressionResult = oldExpressionResult
		fallback := runtimeCall("Panic", textLiteral("runtime invariant: exhaustive match"))
		if native {
			body = append(body, returned(scalarExtract(info.Type, fallback)))
			return call(closure(nil, nativeResultType(info.Type), body...))
		}
		body = append(body, returned(fallback))
		return call(closure(nil, runtimeName("Value"), body...))
	case syntax.KindName, syntax.KindApply:
		if info.Method != nil && info.Method.Contract == nil && info.Method.Native != "" && info.Method.Native != "contract" {
			member := e.Left
			return g.methodDefaults(info.Method, g.nativeReceiverMember(member, info))
		}
		if info.Binding != nil {
			return g.binding(info.Binding)
		}
		if info.Symbol != nil {
			symbol := info.Symbol
			if symbol.Native != "" {
				return g.nativeDefaults(symbol.Decl, info.Type, runtimeCall("StandardFunction", textLiteral(symbol.Native), g.key(info.Type.Result)))
			}
			if len(symbol.Variables) > 0 {
				return g.specialize(symbol, info.TypeArgs)
			}
			return ident(symbol.ID)
		}
		if info.Constructor != nil {
			return runtimeCall("NewAlternative", g.key(info.Constructor), textLiteral(info.Case), ident("nil"), ident("nil"))
		}
	case syntax.KindMember:
		if info.Constructor != nil {
			return runtimeCall("NewAlternative", g.key(info.Constructor), textLiteral(info.Case), ident("nil"), ident("nil"))
		}
		if info.Method != nil && info.Method.Contract == nil && info.Method.Native != "" && info.Method.Native != "contract" {
			return g.methodDefaults(info.Method, g.nativeReceiverMember(e, info))
		}
		if info.Method != nil {
			return g.methodDefaults(info.Method, runtimeCall("Bind", g.expression(e.Left), g.key(info.Method.Contract), textLiteral(e.Text), g.typeScope(g.program.Info(e.Left).Type)))
		}
		if info.Native != "" {
			if info.Native == "milliseconds" || info.Native == "seconds" || info.Native == "minutes" {
				return g.locatedOperation(e, runtimeName("NativeMember"), g.expression(e.Left), textLiteral(e.Text))
			}
			return runtimeCall("NativeMember", g.expression(e.Left), textLiteral(e.Text))
		}
		return runtimeCall("Field", g.expression(e.Left), textLiteral(e.Text))
	case syntax.KindCall:
		if info.Constructor != nil && info.Native == "view" {
			// Select the view path before lowering ordinary call arguments.
			// Lowering a discarded receiver tree would strand source markers
			// and other generator state from its nested callable/match bodies.
			receiver := e.Args[0].Value
			return runtimeCall("ViewOf", g.key(info.Type), g.expression(receiver), g.typeScope(g.program.Info(receiver).Type))
		}
		arguments := e.Args
		if info.Arguments != nil {
			arguments = info.Arguments
		}
		if value := g.numericCall(e); value != nil {
			return value
		}
		if value := g.directCollectionCall(e, arguments); value != nil {
			return value
		}
		if value := g.nativeMethodCall(e, arguments); value != nil {
			return value
		}
		if value := g.nativeSourceCall(e, arguments); value != nil {
			return value
		}
		if value := g.preparedSourceCall(e, arguments); value != nil {
			return value
		}
		if value := g.preparedMethodCall(e, arguments); value != nil {
			return value
		}
		args := g.arguments(arguments)
		if info.Constructor != nil {
			if info.Case != "" {
				var labels []string
				for _, cs := range checker.Cases(info.Constructor) {
					if cs.Name == info.Case {
						for _, f := range cs.Fields {
							labels = append(labels, f.Name)
						}
					}
				}
				return runtimeCall("NewAlternative", g.key(info.Type), textLiteral(info.Case), stringSlice(labels), args)
			}
			if symbol := info.Constructor.Def.Symbol; recordDefaults(symbol.Decl) && (symbol.Native == "" || g.program.ParameterBindings(symbol.Decl) != nil) {
				if symbol.Native != "" {
					if len(arguments) == len(symbol.Decl.Fields) {
						return g.locatedOperation(e, runtimeName("ConstructWithContext"), ident("ctx"), g.key(info.Type), args)
					}
					callable := g.lazyValue("native constructor/"+symbol.ID, g.declaredFunction(symbol))
					return g.locatedOperation(e, runtimeName("Invoke"), ident("ctx"), callable, args)
				}
				var callable ast.Expr = ident(symbol.ID)
				if len(symbol.Variables) > 0 {
					callable = g.specialize(symbol, info.Constructor.Args)
				}
				return g.locatedOperation(e, runtimeName("Invoke"), ident("ctx"), callable, args)
			}
			return g.locatedOperation(e, runtimeName("ConstructWithContext"), ident("ctx"), g.key(info.Type), args)
		}
		var callable ast.Expr
		if info.Symbol != nil {
			if info.Symbol.Native != "" {
				callable = g.nativeDefaults(info.Symbol.Decl, g.program.Info(e.Left).Type, runtimeCall("StandardFunction", textLiteral(info.Symbol.Native), g.key(info.Type)), arguments)
			} else {
				callable = ident(info.Symbol.ID)
				if len(info.Symbol.Variables) > 0 {
					callable = g.specialize(info.Symbol, info.TypeArgs)
				}
			}
		} else {
			// Capture a dynamic callable before arguments that may replace it.
			callable = runtimeCall("SourceAt", address(ident("sourcePosition")), textLiteral(e.Left.Pos.String()), g.methodCallable(e.Left, arguments))
		}
		return g.locatedOperation(e, runtimeName("Invoke"), ident("ctx"), callable, args)
	case syntax.KindUnary:
		if e.Text == "try" {
			args := []ast.Expr{g.expression(e.Right)}
			if info.ScopedPropagation {
				args = append(args, g.typeScope(info.PropagatedError))
			}
			return runtimeCall("Try", args...)
		}
		if e.Text == "-" && e.Right.Kind == syntax.KindNumber && e.Right.Text == "9223372036854775808" {
			return call(ident("int64"), signedInteger("-9223372036854775808"))
		}
		if value := g.scalarUnary(e); value != nil {
			return value
		}
		return g.locatedOperation(e, runtimeName("Unary"), textLiteral(e.Text), g.expression(e.Right))
	case syntax.KindBinary:
		if e.Text == "and" || e.Text == "or" {
			op := token.LAND
			if e.Text == "or" {
				op = token.LOR
			}
			return &ast.BinaryExpr{X: g.scalarValue(e.Left), Op: op, Y: g.scalarValue(e.Right)}
		}
		if e.Text == "==" || e.Text == "!=" {
			if value := g.primitiveEquality(e); value != nil {
				return value
			}
			return g.locatedOperation(e, runtimeName("Equality"), ident("ctx"), textLiteral(e.Text), g.expression(e.Left), g.expression(e.Right), g.typeScope(g.program.Info(e.Left).Type))
		}
		if value := g.numericBinary(e); value != nil {
			return value
		}
		return g.locatedOperation(e, runtimeName("Binary"), textLiteral(e.Text), g.expression(e.Left), g.expression(e.Right))
	case syntax.KindLambda:
		captures := append([]*checker.Binding{}, info.Captures...)
		sort.Slice(captures, func(i, j int) bool { return captures[i].ID < captures[j].ID })
		var declarations []*ast.Field
		var values []ast.Expr
		old := map[*checker.Binding]string{}
		for _, b := range captures {
			values = append(values, g.binding(b))
			old[b] = g.captures[b]
			snapshot := g.temp()
			g.captures[b] = snapshot
			declarations = append(declarations, field(snapshot, runtimeName("Value")))
		}
		result := e.Result
		if result == nil {
			result = &syntax.Type{Pos: e.Pos}
		}
		fn := g.function("<anonymous>", e.Params, result, e.Body, g.program.LambdaBindings(e), nil, info.Type)
		for _, b := range captures {
			if old[b] == "" {
				delete(g.captures, b)
			} else {
				g.captures[b] = old[b]
			}
		}
		return call(closure(declarations, runtimeName("Function"), returned(fn)), values...)
	}
	panic("missing lowering for " + e.Kind)
}

// locatedOperation updates the active frame only after evaluating its operands.
// Nested calls can therefore report their own sites without hiding this call site
// when they succeed. SourceAt inlines to an assignment; no expression closures or
// per-operation recovery are needed.
func (g *generator) locatedOperation(e *syntax.Expression, operation ast.Expr, args ...ast.Expr) ast.Expr {
	last := len(args) - 1
	args[last] = sourceAt(e.Pos, args[last])
	return call(operation, args...)
}
func sourceAt(pos syntax.Position, value ast.Expr) ast.Expr {
	return runtimeCall("SourceAt", address(ident("sourcePosition")), textLiteral(pos.String()), value)
}
func signedInteger(value string) ast.Expr {
	if strings.HasPrefix(value, "-") {
		return &ast.UnaryExpr{Op: token.SUB, X: &ast.BasicLit{Kind: token.INT, Value: value[1:]}}
	}
	return &ast.BasicLit{Kind: token.INT, Value: value}
}
