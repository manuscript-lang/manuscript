package lower

import (
	"go/ast"
	"go/token"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/ir"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// The checked primitive map is shared with equality. No display name decides a
// representation. Captures and existing boxed payload copies keep their ABI.

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
	return scalarExtract(g.ir.Expression(e).Type, value)
}

func (g *generator) scalarValueAs(e *syntax.Expression, expected *checker.Type) ast.Expr {
	return g.scalarEdge(g.ir.Use(e, expected))
}
func (g *generator) scalarEdge(edge ir.Edge) ast.Expr {
	if edge.Never {
		return scalarExtract(edge.Expected, g.expression(edge.Source))
	}
	return g.scalarValue(edge.Source)
}
func (g *generator) condition(e *syntax.Expression) ast.Expr { return g.scalarEdge(g.ir.BoolUse(e)) }

func (g *generator) nativeScalarExpression(e *syntax.Expression) bool {
	x := g.ir.Expression(e)
	if g.constantBool(e) {
		return true
	}
	switch x.NativeForm {
	case "constant", "operation", "call", "field":
		return true
	case "binding":
		return g.typedBinding(x.Binding)
	case "match":
		return g.wantScalar > 0
	}
	return false
}

func (g *generator) bindingValue(b *checker.Binding, e *syntax.Expression) ast.Expr {
	if g.typedBinding(b) {
		return g.scalarValueAs(e, b.Type)
	}
	return g.expression(e)
}
func (g *generator) returnValue(e *syntax.Expression) ast.Expr {
	if g.nativeResult != nil && g.expressionDepth == 0 {
		if g.ir.Expression(e).Type.ID == "Never" {
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
	if !g.ir.Expression(e).Operation.RightEffects {
		// A pure right operand cannot mutate an earlier local read. Keep this
		// common path as one Go expression, with the fault site set before the
		// checked operation, and without an anonymous debugger frame.
		return build(g.scalarEdge(g.ir.Expression(e).Operation.Left), sourceAt(e.Pos, g.scalarEdge(g.ir.Expression(e).Operation.Right)))
	}
	a, b := g.temp(), g.temp()
	result := primitiveEqualityType(g.ir.Expression(e).Type)
	return call(closure(nil, ident(result),
		define(a, g.scalarEdge(g.ir.Expression(e).Operation.Left)), define(b, g.scalarEdge(g.ir.Expression(e).Operation.Right)),
		assign(ident("sourcePosition"), token.ASSIGN, textLiteral(e.Pos.String())),
		returned(build(ident(a), ident(b))),
	))
}

func (g *generator) scalarUnary(e *syntax.Expression) ast.Expr {
	operation := g.ir.Expression(e).Operation
	if operation == nil {
		return nil
	}
	typ := operation.Primitive
	if typ == "" {
		return nil
	}
	switch operation.Identity {
	case "+":
		if g.wantScalar == 0 {
			return nil
		}
		return g.scalarEdge(g.ir.Expression(e).Operation.Right)
	case "not":
		return &ast.UnaryExpr{Op: token.NOT, X: g.scalarEdge(g.ir.Expression(e).Operation.Right)}
	case "-":
		if typ == "int64" {
			return g.locatedOperation(e, runtimeName("IntSubtract"), call(ident("int64"), intLiteral(0)), g.scalarEdge(g.ir.Expression(e).Operation.Right))
		}
		if typ == "float64" {
			// Go constant folding of -float64(0) loses the sign of zero.
			// A typed variable operation retains the source IEEE result.
			return runtimeCall("FloatNegate", g.scalarEdge(g.ir.Expression(e).Operation.Right))
		}
	}
	return nil
}
