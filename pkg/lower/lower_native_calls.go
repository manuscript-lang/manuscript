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
			s := g.program.Symbols[m.File][d.Name]
			g.nativeCalls[s] = s.Native == "" && len(s.Variables) == 0 && !hasTypeVariable(s.Type)
		}
	}
}
func (g *generator) nativeCallAvailable(e *syntax.Expression) bool {
	info := g.program.Expressions[e]
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
	parameters := map[*checker.Binding]bool{}
	for i, b := range g.program.Parameters[s.Decl] {
		parameters[b] = true
		if s.Decl.Params[i].Default != nil || s.Type.Defaults[s.Type.Params[i].Name] {
			return false
		}
	}
	allowed := map[*syntax.Expression]bool{}
	var uses []*syntax.Expression
	valid := true
	syntax.Visitor{Statement: func(stmt *syntax.Statement) {
		if primitiveEqualityType(s.Type.Result) != "" && stmt.Kind == syntax.KindReturn && !g.freshScalar(stmt.Value) {
			valid = false
		}
	}, Expression: func(e *syntax.Expression) {
		info := g.program.Expressions[e]
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
	}}.Callable(s.Decl.Params, s.Decl.Body)
	for _, e := range uses {
		if primitiveEqualityType(g.program.Expressions[e].Type) != "" && !allowed[e] {
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
		return g.scalarLocals[g.program.Expressions[e].Binding] != ""
	}
	return false
}

func (g *generator) nativeFunction(s *checker.Symbol) ([]ast.Decl, ast.Expr) {
	oldParameters, oldResult, oldWant := g.nativeParameters, g.nativeResult, g.wantScalar
	g.nativeParameters = map[*checker.Binding]bool{}
	g.nativeResult = s.Type.Result
	g.wantScalar = 0
	parameters := []*ast.Field{field("ctx", &ast.StarExpr{X: runtimeName("Execution")})}
	values := []ast.Expr{ident("ctx")}
	bindings := g.program.Parameters[s.Decl]
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
	labels, key, position, body := g.functionParts(s.Decl.Name, s.Decl.Params, s.Decl.Result, s.Decl.Body, bindings, nil, s.Type)
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
	if g.shareNativeBody(s) {
		boxed := []ast.Expr{ident("ctx")}
		for i, p := range s.Type.Params {
			boxed = append(boxed, scalarExtract(p.Type, index(ident("args"), intLiteral(i))))
		}
		adapter = runtimeCall("NewSourceFunction", stringSlice(labels), key, textLiteral(position), closure([]*ast.Field{field("ctx", &ast.StarExpr{X: runtimeName("Execution")}), field("args", sliceOf(runtimeName("Value")))}, runtimeName("Value"), returned(call(ident(raw), boxed...))))
	} else {
		adapter = g.declaredFunction(s)
	}
	return decls, adapter
}

func (g *generator) nativeSourceCall(e *syntax.Expression, args []syntax.Argument) ast.Expr {
	if !g.nativeCallAvailable(e) {
		return nil
	}
	s := g.program.Expressions[e].Symbol
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
					value = g.scalarValue(a.Value)
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
			value = g.scalarValue(a.Value)
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
