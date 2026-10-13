package parser

import (
	"github.com/manuscript-lang/manuscript/pkg/lexer"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func (p *Parser) compoundAssignment() bool {
	switch p.peek().Kind {
	case "+", "-", "*", "/", "%":
		return p.at+1 < len(p.tokens) && p.tokens[p.at+1].Kind == "=" && p.peek().End.Offset == p.tokens[p.at+1].Pos.Offset
	}
	return false
}

func (p *Parser) failCompoundAssignment(start lexer.Token, target *syntax.Expression) {
	op, equal := p.peek(), p.tokens[p.at+1]
	d := syntax.Diagnostic{Position: op.Pos, End: &equal.End, Phase: "parse",
		Message: "compound assignment '" + op.Text + "=' is unsupported; write an explicit assignment, e.g. 'total = total " + op.Text + " x'; evaluate a field receiver only once"}
	// Only a bare name with a single name/number operand is unambiguous here.
	// Complex operands require grouping; field receivers can have side effects.
	if target.Kind == syntax.KindName && target.Text != "self" && start.Kind == lexer.Name && p.at+3 < len(p.tokens) {
		rhs, after := p.tokens[p.at+2], p.tokens[p.at+3]
		if (rhs.Kind == lexer.Name || rhs.Kind == lexer.Number) && (after.Kind == lexer.Newline || (p.inlineStatement && (after.Kind == "," || after.Kind == ")" || after.Kind == "]" || after.Kind == "}"))) {
			d.Message = "compound assignment '" + op.Text + "=' is unsupported; write '" + target.Text + " = " + target.Text + " " + op.Text + " " + rhs.Text + "' instead"
			d.Fix = &syntax.DiagnosticFix{Position: op.Pos, End: equal.End, Replacement: "= " + target.Text + " " + op.Text}
		}
	}
	panic(d)
}
