package golower

import (
	"go/ast"
	"go/token"
	"sort"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// funcDecl is one Go function: a source function or method instantiated at
// concrete type arguments.
type funcDecl struct {
	key    string
	name   string
	module string
	symbol *checker.Symbol
	method *checker.Method
	decl   *syntax.Declaration
	typ    *checker.Type // the instantiated function type
	subst  map[string]*checker.Type
	out    *ast.FuncDecl
}

// function returns the Go function for symbol at typeArgs, queueing its body
// for lowering. typeArgs are concrete: the caller has applied its own
// substitution.
func (g *gen) function(symbol *checker.Symbol, typeArgs []*checker.Type) *funcDecl {
	key := symbol.ID
	for _, a := range typeArgs {
		key += "[" + checker.TypeKey(a) + "]"
	}
	if f := g.funcs[key]; f != nil {
		return f
	}
	subst := map[string]*checker.Type{}
	for i, v := range symbol.Variables {
		if i < len(typeArgs) {
			subst[v.ID] = typeArgs[i]
		}
	}
	name := sanitize(symbol.Name)
	for _, a := range typeArgs {
		name += "_" + g.nameOf(a)
	}
	f := &funcDecl{key: key, name: g.unique(name), module: symbol.Module, symbol: symbol, decl: symbol.Decl, subst: subst}
	f.typ = checker.Sub(symbol.Type, subst)
	g.funcs[key] = f
	g.queue = append(g.queue, f)
	return f
}

// lowerFunction produces the Go declaration of f.
func (g *gen) lowerFunction(f *funcDecl) {
	savedModule, savedSubst, savedFn := g.module, g.subst, g.fn
	g.module, g.subst = f.module, f.subst
	g.infoCache = nil
	defer func() { g.module, g.subst, g.fn = savedModule, savedSubst, savedFn; g.infoCache = nil }()

	d := f.decl
	g.fn = &funcState{decl: f, result: g.sub(f.typ.Result)}
	var params []*ast.Field
	params = append(params, field("ctx", pointerTo(rtName("Execution"))))
	bindings := g.program.ParameterBindings(d)
	g.markUsed(d.Params, d.Body)
	var prologue []ast.Stmt
	if f.method != nil {
		if self := g.program.SelfBinding(d); self != nil {
			params = append(params, field(g.bindingName(self), g.goType(self.Type)))
			prologue = append(prologue, g.keepUnused(self)...)
		}
	}
	for i, b := range bindings {
		params = append(params, field(g.bindingName(b), g.goType(b.Type)))
		prologue = append(prologue, g.keepUnused(b)...)
		_ = i
	}
	body := g.body(d.Body, g.fn.result)
	body = append(prologue, body...)
	body = g.finishBody(body, g.fn.result)
	f.out = &ast.FuncDecl{Name: ident(f.name), Type: functionType(params, g.goType(g.fn.result)), Body: block(body...)}
	g.decls = append(g.decls, f.out)
}

// finishBody terminates a body Go cannot prove returns: Unit functions return
// the unit value, and others end in an unreachable fault.
func (g *gen) finishBody(body []ast.Stmt, result *checker.Type) []ast.Stmt {
	if len(body) > 0 {
		if _, ok := unlabel(body[len(body)-1]).(*ast.ReturnStmt); ok {
			return body
		}
	}
	if result.ID == "Unit" || result.ID == "Never" {
		return append(body, returned(g.unit()))
	}
	return append(body, evaluated(rtCall("Unreachable")), returned(g.zero(result)))
}

func unlabel(s ast.Stmt) ast.Stmt {
	for {
		l, ok := s.(*ast.LabeledStmt)
		if !ok {
			return s
		}
		s = l.Stmt
	}
}

func (g *gen) unit() ast.Expr { return composite(rtName("Unit")) }

// zero is the Go zero value of t.
func (g *gen) zero(t *checker.Type) ast.Expr {
	t = g.sub(t)
	switch scalarGo(t) {
	case "int64", "float64":
		return call(ident(scalarGo(t)), intLiteral(0))
	case "bool":
		return ident("false")
	case "string":
		return textLiteral("")
	}
	return call(generic(rtName("Zero"), g.goType(t)))
}

// bindingName is the Go identifier of a Manuscript variable.
func (g *gen) bindingName(b *checker.Binding) string {
	if name, ok := g.captured[b]; ok {
		return name
	}
	return sanitize(b.ID)
}

// markUsed records which bindings the body reads, so declarations of the
// others can be kept alive without a use.
func (g *gen) markUsed(params []syntax.Parameter, body []*syntax.Statement) {
	if g.used == nil {
		g.used = map[*checker.Binding]bool{}
	}
	syntax.Visitor{Expression: func(e *syntax.Expression) {
		if info := g.program.Info(e); info != nil {
			if info.Binding != nil && e.Kind == syntax.KindName {
				g.used[info.Binding] = true
			}
			for _, c := range info.Captures {
				g.used[c] = true
			}
		}
	}}.Callable(params, body)
}

// keepUnused is `_ = name` for a binding nothing reads.
func (g *gen) keepUnused(b *checker.Binding) []ast.Stmt {
	if b == nil || g.used[b] {
		return nil
	}
	return []ast.Stmt{discard(ident(g.bindingName(b)))}
}

// sortedBindings orders captures for deterministic output.
func sortedBindings(bs []*checker.Binding) []*checker.Binding {
	out := append([]*checker.Binding{}, bs...)
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out
}

var _ = token.ADD
