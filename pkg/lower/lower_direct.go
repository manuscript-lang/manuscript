package lower

import (
	"go/ast"
	"go/token"
	"strconv"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// A direct function is a nongeneric top-level source function emitted as a
// plain Go function with typed scalar parameters and result. Calls that name
// it with every argument in order call it directly; the dynamic Function in
// its symbol variable only forwards to it. The function admits and leaves its
// own call-depth accounting when it can recurse, so no wrapper layer runs per call.
type directFunction struct {
	name   string
	params []string  // Go scalar type per parameter, "" for Value
	result string    // Go scalar result type, "" for Value
	shape  *altShape // typed Result/Optional result, nil when result is scalar or Value
	// counted marks a function in a cycle of direct calls: it admits itself
	// with rt.Enter and leaves with rt.Exit so runaway recursion is a fault.
	counted bool
	// receiver marks a method: the Go function takes its receiver as the
	// Value parameter after ctx.
	receiver bool
	// defaulted marks parameters a caller may omit. They are Value parameters
	// that arrive nil when omitted; the body fills in the default, so defaults
	// evaluate in the callee's scope exactly as for a dynamic call.
	defaulted []bool
}

// planDirect decides which top-level functions are emitted as direct functions.
// Profiling needs every call to pass the dynamic wrapper, which labels it.
func (g *generator) planDirect(functions []*checker.Symbol, options Options) {
	g.direct = map[*checker.Symbol]*directFunction{}
	g.directMethods = map[string]*directFunction{}
	g.directOn = options.CPUProfile == "" && options.HeapProfile == "" && options.Trace == ""
	if options.CPUProfile != "" || options.HeapProfile != "" || options.Trace != "" {
		return
	}
	for _, s := range functions {
		if direct := g.planDirectConstructor(s); direct != nil {
			g.direct[s] = direct
			continue
		}
		d := s.Decl
		if s.Native != "" || len(s.Variables) != 0 || d == nil || d.Kind != syntax.KindFn {
			continue
		}
		direct := &directFunction{name: "call_" + s.ID, result: primitiveEqualityType(s.Type.Result), shape: alternativeShape(s.Type.Result)}
		bindings := g.program.ParameterBindings(d)
		if len(bindings) != len(d.Params) || len(s.Type.Params) != len(d.Params) {
			continue
		}
		for i, p := range d.Params {
			omittable := p.Default != nil || s.Type.Defaults[s.Type.Params[i].Name]
			direct.defaulted = append(direct.defaulted, omittable)
			if omittable {
				// Omitted arguments reach the function as nil, which a typed scalar cannot hold.
				direct.params = append(direct.params, "")
				continue
			}
			direct.params = append(direct.params, scalarBinding(bindings[i]))
		}
		g.direct[s] = direct
	}
	for i, m := range g.program.Methods {
		if direct := g.planDirectMethod(m, i); direct != nil {
			g.directMethods[m.ID] = direct
		}
	}
	g.markCounted()
	// Defaults can call back into the program, and markCounted sees no body here.
	for s, direct := range g.direct {
		if s.Decl.Kind == syntax.KindRecord {
			direct.counted = true
		}
	}
}

// planDirectConstructor plans a nongeneric source record whose fields have
// defaults as a direct function over its fields, so constructor calls do not
// go through Invoke. Defaulted fields arrive nil when omitted.
func (g *generator) planDirectConstructor(s *checker.Symbol) *directFunction {
	d := s.Decl
	if s.Native != "" || len(s.Variables) != 0 || d == nil || !recordDefaults(d) || s.Type == nil {
		return nil
	}
	st := g.structFor(s.Type)
	bindings := g.program.ParameterBindings(d)
	signature := checker.ConstructorSignature(s.Type)
	if st == nil || len(bindings) != len(d.Fields) || len(signature.Params) != len(d.Fields) || len(st.fields) != len(d.Fields) {
		return nil
	}
	direct := &directFunction{name: "call_" + s.ID}
	for i, f := range d.Fields {
		direct.defaulted = append(direct.defaulted, f.Default != nil)
		if f.Default != nil {
			direct.params = append(direct.params, "")
			continue
		}
		typ := scalarBinding(bindings[i])
		if typ != "" && typ != st.fields[i].scalar {
			return nil
		}
		direct.params = append(direct.params, typ)
	}
	return direct
}

// constructorStruct returns the record value built from the constructor's
// parameters, in field declaration order.
func (g *generator) constructorStruct(s *checker.Symbol, direct *directFunction) ast.Stmt {
	st := g.structFor(s.Type)
	bindings := g.program.ParameterBindings(s.Decl)
	var elements []ast.Expr
	for i, f := range st.fields {
		var value ast.Expr = ident(bindings[i].ID)
		switch {
		case f.scalar != "" && direct.params[i] == "":
			value = unbox(value, f.scalar)
		case f.scalar == "" && direct.params[i] != "":
			value = call(runtimeName("Value"), value)
		}
		elements = append(elements, keyed(fieldName(f.name), value))
	}
	return returned(call(runtimeName("Value"), address(composite(ident(st.name), elements...))))
}

// planDirectMethod decides whether a source method of a nongeneric record or
// alternative is emitted as a direct function that takes its receiver first.
func (g *generator) planDirectMethod(m *checker.Method, index int) *directFunction {
	d := m.Decl
	if m.Native != "" || d == nil || d.Kind != syntax.KindFn || len(m.Variables) != 0 || m.Receiver == nil || m.Contract == nil {
		return nil
	}
	if (m.Receiver.Kind != syntax.KindRecord && m.Receiver.Kind != "alternative") || len(m.Receiver.Args) != 0 || hasTypeVariable(m.Receiver) || strings.HasPrefix(m.Receiver.ID, "@std/") {
		return nil
	}
	bindings := g.program.ParameterBindings(d)
	if g.program.SelfBinding(d) == nil || len(bindings) != len(d.Params) || len(m.Type.Params) != len(d.Params) {
		return nil
	}
	direct := &directFunction{name: "method_" + strconv.Itoa(index+1), result: primitiveEqualityType(m.Type.Result), shape: alternativeShape(m.Type.Result), receiver: true}
	for i, p := range d.Params {
		// Omitted arguments reach a method as nil; only dynamic calls omit.
		if p.Default != nil || m.Type.Defaults[m.Type.Params[i].Name] {
			return nil
		}
		direct.params = append(direct.params, scalarBinding(bindings[i]))
	}
	// A standard interface can grant omission to parameters the source method
	// declares without a default; those are prepared before the call.
	if m.Contract.Def != nil && m.Contract.Def.Symbol != nil {
		for _, cd := range m.Contract.Def.Symbol.Decl.Methods {
			if cd.Name != d.Name {
				continue
			}
			for _, p := range cd.Params {
				if p.Default != nil {
					return nil
				}
			}
		}
	}
	return direct
}

// directMethodDeclaration emits the Go declaration of a direct method and the
// forwarding body the dynamic implementation table calls.
func (g *generator) directMethodDeclaration(m *checker.Method, direct *directFunction) (*ast.FuncDecl, ast.Expr) {
	d := m.Decl
	literal := g.directFunctionLiteral(direct, m.Receiver.Name+"."+d.Name, d.Params, d.Result, d.Body, g.program.ParameterBindings(d), g.program.SelfBinding(d), m.Type).(*ast.FuncLit)
	decl := &ast.FuncDecl{Name: ident(direct.name), Type: literal.Type, Body: literal.Body}
	forwarded := []ast.Expr{ident("ctx"), ident("receiver")}
	for i := range m.Type.Params {
		var arg ast.Expr = index(ident("args"), intLiteral(i))
		if direct.params[i] != "" {
			arg = unbox(arg, direct.params[i])
		}
		forwarded = append(forwarded, arg)
	}
	var forwardCall ast.Expr = call(ident(direct.name), forwarded...)
	if direct.shape != nil {
		forwardCall = call(selector(forwardCall, "Box"), g.key(m.Type.Result))
	}
	// A dynamic entry counts depth, so a cycle through dynamic dispatch is bounded.
	forward := closure([]*ast.Field{field("ctx", &ast.StarExpr{X: runtimeName("Execution")}), field("receiver", runtimeName("Value")), field("args", sliceOf(runtimeName("Value")))}, runtimeName("Value"),
		evaluated(runtimeCall("Enter", ident("ctx"))),
		define("value", forwardCall),
		evaluated(runtimeCall("Exit", ident("ctx"))),
		returned(ident("value")))
	return decl, forward
}

// directFunction emits the Go declaration and the dynamic wrapper for s.
func (g *generator) directDeclaration(s *checker.Symbol) (*ast.FuncDecl, ast.Expr) {
	d := s.Decl
	direct := g.direct[s]
	signature := s.Type
	resultPos := ""
	var literal *ast.FuncLit
	if d.Kind == syntax.KindRecord {
		signature = checker.ConstructorSignature(s.Type)
		resultPos = d.Pos.String()
		_, _, _, _, lit := g.functionPieces(direct, d.Name, d.Fields, &syntax.Type{Pos: d.Pos}, nil, g.program.ParameterBindings(d), nil, signature, g.constructorStruct(s, direct))
		literal = lit.(*ast.FuncLit)
	} else {
		resultPos = d.Result.Pos.String()
		literal = g.directFunctionLiteral(direct, d.Name, d.Params, d.Result, d.Body, g.program.ParameterBindings(d), nil, s.Type).(*ast.FuncLit)
	}
	decl := &ast.FuncDecl{Name: ident(direct.name), Type: literal.Type, Body: literal.Body}
	var forwarded []ast.Expr
	var labels []string
	for i, p := range signature.Params {
		labels = append(labels, p.Name)
		var arg ast.Expr = index(ident("args"), intLiteral(i))
		if direct.params[i] != "" {
			arg = unbox(arg, direct.params[i])
		}
		forwarded = append(forwarded, arg)
	}
	var forwardCall ast.Expr = call(ident(direct.name), append([]ast.Expr{ident("ctx")}, forwarded...)...)
	if direct.shape != nil {
		forwardCall = call(selector(forwardCall, "Box"), g.key(signature.Result))
	}
	forward := closure([]*ast.Field{field("ctx", &ast.StarExpr{X: runtimeName("Execution")}), field("args", sliceOf(runtimeName("Value")))}, runtimeName("Value"),
		returned(forwardCall))
	wrapper := runtimeCall("NewDirectFunction", stringSlice(labels), g.key(signature.Result), textLiteral(resultPos), forward)
	return decl, concreteFunction(wrapper)
}

// directLiteral assembles the Go function literal for a lowered direct body.
func (g *generator) directLiteral(direct *directFunction, name string, result *syntax.Type, bindings []*checker.Binding, t *checker.Type, body []ast.Stmt) ast.Expr {
	params := []*ast.Field{field("ctx", &ast.StarExpr{X: runtimeName("Execution")})}
	if direct.receiver {
		params = append(params, field("receiver", runtimeName("Value")))
	}
	for i, b := range bindings {
		var typ ast.Expr = runtimeName("Value")
		if direct.params[i] != "" {
			typ = ident(direct.params[i])
		}
		params = append(params, field(b.ID, typ))
	}
	var resultType ast.Expr = runtimeName("Value")
	var zero ast.Expr = unit()
	if direct.result != "" {
		resultType = ident(direct.result)
		zero = zeroScalar(direct.result)
	}
	if direct.shape != nil {
		resultType = direct.shape.typeExpr()
		zero = composite(direct.shape.typeExpr())
	}
	var prologue []ast.Stmt
	if g.recovers {
		// Recovering a control panic abandons the callees that were entered.
		prologue = append(prologue, define("entryDepth", runtimeCall("Depth", ident("ctx"))))
	}
	if direct.counted {
		prologue = append(prologue, evaluated(runtimeCall("Enter", ident("ctx"))))
	}
	if g.recovers {
		var recovered ast.Expr = ident("value")
		if direct.result != "" {
			recovered = unbox(recovered, direct.result)
		}
		if direct.shape != nil {
			recovered = direct.shape.unbox(recovered)
		}
		prologue = append(prologue, &ast.DeferStmt{Call: call(closure(nil, nil,
			&ast.IfStmt{Cond: runtimeCall("ControlPending"), Body: block(
				&ast.IfStmt{Init: define("failure", call(ident("recover"))), Cond: &ast.BinaryExpr{X: ident("failure"), Op: token.NEQ, Y: ident("nil")}, Body: block(
					&ast.IfStmt{Init: &ast.AssignStmt{Lhs: []ast.Expr{ident("value"), ident("ok")}, Tok: token.DEFINE, Rhs: []ast.Expr{runtimeCall("ControlResult", ident("ctx"), ident("entryDepth"), ident("failure"), g.key(t.Result))}}, Cond: ident("ok"), Body: block(
						assign(ident("directResult"), token.ASSIGN, recovered),
						&ast.ReturnStmt{},
					)},
					evaluated(call(ident("panic"), ident("failure"))),
				)},
			)},
		))})
	}
	if g.needsCleanup {
		prologue = append(prologue, define("cleanupStack", runtimeCall("NewCleanupStack")), &ast.DeferStmt{Call: call(selector(ident("cleanupStack"), "Unwind"))})
	}
	out := append(prologue, body...)
	out = append(out, g.locatedStatement(syntax.Position{File: "manuscript.generated.go", Line: 1}, returned(zero)))
	if direct.counted {
		out = exitOnReturn(out)
	}
	lit := closure(params, resultType, out...)
	lit.Type.Results.List[0].Names = []*ast.Ident{ident("directResult")}
	return lit
}

func zeroScalar(typ string) ast.Expr {
	switch typ {
	case "int64", "float64":
		return call(ident(typ), intLiteral(0))
	case "bool":
		return ident("false")
	}
	return textLiteral("")
}

// directTarget returns the direct function a call invokes with every argument
// in declaration order and exactly typed, or nil.
func (g *generator) directTarget(e *syntax.Expression) *directFunction {
	if e.Kind != syntax.KindCall || g.direct == nil {
		return nil
	}
	info := g.program.Info(e)
	if direct, _ := g.directMethodTarget(e, info); direct != nil {
		return direct
	}
	if direct := g.localClosureTarget(e, info); direct != nil {
		return direct
	}
	var symbol *checker.Symbol
	var params []checker.Param
	switch {
	case info.Constructor != nil && info.Case == "" && info.Native != "view" && info.Constructor.Def != nil:
		symbol = info.Constructor.Def.Symbol
		if symbol == nil || g.direct[symbol] == nil || symbol.Decl.Kind != syntax.KindRecord {
			return nil
		}
		params = checker.ConstructorSignature(symbol.Type).Params
	case info.Symbol != nil && info.Constructor == nil && info.ErrorSource == nil:
		symbol = info.Symbol
		params = symbol.Type.Params
	default:
		return nil
	}
	direct := g.direct[symbol]
	if direct == nil {
		return nil
	}
	args := info.Arguments
	if len(args) > len(params) {
		return nil
	}
	// Trailing parameters may be omitted only when they have defaults.
	for i := len(args); i < len(params); i++ {
		if !direct.defaulted[i] {
			return nil
		}
	}
	for i, arg := range args {
		if arg.Name != params[i].Name {
			return nil
		}
		if typ := direct.params[i]; typ != "" && primitiveEqualityType(g.program.Info(arg.Value).Type) != typ {
			return nil
		}
	}
	return direct
}

// directCall lowers a direct call to a Value-compatible expression. A typed
// Result/Optional is boxed here so every consumer that is not try, match or
// return sees the Alternative it always saw.
func (g *generator) directCall(e *syntax.Expression) ast.Expr {
	value, direct := g.typedDirectCall(e)
	if value != nil && direct.shape != nil {
		return call(selector(value, "Box"), g.key(g.program.Info(e).Type))
	}
	return value
}

// typedDirectCall lowers a direct invocation (call or accessor read) without
// boxing its typed result.
func (g *generator) typedDirectCall(e *syntax.Expression) (ast.Expr, *directFunction) {
	if e.Kind == syntax.KindMember {
		if direct := g.directAccessorTarget(e, g.program.Info(e)); direct != nil {
			return orderedCall(ident(direct.name), ident("ctx"), g.expression(e.Left)), direct
		}
		return nil, nil
	}
	direct := g.directTarget(e)
	if direct == nil {
		return nil, nil
	}
	info := g.program.Info(e)
	args := info.Arguments
	values := []ast.Expr{ident("ctx")}
	if direct.receiver {
		// The receiver is evaluated before the arguments.
		receiver := e.Left.Left
		value := g.expression(receiver)
		if !(g.exprFree(receiver) && g.restFree(args)) {
			value = sequence(value)
		}
		values = append(values, value)
	}
	for i, arg := range args {
		var value ast.Expr
		if typ := direct.params[i]; typ != "" {
			value = g.scalar(arg.Value, typ)
		} else {
			value = g.argumentValue(arg)
		}
		// A later match argument can reassign a local used by an earlier
		// argument. Force each value's capture before evaluating the next,
		// unless nothing after it can run code.
		if g.exprFree(arg.Value) && g.restFree(args[i+1:]) {
			values = append(values, value)
		} else {
			values = append(values, sequence(value))
		}
	}
	for i := len(args); i < len(direct.params); i++ {
		values = append(values, call(runtimeName("Value"), ident("nil")))
	}
	return orderedCall(ident(direct.name), values...), direct
}

func (g *generator) restFree(args []syntax.Argument) bool {
	for _, a := range args {
		if !g.exprFree(a.Value) {
			return false
		}
	}
	return true
}

// directMethodTarget returns the direct method a call of a concrete record or
// alternative receiver invokes with every argument in declaration order and
// exactly typed, with the method, or nil.
func (g *generator) directMethodTarget(e *syntax.Expression, info *checker.Info) (*directFunction, *checker.Method) {
	if len(g.directMethods) == 0 || e.Left == nil || e.Left.Kind != syntax.KindMember || info.ErrorSource != nil || info.Constructor != nil {
		return nil, nil
	}
	callee := g.program.Info(e.Left)
	if callee == nil || callee.Method == nil || callee.Method.Accessor {
		return nil, nil
	}
	direct := g.directMethods[callee.Method.ID]
	if direct == nil {
		return nil, nil
	}
	receiverType := g.program.Info(e.Left.Left).Type
	if (receiverType.Kind != syntax.KindRecord && receiverType.Kind != "alternative") || len(receiverType.Args) != 0 || hasTypeVariable(receiverType) || receiverType.ID != callee.Method.Receiver.ID {
		return nil, nil
	}
	args := info.Arguments
	params := callee.Method.Type.Params
	if len(args) != len(params) {
		return nil, nil
	}
	for i, arg := range args {
		if arg.Name != params[i].Name {
			return nil, nil
		}
		if typ := direct.params[i]; typ != "" && primitiveEqualityType(g.program.Info(arg.Value).Type) != typ {
			return nil, nil
		}
	}
	return direct, callee.Method
}
