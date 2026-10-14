package lower

import (
	"go/ast"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/ir"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Scalar locals and parameters (Int, Float, Bool, String) are declared with
// their Go type, so arithmetic and comparisons neither box nor assert.
// A boxed Value is produced only where an operand crosses the Value ABI,
// which Go does implicitly. Captured snapshots stay Value.

// scalarBinding is the Go type of a binding declared as a typed variable, or "".
func scalarBinding(b *checker.Binding) string {
	if b == nil {
		return ""
	}
	return primitiveEqualityType(b.Type)
}

func (g *generator) declareTyped(b *checker.Binding) string {
	typ := scalarBinding(b)
	if typ != "" {
		g.typed[b] = typ
	}
	return typ
}

// typedLocal returns the Go type of the typed variable a binding names in the
// current scope, or "".
func (g *generator) typedLocal(b *checker.Binding) string {
	if b == nil || g.captures[b] != "" {
		return ""
	}
	return g.typed[b]
}

// nativeType is the Go type g.expression(e) has when it is not the Value
// interface, or "".
func (g *generator) nativeType(e *syntax.Expression) string {
	if g.constantBool(e) {
		return "bool"
	}
	info := g.program.Info(e)
	if info.ErrorSource != nil {
		return ""
	}
	if x := g.ir.Operand(e); !isDeferred(x) {
		return g.native(x)
	}
	switch e.Kind {
	case syntax.KindCall:
		if direct := g.directTarget(e); direct != nil {
			return direct.result
		}
	}
	return ""
}

func isDeferred(x ir.Expr) bool {
	_, ok := x.(ir.Deferred)
	return ok
}

// native is the Go type g.irValue(x) has when it is not the Value interface,
// or "".
func (g *generator) native(x ir.Expr) string {
	switch x := x.(type) {
	case ir.IntLiteral:
		return "int64"
	case ir.FloatLiteral:
		return "float64"
	case ir.BoolLiteral:
		return "bool"
	case ir.Local:
		return g.typedLocal(x.Binding)
	case ir.Unary:
		if x.Op == "not" {
			return "bool"
		}
	case ir.Binary:
		switch {
		case x.Op == "and" || x.Op == "or":
			return "bool"
		case x.Op == "==" || x.Op == "!=":
			if equalityIsPrimitive(x) {
				return "bool"
			}
			return ""
		}
		return numericResultType(x)
	case ir.Member:
		if x.Info.Constructor == nil && x.Info.Method == nil && x.Info.Native == "" {
			if _, f := g.structFieldOf(x); f != nil {
				return f.scalar
			}
		}
	case ir.Deferred:
		return g.nativeType(x.Source)
	}
	return ""
}

// scalar lowers e to a Go expression of exactly typ, which is e's checked
// primitive type.
func (g *generator) scalar(e *syntax.Expression, typ string) ast.Expr {
	value := g.expression(e)
	if g.nativeType(e) == typ {
		return value
	}
	return unbox(value, typ)
}

// irScalar lowers x to a Go expression of exactly typ, which is x's checked
// primitive type.
func (g *generator) irScalar(x ir.Expr, typ string) ast.Expr {
	value := g.irValue(x)
	if g.native(x) == typ {
		return value
	}
	return unbox(value, typ)
}

// unbox asserts a Value-typed expression to a Go scalar.
func unbox(value ast.Expr, typ string) ast.Expr {
	switch typ {
	case "int64":
		return runtimeCall("IntValue", value)
	case "float64":
		return runtimeCall("FloatValue", value)
	case "bool":
		return runtimeCall("Bool", value)
	}
	return runtimeCall("StringValue", value)
}

// condition lowers a Bool-typed expression to a Go bool.
func (g *generator) condition(e *syntax.Expression) ast.Expr { return g.scalar(e, "bool") }
