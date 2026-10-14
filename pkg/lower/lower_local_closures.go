package lower

import (
	"go/ast"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// An immutable `let f = fn(...)` whose every use is a direct call in the
// function that declares it is emitted as a typed Go function literal and
// called as `f(ctx, a, b)`: no Function value, argument slice or boxing. Any
// other use of the name (passed, returned, stored, captured by a closure,
// called out of order) keeps the ordinary Function value. Captured variables
// are still snapshotted when the closure is created.

// localClosure lowers the binding or returns nil when it does not qualify.
func (g *generator) localClosure(s *syntax.Statement) []ast.Stmt {
	if !g.directOn || s.Pattern.Kind != syntax.KindName || s.Value.Kind != syntax.KindLambda {
		return nil
	}
	b := g.program.PatternBinding(s.Pattern)
	u := g.altUses[b]
	if b == nil || b.Mutable || u == nil || u.captured || u.calls == 0 || u.names != u.calls {
		return nil
	}
	e := s.Value
	info := g.program.Info(e)
	if info == nil || info.Type == nil || info.Type.Kind != "function" || hasTypeVariable(info.Type) || info.ErrorSource != nil {
		return nil
	}
	bindings := g.program.LambdaBindings(e)
	if len(bindings) != len(e.Params) || len(info.Type.Params) != len(e.Params) {
		return nil
	}
	direct := &directFunction{name: b.ID, result: primitiveEqualityType(info.Type.Result), shape: alternativeShape(info.Type.Result)}
	for i, p := range e.Params {
		if p.Default != nil || info.Type.Defaults[info.Type.Params[i].Name] {
			return nil
		}
		direct.params = append(direct.params, scalarBinding(bindings[i]))
		direct.defaulted = append(direct.defaulted, false)
	}
	for _, site := range u.callSites {
		if !g.closureCallMatches(site, direct) {
			return nil
		}
	}
	if g.localClosures == nil {
		g.localClosures = map[*checker.Binding]*directFunction{}
	}
	g.localClosures[b] = direct
	value := g.directLambda(e, info, direct, bindings)
	literalType := value.typ
	return []ast.Stmt{&ast.DeclStmt{Decl: variable(b.ID, literalType, value.expr)}, discard(ident(b.ID))}
}

type directLambdaValue struct {
	expr ast.Expr
	typ  ast.Expr
}

// directLambda is lambdaValue for a typed Go function literal.
func (g *generator) directLambda(e *syntax.Expression, info *checker.Info, direct *directFunction, bindings []*checker.Binding) directLambdaValue {
	captures := sortedCaptures(info)
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
	literal := g.directFunctionLiteral(direct, "<anonymous>", e.Params, result, e.Body, bindings, nil, info.Type).(*ast.FuncLit)
	for _, b := range captures {
		if old[b] == "" {
			delete(g.captures, b)
		} else {
			g.captures[b] = old[b]
		}
	}
	typ := &ast.FuncType{Params: literal.Type.Params, Results: &ast.FieldList{List: []*ast.Field{{Type: literal.Type.Results.List[0].Type}}}}
	named := runtimeCall("NamedFunc", textLiteral("<anonymous>"), literal)
	return directLambdaValue{expr: call(closure(declarations, typ, returned(named)), values...), typ: typ}
}

// closureCallMatches reports whether a call supplies every argument in
// declaration order with the types the typed closure takes.
func (g *generator) closureCallMatches(e *syntax.Expression, direct *directFunction) bool {
	info := g.program.Info(e)
	callee := g.program.Info(e.Left)
	if info == nil || callee == nil || callee.Type == nil || info.Constructor != nil || info.ErrorSource != nil || len(info.Arguments) != len(callee.Type.Params) || len(info.Arguments) != len(direct.params) {
		return false
	}
	for i, arg := range info.Arguments {
		if arg.Name != callee.Type.Params[i].Name {
			return false
		}
		if typ := direct.params[i]; typ != "" && primitiveEqualityType(g.program.Info(arg.Value).Type) != typ {
			return false
		}
	}
	return true
}

// localClosureTarget is the typed closure a call of a local name invokes, or nil.
func (g *generator) localClosureTarget(e *syntax.Expression, info *checker.Info) *directFunction {
	if len(g.localClosures) == 0 || e.Left == nil || e.Left.Kind != syntax.KindName {
		return nil
	}
	callee := g.program.Info(e.Left)
	if callee == nil || callee.Binding == nil {
		return nil
	}
	direct := g.localClosures[callee.Binding]
	if direct == nil || !g.closureCallMatches(e, direct) {
		return nil
	}
	return direct
}
