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
	op := g.ir.Expression(e).Operation
	if op == nil || (op.Primitive != "int64" && op.Primitive != "float64") {
		return nil
	}
	switch op.Identity {
	case "<", "<=", ">", ">=":
		op := map[string]token.Token{"<": token.LSS, "<=": token.LEQ, ">": token.GTR, ">=": token.GEQ}[op.Identity]
		return g.orderedScalars(e, func(a, b ast.Expr) ast.Expr { return &ast.BinaryExpr{X: a, Op: op, Y: b} })
	case "+", "-", "*", "/", "%":
		if op.Primitive == "int64" {
			operation := map[string]string{"+": "IntAdd", "-": "IntSubtract", "*": "IntMultiply", "/": "IntDivide", "%": "IntRemainder"}[op.Identity]
			return g.orderedScalars(e, func(a, b ast.Expr) ast.Expr { return runtimeCall(operation, a, b) })
		}
		if op.Identity != "%" {
			op := map[string]token.Token{"+": token.ADD, "-": token.SUB, "*": token.MUL, "/": token.QUO}[op.Identity]
			return g.orderedScalars(e, func(a, b ast.Expr) ast.Expr { return call(ident("float64"), &ast.BinaryExpr{X: a, Op: op, Y: b}) })
		}
	}
	return nil
}
