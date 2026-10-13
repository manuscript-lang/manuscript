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

// Fixed declared call results are evidence even when their arguments contain
// literals. Generic results depending on call variables await literal context.
func (c *checker) numericCallNeedsContext(e *syntax.Expression) bool {
	if !freshNumericCall(e) {
		return false
	}
	if c.contextual(e.Left) {
		return true
	}
	var head *Info
	if e.Left.Kind == syntax.KindName && c.scope.binding(e.Left.Text) == nil {
		if symbol := c.names[e.Left.Text]; symbol != nil && symbol.Type.Kind == "function" {
			head = &Info{Type: symbol.Type, Symbol: symbol}
		}
	}
	if head == nil {
		head = c.independentArgument(e.Left)
	}
	if head == nil || head.Type.Kind != "function" {
		return true
	}
	variables := map[string]bool{}
	if head.Symbol != nil {
		for _, variable := range head.Symbol.Variables {
			variables[variable.ID] = true
		}
	}
	if head.Method != nil {
		for _, variable := range head.Method.Variables {
			variables[variable.ID] = true
		}
	}
	return !inferenceTypeKnown(head.Type.Result, variables)
}
