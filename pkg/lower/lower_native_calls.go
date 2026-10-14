package lower

import (
	"go/ast"
	"go/token"
	"strconv"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Native entries are an internal representation of checked source functions.
// Every declaration retains its ordinary first-class callable. Defaults with
// omissions and generics use that callable; fully supplied calls may reorder
// their captured arguments without changing written evaluation order.
func (g *generator) selectNativeCalls() {
	g.nativeCalls = map[*checker.Symbol]bool{}
	for _, m := range g.program.Modules {
		for _, d := range m.Declarations {
			if d.Kind != syntax.KindFn {
				continue
			}
			s := g.program.Symbol(m.File, d.Name)
			g.nativeCalls[s] = s.Native == "" && len(s.Variables) == 0 && !hasTypeVariable(s.Type)
		}
	}
}
func (g *generator) nativeCallAvailable(e *syntax.Expression) bool {
	info := g.program.Info(e)
	if info == nil || !g.nativeCalls[info.Symbol] {
		return false
	}
	args := e.Args
	if info.Arguments != nil {
		args = info.Arguments
	}
	if len(args) > len(info.Symbol.Type.Params) {
		return false
	}
	present := map[string]bool{}
	for _, a := range args {
		present[a.Name] = true
	}
	for i, p := range info.Symbol.Type.Params {
		if !present[p.Name] && !nativeDefault(info.Symbol, i) {
			return false
		}
	}
	return true
}

// The boxed adapter can share the typed body only when its inputs stay native
// and its output is newly computed. Otherwise lower a boxed adapter from the
// same checked body, preserving the original box for identity/capture/storage.
func (g *generator) shareNativeBody(s *checker.Symbol) bool {
	return g.nativeBodyCompatible(s.Decl.Params, s.Decl.Body, g.program.ParameterBindings(s.Decl), s.Type)
}
func (g *generator) nativeBodyCompatible(params []syntax.Parameter, body []*syntax.Statement, bindings []*checker.Binding, t *checker.Type) bool {
	parameters := map[*checker.Binding]bool{}
	for i, b := range bindings {
		parameters[b] = true
		if params[i].Default != nil || t.Defaults[t.Params[i].Name] {
			return false
		}
	}
	allowed := map[*syntax.Expression]bool{}
	var uses []*syntax.Expression
	valid := true
	syntax.Visitor{Statement: func(stmt *syntax.Statement) {
		if primitiveEqualityType(t.Result) != "" && stmt.Kind == syntax.KindReturn && !g.freshScalar(stmt.Value) {
			valid = false
		}
	}, Expression: func(e *syntax.Expression) {
		info := g.program.Info(e)
		if info == nil {
			return
		}
		if parameters[info.Binding] {
			uses = append(uses, e)
		}
		if e.Kind == syntax.KindLambda {
			for _, b := range info.Captures {
				if parameters[b] {
					valid = false
				}
			}
		}
		if e.Kind == syntax.KindBinary && g.nativeBinaryOperands(e) {
			allowed[e.Left], allowed[e.Right] = true, true
		}
		if e.Kind == syntax.KindUnary && (e.Text == "-" || e.Text == "not") {
			allowed[e.Right] = true
		}
	}}.Callable(params, body)
	for _, e := range uses {
		if primitiveEqualityType(g.program.Info(e).Type) != "" && !allowed[e] {
			valid = false
		}
	}
	return valid
}
func (g *generator) freshScalar(e *syntax.Expression) bool {
	if e == nil {
		return false
	}
	switch e.Kind {
	case syntax.KindNumber, syntax.KindBool:
		return true
	case syntax.KindBinary:
		return g.nativeBinaryOperands(e)
	case syntax.KindUnary:
		return e.Text == "-" || e.Text == "not"
	case syntax.KindName:
		return g.scalarLocals[g.program.Info(e).Binding] != ""
	case syntax.KindCall:
		return g.numericCallName(e) != "" || g.typedCollectionScalar(e)
	}
	return false
}

func (g *generator) nativeFunction(s *checker.Symbol) ([]ast.Decl, ast.Expr) {
	return g.nativeCallable(s, nil, s.Decl.Name)
}
func (g *generator) nativeCallable(s *checker.Symbol, self *checker.Binding, name string) ([]ast.Decl, ast.Expr) {
	oldParameters, oldResult, oldWant := g.nativeParameters, g.nativeResult, g.wantScalar
	g.nativeParameters = map[*checker.Binding]bool{}
	g.nativeResult = s.Type.Result
	g.wantScalar = 0
	parameters := []*ast.Field{field("ctx", &ast.StarExpr{X: runtimeName("Execution")})}
	values := []ast.Expr{ident("ctx")}
	if self != nil {
		parameters = append(parameters, field("receiver", runtimeName("Value")))
		values = append(values, ident("receiver"))
	}
	bindings := g.program.ParameterBindings(s.Decl)
	for _, b := range bindings {
		typ := runtimeName("Value")
		if scalar := primitiveEqualityType(b.Type); scalar != "" {
			typ = ident(scalar)
			g.nativeParameters[b] = true
		}
		parameters = append(parameters, field(b.ID, typ))
		values = append(values, ident(b.ID))
	}
	for i := range s.Type.Params {
		if nativeDefault(s, i) {
			parameters = append(parameters, field(nativePresence(i), ident("bool")))
			values = append(values, ident(nativePresence(i)))
		}
	}
	labels, key, position, body := g.functionParts(name, s.Decl.Params, s.Decl.Result, s.Decl.Body, bindings, self, s.Type)
	result := nativeResultType(s.Type.Result)
	raw, native := s.ID+"Body", s.ID+"Native"
	run := func() ast.Expr {
		return closure([]*ast.Field{field("ctx", &ast.StarExpr{X: runtimeName("Execution")})}, result, returned(call(ident(raw), values...)))
	}
	decls := []ast.Decl{
		&ast.FuncDecl{Name: ident(raw), Type: functionType(parameters, result), Body: block(body...)},
		&ast.FuncDecl{Name: ident(native), Type: functionType(parameters, result), Body: block(
			&ast.IfStmt{Cond: runtimeCall("SourceCallNeedsProfile", ident("ctx")), Body: block(returned(call(index(runtimeName("ProfileSourceCall"), result), ident("ctx"), key, textLiteral(position), run())))},
			returned(call(index(runtimeName("SourceCall"), result), ident("ctx"), key, run())),
		)},
	}
	g.nativeParameters, g.nativeResult, g.wantScalar = oldParameters, oldResult, oldWant
	var adapter ast.Expr
	if self != nil {
		var out []ast.Stmt
		if g.shareNativeBody(s) {
			boxed := []ast.Expr{ident("ctx"), ident("receiver")}
			for i, p := range s.Type.Params {
				boxed = append(boxed, scalarExtract(p.Type, index(ident("args"), intLiteral(i))))
			}
			out = []ast.Stmt{returned(call(ident(raw), boxed...))}
		} else {
			_, _, _, out = g.functionParts(name, s.Decl.Params, s.Decl.Result, s.Decl.Body, bindings, self, s.Type)
		}
		adapter = runtimeCall("SourceDirect", textLiteral(position), key, closure([]*ast.Field{field("ctx", &ast.StarExpr{X: runtimeName("Execution")}), field("receiver", runtimeName("Value")), field("args", sliceOf(runtimeName("Value")))}, runtimeName("Value"), out...))
	} else if g.shareNativeBody(s) {
		boxed := []ast.Expr{ident("ctx")}
		for i, p := range s.Type.Params {
			boxed = append(boxed, scalarExtract(p.Type, index(ident("args"), intLiteral(i))))
		}
		if kind := comparatorKind(s.Type, s.Decl.Params); kind != "" {
			adapter = runtimeCall("New"+kind+"CompareFunction", stringSlice(labels), key, textLiteral(position), ident(raw))
		} else {
			// The adapter passes scalar/Value copies to the raw body, which has
			// no access to this incoming slice, even when a Value is captured.
			adapter = runtimeCall("NewCompiledSourceFunction", stringSlice(labels), key, textLiteral(position), closure([]*ast.Field{field("ctx", &ast.StarExpr{X: runtimeName("Execution")}), field("args", sliceOf(runtimeName("Value")))}, runtimeName("Value"), returned(call(ident(raw), boxed...))))
		}
	} else {
		adapter = g.declaredFunction(s)
	}
	return decls, adapter
}

func (g *generator) nativeSourceCall(e *syntax.Expression, args []syntax.Argument) ast.Expr {
	if !g.nativeCallAvailable(e) {
		return nil
	}
	s := g.program.Info(e).Symbol
	// A boxed identity/forwarding call must keep the box it already owns.
	if g.wantScalar == 0 && !g.shareNativeBody(s) {
		return nil
	}
	ordered := true
	previous := -1
	for _, a := range args {
		for i, p := range s.Type.Params {
			if p.Name == a.Name {
				ordered = ordered && i > previous
				previous = i
			}
		}
	}
	if ordered {
		byName := map[string]syntax.Argument{}
		for _, a := range args {
			byName[a.Name] = a
		}
		values := []ast.Expr{ident("ctx")}
		for _, p := range s.Type.Params {
			value := nativeZero(p.Type)
			if a, present := byName[p.Name]; present {
				if primitiveEqualityType(p.Type) != "" {
					value = g.scalarValueAs(a.Value, p.Type)
				} else {
					value = g.argumentValue(a)
				}
				value = sourceAt(a.Pos, value)
			}
			values = append(values, value)
		}
		for i, p := range s.Type.Params {
			if nativeDefault(s, i) {
				_, present := byName[p.Name]
				values = append(values, ident(strconv.FormatBool(present)))
			}
		}
		return g.locatedOperation(e, ident(s.ID+"Native"), values...)
	}
	var captures []ast.Stmt
	byName := map[string]ast.Expr{}
	for _, a := range args {
		name := g.temp()
		var typ *checker.Type
		for _, p := range s.Type.Params {
			if p.Name == a.Name {
				typ = p.Type
			}
		}
		var value ast.Expr
		if primitiveEqualityType(typ) != "" {
			value = g.scalarValueAs(a.Value, typ)
		} else {
			value = g.argumentValue(a)
		}
		captures = append(captures, define(name, sourceAt(a.Pos, value)))
		byName[a.Name] = ident(name)
	}
	values := []ast.Expr{ident("ctx")}
	for _, p := range s.Type.Params {
		value := byName[p.Name]
		if value == nil {
			value = nativeZero(p.Type)
		}
		values = append(values, value)
	}
	for i, p := range s.Type.Params {
		if nativeDefault(s, i) {
			values = append(values, ident(strconv.FormatBool(byName[p.Name] != nil)))
		}
	}
	captures = append(captures, assign(ident("sourcePosition"), token.ASSIGN, textLiteral(e.Pos.String())), returned(call(ident(s.ID+"Native"), values...)))
	return call(closure(nil, nativeResultType(s.Type.Result), captures...))
}

func nativeResultType(t *checker.Type) ast.Expr {
	if primitive := primitiveEqualityType(t); primitive != "" {
		return ident(primitive)
	}
	return runtimeName("Value")
}

func nativeDefault(s *checker.Symbol, index int) bool {
	return s.Decl.Params[index].Default != nil || s.Type.Defaults[s.Type.Params[index].Name]
}
func nativePresence(index int) string { return "suppliedArgument" + strconv.Itoa(index) }
func nativeZero(t *checker.Type) ast.Expr {
	switch primitiveEqualityType(t) {
	case "int64", "float64":
		return call(ident(primitiveEqualityType(t)), intLiteral(0))
	case "bool":
		return ident("false")
	case "string":
		return textLiteral("")
	}
	return ident("nil")
}

func comparatorKind(t *checker.Type, params []syntax.Parameter) string {
	if t == nil || hasTypeVariable(t) || primitiveEqualityType(t.Result) != "int64" || len(t.Params) != 2 {
		return ""
	}
	for i, p := range t.Params {
		if params[i].Default != nil || t.Defaults[p.Name] {
			return ""
		}
	}
	a, b := primitiveEqualityType(t.Params[0].Type), primitiveEqualityType(t.Params[1].Type)
	if a != b {
		return ""
	}
	if a == "int64" {
		return "Int"
	}
	if a == "float64" {
		return "Float"
	}
	return ""
}
