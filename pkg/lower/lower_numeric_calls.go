package lower

import (
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"go/ast"
)

// Resolve intrinsics by checked native identity, not the visible source name.
// Bound methods and first-class references retain the ordinary callable ABI.
func (g *generator) numericCallName(e *syntax.Expression) string {
	if e.Kind != syntax.KindCall {
		return ""
	}
	info := g.program.Info(e)
	if info == nil {
		return ""
	}
	args := e.Args
	if info.Arguments != nil {
		args = info.Arguments
	}
	if info.Symbol != nil && len(args) == 1 && args[0].Name == "value" && primitiveEqualityType(g.program.Info(args[0].Value).Type) == "float64" {
		return map[string]string{"math/sqrt": "NativeFloatSqrt", "math/abs": "NativeFloatAbs", "math/floor": "NativeFloatFloor", "math/ceil": "NativeFloatCeil"}[info.Symbol.Native]
	}
	if e.Left.Kind == syntax.KindMember && len(args) == 0 {
		callee := g.program.Info(e.Left)
		if callee != nil && callee.Method != nil && callee.Method.Contract == nil && callee.Method.Native == "to_float" && primitiveEqualityType(g.program.Info(e.Left.Left).Type) == "int64" {
			return "NativeIntToFloat"
		}
	}
	return ""
}
func (g *generator) numericCall(e *syntax.Expression) ast.Expr {
	name := g.numericCallName(e)
	if name == "" {
		return nil
	}
	args := e.Args
	if converted := g.program.Info(e).Arguments; converted != nil {
		args = converted
	}
	operand := e.Left.Left
	if len(args) == 1 {
		operand = args[0].Value
	}
	return g.locatedOperation(e, runtimeName(name), ident("ctx"), g.scalarValue(operand))
}
