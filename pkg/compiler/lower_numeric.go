package compiler

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
	left := g.program.Expressions[e.Left].Type
	right := g.program.Expressions[e.Right].Type
	if left.ID != right.ID || left.ID != "Int" && left.ID != "Float" {
		return nil
	}
	goType := primitiveEqualityType(left)
	a := paren(g.numericOperand(e.Left, goType))
	b := paren(g.numericOperand(e.Right, goType))
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
	left := g.program.Expressions[e.Left].Type
	right := g.program.Expressions[e.Right].Type
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
	if _, ok := g.booleans[e]; ok {
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
