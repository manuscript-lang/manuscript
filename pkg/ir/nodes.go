package ir

import (
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// These nodes carry the common site and resolved performance facts. Source on
// the site is provenance; only statement/cleanup bodies remain deferred.
type Local struct{ Site *Expression }
type Reference = Local
type Unary struct{ Site *Expression }
type Binary struct{ Site *Expression }

// PrimitiveExpression is the common resolved primitive-node interface.
type PrimitiveExpression interface {
	Expr
	primitiveExpression()
}
type ResolvedCall struct{ Site *Expression }
type MatchValue struct{ Site *Expression }
type RecordAccess struct {
	Site  *Expression
	Field *FieldUse
}

func (Local) expr()                 {}
func (Unary) expr()                 {}
func (Binary) expr()                {}
func (Unary) primitiveExpression()  {}
func (Binary) primitiveExpression() {}
func (ResolvedCall) expr()          {}
func (MatchValue) expr()            {}
func (RecordAccess) expr()          {}

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
			if x.Operation.Left.Source == nil {
				node = Unary{Site: x}
			} else {
				node = Binary{Site: x}
			}
		case e.Kind == syntax.KindMatch:
			node = MatchValue{Site: x}
		case x.Binding != nil && (e.Kind == syntax.KindName || e.Kind == syntax.KindApply):
			node = Local{Site: x}
		case p.Fields[e] != nil:
			node = RecordAccess{Site: x, Field: p.Fields[e]}
		}
	}
	p.nodes[e] = node
	return node
}

// Value and Operand use the shared node cache. info may describe the raw value
// at an error-widening boundary; explicit use conversions remain on Edge.
func (p *Elaborator) Value(e *syntax.Expression, info *checker.Info) Expr {
	if value, constant := p.Bool(e); constant {
		return BoolLiteral{Value: value, Type: info.Type}
	}
	if checker.Same(info.Type, p.Expression(e).SourceType) {
		return p.Node(e)
	}
	return Value(p.checked, e, info)
}
func (p *Elaborator) Operand(e *syntax.Expression) Expr {
	edge := p.Use(e, nil)
	if edge.ErrorSource != nil || edge.Optional != nil || edge.Never {
		return Converted{Use: edge}
	}
	if x := p.Node(e); x != nil {
		return x
	}
	return Deferred{Source: e}
}
