package compiler

import "github.com/manuscript-lang/manuscript/pkg/syntax"

// Keep statically known scalar operands typed through an expression. Locals,
// captures, generic values, and call boundaries retain the shared Value ABI.
// Equality still follows the checker's selected implementation scope.
func (g *generator) numericBinary(e *syntax.Expression) string {
	left := g.program.Expressions[e.Left].Type
	right := g.program.Expressions[e.Right].Type
	if left.ID != right.ID || left.ID != "Int" && left.ID != "Float" {
		return ""
	}
	extract := "rt.IntValue"
	if left.ID == "Float" {
		extract = "rt.FloatValue"
	}
	a := extract + "(" + g.expression(e.Left) + ")"
	b := extract + "(" + g.expression(e.Right) + ")"
	switch e.Text {
	case "<", "<=", ">", ">=":
		return "(" + a + e.Text + b + ")"
	case "+", "-", "*", "/", "%":
		if left.ID == "Int" {
			operation := map[string]string{"+": "IntAdd", "-": "IntSubtract", "*": "IntMultiply", "/": "IntDivide", "%": "IntRemainder"}[e.Text]
			return g.locatedOperation(e, "rt."+operation, a, b)
		}
		if e.Text != "%" {
			// Explicit rounding preserves each source operation even on FMA targets.
			return "float64(" + a + e.Text + b + ")"
		}
	}
	return ""
}
