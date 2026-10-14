package lower

import (
	"go/ast"
	"go/token"

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
	params []string // Go scalar type per parameter, "" for Value
	result string   // Go scalar result type, "" for Value
}

// planDirect decides which top-level functions are emitted as direct functions.
// Profiling needs every call to pass the dynamic wrapper, which labels it.
func (g *generator) planDirect(functions []*checker.Symbol, options Options) {
	g.direct = map[*checker.Symbol]*directFunction{}
	if options.CPUProfile != "" || options.HeapProfile != "" || options.Trace != "" {
		return
	}
	for _, s := range functions {
		d := s.Decl
		if s.Native != "" || len(s.Variables) != 0 || d == nil || d.Kind != syntax.KindFn {
			continue
		}
		direct := &directFunction{name: "call_" + s.ID, result: primitiveEqualityType(s.Type.Result)}
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
}

// directFunction emits the Go declaration and the dynamic wrapper for s.
func (g *generator) directDeclaration(s *checker.Symbol) (*ast.FuncDecl, ast.Expr) {
	d := s.Decl
	direct := g.direct[s]
	literal := g.directFunctionLiteral(direct, d.Name, d.Params, d.Result, d.Body, g.program.ParameterBindings(d), s.Type).(*ast.FuncLit)
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
	forward := closure([]*ast.Field{field("ctx", &ast.StarExpr{X: runtimeName("Execution")}), field("args", sliceOf(runtimeName("Value")))}, runtimeName("Value"),
		returned(call(ident(direct.name), append([]ast.Expr{ident("ctx")}, forwarded...)...)))
	wrapper := runtimeCall("NewDirectFunction", stringSlice(labels), g.key(s.Type.Result), textLiteral(d.Result.Pos.String()), forward)
	return decl, concreteFunction(wrapper)
}

// directLiteral assembles the Go function literal for a lowered direct body.
func (g *generator) directLiteral(direct *directFunction, name string, result *syntax.Type, bindings []*checker.Binding, t *checker.Type, body []ast.Stmt) ast.Expr {
	params := []*ast.Field{field("ctx", &ast.StarExpr{X: runtimeName("Execution")})}
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
	prologue := []ast.Stmt{
		evaluated(runtimeCall("Enter", ident("ctx"))),
		define("sourcePosition", textLiteral(result.Pos.String())),
	}
	if g.recovers {
		var recovered ast.Expr = ident("value")
		if direct.result != "" {
			recovered = unbox(recovered, direct.result)
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
	if info.Symbol == nil || info.Constructor != nil || info.ErrorSource != nil {
		return nil
	}
	direct := g.direct[info.Symbol]
	if direct == nil {
		return nil
	}
	args := e.Args
	if info.Arguments != nil {
		args = info.Arguments
	}
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

func (g *generator) directCall(e *syntax.Expression) ast.Expr {
	direct := g.directTarget(e)
	if direct == nil {
		return nil
	}
	info := g.program.Info(e)
	args := e.Args
	if info.Arguments != nil {
		args = info.Arguments
	}
	values := []ast.Expr{ident("ctx")}
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
	return g.locatedOperation(e, ident(direct.name), values...)
}

func (g *generator) restFree(args []syntax.Argument) bool {
	for _, a := range args {
		if !g.exprFree(a.Value) {
			return false
		}
	}
	return true
}
