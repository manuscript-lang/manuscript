package lower

import (
	"fmt"
	"go/ast"
	"go/token"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func recordDefaults(d *syntax.Declaration) bool {
	if d == nil || d.Kind != syntax.KindRecord {
		return false
	}
	for _, f := range d.Fields {
		if f.Default != nil {
			return true
		}
	}
	return false
}

// Native Optional.none adapters already implement omission. Other defaults use
// the same checked per-call prologue as source functions, then tail-dispatch to
// the existing native body with full concrete argument slots.
func (g *generator) nativeDefaults(d *syntax.Declaration, t *checker.Type, callee ast.Expr, supplied ...[]syntax.Argument) ast.Expr {
	value := g.nativeDefaultParameters(d, t, nil, callee, supplied...)
	if value == callee || hasTypeVariable(t) {
		return value
	}
	// Cache the stateless callable, never its default values. Native free
	// functions have no receiver/captured locals; preparation stays per-call.
	return g.lazyValue("native defaults/"+d.Pos.String()+"/"+checker.TypeKey(t), value)
}

func (g *generator) nativeDefaultParameters(d *syntax.Declaration, t *checker.Type, overridden map[string]bool, callee ast.Expr, supplied ...[]syntax.Argument) ast.Expr {
	if d == nil || g.program.ParameterBindings(d) == nil {
		return callee
	}
	oldModule := g.module
	g.module = d.Pos.File
	defer func() { g.module = oldModule }()
	var values []ast.Expr
	for _, binding := range g.program.ParameterBindings(d) {
		values = append(values, ident(binding.ID))
	}
	params := append([]syntax.Parameter{}, d.Params...)
	present := map[string]bool{}
	if len(supplied) > 0 {
		for _, arg := range supplied[0] {
			present[arg.Name] = true
		}
	}
	var slots []ast.Expr
	needed := false
	for i := range params {
		if overridden[params[i].Name] {
			params[i].Default = nil
		}
		if e := params[i].Default; e != nil && (e.Kind != syntax.KindName || e.Text != "none") {
			slots = append(slots, intLiteral(i))
			needed = needed || !present[params[i].Name]
		}
	}
	if !needed {
		return callee
	}
	if !g.enterNativeDefault(d) {
		return callee
	}
	defer delete(g.defaultExpansion, d)
	preparedType := *t
	preparedType.Defaults = nil // Only the selected expression defaults run here.
	prepare := g.function(d.Name+" defaults", params, d.Result, nil, g.program.ParameterBindings(d), nil, &preparedType,
		returned(composite(runtimeName("PreparedDefaults"), values...)))
	return runtimeCall("WithDefaults", callee, concreteFunction(prepare), sliceLiteral(ident("int"), slots...))
}

func (g *generator) methodDefaults(m *checker.Method, callee ast.Expr, supplied ...[]syntax.Argument) ast.Expr {
	if m.Native != "" {
		return g.nativeDefaultParameters(m.Decl, m.Type, nil, callee, supplied...)
	}
	// Source implementations inherit omission permission from a standard
	// interface. Prepare its new defaults before entering the source method;
	// explicit method defaults keep their existing precedence.
	if m.Contract != nil && m.Contract.Def != nil && m.Contract.Def.Symbol != nil {
		for _, d := range m.Contract.Def.Symbol.Decl.Methods {
			if d.Name != m.Decl.Name || g.program.ParameterBindings(d) == nil {
				continue
			}
			overridden := map[string]bool{}
			for _, p := range m.Decl.Params {
				overridden[p.Name] = p.Default != nil
			}
			return g.nativeDefaultParameters(d, m.Type, overridden, callee, supplied...)
		}
	}
	return callee
}

// A direct member call carries checked omission facts. Avoid materializing a
// default wrapper when every new default is supplied; old none adapters still
// receive exactly the slots they handled before this feature.
func (g *generator) methodCallable(e *syntax.Expression, arguments []syntax.Argument) ast.Expr {
	info := g.program.Info(e)
	if e.Kind != syntax.KindMember || info.Method == nil {
		return g.expression(e)
	}
	m := info.Method
	if m.Contract == nil && m.Native != "" && m.Native != "contract" {
		return g.methodDefaults(m, g.nativeReceiverMember(e, info), arguments)
	}
	return g.methodDefaults(m, runtimeCall("Bind", g.expression(e.Left), g.key(m.Contract), textLiteral(e.Text), g.typeScope(g.program.Info(e.Left).Type)), arguments)
}
func (g *generator) declaredFunction(s *checker.Symbol) ast.Expr {
	d := s.Decl
	if s.Native != "" {
		if !g.enterNativeDefault(d) {
			return ident("nil")
		}
		defer delete(g.defaultExpansion, d)
		oldModule := g.module
		g.module = s.Module
		defer func() { g.module = oldModule }()
	}
	if d.Kind == syntax.KindFn {
		return g.function(d.Name, d.Params, d.Result, d.Body, g.program.ParameterBindings(d), nil, s.Type)
	}
	var args []ast.Expr
	for i, field := range d.Fields {
		args = append(args, composite(runtimeName("Argument"), keyed("Name", textLiteral(field.Name)), keyed("Value", ident(g.program.ParameterBindings(d)[i].ID))))
	}
	t := checker.ConstructorSignature(s.Type)
	if st := g.structFor(s.Type); st != nil {
		var elements []ast.Expr
		for i, f := range st.fields {
			var value ast.Expr = ident(g.program.ParameterBindings(d)[i].ID)
			if f.scalar != "" {
				value = unbox(value, f.scalar)
			}
			elements = append(elements, keyed(fieldName(f.name), value))
		}
		return g.function(d.Name, d.Fields, &syntax.Type{Pos: d.Pos}, nil, g.program.ParameterBindings(d), nil, t,
			returned(call(runtimeName("Value"), address(composite(ident(st.name), elements...)))))
	}
	return g.function(d.Name, d.Fields, &syntax.Type{Pos: d.Pos}, nil, g.program.ParameterBindings(d), nil, t,
		returned(runtimeCall("ConstructWithContext", ident("ctx"), g.key(s.Type), sliceLiteral(runtimeName("Argument"), args...))))
}

func (g *generator) enterNativeDefault(d *syntax.Declaration) bool {
	if g.defaultExpansion[d] {
		if g.loweringError == nil {
			g.loweringError = fmt.Errorf("recursive native default expansion at %s; move the recursive default into a source wrapper", d.Pos)
		}
		return false
	}
	if g.defaultExpansion == nil {
		g.defaultExpansion = map[*syntax.Declaration]bool{}
	}
	g.defaultExpansion[d] = true
	return true
}
func (g *generator) function(name string, params []syntax.Parameter, result *syntax.Type, body []*syntax.Statement, bindings []*checker.Binding, self *checker.Binding, t *checker.Type, tail ...ast.Stmt) ast.Expr {
	labels, key, position, out, _ := g.functionPieces(nil, name, params, result, body, bindings, self, t, tail...)
	return runtimeCall("NewSourceFunction", stringSlice(labels), key, textLiteral(position), closure([]*ast.Field{field("ctx", &ast.StarExpr{X: runtimeName("Execution")}), field("args", sliceOf(runtimeName("Value")))}, runtimeName("Value"), out...))
}

// functionParts lowers a callable's labels, result key, source position, and
// body statements. A method body reads its receiver from the identifier
// "receiver", which the enclosing closure supplies.
func (g *generator) functionParts(name string, params []syntax.Parameter, result *syntax.Type, body []*syntax.Statement, bindings []*checker.Binding, self *checker.Binding, t *checker.Type, tail ...ast.Stmt) ([]string, ast.Expr, string, []ast.Stmt) {
	labels, key, position, out, _ := g.functionPieces(nil, name, params, result, body, bindings, self, t, tail...)
	return labels, key, position, out
}

// directFunctionLiteral lowers a direct function to its Go function literal.
func (g *generator) directFunctionLiteral(direct *directFunction, name string, params []syntax.Parameter, result *syntax.Type, body []*syntax.Statement, bindings []*checker.Binding, t *checker.Type) ast.Expr {
	_, _, _, _, literal := g.functionPieces(direct, name, params, result, body, bindings, nil, t)
	return literal
}

// functionPieces lowers a source callable. With direct set it also yields the
// Go function literal of a direct function instead of the dynamic wrapper's
// statements.
func (g *generator) functionPieces(direct *directFunction, name string, params []syntax.Parameter, result *syntax.Type, body []*syntax.Statement, bindings []*checker.Binding, self *checker.Binding, t *checker.Type, tail ...ast.Stmt) ([]string, ast.Expr, string, []ast.Stmt, ast.Expr) {
	oldCleanups, oldLoops, oldLabels, oldDepth, oldResult := g.cleanups, g.loopCleanup, g.loopLabels, g.expressionDepth, g.resultKey
	oldNeedsCleanup, oldResultType, oldRecovers := g.needsCleanup, g.resultType, g.recovers
	oldShape, oldTypeKey := g.resultShape, g.resultTypeKey
	resultKey := g.key(t.Result)
	g.resultKey = resultKey
	g.resultType, g.recovers = "", false
	g.resultShape, g.resultTypeKey = nil, checker.TypeKey(t.Result)
	if direct != nil {
		g.resultType, g.resultShape = direct.result, direct.shape
	}
	g.expressionDepth = 0
	g.cleanups = nil
	g.needsCleanup = false
	g.loopCleanup = nil
	g.loopLabels = nil
	defer func() {
		g.cleanups = oldCleanups
		g.needsCleanup = oldNeedsCleanup
		g.loopCleanup = oldLoops
		g.loopLabels = oldLabels
		g.expressionDepth = oldDepth
		g.resultKey = oldResult
		g.resultType, g.recovers = oldResultType, oldRecovers
		g.resultShape, g.resultTypeKey = oldShape, oldTypeKey
	}()
	var labels []string
	for _, p := range t.Params {
		labels = append(labels, p.Name)
	}
	prologue := []ast.Stmt{
		define("sourcePosition", textLiteral(result.Pos.String())),
		&ast.DeferStmt{Call: runtimeCall("TraceSource", ident("ctx"), address(ident("sourcePosition")), textLiteral(name))},
	}
	var out []ast.Stmt
	if self != nil {
		out = append(out, define(self.ID, ident("receiver")), discard(ident(self.ID)))
	}
	for i, b := range bindings {
		if direct != nil {
			// The Go parameter is the binding; callers supply typed values.
			if typ := direct.params[i]; typ != "" {
				g.typed[b] = typ
			}
			out = append(out, discard(ident(b.ID)))
			continue
		}
		if typ := scalarBinding(b); typ != "" && params[i].Default == nil && !t.Defaults[t.Params[i].Name] {
			// A required scalar argument is never nil; copy it into a typed variable.
			g.typed[b] = typ
			out = append(out, &ast.DeclStmt{Decl: variable(b.ID, ident(typ), unbox(index(ident("args"), intLiteral(i)), typ))}, discard(ident(b.ID)))
			continue
		}
		out = append(out, define(b.ID, index(ident("args"), intLiteral(i))), discard(ident(b.ID)))
		// Checked source values are concrete (including Unit and Optional.none);
		// Invoke leaves nil only for an omitted argument.
		if params[i].Default == nil && t.Defaults[t.Params[i].Name] && b.Type.ID == "@std/Optional" {
			out = append(out, &ast.IfStmt{Cond: &ast.BinaryExpr{X: ident(b.ID), Op: token.EQL, Y: ident("nil")}, Body: block(assign(ident(b.ID), token.ASSIGN, runtimeCall("NewAlternative", g.key(b.Type), textLiteral("none"), ident("nil"), ident("nil"))))})
		}
		if params[i].Default != nil {
			stmt := &ast.IfStmt{Cond: &ast.BinaryExpr{X: ident(b.ID), Op: token.EQL, Y: ident("nil")}, Body: block(assign(ident(b.ID), token.ASSIGN, g.expression(params[i].Default)))}
			out = append(out, g.locatedStatement(params[i].Default.Pos, stmt))
		}
	}
	out = append(out, g.body(body)...)
	out = append(out, tail...)
	if direct != nil {
		return nil, nil, "", nil, g.directLiteral(direct, name, result, bindings, t, out)
	}
	// Defaults and generated match closures belong to this callable; nested
	// source functions save their own flag. Lexical cleanup lists are empty again
	// after lowering each scope, so their final length cannot prove absence.
	if g.needsCleanup {
		prologue = append(prologue, define("cleanupStack", runtimeCall("NewCleanupStack")), &ast.DeferStmt{Call: call(selector(ident("cleanupStack"), "Unwind"))})
	}
	out = append(prologue, out...)
	out = append(out, g.locatedStatement(syntax.Position{File: "manuscript.generated.go", Line: 1}, returned(unit())))
	return labels, resultKey, result.Pos.String(), out, nil
}
