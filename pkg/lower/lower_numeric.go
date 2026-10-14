package lower

import (
	"go/ast"
	"go/token"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Keep statically known scalar operands typed through an expression. Scalar
// locals and parameters of the function being lowered are typed Go variables;
// captures, generic values, and call boundaries retain the shared Value ABI.
// Nonprimitive equality retains the checker's selected implementation scope.
func (g *generator) numericBinary(e *syntax.Expression) ast.Expr {
	left := g.program.Info(e.Left).Type
	right := g.program.Info(e.Right).Type
	if left.ID != right.ID || left.ID != "Int" && left.ID != "Float" {
		return nil
	}
	goType := primitiveEqualityType(left)
	if g.orderedFirst(e) {
		return g.orderedNumeric(e, goType)
	}
	a := paren(g.numericOperand(e.Left, goType))
	b := paren(g.numericOperand(e.Right, goType))
	return g.numericOperation(e, a, b)
}

// orderedFirst reports whether the right operand holds a match whose arms can
// assign a local the left operand reads. Go does not order a variable read
// before a later operand's evaluation, so the left value is captured first.
func (g *generator) orderedFirst(e *syntax.Expression) bool {
	if g.constant(e.Left) {
		return false
	}
	found := false
	syntax.Visitor{Expression: func(x *syntax.Expression) {
		if x.Kind == syntax.KindMatch {
			found = true
		}
	}}.Callable(nil, []*syntax.Statement{{Kind: syntax.KindCall, Value: e.Right}})
	return found
}

// orderedNumeric evaluates the left operand into a temporary before the right.
func (g *generator) orderedNumeric(e *syntax.Expression, goType string) ast.Expr {
	a, b := g.temp(), g.temp()
	result := g.numericResult(e)
	return call(closure(nil, ident(result),
		define(a, g.numericOperand(e.Left, goType)),
		define(b, g.numericOperand(e.Right, goType)),
		returned(g.numericOperation(e, ident(a), ident(b))),
	))
}

func (g *generator) numericOperation(e *syntax.Expression, a, b ast.Expr) ast.Expr {
	left := g.program.Info(e.Left).Type
	switch e.Text {
	case "<", "<=", ">", ">=":
		op := map[string]token.Token{"<": token.LSS, "<=": token.LEQ, ">": token.GTR, ">=": token.GEQ}[e.Text]
		return &ast.BinaryExpr{X: a, Op: op, Y: b}
	case "+", "-", "*", "/", "%":
		if left.ID == "Int" {
			// The operation's site travels with it and is recorded only on a fault.
			operation := map[string]string{"+": "IntAddAt", "-": "IntSubtractAt", "*": "IntMultiplyAt", "/": "IntDivideAt", "%": "IntRemainderAt"}[e.Text]
			return runtimeCall(operation, a, b, address(ident("sourcePosition")), textLiteral(e.Pos.String()))
		}
		if e.Text != "%" {
			// Explicit rounding preserves each source operation even on FMA targets.
			op := map[string]token.Token{"+": token.ADD, "-": token.SUB, "*": token.MUL, "/": token.QUO}[e.Text]
			return call(ident("float64"), &ast.BinaryExpr{X: a, Op: op, Y: b})
		}
	}
	return nil
}

// numericResult is the Go type numericBinary yields for e, or "".
func (g *generator) numericResult(e *syntax.Expression) string {
	left := g.program.Info(e.Left).Type
	right := g.program.Info(e.Right).Type
	if left.ID != right.ID || left.ID != "Int" && left.ID != "Float" {
		return ""
	}
	switch e.Text {
	case "<", "<=", ">", ">=":
		return "bool"
	case "+", "-", "*", "/", "%":
		if left.ID == "Int" {
			return "int64"
		}
		if e.Text != "%" {
			return "float64"
		}
	}
	return ""
}

// numericOperand lowers one operand. A constant Float expression is hidden from
// the Go compiler so division by zero and overflow follow Manuscript's runtime
// rules instead of becoming compile-time errors.
func (g *generator) numericOperand(e *syntax.Expression, goType string) ast.Expr {
	if goType == "float64" && g.constant(e) {
		return runtimeCall("FloatValue", g.expression(e))
	}
	return g.scalar(e, goType)
}

// constant reports whether g.expression(e) is a Go constant expression.
func (g *generator) constant(e *syntax.Expression) bool {
	if g.constantBool(e) {
		return true
	}
	switch e.Kind {
	case syntax.KindNumber, syntax.KindBool:
		return g.nativeType(e) != ""
	case syntax.KindBinary:
		return g.nativeType(e) != "" && g.constant(e.Left) && g.constant(e.Right)
	}
	return false
}
