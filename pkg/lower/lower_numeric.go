package lower

import (
	"go/ast"
	"go/token"

	"github.com/manuscript-lang/manuscript/pkg/ir"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Keep statically known scalar operands typed through an expression. Scalar
// locals and parameters of the function being lowered are typed Go variables;
// captures, generic values, and call boundaries retain the shared Value ABI.
// Nonprimitive equality retains the checker's selected implementation scope.
func (g *generator) numericBinary(x ir.Binary) ast.Expr {
	if numericResultType(x) == "" && !isComparison(x.Op) || !sameNumeric(x) {
		return nil
	}
	goType := primitiveEqualityType(x.LeftType)
	if g.orderedFirst(x) {
		return g.orderedNumeric(x, goType)
	}
	a := paren(g.numericOperand(x.Left, goType))
	b := paren(g.numericOperand(x.Right, goType))
	return g.numericOperation(x, a, b)
}

func isComparison(op string) bool { return op == "<" || op == "<=" || op == ">" || op == ">=" }

// sameNumeric reports whether both operands have the same Int or Float type.
func sameNumeric(x ir.Binary) bool {
	return x.LeftType.ID == x.RightType.ID && (x.LeftType.ID == "Int" || x.LeftType.ID == "Float")
}

// orderedFirst reports whether the right operand holds a match whose arms can
// assign a local the left operand reads. Go does not order a variable read
// before a later operand's evaluation, so the left value is captured first.
func (g *generator) orderedFirst(x ir.Binary) bool {
	return !g.constant(x.Left) && containsMatch(x.Right)
}

// containsMatch reports whether evaluating x can run a match expression.
func containsMatch(x ir.Expr) bool {
	switch x := x.(type) {
	case ir.Deferred:
		found := false
		syntax.Visitor{Expression: func(e *syntax.Expression) {
			if e.Kind == syntax.KindMatch {
				found = true
			}
		}}.Callable(nil, []*syntax.Statement{{Kind: syntax.KindCall, Value: x.Source}})
		return found
	case ir.Call:
		if containsMatch(x.Callee) {
			return true
		}
		for _, a := range x.Args {
			if containsMatch(a.Value) {
				return true
			}
		}
	case ir.View:
		return containsMatch(x.Receiver)
	case ir.Member:
		return containsMatch(x.Receiver)
	case ir.Unary:
		return containsMatch(x.Operand)
	case ir.Binary:
		return containsMatch(x.Left) || containsMatch(x.Right)
	case ir.Text:
		for _, p := range x.Parts {
			if p.Value != nil && containsMatch(p.Value) {
				return true
			}
		}
	case ir.List:
		for _, item := range x.Items {
			if containsMatch(item) {
				return true
			}
		}
	case ir.Map:
		for _, entry := range x.Entries {
			if containsMatch(entry.Key) || containsMatch(entry.Value) {
				return true
			}
		}
	}
	return false
}

// orderedNumeric evaluates the left operand into a temporary before the right.
func (g *generator) orderedNumeric(x ir.Binary, goType string) ast.Expr {
	a, b := g.temp(), g.temp()
	return call(closure(nil, ident(numericResultType(x)),
		define(a, g.numericOperand(x.Left, goType)),
		define(b, g.numericOperand(x.Right, goType)),
		returned(g.numericOperation(x, ident(a), ident(b))),
	))
}

func (g *generator) numericOperation(x ir.Binary, a, b ast.Expr) ast.Expr {
	switch x.Op {
	case "<", "<=", ">", ">=":
		op := map[string]token.Token{"<": token.LSS, "<=": token.LEQ, ">": token.GTR, ">=": token.GEQ}[x.Op]
		return &ast.BinaryExpr{X: a, Op: op, Y: b}
	case "+", "-", "*", "/", "%":
		if x.LeftType.ID == "Int" {
			// The operation's site travels with it and is recorded only on a fault.
			operation := map[string]string{"+": "IntAddAt", "-": "IntSubtractAt", "*": "IntMultiplyAt", "/": "IntDivideAt", "%": "IntRemainderAt"}[x.Op]
			return runtimeCall(operation, a, b, address(ident("sourcePosition")), textLiteral(x.Pos.String()))
		}
		if x.Op != "%" {
			// Explicit rounding preserves each source operation even on FMA targets.
			op := map[string]token.Token{"+": token.ADD, "-": token.SUB, "*": token.MUL, "/": token.QUO}[x.Op]
			return call(ident("float64"), &ast.BinaryExpr{X: a, Op: op, Y: b})
		}
	}
	return nil
}

// numericResultType is the Go type numericBinary yields for x, or "".
func numericResultType(x ir.Binary) string {
	if !sameNumeric(x) {
		return ""
	}
	switch x.Op {
	case "<", "<=", ">", ">=":
		return "bool"
	case "+", "-", "*", "/", "%":
		if x.LeftType.ID == "Int" {
			return "int64"
		}
		if x.Op != "%" {
			return "float64"
		}
	}
	return ""
}

// numericOperand lowers one operand. A constant Float expression is hidden from
// the Go compiler so division by zero and overflow follow Manuscript's runtime
// rules instead of becoming compile-time errors.
func (g *generator) numericOperand(x ir.Expr, goType string) ast.Expr {
	if goType == "float64" && g.constant(x) {
		return runtimeCall("FloatValue", g.irValue(x))
	}
	return g.irScalar(x, goType)
}

// constant reports whether g.irValue(x) is a Go constant expression.
func (g *generator) constant(x ir.Expr) bool {
	switch x := x.(type) {
	case ir.IntLiteral, ir.FloatLiteral, ir.BoolLiteral:
		return true
	case ir.Binary:
		return g.native(x) != "" && g.constant(x.Left) && g.constant(x.Right)
	}
	return false
}
