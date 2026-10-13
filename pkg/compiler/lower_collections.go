package compiler

import "github.com/manuscript-lang/manuscript/pkg/syntax"

// These checked native operations neither invoke callbacks nor acquire
// resources. Direct calls can share their runtime implementation without
// constructing a bound Function, resolving labels, or changing Optional storage.
// References to bound methods still use ordinary callable dispatch.
func (g *generator) directCollectionCall(e *syntax.Expression, arguments []syntax.Argument) string {
	callee := g.program.Expressions[e.Left]
	if e.Left.Kind != syntax.KindMember || callee == nil || callee.Method == nil || callee.Method.Contract != nil {
		return ""
	}
	switch callee.Method.Native {
	case "collections/at":
		if len(arguments) == 1 {
			return "rt.ListAt(ctx," + g.expression(e.Left.Left) + "," + g.expression(arguments[0].Value) + "," + g.key(g.program.Expressions[e].Type) + ")"
		}
	case "optional/unwrap":
		if len(arguments) == 0 {
			return "rt.OptionalUnwrap(ctx," + g.expression(e.Left.Left) + ")"
		}
	}
	return ""
}
