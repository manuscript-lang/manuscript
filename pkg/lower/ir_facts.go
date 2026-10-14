package lower

import (
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/ir"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func primitiveListSuffix(t *checker.Type) string { return ir.ListSuffix(t) }
func (g *generator) nativeCallAvailable(e *syntax.Expression) bool {
	x := g.ir.Expression(e)
	return x.Call != nil && x.Call.Symbol != nil && x.Call.Native
}
func (g *generator) nativeMethodAvailable(e *syntax.Expression) bool {
	x := g.ir.Expression(e)
	return x.Call != nil && x.Call.Method != nil && x.Call.Native
}
func (g *generator) shareNativeBody(s *checker.Symbol) bool { return g.ir.ShareNativeBody(s) }
func (g *generator) nativeBodyCompatible(params []syntax.Parameter, body []*syntax.Statement, bindings []*checker.Binding, t *checker.Type) bool {
	return g.ir.BodyCompatible(params, body, bindings, t)
}
func comparatorKind(t *checker.Type, params []syntax.Parameter) string {
	return ir.ComparatorKind(t, params)
}
func (g *generator) nativeBinaryOperands(e *syntax.Expression) bool {
	return g.ir.Expression(e).Operation != nil
}
func (g *generator) typedListAtSuffix(e *syntax.Expression) string {
	if e == nil {
		return ""
	}
	x := g.ir.Expression(e)
	if x.Call != nil && x.Call.Collection == "ListAt" {
		return x.Call.ListSuffix
	}
	return ""
}
func (g *generator) typedUnwrapAt(e *syntax.Expression) bool {
	x := g.ir.Expression(e)
	return x.Call != nil && x.Call.UnwrapAt != nil
}
func (g *generator) typedCollectionScalar(e *syntax.Expression) bool {
	x := g.ir.Expression(e)
	return x.Call != nil && (x.Call.UnwrapAt != nil || x.Call.Collection == "CollectionLengthInt")
}
func (g *generator) numericCallName(e *syntax.Expression) string {
	x := g.ir.Expression(e)
	if x.Call != nil {
		return x.Call.Numeric
	}
	return ""
}

// callSyntax supports the temporary dynamic/constructor body boundary. Labels
// and order have already been resolved by IR, never rediscovered here.
func callSyntax(x *ir.Call) []syntax.Argument {
	args := make([]syntax.Argument, len(x.Arguments))
	for i, a := range x.Arguments {
		args[i] = syntax.Argument{Name: a.Name, Pos: a.Pos, Value: a.Value.Source}
	}
	return args
}
