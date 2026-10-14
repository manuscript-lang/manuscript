package lower

import (
	"go/ast"
	"go/token"
	"sort"
	"strconv"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func (g *generator) arguments(args []syntax.Argument) ast.Expr {
	var values []ast.Expr
	for _, a := range args {
		// Go orders calls, but a later argument can mutate a plain local value.
		// Capture each supplied value before evaluating the next argument.
		value := sequence(g.argumentValue(a))
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
	if t, ok := g.tried[e]; ok {
		return t.value
	}
	info := g.program.Info(e)
	if info != nil && info.Folded {
		return ident(strconv.FormatBool(info.Constant))
	}
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
		return orderedCall(runtimeName("Index"), g.expression(e.Left), g.expression(e.Right))
	}
	switch e.Kind {
	case syntax.KindIndex:
		return orderedCall(runtimeName("Index"), g.expression(e.Left), g.expression(e.Right))
	case syntax.KindMatch:
		return g.matchValue(e)
	case syntax.KindNumber:
		return numberValue(e)
	case syntax.KindBool:
		return ident(e.Text)
	case syntax.KindUnit:
		return unit()
	case syntax.KindText:
		return g.textValue(e)
	case syntax.KindName, syntax.KindApply:
		if value := g.nameValue(e, info); value != nil {
			return value
		}
	case syntax.KindMember:
		return g.memberValue(e, info)
	case syntax.KindCall:
		return g.callValue(e, info)
	case syntax.KindList:
		return g.listValue(e, info)
	case syntax.KindMap:
		return g.mapValue(e, info)
	case syntax.KindUnary:
		return g.unaryValue(e, info)
	case syntax.KindBinary:
		return g.binaryValue(e)
	case syntax.KindLambda:
		return g.lambdaValue(e, info)
	}
	panic("missing lowering for " + e.Kind)
}

// matchValue lowers a match expression to an immediately called closure.
func (g *generator) matchValue(e *syntax.Expression) ast.Expr {
	g.expressionDepth++
	body := g.match(e.Left, e.Arms, func(a *syntax.Arm) []ast.Stmt {
		body := g.body(a.Body)
		value := unit()
		if a.Value != nil {
			value = g.expression(a.Value)
		}
		return append(body, returned(value))
	})
	g.expressionDepth--
	body = append(body, returned(runtimeCall("Panic", textLiteral("runtime invariant: exhaustive match"))))
	return call(closure(nil, runtimeName("Value"), body...))
}

// numberValue lowers a numeric literal to its native Go constant.
func numberValue(e *syntax.Expression) ast.Expr {
	if strings.HasSuffix(e.Text, "d") {
		return runtimeCall("DecimalLiteral", textLiteral(e.Text))
	}
	if strings.ContainsAny(e.Text, ".eE") {
		value, _ := strconv.ParseFloat(e.Text, 64)
		return call(ident("float64"), &ast.BasicLit{Kind: token.FLOAT, Value: strconv.FormatFloat(value, 'g', -1, 64)})
	}
	value, _ := strconv.ParseInt(e.Text, 10, 64)
	return call(ident("int64"), signedInteger(strconv.FormatInt(value, 10)))
}

// textValue lowers text with interpolated parts.
func (g *generator) textValue(e *syntax.Expression) ast.Expr {
	var result ast.Expr
	join := func(part ast.Expr) {
		if result == nil {
			result = part
			return
		}
		result = &ast.BinaryExpr{X: result, Op: token.ADD, Y: part}
	}
	for _, p := range e.Parts {
		if p.Value == nil {
			join(textLiteral(p.Text))
			continue
		}
		value := g.expression(p.Value)
		switch g.nativeType(p.Value) {
		case "string":
			join(value)
		case "int64":
			join(runtimeCall("FormatInt", value))
		case "float64":
			join(runtimeCall("FormatFloat", value))
		case "bool":
			join(runtimeCall("FormatBool", value))
		default:
			join(runtimeCall("Format", value))
		}
	}
	if result == nil {
		return textLiteral("")
	}
	return result
}

// nameValue lowers a reference; nil means the name resolved to nothing
// lowerable.
func (g *generator) nameValue(e *syntax.Expression, info *checker.Info) ast.Expr {
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
	return nil
}

// memberValue lowers a member read: constructor, method value, native
// member, struct field, or dynamic field.
func (g *generator) memberValue(e *syntax.Expression, info *checker.Info) ast.Expr {
	if info.Method != nil && info.Method.Accessor {
		return g.accessorValue(e, info)
	}
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
		return runtimeCall("NativeMember", g.expression(e.Left), textLiteral(e.Text))
	}
	if st, _ := g.structFieldOf(e); st != nil {
		return call(selector(g.structOperand(st, e.Left), "Get_"+e.Text))
	}
	return runtimeCall("Field", g.expression(e.Left), textLiteral(e.Text))
}

// callValue lowers a call, preferring direct Go calls and struct
// construction over runtime dispatch.
func (g *generator) callValue(e *syntax.Expression, info *checker.Info) ast.Expr {
	if info.Constructor != nil && info.Native == "view" {
		// Select the view path before lowering ordinary call arguments.
		// Lowering a discarded receiver tree would strand source markers
		// and other generator state from its nested callable/match bodies.
		receiver := e.Args[0].Value
		return runtimeCall("ViewOf", g.key(info.Type), g.expression(receiver), g.typeScope(g.program.Info(receiver).Type))
	}
	arguments := info.Arguments
	if value := g.scalarNativeValue(e); value != nil {
		return value
	}
	if value := g.directCollectionCall(e, arguments); value != nil {
		return value
	}
	if value := g.directCall(e); value != nil {
		return value
	}
	if value := g.preparedSourceCall(e, arguments); value != nil {
		return value
	}
	if value := g.preparedMethodCall(e, arguments); value != nil {
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
		return g.constructorCall(e, info, arguments, args)
	}
	return g.functionCall(e, info, arguments, args)
}

// constructorCall lowers a record or alternative constructor call.
func (g *generator) constructorCall(e *syntax.Expression, info *checker.Info, arguments []syntax.Argument, args ast.Expr) ast.Expr {
	if info.Case != "" {
		return runtimeCall("NewAlternative", g.key(info.Type), textLiteral(info.Case), stringSlice(g.caseLabels(info)), args)
	}
	if symbol := info.Constructor.Def.Symbol; recordDefaults(symbol.Decl) && (symbol.Native == "" || g.program.ParameterBindings(symbol.Decl) != nil) {
		if symbol.Native != "" {
			if len(arguments) == len(symbol.Decl.Fields) {
				return orderedCall(runtimeName("ConstructWithContext"), ident("ctx"), g.key(info.Type), args)
			}
			callable := g.lazyValue("native constructor/"+symbol.ID, g.declaredFunction(symbol))
			return orderedCall(runtimeName("Invoke"), ident("ctx"), callable, args)
		}
		var callable ast.Expr = ident(symbol.ID)
		if len(symbol.Variables) > 0 {
			callable = g.specialize(symbol, info.Constructor.Args)
		}
		return orderedCall(runtimeName("Invoke"), ident("ctx"), callable, args)
	}
	return orderedCall(runtimeName("ConstructWithContext"), ident("ctx"), g.key(info.Type), args)

}

// functionCall lowers a call of a function, native function, or dynamic callable.
func (g *generator) functionCall(e *syntax.Expression, info *checker.Info, arguments []syntax.Argument, args ast.Expr) ast.Expr {
	var callable ast.Expr
	if info.Symbol != nil {
		if info.Symbol.Native != "" {
			standard := runtimeCall("StandardFunction", textLiteral(info.Symbol.Native), g.key(info.Type))
			callable = g.nativeDefaults(info.Symbol.Decl, g.program.Info(e.Left).Type, standard, arguments)
			if callable == ast.Expr(standard) && !hasTypeVariable(info.Type) {
				// A standard function with no default expressions is stateless:
				// resolve it once instead of rebuilding its Function per call.
				callable = g.lazyValue("standard function\x00"+info.Symbol.Native+"\x00"+checker.TypeKey(info.Type), standard)
			}
		} else {
			callable = ident(info.Symbol.ID)
			if len(info.Symbol.Variables) > 0 {
				callable = g.specialize(info.Symbol, info.TypeArgs)
			}
		}
	} else {
		// Capture a dynamic callable before arguments that may replace it.
		callable = sequence(g.methodCallable(e.Left, arguments))
	}
	return orderedCall(runtimeName("Invoke"), ident("ctx"), callable, args)
}

// listValue lowers a list literal.
func (g *generator) listValue(e *syntax.Expression, info *checker.Info) ast.Expr {
	if value := g.debugListLiteral(e, info.Type); value != nil {
		return value
	}
	if value := g.largeListValue(e, info); value != nil {
		return value
	}
	elements := g.siblings(e.Elements)
	// Large literals keep the separately owned boxed route and its oracle.
	if len(elements) > debugListThreshold {
		return address(composite(runtimeName("List"), keyed("Type", g.key(info.Type)), keyed("Items", sliceLiteral(runtimeName("Value"), elements...))))
	}
	return runtimeCall("NewList", g.key(info.Type), sliceLiteral(runtimeName("Value"), elements...))
}

// mapValue lowers a map literal.
func (g *generator) mapValue(e *syntax.Expression, info *checker.Info) ast.Expr {
	var entries []ast.Expr
	operands := g.siblings(e.Elements)
	for at := 0; at < len(operands); at += 2 {
		entries = append(entries, composite(nil, keyed("Key", operands[at]), keyed("Value", operands[at+1])))
	}
	return orderedCall(runtimeName("MapLiteral"), ident("ctx"), g.key(info.Type), sliceLiteral(runtimeName("Entry"), entries...), g.typeScope(info.Type))
}

// unaryValue lowers try, negation, not, and other unary operators.
func (g *generator) unaryValue(e *syntax.Expression, info *checker.Info) ast.Expr {
	if e.Text == "try" {
		args := []ast.Expr{g.expression(e.Right)}
		if info.ScopedPropagation {
			args = append(args, g.typeScope(info.PropagatedError))
		}
		g.recovers = true
		return runtimeCall("Try", args...)
	}
	if e.Text == "-" && e.Right.Kind == syntax.KindNumber && e.Right.Text == "9223372036854775808" {
		return call(ident("int64"), signedInteger("-9223372036854775808"))
	}
	if e.Text == "not" {
		return &ast.UnaryExpr{Op: token.NOT, X: paren(g.condition(e.Right))}
	}
	if negated := g.negation(e); negated != nil {
		return negated
	}
	return orderedCall(runtimeName("Unary"), textLiteral(e.Text), g.expression(e.Right))
}

// binaryValue lowers logical, equality, numeric, and generic binary operators.
func (g *generator) binaryValue(e *syntax.Expression) ast.Expr {
	if e.Text == "and" || e.Text == "or" {
		op := token.LAND
		if e.Text == "or" {
			op = token.LOR
		}
		return &ast.BinaryExpr{X: paren(g.condition(e.Left)), Op: op, Y: paren(g.condition(e.Right))}
	}
	if e.Text == "==" || e.Text == "!=" {
		if value := g.primitiveEquality(e); value != nil {
			return value
		}
		operands := g.siblings([]*syntax.Expression{e.Left, e.Right})
		return orderedCall(runtimeName("Equality"), ident("ctx"), textLiteral(e.Text), operands[0], operands[1], g.typeScope(g.program.Info(e.Left).Type))
	}
	if value := g.numericBinary(e); value != nil {
		return value
	}
	operands := g.siblings([]*syntax.Expression{e.Left, e.Right})
	return orderedCall(runtimeName("Binary"), textLiteral(e.Text), operands[0], operands[1])
}

// siblings lowers operands that one Go expression evaluates together. Go
// orders calls but not a plain variable read against a later call, and a match
// arm can assign a local an earlier operand reads, so such an operand is
// captured in source order first.
func (g *generator) siblings(items []*syntax.Expression) []ast.Expr {
	out := make([]ast.Expr, len(items))
	later := false
	for i := len(items) - 1; i >= 0; i-- {
		out[i] = g.expression(items[i])
		if later && !g.constant(items[i]) {
			out[i] = sequence(out[i])
		}
		later = later || containsMatch(items[i])
	}
	return out
}

// lambdaValue lowers a lambda, snapshotting its captured bindings.
func (g *generator) lambdaValue(e *syntax.Expression, info *checker.Info) ast.Expr {
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
	// Lambda bodies copy every incoming argument into locals before running, so
	// library callbacks may reuse one argument buffer across calls.
	if constructor, ok := fn.(*ast.CallExpr); ok {
		constructor.Fun = runtimeName("NewCompiledSourceFunction")
	}
	for _, b := range captures {
		if old[b] == "" {
			delete(g.captures, b)
		} else {
			g.captures[b] = old[b]
		}
	}
	return call(closure(declarations, runtimeName("Function"), returned(fn)), values...)
}

// orderedCall makes the final operand a Go call, retaining its evaluation order
// relative to other calls. Earlier plain reads still need their explicit capture
// or sequence wrapper; this helper does not capture them.
func orderedCall(operation ast.Expr, args ...ast.Expr) ast.Expr {
	last := len(args) - 1
	args[last] = sequence(args[last])
	return call(operation, args...)
}
func sequence(value ast.Expr) ast.Expr {
	return runtimeCall("Seq", value)
}
func signedInteger(value string) ast.Expr {
	if strings.HasPrefix(value, "-") {
		return &ast.UnaryExpr{Op: token.SUB, X: &ast.BasicLit{Kind: token.INT, Value: value[1:]}}
	}
	return &ast.BasicLit{Kind: token.INT, Value: value}
}

// caseLabels are the payload labels of the alternative case a constructor call builds.
func (g *generator) caseLabels(info *checker.Info) []string {
	var labels []string
	for _, cs := range checker.Cases(info.Constructor) {
		if cs.Name == info.Case {
			for _, f := range cs.Fields {
				labels = append(labels, f.Name)
			}
		}
	}
	return labels
}

// alternativeFields lowers constructor arguments straight into the payload
// slice when they are supplied once each, in payload order. Anything else
// returns nil without lowering, leaving NewAlternative to match labels.
func (g *generator) alternativeFields(labels []string, args []syntax.Argument) []ast.Expr {
	if len(args) != len(labels) {
		return nil
	}
	for i, a := range args {
		if a.Name != labels[i] {
			return nil
		}
	}
	fields := make([]ast.Expr, len(args))
	for i, a := range args {
		fields[i] = sequence(g.argumentValue(a))
	}
	return fields
}
