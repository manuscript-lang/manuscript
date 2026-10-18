package lower

import (
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// An exact Result unwrapped and immediately rewrapped at a tail is itself.
// Keep the original statements when source bindings are needed by a debugger.
func (g *gen) tailResultOperand(stmts []*syntax.Statement) *syntax.Expression {
	return g.tailResultOperandAs(stmts, g.fn.result)
}

func (g *gen) tailResultOperandAs(stmts []*syntax.Statement, result *checker.Type) *syntax.Expression {
	if g.options.PreserveBindings || g.options.Locals != nil || len(stmts) < 2 {
		return nil
	}
	bind, ret := stmts[len(stmts)-2], stmts[len(stmts)-1]
	if bind.Kind != syntax.KindBind || bind.Pattern.Kind != syntax.KindName ||
		bind.Value == nil || bind.Value.Kind != syntax.KindUnary || bind.Value.Text != "try" ||
		ret.Kind != syntax.KindReturn || ret.Value == nil || ret.Value.Kind != syntax.KindCall || len(ret.Value.Args) != 1 {
		return nil
	}
	binding := g.program.PatternBinding(bind.Pattern)
	arg := ret.Value.Args[0].Value
	if binding == nil || binding.Mutable || arg.Kind != syntax.KindName || g.info(arg) == nil || g.info(arg).Binding != binding {
		return nil
	}
	constructor, tried, argument := g.info(ret.Value), g.info(bind.Value), g.info(arg)
	inner := bind.Value.Right
	operand := g.info(inner)
	result = g.sub(result)
	if constructor == nil || !isStd(constructor.Constructor, "Result") || constructor.Case != "ok" ||
		tried == nil || argument == nil || operand == nil || !isStd(result, "Result") {
		return nil
	}
	for _, info := range []*checker.Info{constructor, tried, argument, operand} {
		if info.ErrorSource != nil || info.OptionalArgument != nil || info.PropagatedError != nil {
			return nil
		}
	}
	// Function defaults affect the Go ABI but are omitted from TypeKey. Keep
	// their existing conversion path rather than assuming a matching key suffices.
	if resultPayloadHasFunction(g.sub(binding.Type)) ||
		checker.TypeKey(g.sub(binding.Type)) != checker.TypeKey(result.Args[0]) ||
		checker.TypeKey(g.sub(operand.Type)) != checker.TypeKey(result) ||
		checker.TypeKey(g.sub(constructor.Type)) != checker.TypeKey(result) {
		return nil
	}
	return inner
}

func resultPayloadHasFunction(t *checker.Type) bool {
	if t.Kind == "function" {
		return true
	}
	for _, arg := range t.Args {
		if resultPayloadHasFunction(arg) {
			return true
		}
	}
	return false
}
