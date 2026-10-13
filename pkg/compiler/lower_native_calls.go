package compiler

import (
	"go/ast"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// The held pilot reuses the existing checked scalar representation mapping.
// #271 owns its numeric widths; explicit wide/composite types stay boxed here.
func (g *generator) selectNativeCalls() {
	g.nativeCalls = map[*checker.Symbol]bool{}
	for _, module := range g.program.Modules {
		for _, d := range module.Declarations {
			if d.Kind != syntax.KindFn {
				continue
			}
			s := g.program.Symbols[module.File][d.Name]
			if s.Native != "" || len(s.Variables) != 0 || hasTypeVariable(s.Type) || primitiveEqualityType(s.Type.Result) == "" {
				continue
			}
			eligible := true
			for i, p := range s.Type.Params {
				if primitiveEqualityType(p.Type) == "" || d.Params[i].Default != nil || s.Type.Defaults[p.Name] {
					eligible = false
					break
				}
			}
			g.nativeCalls[s] = eligible
		}
	}
	// ABI-only identity/forwarding returns must keep their existing Value. A
	// typed adapter would otherwise unbox then allocate a replacement box. Prune
	// forwarding chains to a fixed point, retaining scalar producers and cycles
	// with their ordinary every-call guard.
	changed := true
	for changed {
		changed = false
		for s, eligible := range g.nativeCalls {
			if !eligible {
				continue
			}
			valid := true
			syntax.Visitor{Statement: func(stmt *syntax.Statement) {
				if stmt.Kind == syntax.KindReturn && !g.nativeReturnProducer(stmt.Value) {
					valid = false
				}
			}}.Callable(s.Decl.Params, s.Decl.Body)
			if !valid {
				g.nativeCalls[s] = false
				changed = true
			}
		}
	}
}

func (g *generator) nativeReturnProducer(e *syntax.Expression) bool {
	if e == nil {
		return false
	}
	switch e.Kind {
	case syntax.KindNumber, syntax.KindBool, syntax.KindText:
		return primitiveEqualityType(g.program.Expressions[e].Type) != ""
	case syntax.KindBinary:
		if e.Text == "and" || e.Text == "or" || e.Text == "==" || e.Text == "!=" {
			return true
		}
		t := g.program.Expressions[e.Left].Type
		return (t.ID == "Int" || t.ID == "Float") && !(t.ID == "Float" && e.Text == "%")
	case syntax.KindCall:
		args := e.Args
		if converted := g.program.Expressions[e].Arguments; converted != nil {
			args = converted
		}
		return g.nativeCallArguments(e, args)
	}
	return false
}

func (g *generator) nativeExtract(t *checker.Type, value ast.Expr) ast.Expr {
	return &ast.TypeAssertExpr{X: runtimeCall("Value", value), Type: ident(primitiveEqualityType(t))}
}

// One typed body has no call guard. Both adapters select the shared guard once.
// Keeping the first-class adapter preserves labels and the ordinary Value ABI.
func (g *generator) nativeFunction(s *checker.Symbol) ([]ast.Decl, ast.Expr) {
	oldParameters, oldResult := g.nativeParameters, g.nativeResult
	g.nativeParameters = map[*checker.Binding]bool{}
	g.nativeResult = s.Type.Result
	defer func() { g.nativeParameters, g.nativeResult = oldParameters, oldResult }()

	parameters := []*ast.Field{field("ctx", &ast.StarExpr{X: runtimeName("Execution")})}
	values := []ast.Expr{ident("ctx")}
	bindings := g.program.Parameters[s.Decl]
	for _, b := range bindings {
		g.nativeParameters[b] = true
		parameters = append(parameters, field(b.ID, ident(primitiveEqualityType(b.Type))))
		values = append(values, ident(b.ID))
	}
	labels, key, position, body := g.functionParts(s.Decl.Name, s.Decl.Params, s.Decl.Result, s.Decl.Body, bindings, nil, s.Type)
	result := ident(primitiveEqualityType(s.Type.Result))
	raw, native := s.ID+"Body", s.ID+"Native"
	run := func() ast.Expr {
		return closure([]*ast.Field{field("ctx", &ast.StarExpr{X: runtimeName("Execution")})}, result, returned(call(ident(raw), values...)))
	}
	guard := call(index(runtimeName("SourceCall"), result), ident("ctx"), key, run())
	profiled := call(index(runtimeName("ProfileSourceCall"), result), ident("ctx"), key, textLiteral(position), run())
	decls := []ast.Decl{
		&ast.FuncDecl{Name: ident(raw), Type: functionType(parameters, result), Body: block(body...)},
		&ast.FuncDecl{Name: ident(native), Type: functionType(parameters, result), Body: block(
			&ast.IfStmt{Cond: runtimeCall("SourceCallNeedsProfile", ident("ctx")), Body: block(returned(profiled))},
			returned(guard))},
	}
	boxed := []ast.Expr{ident("ctx")}
	for i, p := range s.Type.Params {
		boxed = append(boxed, g.nativeExtract(p.Type, index(ident("args"), intLiteral(i))))
	}
	adapter := runtimeCall("NewSourceFunction", stringSlice(labels), key, textLiteral(position),
		closure([]*ast.Field{field("ctx", &ast.StarExpr{X: runtimeName("Execution")}), field("args", sliceOf(runtimeName("Value")))}, runtimeName("Value"), returned(call(ident(raw), boxed...))))
	return decls, adapter
}

func (g *generator) nativeSourceCall(e *syntax.Expression, args []syntax.Argument) ast.Expr {
	s := g.program.Expressions[e].Symbol
	if !g.nativeCallArguments(e, args) {
		return nil
	}
	var captures []ast.Stmt
	values := []ast.Expr{ident("ctx")}
	for i, a := range args {
		name := g.temp()
		// Conversion and capture stay in written order, including match returns
		// and later arguments that mutate earlier bindings. No raw local loads
		// remain in the final argument list.
		captures = append(captures, define(name, sourceAt(a.Pos, g.nativeExtract(s.Type.Params[i].Type, g.argumentValue(a)))))
		values = append(values, ident(name))
	}
	captures = append(captures, returned(g.locatedOperation(e, ident(s.ID+"Native"), values...)))
	return call(closure(nil, ident(primitiveEqualityType(s.Type.Result)), captures...))
}

func (g *generator) nativeCallArguments(e *syntax.Expression, args []syntax.Argument) bool {
	s := g.program.Expressions[e].Symbol
	if !g.nativeCalls[s] || len(args) != len(s.Type.Params) {
		return false
	}
	for i, a := range args {
		if a.Name != s.Type.Params[i].Name {
			return false
		}
	}
	return true
}
