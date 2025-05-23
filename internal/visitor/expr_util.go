package visitor

import (
	"go/ast"
	"go/token"
	"manuscript-co/manuscript/internal/parser"

	"github.com/antlr4-go/antlr/v4"
)

func (v *ManuscriptAstVisitor) buildChainedBinaryExpr(
	children []antlr.Tree,
	assertAndGetOperand func(child antlr.Tree) (antlr.ParserRuleContext, bool),
	opTokenType int,
	goOp token.Token,
	exprName string,
	errTok antlr.Token,
) interface{} {
	if len(children) == 0 {
		v.addError(exprName+" expression has no children", errTok)
		return &ast.BadExpr{}
	}
	first, ok := assertAndGetOperand(children[0])
	if !ok {
		v.addError("First child of "+exprName+" expression is not the expected operand type", errTok)
		return &ast.BadExpr{}
	}
	lhs := v.Visit(first)
	if lhs == nil {
		return &ast.BadExpr{}
	}
	lexpr, ok := lhs.(ast.Expr)
	if !ok {
		v.addError("Visiting left operand of "+exprName+" expression did not return ast.Expr", first.GetStart())
		return &ast.BadExpr{}
	}
	if len(children) == 1 {
		return lexpr
	}
	idx := 1
	for idx < len(children) {
		op, ok := children[idx].(antlr.TerminalNode)
		if !ok || op.GetSymbol().GetTokenType() != opTokenType {
			v.addError("Expected operator token in "+exprName+" expression", errTok)
			return &ast.BadExpr{}
		}
		idx++
		if idx >= len(children) {
			v.addError("Missing right operand in "+exprName+" expression", op.GetSymbol())
			return &ast.BadExpr{}
		}
		right, ok := assertAndGetOperand(children[idx])
		if !ok {
			v.addError("Expected right operand in "+exprName+" expression", op.GetSymbol())
			return &ast.BadExpr{}
		}
		idx++
		rval := v.Visit(right)
		if rval == nil {
			return &ast.BadExpr{}
		}
		rexpr, ok := rval.(ast.Expr)
		if !ok {
			v.addError("Visiting right operand of "+exprName+" expression did not return ast.Expr", right.GetStart())
			return &ast.BadExpr{}
		}
		lexpr = &ast.BinaryExpr{X: lexpr, Op: goOp, Y: rexpr}
	}
	return lexpr
}

func (v *ManuscriptAstVisitor) buildChainedBinaryExprMultiOp(
	children []antlr.Tree,
	assertAndGetOperand func(child antlr.Tree) (antlr.ParserRuleContext, bool),
	opMap map[int]token.Token,
	exprName string,
	errTok antlr.Token,
) interface{} {
	if len(children) == 0 {
		v.addError(exprName+" expression has no children", errTok)
		return &ast.BadExpr{}
	}
	first, ok := assertAndGetOperand(children[0])
	if !ok {
		v.addError("First child of "+exprName+" expression is not the expected operand type", errTok)
		return &ast.BadExpr{}
	}
	lhs := v.Visit(first)
	if lhs == nil {
		return &ast.BadExpr{}
	}
	lexpr, ok := lhs.(ast.Expr)
	if !ok {
		v.addError("Visiting left operand of "+exprName+" expression did not return ast.Expr", first.GetStart())
		return &ast.BadExpr{}
	}
	if len(children) == 1 {
		return lexpr
	}
	idx := 1
	for idx < len(children) {
		op, ok := children[idx].(antlr.TerminalNode)
		var goOp token.Token
		var found bool
		if ok {
			goOp, found = opMap[op.GetSymbol().GetTokenType()]
		}
		if !ok || !found {
			v.addError("Expected operator token in "+exprName+" expression", errTok)
			return &ast.BadExpr{}
		}
		idx++
		if idx >= len(children) {
			v.addError("Missing right operand in "+exprName+" expression", op.GetSymbol())
			return &ast.BadExpr{}
		}
		right, ok := assertAndGetOperand(children[idx])
		if !ok {
			v.addError("Expected right operand in "+exprName+" expression", op.GetSymbol())
			return &ast.BadExpr{}
		}
		idx++
		rval := v.Visit(right)
		if rval == nil {
			return &ast.BadExpr{}
		}
		rexpr, ok := rval.(ast.Expr)
		if !ok {
			v.addError("Visiting right operand of "+exprName+" expression did not return ast.Expr", right.GetStart())
			return &ast.BadExpr{}
		}
		lexpr = &ast.BinaryExpr{X: lexpr, Op: goOp, Y: rexpr}
	}
	return lexpr
}

// mapEqualityOpToken maps Manuscript equality operator tokens to Go's token.Token
func (v *ManuscriptAstVisitor) mapEqualityOpToken(msOpToken antlr.Token) (token.Token, bool) {
	switch msOpToken.GetTokenType() {
	case parser.ManuscriptEQUALS_EQUALS:
		return token.EQL, true
	case parser.ManuscriptNEQ:
		return token.NEQ, true
	default:
		return token.ILLEGAL, false
	}
}

// flattenEqualityChain recursively flattens a left-recursive equalityExpr tree into operands and operators.
func (v *ManuscriptAstVisitor) flattenEqualityChain(ctx *parser.EqualityExprContext) ([]ast.Expr, []token.Token) {
	var operands []ast.Expr
	var ops []token.Token
	var recur func(c *parser.EqualityExprContext)
	recur = func(c *parser.EqualityExprContext) {
		if c == nil {
			return
		}
		left := c.GetLeft()
		op := c.GetOp()
		right := c.GetRight()
		if left != nil && op != nil && right != nil {
			recur(left.(*parser.EqualityExprContext))
			// operator
			goOp, knownOp := v.mapEqualityOpToken(op)
			if !knownOp {
				ops = append(ops, token.ILLEGAL)
			} else {
				ops = append(ops, goOp)
			}
			// right operand
			visited := v.Visit(right)
			if expr, ok := visited.(ast.Expr); ok {
				operands = append(operands, expr)
			}
		} else {
			// base case: just a comparisonExpr
			visited := v.Visit(c.ComparisonExpr())
			if expr, ok := visited.(ast.Expr); ok {
				operands = append(operands, expr)
			}
		}
	}
	recur(ctx)
	// The recursion above appends operands in left-to-right order for the base, but for chains, the leftmost operand is only appended at the end, so reverse operands and ops if needed
	if len(ops) > 0 {
		// For left-recursive, operands are in reverse order except the first
		// e.g. for a == b == c: operands = [a, b, c], ops = [==, ==]
		// But our recursion appends as [a, b, c], so no need to reverse
	}
	return operands, ops
}

// flattenComparisonChain recursively flattens a left-recursive comparisonExpr tree into operands and operators.
func (v *ManuscriptAstVisitor) flattenComparisonChain(ctx *parser.ComparisonExprContext) ([]ast.Expr, []token.Token) {
	var operands []ast.Expr
	var ops []token.Token
	var recur func(c *parser.ComparisonExprContext)
	recur = func(c *parser.ComparisonExprContext) {
		if c == nil {
			return
		}
		left := c.GetLeft()
		op := c.GetOp()
		right := c.GetRight()
		if left != nil && op != nil && right != nil {
			recur(left.(*parser.ComparisonExprContext))
			// Extract the actual operator token from op (IComparisonOpContext)
			var opToken antlr.Token
			if opNode, ok := op.(*parser.ComparisonOpContext); ok {
				for i := 0; i < opNode.GetChildCount(); i++ {
					if tn, ok := opNode.GetChild(i).(antlr.TerminalNode); ok {
						opToken = tn.GetSymbol()
						break
					}
				}
			}
			goOp, knownOp := v.mapComparisonOpToken(opToken)
			if !knownOp {
				ops = append(ops, token.ILLEGAL)
			} else {
				ops = append(ops, goOp)
			}
			visited := v.Visit(right)
			if expr, ok := visited.(ast.Expr); ok {
				operands = append(operands, expr)
			}
		} else {
			visited := v.Visit(c.AdditiveExpr())
			if expr, ok := visited.(ast.Expr); ok {
				operands = append(operands, expr)
			}
		}
	}
	recur(ctx)
	return operands, ops
}

// mapComparisonOpToken maps Manuscript comparison operator tokens to Go's token.Token
func (v *ManuscriptAstVisitor) mapComparisonOpToken(msOpToken antlr.Token) (token.Token, bool) {
	switch msOpToken.GetTokenType() {
	case parser.ManuscriptLT:
		return token.LSS, true
	case parser.ManuscriptLT_EQUALS:
		return token.LEQ, true
	case parser.ManuscriptGT:
		return token.GTR, true
	case parser.ManuscriptGT_EQUALS:
		return token.GEQ, true
	default:
		return token.ILLEGAL, false
	}
}
