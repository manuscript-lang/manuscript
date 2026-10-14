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
	left := g.program.Info(e.Left).Type
	right := g.program.Info(e.Right).Type
	if left.ID != right.ID || left.ID != "Int" && left.ID != "Float" {
		return nil
	}
	switch e.Text {
	case "<", "<=", ">", ">=":
		op := map[string]token.Token{"<": token.LSS, "<=": token.LEQ, ">": token.GTR, ">=": token.GEQ}[e.Text]
		return g.orderedScalars(e, func(a, b ast.Expr) ast.Expr { return &ast.BinaryExpr{X: a, Op: op, Y: b} })
	case "+", "-", "*", "/", "%":
		if left.ID == "Int" {
			operation := map[string]string{"+": "IntAdd", "-": "IntSubtract", "*": "IntMultiply", "/": "IntDivide", "%": "IntRemainder"}[e.Text]
			return g.orderedScalars(e, func(a, b ast.Expr) ast.Expr { return runtimeCall(operation, a, b) })
		}
		if e.Text != "%" {
			op := map[string]token.Token{"+": token.ADD, "-": token.SUB, "*": token.MUL, "/": token.QUO}[e.Text]
			return g.orderedScalars(e, func(a, b ast.Expr) ast.Expr { return call(ident("float64"), &ast.BinaryExpr{X: a, Op: op, Y: b}) })
		}
	}
	return nil
}
