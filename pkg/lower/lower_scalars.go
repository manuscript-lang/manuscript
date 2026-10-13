package lower

import (
	"go/ast"
	"go/token"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// The checked primitive map is shared with equality. No display name decides a
// representation. Captures and existing boxed payload copies keep their ABI.
func (g *generator) selectScalarLocals() map[*checker.Binding]string {
	captured := map[*checker.Binding]bool{}
	for _, info := range g.program.Expressions {
		for _, b := range info.Captures {
			captured[b] = true
		}
	}
	locals := map[*checker.Binding]string{}
	allowed := map[*syntax.Expression]bool{}
	uses := map[*checker.Binding][]*syntax.Expression{}
	for e, info := range g.program.Expressions {
		if info.Binding != nil {
			uses[info.Binding] = append(uses[info.Binding], e)
		}
		if e.Kind == syntax.KindBinary && g.nativeBinaryOperands(e) {
			allowed[e.Left], allowed[e.Right] = true, true
		}
		if e.Kind == syntax.KindUnary && (e.Text == "-" || e.Text == "not") {
			allowed[e.Right] = true
		}
	}
	visitor := syntax.Visitor{Statement: func(s *syntax.Statement) {
		if s.Kind == syntax.KindIf || s.Kind == syntax.KindWhile || s.Kind == syntax.KindReturn {
			allowed[s.Value] = true
		}
		if s.Kind != syntax.KindBind || s.Pattern.Kind != syntax.KindName || !g.scalarProducer(s.Value) {
			return
		}
		b := g.program.Bindings[s.Pattern]
		if b == nil || b.Mutable || captured[b] {
			return
		}
		valid := true
		for _, use := range uses[b] {
			valid = valid && allowed[use]
		}
		if typ := primitiveEqualityType(b.Type); valid && typ != "" {
			locals[b] = typ
		}
	}}
	// Build permitted statement uses before selecting immutable producers.
	for _, module := range g.program.Modules {
		for _, d := range module.Declarations {
			syntax.Visitor{Statement: func(s *syntax.Statement) {
				if s.Kind == syntax.KindIf || s.Kind == syntax.KindWhile || s.Kind == syntax.KindReturn {
					allowed[s.Value] = true
				}
			}}.Walk(d)
		}
	}
	for _, module := range g.program.Modules {
		for _, d := range module.Declarations {
			visitor.Walk(d)
		}
	}
	for e, b := range g.program.Assignments {
		if b.Mutable && !captured[b] && g.scalarProducer(e) {
			if typ := primitiveEqualityType(b.Type); typ != "" {
				locals[b] = typ
			}
		}
	}
	// A boxed source result/payload can reuse its box at the next boxed call.
	// Only known native producers remove both sides of that boundary.
	for e, b := range g.program.Assignments {
		if e.Kind == syntax.KindCall && !g.nativeCallAvailable(e) {
			delete(locals, b)
		}
		if e.Kind == syntax.KindUnary && (e.Text == "try" || e.Text == "+") {
			delete(locals, b)
		}
	}
	return locals
}

func (g *generator) scalarProducer(e *syntax.Expression) bool {
	if e == nil {
		return false
	}
	switch e.Kind {
	case syntax.KindBinary:
		return g.nativeBinaryOperands(e)
	case syntax.KindUnary:
		return e.Text == "-" || e.Text == "not"
	case syntax.KindCall:
		return g.nativeCallAvailable(e)
	}
	return false
}

func (g *generator) typedBinding(b *checker.Binding) bool {
	return b != nil && g.captures[b] == "" && (g.nativeParameters[b] || g.scalarLocals[b] != "")
}

func scalarExtract(t *checker.Type, value ast.Expr) ast.Expr {
	switch primitiveEqualityType(t) {
	case "int64":
		return runtimeCall("IntValue", value)
	case "float64":
		return runtimeCall("FloatValue", value)
	case "bool":
		return runtimeCall("Bool", value)
	case "string":
		return &ast.TypeAssertExpr{X: call(runtimeName("Value"), value), Type: ident("string")}
	}
	return value
}

// Keep native-consuming contexts typed. Unknown/generic/Optional values cross
// the shared boundary exactly once; never keep a second boxed local mirror.
func (g *generator) scalarValue(e *syntax.Expression) ast.Expr {
	g.wantScalar++
	native := g.nativeScalarExpression(e)
	value := g.expression(e)
	g.wantScalar--
	if native {
		return value
	}
	return scalarExtract(g.program.Expressions[e].Type, value)
}
func (g *generator) nativeScalarExpression(e *syntax.Expression) bool {
	info := g.program.Expressions[e]
	if info == nil || primitiveEqualityType(info.Type) == "" || info.ErrorSource != nil {
		return false
	}
	if _, ok := g.booleans[e]; ok {
		return true
	}
	switch e.Kind {
	case syntax.KindNumber, syntax.KindBool:
		return true
	case syntax.KindName, syntax.KindApply:
		return g.typedBinding(info.Binding)
	case syntax.KindBinary:
		return g.nativeBinaryOperands(e)
	case syntax.KindUnary:
		return e.Text == "not" || e.Text == "-" || e.Text == "+"
	case syntax.KindCall:
		return g.nativeCallAvailable(e)
	}
	return false
}
func (g *generator) bindingValue(b *checker.Binding, e *syntax.Expression) ast.Expr {
	if g.typedBinding(b) {
		return g.scalarValue(e)
	}
	return g.expression(e)
}
func (g *generator) returnValue(e *syntax.Expression) ast.Expr {
	if g.nativeResult != nil && g.expressionDepth == 0 {
		if g.program.Expressions[e].Type.ID == "Never" {
			return scalarExtract(g.nativeResult, g.expression(e))
		}
		return g.scalarValue(e)
	}
	return g.expression(e)
}

// Numeric extraction used to provide ordering through Go function calls. Once
// an extraction disappears, capture every operand explicitly before a later
// call/match can mutate an earlier local. Go can inline these scalar closures.
func (g *generator) orderedScalars(e *syntax.Expression, build func(ast.Expr, ast.Expr) ast.Expr) ast.Expr {
	a, b := g.temp(), g.temp()
	result := primitiveEqualityType(g.program.Expressions[e].Type)
	return call(closure(nil, ident(result),
		define(a, g.scalarValue(e.Left)), define(b, g.scalarValue(e.Right)),
		assign(ident("sourcePosition"), token.ASSIGN, textLiteral(e.Pos.String())),
		returned(build(ident(a), ident(b))),
	))
}

func (g *generator) nativeBinaryOperands(e *syntax.Expression) bool {
	a, b := g.program.Expressions[e.Left], g.program.Expressions[e.Right]
	if a == nil || b == nil || primitiveEqualityType(a.Type) == "" || a.Type.ID != b.Type.ID || primitiveEqualityType(a.Type) != primitiveEqualityType(b.Type) {
		return false
	}
	switch e.Text {
	case "==", "!=":
		return true
	case "and", "or":
		return a.Type.ID == "Bool"
	case "+", "-", "*", "/", "<", "<=", ">", ">=":
		return a.Type.ID == "Int" || a.Type.ID == "Float"
	case "%":
		return a.Type.ID == "Int"
	}
	return false
}

func (g *generator) scalarUnary(e *syntax.Expression) ast.Expr {
	typ := primitiveEqualityType(g.program.Expressions[e].Type)
	if typ == "" {
		return nil
	}
	switch e.Text {
	case "+":
		return g.scalarValue(e.Right)
	case "not":
		return &ast.UnaryExpr{Op: token.NOT, X: g.scalarValue(e.Right)}
	case "-":
		if typ == "int64" {
			return g.locatedOperation(e, runtimeName("IntSubtract"), call(ident("int64"), intLiteral(0)), g.scalarValue(e.Right))
		}
		if typ == "float64" {
			return &ast.UnaryExpr{Op: token.SUB, X: g.scalarValue(e.Right)}
		}
	}
	return nil
}
