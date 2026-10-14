package lower

import (
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/ir"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func (g *generator) shareNativeBody(s *checker.Symbol) bool { return g.ir.ShareNativeBody(s) }

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
