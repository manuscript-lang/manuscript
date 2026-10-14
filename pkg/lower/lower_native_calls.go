package lower

import (
	"go/ast"
	"go/token"
	"strconv"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/ir"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Native entries are an internal representation of checked source functions.
// Every declaration retains its ordinary first-class callable. Defaults with
// omissions and generics use that callable; fully supplied calls may reorder
// their captured arguments without changing written evaluation order.

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
		if g.ir.Callables[s.Decl].Parameters[i].Omittable {
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
		if kind := g.ir.Callables[s.Decl].Comparator; kind != "" {
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

func (g *generator) nativeSourceCall(e *syntax.Expression, _ []syntax.Argument) ast.Expr {
	x := g.ir.Expression(e).Call
	if x.Symbol == nil || !x.Native {
		return nil
	}
	s := x.Symbol
	if g.wantScalar == 0 && !g.shareNativeBody(s) {
		return nil
	}
	values := []ast.Expr{ident("ctx")}
	bySlot := make([]ast.Expr, len(x.Parameters))
	var captures []ast.Stmt
	for _, a := range x.Arguments {
		value := g.callArgument(a)
		value = sourceAt(a.Pos, value)
		if !x.Ordered {
			name := g.temp()
			captures = append(captures, define(name, value))
			value = ident(name)
		}
		bySlot[a.Slot] = value
	}
	for slot, p := range x.Parameters {
		value := bySlot[slot]
		if value == nil {
			value = nativeZero(p.Type)
		}
		values = append(values, value)
	}
	for _, p := range x.Parameters {
		if p.Omittable {
			values = append(values, ident(strconv.FormatBool(p.Supplied)))
		}
	}
	if x.Ordered {
		return g.locatedOperation(e, ident(s.ID+"Native"), values...)
	}
	captures = append(captures, assign(ident("sourcePosition"), token.ASSIGN, textLiteral(e.Pos.String())), returned(call(ident(s.ID+"Native"), values...)))
	return call(closure(nil, nativeResultType(s.Type.Result), captures...))
}

func (g *generator) callArgument(a ir.Argument) ast.Expr {
	if ir.Primitive(a.Value.Expected) != "" {
		return g.scalarEdge(a.Value)
	}
	return g.edgeValue(a.Value)
}

func nativeResultType(t *checker.Type) ast.Expr {
	if primitive := primitiveEqualityType(t); primitive != "" {
		return ident(primitive)
	}
	return runtimeName("Value")
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
