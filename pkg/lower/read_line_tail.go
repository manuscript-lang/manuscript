package lower

import (
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"go/ast"
)

// This tail observes only read_line's success and Optional presence. The runtime
// can consume and validate identically without materializing an unobserved String.
func (g *gen) tailLineOperand(body []*syntax.Statement) *syntax.Expression {
	if g.options.PreserveBindings || g.options.Locals != nil || g.localImpl || len(body) < 2 || g.sub(g.fn.result).ID != "Bool" {
		return nil
	}
	branch, last := body[len(body)-2], body[len(body)-1]
	if branch.Kind != syntax.KindIf || branch.Pattern == nil || branch.Pattern.Kind != syntax.KindName || len(branch.Else) != 0 || len(branch.Body) != 1 ||
		last.Kind != syntax.KindReturn || last.Value == nil || last.Value.Text != "false" || last.Value.Kind != syntax.KindBool {
		return nil
	}
	read := branch.Value
	if read == nil || read.Kind != syntax.KindCall {
		return nil
	}
	info := g.info(read)
	if info == nil || info.Symbol == nil || info.Symbol.Module != "@std/io.ms" || info.Symbol.Native != "io/read_line" {
		return nil
	}
	result := g.sub(info.Type)
	if !isStd(result, "Result") || len(result.Args) != 2 || !isStd(result.Args[0], "Optional") || len(result.Args[0].Args) != 1 ||
		result.Args[0].Args[0].ID != "String" || !isStd(result.Args[1], "IoError") {
		return nil
	}
	binding := g.program.PatternBinding(branch.Pattern)
	if binding == nil || binding.Mutable {
		return nil
	}
	ret := branch.Body[0]
	if ret.Kind != syntax.KindReturn || ret.Value == nil || ret.Value.Kind != syntax.KindCall || len(ret.Value.Args) != 0 {
		return nil
	}
	member := ret.Value.Left
	if member.Kind != syntax.KindMember || member.Text != "is_some" || member.Left.Kind != syntax.KindName || g.info(member.Left).Binding != binding {
		return nil
	}
	methodInfo := g.info(member)
	if methodInfo == nil || methodInfo.Method == nil {
		return nil
	}
	m := g.resolveMethod(methodInfo.Method, binding.Type, "is_some")
	if m.Native != "optional/is_some" || m.Local || m.Contract != nil || !isStd(m.Receiver, "Optional") || g.nativeMethodName(m, binding.Type) != "Optional_IsSome" {
		return nil
	}
	for _, e := range []*syntax.Expression{read, ret.Value, member.Left} {
		info := g.info(e)
		if info == nil || info.OptionalArgument != nil || info.ErrorSource != nil || info.PropagatedError != nil {
			return nil
		}
	}
	return read
}
func (g *gen) linePresence(read *syntax.Expression) ast.Expr {
	expression := g.expr(read)
	invoke, ok := expression.(*ast.CallExpr)
	if !ok {
		g.fail("read_line tail did not lower to its native call")
		return expression
	}
	invoke.Fun = rtName("Io_HasLine")
	return invoke
}
