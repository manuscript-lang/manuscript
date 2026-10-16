package lower

import (
	"go/ast"
	"go/token"
	"sort"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// funcDecl is one Go function: a source function or method instantiated at
// concrete type arguments.
type funcDecl struct {
	node
	key    string
	name   string
	module string
	scope  string
	symbol *checker.Symbol
	method *checker.Method
	decl   *syntax.Declaration
	typ    *checker.Type // the instantiated function type
	subst  map[string]*checker.Type
	out    *ast.FuncDecl
}

// sourceName is the name fault traces show for f.
func (f *funcDecl) sourceName() string {
	if f.method == nil && f.symbol == nil && f.decl != nil && f.decl.Kind == syntax.KindTest {
		return "test " + f.decl.Name
	}
	if f.method != nil && f.method.Receiver != nil {
		return f.method.Receiver.Name + "." + f.decl.Name
	}
	if f.decl != nil {
		return f.decl.Name
	}
	return f.name
}

// function returns the Go function for symbol at typeArgs, queueing its body
// for lowering. typeArgs are concrete: the caller has applied its own
// substitution.
func (g *gen) function(symbol *checker.Symbol, typeArgs []*checker.Type) *funcDecl {
	key := symbol.ID
	for _, a := range typeArgs {
		key += "[" + checker.TypeKey(a) + "]"
	}
	scope := g.scopeFor(symbol.Module, len(symbol.Variables))
	if scope != "" {
		key += "@" + scope
	}
	g.mu.Lock()
	f := g.funcs[key]
	g.mu.Unlock()
	if f != nil {
		g.touch(&f.node)
		return f
	}
	subst := map[string]*checker.Type{}
	for i, v := range symbol.Variables {
		if i < len(typeArgs) {
			subst[v.ID] = typeArgs[i]
		}
	}
	base := sanitize(symbol.Name)
	name := base
	if g.dup[base] {
		name += "_" + shortHash(symbol.ID)
	}
	for _, a := range typeArgs {
		name += "_" + g.nameOf(a)
	}
	if scope != "" {
		name += "_" + shortHash(scope)
	}
	created := &funcDecl{key: key, name: g.derivedOrClaim(name, key, len(typeArgs) > 0 || scope != ""), module: symbol.Module, scope: scope, symbol: symbol, decl: symbol.Decl, subst: subst}
	created.typ = checker.Sub(symbol.Type, subst)
	created.fn = created
	return g.intern(created)
}

// intern registers f unless an equal instance already exists, and notes that
// the node being built needs the instance either way.
func (g *gen) intern(f *funcDecl) *funcDecl {
	g.mu.Lock()
	if existing := g.funcs[f.key]; existing != nil {
		f = existing
	} else {
		g.funcs[f.key] = f
	}
	g.mu.Unlock()
	g.touch(&f.node)
	return f
}

// lowerFunction produces the Go declaration of f.
func (g *gen) lowerFunction(f *funcDecl) {
	g.module, g.scope, g.subst = f.module, f.scope, f.subst
	g.stack = []*node{&f.node}

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
		fld, fill := g.parameter(b, f.typ, i, d.Params)
		params = append(params, fld)
		prologue = append(prologue, fill...)
	}
	if fixture := g.program.FixtureBinding(d); fixture != nil {
		params = append(params, field(g.bindingName(fixture), g.goType(fixture.Type)))
		prologue = append(prologue, g.keepUnused(fixture)...)
	}
	body := g.body(d.Body, g.fn.result)
	body = append(prologue, body...)
	body = g.finishBody(body, g.fn.result)
	if g.recursive[d] {
		// Depth is counted without a defer: every normal return leaves, and
		// code that recovers a panic restores the depth it saw.
		body = append([]ast.Stmt{evaluated(rtCall("Enter", ident("ctx")))}, exitBeforeReturns(body)...)
	}
	body = g.cleanupPrologue(body)
	f.out = &ast.FuncDecl{Name: ident(f.name), Type: functionType(params, g.goType(g.fn.result)), Body: block(body...)}
}

// parameter declares parameter i of a function or lambda. A defaulted
// parameter arrives as rt.Arg; its prologue binds the supplied value or, when
// the argument was omitted, evaluates the default here, in the callee's scope,
// so a default may read earlier parameters and `try` returns from the callee.
func (g *gen) parameter(b *checker.Binding, sig *checker.Type, i int, decls []syntax.Parameter) (*ast.Field, []ast.Stmt) {
	name := g.bindingName(b)
	if sig == nil || i >= len(sig.Params) || !defaulted(sig, i) {
		return field(name, g.goType(b.Type)), g.keepUnused(b)
	}
	arg := "arg_" + name
	typ := g.goType(b.Type)
	var absent []ast.Stmt
	expr, module := g.defaultExpression(sig, i, decls)
	if expr != nil {
		saved, savedModule := g.fn.pre, g.module
		g.fn.pre, g.module = nil, module
		value := g.valueAs(expr, b.Type)
		absent = append(g.fn.pre, assign(ident(name), token.ASSIGN, value))
		for i, s := range absent {
			absent[i] = g.locatedStatement(expr.Pos, s)
		}
		g.fn.pre, g.module = saved, savedModule
	} else {
		// An omittable parameter without a default expression is none.
		absent = []ast.Stmt{assign(ident(name), token.ASSIGN, composite(typ))}
	}
	stmts := []ast.Stmt{
		varDecl(name, typ, nil),
		&ast.IfStmt{
			Cond: selector(ident(arg), "Set"),
			Body: block(assign(ident(name), token.ASSIGN, selector(ident(arg), "Val"))),
			Else: block(absent...),
		},
	}
	return field(arg, generic(rtName("Arg"), typ)), append(stmts, g.keepUnused(b)...)
}

// defaultExpression finds the default of parameter i: the one it declares, or
// for a method implementing a contract operation, the one the operation
// declares in the contract's module.
func (g *gen) defaultExpression(sig *checker.Type, i int, decls []syntax.Parameter) (*syntax.Expression, string) {
	if i < len(decls) && decls[i].Default != nil {
		return decls[i].Default, g.module
	}
	if f := g.fn.decl; f != nil && f.method != nil && f.method.Contract != nil && f.method.Contract.Def != nil {
		for _, op := range f.method.Contract.Def.Operations {
			if op.Name == f.method.Decl.Name && op.Decl != nil && i < len(op.Decl.Params) && op.Decl.Params[i].Default != nil {
				module := g.module
				if sym := f.method.Contract.Def.Symbol; sym != nil {
					module = sym.Module
				}
				def := op.Decl.Params[i].Default
				if g.program.Info(def) == nil && def.Kind == syntax.KindName && def.Text == "none" {
					return nil, module // standard declarations spell the omitted Optional as none
				}
				return def, module
			}
		}
	}
	return nil, g.module
}

// cleanupPrologue creates the function's cleanup stack when its body uses with.
func (g *gen) cleanupPrologue(body []ast.Stmt) []ast.Stmt {
	if !g.fn.cleanup {
		return body
	}
	return append([]ast.Stmt{
		define("cs", address(composite(rtName("CleanupStack")))),
		&ast.DeferStmt{Call: call(selector(ident("cs"), "Unwind"))},
	}, body...)
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
	case "int", "float64":
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
	if name, ok := g.locals[b]; ok {
		return name
	}
	base := sanitize(b.Name)
	if base == "" || reservedLocal(base) {
		base += "_"
	}
	name := base
	for n := 2; g.localNames[name]; n++ {
		name = base + "_" + itoa(n)
	}
	if g.locals == nil {
		g.locals, g.localNames = map[*checker.Binding]string{}, map[string]bool{}
	}
	g.locals[b], g.localNames[name] = name, true
	if g.options.Locals != nil && g.fn != nil && g.fn.decl != nil {
		g.mu.Lock()
		g.options.Locals(g.fn.decl.sourceName(), name, b)
		g.mu.Unlock()
	}
	return name
}

// reservedLocal reports names a local variable must not take: the generated
// code's own identifiers, Go keywords, and predeclared names it relies on.
func reservedLocal(name string) bool {
	if goKeywords[name] || reserved[name] || predeclared[name] || name == "cs" {
		return true
	}
	if len(name) > 1 && name[0] == 't' {
		for _, r := range name[1:] {
			if r < '0' || r > '9' {
				return false
			}
		}
		return true
	}
	return false
}

var predeclared = map[string]bool{
	"bool": true, "byte": true, "error": true, "float64": true, "int": true, "int64": true, "string": true,
	"uint32": true, "true": true, "false": true, "nil": true, "len": true, "append": true, "copy": true,
	"make": true, "new": true, "panic": true, "recover": true, "clear": true, "min": true, "max": true,
	"iota": true, "any": true, "rune": true, "uint8": true, "uint64": true, "cap": true, "delete": true,
	"int8": true, "int16": true, "int32": true, "uint": true, "uint16": true, "uintptr": true, "float32": true,
	"complex64": true, "complex128": true, "complex": true, "real": true, "imag": true, "close": true,
	"print": true, "println": true, "comparable": true,
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

// scopeFor is the extra implementation scope of an instance of a declaration
// in module with the given number of type variables: a generic instance
// resolves contract operations against the implementations visible where it
// is used, so two modules with different local implementations get distinct
// instances.
func (g *gen) scopeFor(module string, variables int) string {
	if variables == 0 {
		return ""
	}
	var chain []string
	seen := map[string]bool{module: true}
	for _, m := range append([]string{g.module}, strings.Split(g.scope, ",")...) {
		if m != "" && !seen[m] {
			seen[m] = true
			chain = append(chain, m)
		}
	}
	return strings.Join(chain, ",")
}

// resolve lists the operations name on t visible to the code being lowered:
// those of the instantiating module first, then the declaring module's.
func (g *gen) resolve(t *checker.Type, name string) []*checker.Method {
	var out []*checker.Method
	if g.scope != "" {
		for _, m := range strings.Split(g.scope, ",") {
			out = append(out, g.program.ResolveMethods(m, t, name)...)
		}
	}
	return append(out, g.program.ResolveMethods(g.module, t, name)...)
}

// exitBeforeReturns makes every return of the function leave the call-depth
// count first. The returned value is computed before the count drops, so the
// callee's own calls still run inside it. Function literals are not entered.
func exitBeforeReturns(stmts []ast.Stmt) []ast.Stmt {
	out := make([]ast.Stmt, len(stmts))
	for i, s := range stmts {
		out[i] = exitBeforeReturn(s)
	}
	return out
}

func exitBeforeReturn(s ast.Stmt) ast.Stmt {
	switch s := s.(type) {
	case *ast.ReturnStmt:
		leave := evaluated(rtCall("Exit", ident("ctx")))
		if _, name := s.Results[0].(*ast.Ident); len(s.Results) != 1 || name || trivial(s.Results[0]) {
			return block(leave, s)
		}
		return block(define("r__", s.Results[0]), leave, returned(ident("r__")))
	case *ast.BlockStmt:
		return &ast.BlockStmt{List: exitBeforeReturns(s.List)}
	case *ast.IfStmt:
		out := *s
		out.Body = &ast.BlockStmt{List: exitBeforeReturns(s.Body.List)}
		if s.Else != nil {
			out.Else = exitBeforeReturn(s.Else)
		}
		return &out
	case *ast.ForStmt:
		out := *s
		out.Body = &ast.BlockStmt{List: exitBeforeReturns(s.Body.List)}
		return &out
	case *ast.RangeStmt:
		out := *s
		out.Body = &ast.BlockStmt{List: exitBeforeReturns(s.Body.List)}
		return &out
	case *ast.LabeledStmt:
		out := *s
		out.Stmt = exitBeforeReturn(s.Stmt)
		return &out
	case *ast.SwitchStmt:
		out := *s
		out.Body = exitBeforeClauses(s.Body)
		return &out
	case *ast.TypeSwitchStmt:
		out := *s
		out.Body = exitBeforeClauses(s.Body)
		return &out
	}
	return s
}

func exitBeforeClauses(body *ast.BlockStmt) *ast.BlockStmt {
	out := &ast.BlockStmt{}
	for _, c := range body.List {
		clause := *c.(*ast.CaseClause)
		clause.Body = exitBeforeReturns(clause.Body)
		out.List = append(out.List, &clause)
	}
	return out
}
