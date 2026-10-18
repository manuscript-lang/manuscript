package lower

import (
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Bounds describe normally returned success payloads, never call totality.
// Summaries have a fixed checked shape and at most one direct wrapper hop.
type resultIntSummary struct {
	offset   int64
	subtract bool
}

func (g *gen) resultIntSummaries() map[*syntax.Declaration]resultIntSummary {
	summaries := map[*syntax.Declaration]resultIntSummary{}
	wrappers := map[*syntax.Declaration]*syntax.Declaration{}
	if g.program == nil {
		return summaries
	}
	for _, module := range g.program.Modules {
		for _, d := range module.Declarations {
			if d.Kind != syntax.KindFn || len(d.TypeParams) != 0 || len(d.Params) != 1 || d.Params[0].Default != nil || len(d.Body) != 2 {
				continue
			}
			bindings := g.program.ParameterBindings(d)
			symbol := g.program.Symbol(module.File, d.Name)
			if len(bindings) != 1 || bindings[0].Mutable || bindings[0].Type.ID != "Int" || symbol == nil || symbol.Native != "" || len(symbol.Variables) != 0 || defaulted(symbol.Type, 0) {
				continue
			}
			result := symbol.Type.Result
			if !isStd(result, "Result") || len(result.Args) != 2 || result.Args[0].ID != "Int" {
				continue
			}
			param := bindings[0]
			if inner := g.tailResultOperandAs(d.Body, result); inner != nil && inner.Kind == syntax.KindCall && len(inner.Args) == 1 && g.resultParameter(inner.Args[0].Value, param) {
				info, callee := g.info(inner), g.info(inner.Left)
				if info != nil && callee != nil && inner.Left.Kind == syntax.KindName && callee.Binding == nil && info.Symbol != nil && info.Symbol == callee.Symbol && info.Symbol.Native == "" && len(info.TypeArgs) == 0 && len(info.Symbol.Variables) == 0 && !defaulted(callee.Type, 0) && checker.TypeKey(info.Type) == checker.TypeKey(result) {
					wrappers[d] = info.Symbol.Decl
				}
				continue
			}
			guard, ret := d.Body[0], d.Body[1]
			if guard.Kind != syntax.KindIf || guard.Pattern != nil || len(guard.Else) != 0 || len(guard.Body) != 1 || guard.Body[0].Kind != syntax.KindReturn || ret.Kind != syntax.KindReturn {
				continue
			}
			cond := guard.Value
			if cond == nil || cond.Kind != syntax.KindBinary || !g.resultParameter(cond.Left, param) || !g.resultPlain(cond) {
				continue
			}
			switch cond.Text {
			case "<", "<=", ">", ">=", "==", "!=":
			default:
				continue
			}
			if _, ok := (&intProof{g: g}).literal(cond.Right); !ok {
				continue
			}
			cause := g.resultConstructorArgument(guard.Body[0].Value, "error", result)
			if cause == nil || !g.resultErrorLiteral(cause) {
				continue
			}
			value := g.resultConstructorArgument(ret.Value, "ok", result)
			if value == nil || value.Kind != syntax.KindBinary || (value.Text != "+" && value.Text != "-") || !g.resultPlain(value) || !g.resultParameter(value.Left, param) {
				continue
			}
			offset, ok := (&intProof{g: g}).literal(value.Right)
			if ok {
				summaries[d] = resultIntSummary{offset, value.Text == "-"}
			}
		}
	}
	// Read only the direct summaries, not previously expanded wrappers. Order
	// cannot accidentally turn this into unbounded graph interpretation.
	expanded := map[*syntax.Declaration]resultIntSummary{}
	for wrapper, inner := range wrappers {
		if s, ok := summaries[inner]; ok {
			expanded[wrapper] = s
		}
	}
	for wrapper, s := range expanded {
		summaries[wrapper] = s
	}
	return summaries
}

func (g *gen) resultPlain(e *syntax.Expression) bool {
	i := g.info(e)
	return i != nil && i.ErrorSource == nil && i.PropagatedError == nil && i.OptionalArgument == nil
}
func (g *gen) resultParameter(e *syntax.Expression, b *checker.Binding) bool {
	return e != nil && e.Kind == syntax.KindName && g.resultPlain(e) && g.info(e).Binding == b
}
func (g *gen) resultConstructorArgument(e *syntax.Expression, name string, result *checker.Type) *syntax.Expression {
	if e == nil || e.Kind != syntax.KindCall || len(e.Args) != 1 || !g.resultPlain(e) {
		return nil
	}
	i := g.info(e)
	if !isStd(i.Constructor, "Result") || i.Case != name || checker.TypeKey(i.Type) != checker.TypeKey(result) {
		return nil
	}
	return e.Args[0].Value
}
func (g *gen) resultStringLiteral(e *syntax.Expression) bool {
	if e == nil || e.Kind != syntax.KindText || !g.resultPlain(e) || g.info(e).Type.ID != "String" {
		return false
	}
	// Literal parts may contain text, but no interpolation/control flow.
	for _, part := range e.Parts {
		if part.Value != nil {
			return false
		}
	}
	return true
}
func (g *gen) resultErrorLiteral(e *syntax.Expression) bool {
	if g.resultStringLiteral(e) {
		return true
	}
	if e == nil || e.Kind != syntax.KindCall || len(e.Args) != 1 || !g.resultPlain(e) || !g.resultStringLiteral(e.Args[0].Value) {
		return false
	}
	t := g.info(e).Constructor
	if t == nil || t.Kind != "record" || len(t.Args) != 0 || t.Def == nil || len(t.Def.Fields) != 1 || t.Def.Fields[0].Type.ID != "String" {
		return false
	}
	signature := checker.ConstructorSignature(t)
	return len(signature.Params) == 1 && !defaulted(signature, 0)
}

func (p *intProof) successBinding(s *syntax.Statement) {
	if s.Pattern == nil || s.Pattern.Kind != syntax.KindName || s.Value == nil || s.Value.Kind != syntax.KindCall {
		return
	}
	b := p.g.program.PatternBinding(s.Pattern)
	if b == nil || b.Mutable || p.g.sub(b.Type).ID != "Int" || !p.g.resultPlain(s.Value) {
		return
	}
	call := s.Value
	info, callee := p.g.info(call), p.g.info(call.Left)
	if info == nil || callee == nil || call.Left.Kind != syntax.KindName || callee.Binding != nil || info.Symbol == nil || callee.Symbol != info.Symbol || len(info.TypeArgs) != 0 || len(info.Arguments) != 1 || defaulted(callee.Type, 0) {
		return
	}
	summary, ok := p.g.resultBounds[info.Symbol.Decl]
	if !ok {
		return
	}
	input := p.expression(info.Arguments[0].Value, false)
	bounds, ok := addIntBounds(input, intBounds{summary.offset, summary.offset}, summary.subtract)
	if ok {
		p.set(b, bounds)
	}
}

// Visit each statement once, with success facts scoped to their success arm.
// Carries remain invalidated: this walk never transfers assignment values.
func (p *intProof) loopDeltas(body []*syntax.Statement, writes map[*syntax.Expression]intLoopWrite, collect func(intLoopWrite)) {
	for _, s := range body {
		if w, ok := writes[s.Value]; ok {
			collect(w)
		}
		if s.Kind == syntax.KindIf {
			mark, epoch := len(p.journal), p.epoch
			p.successBinding(s)
			p.loopDeltas(s.Body, writes, collect)
			p.restore(mark, epoch)
			p.loopDeltas(s.Else, writes, collect)
			p.restore(mark, epoch)
		}
	}
}
