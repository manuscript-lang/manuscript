package parser

import (
	"github.com/manuscript-lang/manuscript/pkg/lexer"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// assignTarget records the left side of an assignment on s.
func (p *Parser) assignTarget(s *syntax.Statement, start lexer.Token, e *syntax.Expression) {
	if (e.Kind != syntax.KindName && e.Kind != syntax.KindMember) || (e.Text == "self" || e.Text == "fixture") {
		p.fail(start, "assignment requires a local binding name or record field; the left side of '=' must be a name or a.field; to change a collection element, call its method such as set(index:, value:) on a List or add(key:, value:) on a Map")
	}
	s.Kind = syntax.KindAssign
	if e.Kind == syntax.KindMember {
		s.Target = e
	} else {
		s.Name = e.Text
	}
}

// compound parses `target op= value` as the assignment `target = target op value`,
// keeping the written operator in Compound so formatting preserves it. A field
// target's receiver must be a plain name chain so that reading it twice evaluates
// it once.
func (p *Parser) compound(s *syntax.Statement, start lexer.Token, e *syntax.Expression) {
	op, equal := p.peek(), p.tokens[p.at+1]
	p.assignTarget(s, start, e)
	if !plainChain(e) {
		panic(syntax.Diagnostic{Position: op.Pos, End: &equal.End, Phase: "parse",
			Message: "compound assignment '" + op.Text + "=' needs a name or a.field target whose receiver is names only; bind the receiver to a name first, or write the assignment out"})
	}
	p.at += 2
	s.Compound = op.Text
	s.Value = &syntax.Expression{Kind: syntax.KindBinary, Text: op.Text, Pos: op.Pos, Left: cloneChain(e), Right: p.expression(0)}
}

// plainChain reports whether e is a name or member access over names.
func plainChain(e *syntax.Expression) bool {
	for e.Kind == syntax.KindMember {
		e = e.Left
	}
	return e.Kind == syntax.KindName
}

// cloneChain copies a plain name chain so the read and the write are distinct nodes.
func cloneChain(e *syntax.Expression) *syntax.Expression {
	c := *e
	if e.Kind == syntax.KindMember {
		c.Left = cloneChain(e.Left)
	}
	return &c
}

func (p *Parser) compoundAssignment() bool {
	switch p.peek().Kind {
	case "+", "-", "*", "/", "%":
		return p.at+1 < len(p.tokens) && p.tokens[p.at+1].Kind == "=" && p.peek().End.Offset == p.tokens[p.at+1].Pos.Offset
	}
	return false
}
