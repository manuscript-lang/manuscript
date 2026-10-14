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
// own frame (rt.Enter, rt.Leave), so no wrapper layer runs per call.
type directFunction struct {
	name   string
	params []string  // Go scalar type per parameter, "" for Value
	result string    // Go scalar result type, "" for Value
	shape  *altShape // typed Result/Optional result, nil when result is scalar or Value
	// receiver marks a method: the Go function takes its receiver as the
	// Value parameter after ctx.
	receiver bool
}

// planDirect decides which top-level functions are emitted as direct functions.
// Profiling needs every call to pass the dynamic wrapper, which labels it.
func (g *generator) planDirect(functions []*checker.Symbol, options Options) {
	g.direct = map[*checker.Symbol]*directFunction{}
	g.directMethods = map[string]*directFunction{}
	if options.CPUProfile != "" || options.HeapProfile != "" || options.Trace != "" {
		return
	}
	for _, s := range functions {
		d := s.Decl
		if s.Native != "" || len(s.Variables) != 0 || d == nil || d.Kind != syntax.KindFn {
			continue
		}
		direct := &directFunction{name: "call_" + s.ID, result: primitiveEqualityType(s.Type.Result), shape: alternativeShape(s.Type.Result)}
		bindings := g.program.ParameterBindings(d)
		if len(bindings) != len(d.Params) || len(s.Type.Params) != len(d.Params) {
			continue
		}
		eligible := true
		for i, p := range d.Params {
			// Omitted arguments reach the function as nil; only dynamic calls omit.
			if p.Default != nil || s.Type.Defaults[s.Type.Params[i].Name] {
				eligible = false
			}
			direct.params = append(direct.params, scalarBinding(bindings[i]))
		}
		if eligible {
			g.direct[s] = direct
		}
	}
	for i, m := range g.program.Methods {
		if direct := g.planDirectMethod(m, i); direct != nil {
			g.directMethods[m.ID] = direct
		}
	}
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
	forward := closure([]*ast.Field{field("ctx", &ast.StarExpr{X: runtimeName("Execution")}), field("receiver", runtimeName("Value")), field("args", sliceOf(runtimeName("Value")))}, runtimeName("Value"),
		returned(forwardCall))
	return decl, forward
}

// directFunction emits the Go declaration and the dynamic wrapper for s.
func (g *generator) directDeclaration(s *checker.Symbol) (*ast.FuncDecl, ast.Expr) {
	d := s.Decl
	direct := g.direct[s]
	literal := g.directFunctionLiteral(direct, d.Name, d.Params, d.Result, d.Body, g.program.ParameterBindings(d), nil, s.Type).(*ast.FuncLit)
	decl := &ast.FuncDecl{Name: ident(direct.name), Type: literal.Type, Body: literal.Body}
	var forwarded []ast.Expr
	var labels []string
	for i, p := range s.Type.Params {
		labels = append(labels, p.Name)
		var arg ast.Expr = index(ident("args"), intLiteral(i))
		if direct.params[i] != "" {
			arg = unbox(arg, direct.params[i])
		}
		forwarded = append(forwarded, arg)
	}
	var forwardCall ast.Expr = call(ident(direct.name), append([]ast.Expr{ident("ctx")}, forwarded...)...)
	if direct.shape != nil {
		forwardCall = call(selector(forwardCall, "Box"), g.key(s.Type.Result))
	}
	forward := closure([]*ast.Field{field("ctx", &ast.StarExpr{X: runtimeName("Execution")}), field("args", sliceOf(runtimeName("Value")))}, runtimeName("Value"),
		returned(forwardCall))
	wrapper := runtimeCall("NewDirectFunction", stringSlice(labels), g.key(s.Type.Result), textLiteral(d.Result.Pos.String()), forward)
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
	prologue := []ast.Stmt{
		evaluated(runtimeCall("Enter", ident("ctx"))),
		define("sourcePosition", textLiteral(result.Pos.String())),
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
					&ast.IfStmt{Init: &ast.AssignStmt{Lhs: []ast.Expr{ident("value"), ident("ok")}, Tok: token.DEFINE, Rhs: []ast.Expr{runtimeCall("ControlResult", ident("ctx"), ident("failure"), g.key(t.Result))}}, Cond: ident("ok"), Body: block(
						assign(ident("directResult"), token.ASSIGN, recovered),
						&ast.ReturnStmt{},
					)},
					evaluated(call(ident("panic"), ident("failure"))),
				)},
			)},
		))})
	}
	prologue = append(prologue, &ast.DeferStmt{Call: runtimeCall("Leave", ident("ctx"), address(ident("sourcePosition")), textLiteral(name))})
	if g.needsCleanup {
		prologue = append(prologue, define("cleanupStack", runtimeCall("NewCleanupStack")), &ast.DeferStmt{Call: call(selector(ident("cleanupStack"), "Unwind"))})
	}
	out := append(prologue, body...)
	out = append(out, g.locatedStatement(syntax.Position{File: "manuscript.generated.go", Line: 1}, returned(zero)))
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
	if info.Symbol == nil || info.Constructor != nil || info.ErrorSource != nil {
		return nil
	}
	direct := g.direct[info.Symbol]
	if direct == nil {
		return nil
	}
	args := info.Arguments
	params := info.Symbol.Type.Params
	if len(args) != len(params) {
		return nil
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

// typedDirectCall lowers a direct call without boxing its typed result.
func (g *generator) typedDirectCall(e *syntax.Expression) (ast.Expr, *directFunction) {
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
			value = sourceAt(receiver.Pos, value)
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
			values = append(values, sourceAt(arg.Pos, value))
		}
	}
	return g.locatedOperation(e, ident(direct.name), values...), direct
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
	if callee == nil || callee.Method == nil {
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
