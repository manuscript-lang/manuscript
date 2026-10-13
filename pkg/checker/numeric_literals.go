package checker

import (
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Only numeric literal expressions can borrow a known width. Already typed
// names, fields and call results retain their own type and never auto-promote.
func numericLiteralExpression(e *syntax.Expression) bool {
	if e == nil {
		return false
	}
	if e.Kind == syntax.KindNumber {
		return !strings.HasSuffix(e.Text, "d")
	}
	if e.Kind == syntax.KindUnary && (e.Text == "+" || e.Text == "-") {
		return numericLiteralExpression(e.Right)
	}
	if e.Kind == syntax.KindBinary && strings.Contains("|+|-|*|/|%|", "|"+e.Text+"|") {
		return numericLiteralExpression(e.Left) && numericLiteralExpression(e.Right)
	}
	return false
}

func numericLiteralContext(e *syntax.Expression, expected *Type) *Type {
	if expected != nil && (expected.ID == "Int64" || expected.ID == "Float64") && numericLiteralExpression(e) {
		return expected
	}
	return nil
}

func containsWideNumeric(t *Type) bool {
	seen := map[*Type]bool{}
	var visit func(*Type) bool
	visit = func(t *Type) bool {
		if t == nil || seen[t] {
			return false
		}
		seen[t] = true
		if t.ID == "Int64" || t.ID == "Float64" {
			return true
		}
		for _, arg := range t.Args {
			if visit(arg) {
				return true
			}
		}
		for _, param := range t.Params {
			if visit(param.Type) {
				return true
			}
		}
		return visit(t.Result)
	}
	return visit(t)
}

func (c *checker) numericOperands(e *syntax.Expression, expected *Type) (*Info, *Info) {
	if numericLiteralContext(e, expected) != nil {
		return c.expression(e.Left, numericLiteralContext(e.Left, expected)), c.expression(e.Right, numericLiteralContext(e.Right, expected))
	}
	if numericLiteralExpression(e.Left) && !numericLiteralExpression(e.Right) {
		right := c.expression(e.Right, nil)
		return c.expression(e.Left, numericLiteralContext(e.Left, right.Type)), right
	}
	left := c.expression(e.Left, numericLiteralContext(e.Left, expected))
	return left, c.expression(e.Right, numericLiteralContext(e.Right, left.Type))
}

// A fresh call can pass literal context through generic results. This never
// follows names or fields back to their initializers: bound values keep their type.
func freshNumericCall(e *syntax.Expression) bool {
	if e == nil || e.Kind != syntax.KindCall {
		return false
	}
	for _, arg := range e.Args {
		if numericLiteralExpression(arg.Value) || freshNumericCall(arg.Value) {
			return true
		}
	}
	return false
}
