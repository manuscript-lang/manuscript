package lower

import (
	"go/ast"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Scalar locals and parameters (Int, Float, Bool, String) are declared with
// their Go type, so arithmetic and comparisons neither box nor assert.
// A boxed Value is produced only where an operand crosses the Value ABI,
// which Go does implicitly. Captured snapshots stay Value.

// scalarBinding is the Go type of a binding declared as a typed variable, or "".
// primitiveKinds names the runtime entry points of each Go scalar type.
var primitiveKinds = map[string]string{"int64": "Int", "float64": "Float", "bool": "Bool", "string": "String"}

func (g *generator) scalarBinding(b *checker.Binding) string {
	if b == nil {
		return ""
	}
	return primitiveEqualityType(g.sub(b.Type))
}

func (g *generator) declareTyped(b *checker.Binding) string {
	typ := g.scalarBinding(b)
	if typ != "" {
		g.typed[b] = typ
	}
	return typ
}

// typedLocal returns the Go type of the typed variable a name refers to in the
// current scope, or "".
func (g *generator) typedLocal(e *syntax.Expression) string {
	if e.Kind != syntax.KindName {
		return ""
	}
	info := g.info(e)
	if info.Method != nil || info.Binding == nil || g.captures[info.Binding] != "" {
		return ""
	}
	return g.typed[info.Binding]
}

// nativeType is the Go type g.expression(e) has when it is not the Value
// interface, or "".
func (g *generator) nativeType(e *syntax.Expression) string {
	if t, ok := g.tried[e]; ok {
		return t.native
	}
	if g.constantBool(e) {
		return "bool"
	}
	info := g.info(e)
	if info.ErrorSource != nil {
		return ""
	}
	switch e.Kind {
	case syntax.KindNumber:
		if strings.HasSuffix(e.Text, "d") {
			return ""
		}
		if strings.ContainsAny(e.Text, ".eE") {
			return "float64"
		}
		return "int64"
	case syntax.KindBool:
		return "bool"
	case syntax.KindText:
		return "string"
	case syntax.KindName:
		return g.typedLocal(e)
	case syntax.KindBinary:
		if e.Text == "and" || e.Text == "or" {
			return "bool"
		}
		if e.Text == "==" || e.Text == "!=" {
			if g.equalityIsPrimitive(e) {
				return "bool"
			}
			return ""
		}
		return g.numericResult(e)
	case syntax.KindMember:
		if info.Method != nil && info.Method.Accessor {
			if g.nativeAccessorHelper(e, info) != "" {
				return primitiveEqualityType(info.Type)
			}
			if direct := g.directAccessorTarget(e, info); direct != nil {
				return direct.result
			}
			return ""
		}
		if info.Constructor == nil && info.Method == nil && info.Native == "" {
			if _, f := g.structFieldOf(e); f != nil {
				return f.scalar
			}
		}
	case syntax.KindCall:
		if direct := g.directTarget(e); direct != nil {
			return direct.result
		}
		if entry, _, ok := g.scalarNativeCall(e); ok {
			return entry.result
		}
	case syntax.KindUnary:
		if e.Text == "not" {
			return "bool"
		}
		if e.Text == "-" && e.Right.Kind == syntax.KindNumber && e.Right.Text == "9223372036854775808" {
			return "int64"
		}
		return g.negationType(e)
	}
	return ""
}

func (g *generator) equalityIsPrimitive(e *syntax.Expression) bool {
	left := g.info(e.Left).Type
	right := g.info(e.Right).Type
	typ := primitiveEqualityType(left)
	return typ != "" && left.ID == right.ID && primitiveEqualityType(right) == typ
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
