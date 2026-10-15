package lower

import (
	"go/ast"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// triedValue is a nested `try` already evaluated by an early return: value is
// the Go expression that reads its success value, native its Go type or "".
type triedValue struct {
	value  ast.Expr
	native string
}

// hoistTries evaluates the `try` operands nested in a statement's value ahead
// of the statement, each with an early Go return on failure, so they do not
// unwind through deferred handlers by panic. It applies only when nothing the
// statement evaluates before a `try` can be observed to move after it: those
// parts must be literals, immutable names and earlier `try` operands.
// The statement is then lowered with each `try` replaced by its value.
func (g *generator) hoistTries(s *syntax.Statement) []ast.Stmt {
	if g.expressionDepth > 0 || s.Value == nil || s.Target != nil {
		return nil
	}
	switch s.Kind {
	case syntax.KindBind, syntax.KindAssign, syntax.KindReturn:
	case syntax.KindCall:
		if s.Value.Kind == syntax.KindMatch {
			return nil
		}
	default:
		return nil
	}
	h := triedScan{g: g}
	if !h.visit(s.Value) || len(h.tries) == 0 {
		return nil
	}
	if g.tried == nil {
		g.tried = map[*syntax.Expression]triedValue{}
	}
	var out []ast.Stmt
	for _, e := range h.tries {
		pre, value, native := g.tryReturn(e)
		tmp := g.temp()
		out = append(out, pre...)
		out = append(out, define(tmp, value), discard(ident(tmp)))
		g.tried[e] = triedValue{value: ident(tmp), native: native}
	}
	return out
}

// triedScan walks a statement value in evaluation order collecting its `try`
// operands, innermost first. effect records that something already visited
// runs code a hoisted `try` would overtake.
type triedScan struct {
	g      *generator
	tries  []*syntax.Expression
	effect bool
}

func (h *triedScan) visit(e *syntax.Expression) bool {
	if e == nil {
		return true
	}
	info := h.g.info(e)
	if info == nil || info.Folded {
		return true
	}
	switch e.Kind {
	case syntax.KindNumber, syntax.KindBool, syntax.KindUnit:
		return true
	case syntax.KindName:
		// Lambdas snapshot what they capture, so no call changes a local.
		return true
	case syntax.KindText:
		for _, part := range e.Parts {
			if part.Value != nil && !h.visit(part.Value) {
				return false
			}
		}
		// Formatting a value can run user code.
		h.effect = len(e.Parts) > 0 || h.effect
		return true
	case syntax.KindList, syntax.KindMap:
		for _, el := range e.Elements {
			if !h.visit(el) {
				return false
			}
		}
		return true
	case syntax.KindUnary:
		if e.Text == "try" {
			if _, done := h.g.tried[e]; done {
				return true
			}
			if info.ErrorSource != nil || h.effect || !h.visit(e.Right) {
				return false
			}
			// The operand runs with the try, so its own effects move with it.
			h.effect = false
			h.tries = append(h.tries, e)
			return true
		}
		if !h.visit(e.Right) {
			return false
		}
		h.effect = true
		return true
	case syntax.KindBinary:
		if e.Text == "and" || e.Text == "or" {
			return !containsTry(e.Right) && h.visit(e.Left) && h.markEffect()
		}
		if !h.visit(e.Left) || !h.visit(e.Right) {
			return false
		}
		h.effect = true
		return true
	case syntax.KindCall, syntax.KindApply:
		if !h.visit(e.Left) {
			return false
		}
		for _, a := range e.Args {
			if !h.visit(a.Value) {
				return false
			}
		}
		h.effect = true
		return true
	case syntax.KindMember:
		if !h.visit(e.Left) {
			return false
		}
		if info.Method != nil && info.Method.Accessor {
			h.effect = true
		}
		return true
	case syntax.KindIndex:
		if !h.visit(e.Left) || !h.visit(e.Right) {
			return false
		}
		h.effect = true
		return true
	}
	// Lambdas, matches and anything else are not looked into.
	if containsTry(e) {
		return false
	}
	h.effect = true
	return true
}

func (h *triedScan) markEffect() bool {
	h.effect = true
	return true
}

// containsTry reports whether e or anything it evaluates is a `try`.
func containsTry(e *syntax.Expression) bool {
	found := false
	syntax.Visitor{Expression: func(x *syntax.Expression) {
		if x.Kind == syntax.KindUnary && x.Text == "try" {
			found = true
		}
	}}.Callable(nil, []*syntax.Statement{{Kind: syntax.KindCall, Value: e}})
	return found
}
