package lower

import (
	"go/ast"
	"go/token"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// A direct function is a nongeneric top-level source function emitted as a
// plain Go function with typed scalar parameters and result. Calls that name
// it with checked supplied/default slots call it directly; the dynamic Function in
// its symbol variable only forwards to it. The function admits and leaves its
// own frame (rt.Enter, rt.Leave), so no wrapper layer runs per call.
type directFunction struct {
	name     string
	params   []string // Go scalar type per parameter, "" for Value
	result   string   // Go scalar result type, "" for Value
	defaults []bool   // supplied flags for eligible scalar defaults
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
			// Only pure scalar arithmetic defaults use typed supplied flags.
			if p.Default != nil || s.Type.Defaults[s.Type.Params[i].Name] {
				eligible = eligible && g.scalarDefaultBody(d, bindings)
			}
			direct.params = append(direct.params, scalarBinding(bindings[i]))
			direct.defaults = append(direct.defaults, p.Default != nil || s.Type.Defaults[s.Type.Params[i].Name])
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
			if direct.defaults[i] {
				arg = runtimeCall(map[string]string{"int64": "IntArgument", "float64": "FloatArgument", "bool": "BoolArgument", "string": "StringArgument"}[direct.params[i]], arg)
			} else {
				arg = unbox(arg, direct.params[i])
			}
		}
		forwarded = append(forwarded, arg)
		if direct.defaults[i] {
			forwarded = append(forwarded, &ast.BinaryExpr{X: index(ident("args"), intLiteral(i)), Op: token.NEQ, Y: ident("nil")})
		}
	}
	forward := closure([]*ast.Field{field("ctx", &ast.StarExpr{X: runtimeName("Execution")}), field("args", sliceOf(runtimeName("Value")))}, runtimeName("Value"),
		returned(call(ident(direct.name), append([]ast.Expr{ident("ctx")}, forwarded...)...)))
	wrapper := runtimeCall("NewCompiledDirectFunction", stringSlice(labels), g.key(s.Type.Result), textLiteral(d.Result.Pos.String()), forward)
	if len(direct.params) == 2 && !direct.defaults[0] && !direct.defaults[1] && direct.result == "int64" && direct.params[0] == direct.params[1] && (direct.params[0] == "int64" || direct.params[0] == "float64") && labels[0] == "left" && labels[1] == "right" {
		typ := direct.params[0]
		name := map[string]string{"int64": "Int", "float64": "Float"}[typ]
		compare := closure([]*ast.Field{field("ctx", &ast.StarExpr{X: runtimeName("Execution")}), field("left", ident(typ)), field("right", ident(typ))}, ident("int64"), returned(call(ident(direct.name), ident("ctx"), ident("left"), ident("right"))))
		wrapper = runtimeCall("WithDirect"+name+"Compare", wrapper, compare)
	}
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
		if len(direct.defaults) > i && direct.defaults[i] {
			params = append(params, field("provided_"+b.ID, ident("bool")))
		}
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

// directTarget selects a checked direct function with compatible supplied
// arguments and defaults. Written argument order is retained by directCall.
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
	args := info.Arguments
	params := info.Symbol.Type.Params
	if len(args) > len(params) {
		return nil
	}
	if len(args) < len(params) {
		for i, p := range params {
			supplied := false
			for _, a := range args {
				supplied = supplied || a.Name == p.Name
			}
			if !supplied && !direct.defaults[i] {
				return nil
			}
		}
	}
	for _, arg := range args {
		slot := -1
		for j, p := range params {
			if p.Name == arg.Name {
				slot = j
				break
			}
		}
		if slot < 0 {
			return nil
		}
		if typ := direct.params[slot]; typ != "" && primitiveEqualityType(g.program.Info(arg.Value).Type) != typ {
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
	args := info.Arguments
	params := info.Symbol.Type.Params
	values := make([]ast.Expr, len(params))
	present := make([]bool, len(params))
	var captures []ast.Stmt
	ordered := len(args) == len(params)
	for i, arg := range args {
		if arg.Name != params[i].Name {
			ordered = false
			break
		}
	}
	for i, arg := range args {
		slot := i
		if !ordered {
			for j, p := range params {
				if p.Name == arg.Name {
					slot = j
					break
				}
			}
		}
		var value ast.Expr
		if typ := direct.params[slot]; typ != "" {
			value = g.scalar(arg.Value, typ)
		} else {
			value = g.argumentValue(arg)
		}
		if !ordered {
			tmp := g.temp()
			captures = append(captures, define(tmp, sourceAt(arg.Pos, value)))
			value = ident(tmp)
		} else if !(g.exprFree(arg.Value) && g.restFree(args[i+1:])) {
			value = sourceAt(arg.Pos, value)
		}
		values[slot] = value
		present[slot] = true
	}
	arguments := []ast.Expr{ident("ctx")}
	for i, value := range values {
		if !present[i] {
			value = zeroScalar(direct.params[i])
		}
		arguments = append(arguments, value)
		if direct.defaults[i] {
			if present[i] {
				arguments = append(arguments, ident("true"))
			} else {
				arguments = append(arguments, ident("false"))
			}
		}
	}

	operation := g.locatedOperation(e, ident(direct.name), arguments...)
	if ordered {
		return operation
	}
	captures = append(captures, returned(operation))
	var result ast.Expr = runtimeName("Value")
	if direct.result != "" {
		result = ident(direct.result)
	}
	return call(closure(nil, result, captures...))

}

func (g *generator) restFree(args []syntax.Argument) bool {
	for _, a := range args {
		if !g.exprFree(a.Value) {
			return false
		}
	}
	return true
}

// Restrict new default signatures to arithmetic bodies that already box their
// scalar result at a dynamic boundary. Forwarding/identity functions retain
// their original boxed representation, avoiding replacement allocations.
func (g *generator) scalarDefaultBody(d *syntax.Declaration, bindings []*checker.Binding) bool {
	if len(d.Body) != 1 || d.Body[0].Kind != syntax.KindReturn || d.Body[0].Value == nil || d.Body[0].Value.Kind != syntax.KindBinary || g.numericResult(d.Body[0].Value) == "" {
		return false
	}
	for _, b := range bindings {
		if scalarBinding(b) == "" {
			return false
		}
	}
	valid, usesParameter := true, false
	syntax.Visitor{Expression: func(e *syntax.Expression) {
		switch e.Kind {
		case syntax.KindNumber, syntax.KindName, syntax.KindBinary, syntax.KindUnary:
		default:
			valid = false
		}
		if e.Kind == syntax.KindName {
			for _, b := range bindings {
				if g.program.Info(e).Binding == b {
					usesParameter = true
				}
			}
		}
	}}.Callable(nil, d.Body)
	return valid && usesParameter
}
