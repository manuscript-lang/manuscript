package lower

import (
	"go/ast"
	"go/token"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Keep statically known scalar operands typed through an expression. Locals,
// captures, generic values, and call boundaries retain the shared Value ABI.
// Nonprimitive equality retains the checker's selected implementation scope.
func (g *generator) numericBinary(e *syntax.Expression) ast.Expr {
	left := g.program.Expressions[e.Left].Type
	right := g.program.Expressions[e.Right].Type
	if left.ID != right.ID || left.ID != "Int" && left.ID != "Float" {
		return nil
	}
	extract := "IntValue"
	if left.ID == "Float" {
		extract = "FloatValue"
	}
	a := runtimeCall(extract, g.expression(e.Left))
	b := runtimeCall(extract, g.expression(e.Right))
	switch e.Text {
	case "<", "<=", ">", ">=":
		op := map[string]token.Token{"<": token.LSS, "<=": token.LEQ, ">": token.GTR, ">=": token.GEQ}[e.Text]
		return &ast.BinaryExpr{X: a, Op: op, Y: b}
	case "+", "-", "*", "/", "%":
		if left.ID == "Int" {
			operation := map[string]string{"+": "IntAdd", "-": "IntSubtract", "*": "IntMultiply", "/": "IntDivide", "%": "IntRemainder"}[e.Text]
			return g.locatedOperation(e, runtimeName(operation), a, b)
		}
		if e.Text != "%" {
			// Explicit rounding preserves each source operation even on FMA targets.
			op := map[string]token.Token{"+": token.ADD, "-": token.SUB, "*": token.MUL, "/": token.QUO}[e.Text]
			return call(ident("float64"), &ast.BinaryExpr{X: a, Op: op, Y: b})
		}
	}
	return nil
}
