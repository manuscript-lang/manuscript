package ir

import "github.com/manuscript-lang/manuscript/pkg/syntax"

// These nodes carry the common site and resolved performance facts. Source on
// the site is provenance; only statement/cleanup bodies remain deferred.
type Reference struct{ Site *Expression }
type PrimitiveExpression struct{ Site *Expression }
type ResolvedCall struct{ Site *Expression }
type MatchValue struct{ Site *Expression }
type RecordAccess struct {
	Site  *Expression
	Field *FieldUse
}

func (Reference) expr()           {}
func (PrimitiveExpression) expr() {}
func (ResolvedCall) expr()        {}
func (MatchValue) expr()          {}
func (RecordAccess) expr()        {}

// Node returns the elaborated node. Unsupported bodies remain at the explicit
// Deferred boundary. Memoization avoids rebuilding nodes for native/boxed bodies.
func (p *Program) Node(e *syntax.Expression) Expr {
	if node, ok := p.nodes[e]; ok {
		return node
	}
	x := p.Expression(e)
	info := *p.checked.Info(e)
	info.Type = x.SourceType
	var node Expr
	if value := Value(p.checked, e, &info); value != nil {
		node = value
	} else {
		switch {
		case x.Call != nil:
			node = ResolvedCall{Site: x}
		case x.Operation != nil:
			node = PrimitiveExpression{Site: x}
		case e.Kind == syntax.KindMatch:
			node = MatchValue{Site: x}
		case x.Binding != nil && (e.Kind == syntax.KindName || e.Kind == syntax.KindApply):
			node = Reference{Site: x}
		case p.Fields[e] != nil:
			node = RecordAccess{Site: x, Field: p.Fields[e]}
		}
	}
	p.nodes[e] = node
	return node
}
