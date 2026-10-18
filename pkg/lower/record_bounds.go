package lower

import (
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"go/ast"
	"go/token"
)

type localRecordCall struct {
	binding         *checker.Binding
	method          *checker.Method
	field, operator string
}

// Match a checked, concrete two-statement method. This is deliberately not a
// general source inliner: a single private Int cell is its entire state.
func (g *gen) localRecordMethod(m *checker.Method, receiver *checker.Type, field string) *localRecordCall {
	if m == nil || m.Decl == nil {
		return nil
	}
	m = g.resolveMethod(m, receiver, m.Decl.Name)
	d := m.Decl
	if d == nil || m.Native != "" || m.Local || len(m.Variables) != 0 || len(d.TypeParams) != 0 || len(d.Params) != 1 || d.Params[0].Default != nil ||
		len(d.Body) != 2 || len(receiver.Args) != 0 || checker.TypeKey(g.sub(m.Receiver)) != checker.TypeKey(receiver) {
		return nil
	}
	params := g.program.ParameterBindings(d)
	self := g.program.SelfBinding(d)
	if len(params) != 1 || params[0].Mutable || g.sub(params[0].Type).ID != "Int" || self == nil || g.sub(m.Type.Result).ID != "Int" {
		return nil
	}
	update, ret := d.Body[0], d.Body[1]
	isField := func(e *syntax.Expression) bool {
		return e != nil && e.Kind == syntax.KindMember && e.Text == field && e.Left.Kind == syntax.KindName &&
			g.info(e.Left).Binding == self && g.info(e).Method == nil && g.sub(g.info(e).Type).ID == "Int"
	}
	v := update.Value
	if update.Kind != syntax.KindAssign || !isField(update.Target) || v == nil || v.Kind != syntax.KindBinary || (v.Text != "+" && v.Text != "-") ||
		!isField(v.Left) || v.Right.Kind != syntax.KindName || g.info(v.Right).Binding != params[0] ||
		ret.Kind != syntax.KindReturn || !isField(ret.Value) {
		return nil
	}
	for _, e := range []*syntax.Expression{v, v.Left, v.Right, ret.Value} {
		info := g.info(e)
		if info == nil || g.sub(info.Type).ID != "Int" || info.OptionalArgument != nil || info.ErrorSource != nil || info.PropagatedError != nil {
			return nil
		}
	}
	return &localRecordCall{method: m, field: field, operator: v.Text}
}
func (p *intProof) recordField(b *checker.Binding) string {
	if p.g.fn.localCollections != nil {
		return p.g.fn.localCollections.records[b]
	}
	return ""
}
func (p *intProof) recordCall(e *syntax.Expression) *localRecordCall {
	if p.g.fn.localCollections != nil {
		return p.g.fn.localCollections.recordCalls[e]
	}
	return nil
}
func (p *intProof) getCell(b *checker.Binding) intBounds {
	if p.recordField(b) != "" {
		if f, ok := p.facts[b]; ok && f.epoch == p.epoch {
			return f.bounds
		}
		return unknownIntBounds
	}
	return p.get(b)
}
func (p *intProof) setCell(b *checker.Binding, bounds intBounds) {
	if p.recordField(b) == "" {
		p.set(b, bounds)
		return
	}
	old, had := p.facts[b]
	p.journal = append(p.journal, intUndo{b, old, had})
	p.facts[b] = intFact{bounds: bounds, epoch: p.epoch}
}
func (p *intProof) recordOperation(e *syntax.Expression, args []intBounds, annotate bool) (intBounds, bool) {
	if op := p.recordCall(e); op != nil {
		bounds, ok := addIntBounds(p.getCell(op.binding), args[0], op.operator == "-")
		if ok && annotate {
			p.g.fn.recordUpdates[e] = op
		}
		p.setCell(op.binding, bounds)
		return bounds, true
	}
	if e.Kind == syntax.KindMember && e.Left.Kind == syntax.KindName {
		b := p.g.info(e.Left).Binding
		if field := p.recordField(b); field != "" && field == e.Text && p.g.info(e).Method == nil {
			return p.getCell(b), true
		}
	}
	return unknownIntBounds, false
}

func (g *gen) localRecordUpdate(e *syntax.Expression, m *checker.Method, receiver ast.Expr, args []ast.Expr) ast.Expr {
	op := g.fn.recordUpdates[e]
	if op == nil {
		return nil
	}
	if m.ID != op.method.ID || len(args) != 1 {
		g.fail("closed record method changed after proof")
		return nil
	}
	// Even a simple field read argument must happen before the callee's update.
	argument := g.spill(args[0])
	target := selector(receiver, fieldName(op.field))
	operator := token.ADD
	if op.operator == "-" {
		operator = token.SUB
	}
	g.fn.pre = append(g.fn.pre, assign(target, token.ASSIGN, binary(target, operator, argument)))
	return target
}
