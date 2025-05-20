package visitor

import (
	"go/ast"
	"go/token"
	"manuscript-co/manuscript/internal/parser"

	"github.com/antlr4-go/antlr/v4"
)

// safeGetNodeText is an unexported helper to safely get text from an antlr.Tree node.
func (v *ManuscriptAstVisitor) safeGetNodeText(node antlr.Tree) string {
	if node == nil {
		return "<nil_node>"
	}
	if prc, ok := node.(antlr.ParserRuleContext); ok {
		return prc.GetText()
	}
	if tn, ok := node.(antlr.TerminalNode); ok {
		return tn.GetText()
	}
	// Fallback for other tree types if GetPayload() returns a token
	if p := node.GetPayload(); p != nil {
		if tok, ok := p.(antlr.Token); ok {
			return tok.GetText()
		}
	}
	return "<unknown_node_type_for_text>"
}

// VisitLogicalOrExpr handles binary OR expressions (||)
func (v *ManuscriptAstVisitor) VisitLogicalOrExpr(ctx *parser.LogicalOrExprContext) interface{} {
	return v.buildChainedBinaryExpr(ctx.GetChildren(), func(child antlr.Tree) (antlr.ParserRuleContext, bool) {
		prc, ok := child.(antlr.ParserRuleContext)
		if !ok {
			return nil, false
		}
		if c, ok := prc.(parser.ILogicalOrExprContext); ok {
			return c, true
		}
		if c, ok := prc.(parser.ILogicalAndExprContext); ok {
			return c, true
		}
		return nil, false
	}, parser.ManuscriptPIPE_PIPE, token.LOR, "logical OR", ctx.GetStart())
}

// VisitLogicalAndExpr handles binary AND expressions (&&)
func (v *ManuscriptAstVisitor) VisitLogicalAndExpr(ctx *parser.LogicalAndExprContext) interface{} {
	return v.buildChainedBinaryExpr(ctx.GetChildren(), func(child antlr.Tree) (antlr.ParserRuleContext, bool) {
		prc, ok := child.(antlr.ParserRuleContext)
		if !ok {
			return nil, false
		}
		if c, ok := prc.(parser.ILogicalAndExprContext); ok {
			return c, true
		}
		if c, ok := prc.(parser.IBitwiseOrExprContext); ok {
			return c, true
		}
		return nil, false
	}, parser.ManuscriptAMP_AMP, token.LAND, "logical AND", ctx.GetStart())
}

// VisitBitwiseOrExpr handles bitwise OR expressions (|)
func (v *ManuscriptAstVisitor) VisitBitwiseOrExpr(ctx *parser.BitwiseOrExprContext) interface{} {
	return v.buildChainedBinaryExpr(ctx.GetChildren(), func(child antlr.Tree) (antlr.ParserRuleContext, bool) {
		prc, ok := child.(antlr.ParserRuleContext)
		if !ok {
			return nil, false
		}
		if c, ok := prc.(parser.IBitwiseOrExprContext); ok {
			return c, true
		}
		if c, ok := prc.(parser.IBitwiseXorExprContext); ok {
			return c, true
		}
		return nil, false
	}, parser.ManuscriptPIPE, token.OR, "bitwise OR", ctx.GetStart())
}

// VisitBitwiseXorExpr handles bitwise XOR expressions (^)
func (v *ManuscriptAstVisitor) VisitBitwiseXorExpr(ctx *parser.BitwiseXorExprContext) interface{} {
	return v.buildChainedBinaryExpr(ctx.GetChildren(), func(child antlr.Tree) (antlr.ParserRuleContext, bool) {
		prc, ok := child.(antlr.ParserRuleContext)
		if !ok {
			return nil, false
		}
		if c, ok := prc.(parser.IBitwiseXorExprContext); ok {
			return c, true
		}
		if c, ok := prc.(parser.IBitwiseAndExprContext); ok {
			return c, true
		}
		return nil, false
	}, parser.ManuscriptCARET, token.XOR, "bitwise XOR", ctx.GetStart())
}

// VisitBitwiseAndExpr handles bitwise AND expressions (&)
func (v *ManuscriptAstVisitor) VisitBitwiseAndExpr(ctx *parser.BitwiseAndExprContext) interface{} {
	return v.buildChainedBinaryExpr(ctx.GetChildren(), func(child antlr.Tree) (antlr.ParserRuleContext, bool) {
		prc, ok := child.(antlr.ParserRuleContext)
		if !ok {
			return nil, false
		}
		if c, ok := prc.(parser.IBitwiseAndExprContext); ok {
			return c, true
		}
		if c, ok := prc.(parser.IEqualityExprContext); ok {
			return c, true
		}
		return nil, false
	}, parser.ManuscriptAMP, token.AND, "bitwise AND", ctx.GetStart())
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
			visited := v.Visit(c.ShiftExpr())
			if expr, ok := visited.(ast.Expr); ok {
				operands = append(operands, expr)
			}
		}
	}
	recur(ctx)
	return operands, ops
}

// VisitEqualityExpr handles equality expressions (==, !=)
func (v *ManuscriptAstVisitor) VisitEqualityExpr(ctx *parser.EqualityExprContext) interface{} {
	operands, ops := v.flattenEqualityChain(ctx)
	if len(operands) == 0 {
		v.addError("Equality expression has no operands", ctx.GetStart())
		return &ast.BadExpr{}
	}
	if len(ops) != len(operands)-1 {
		v.addError("Mismatch in operands and operators in equality expr", ctx.GetStart())
		return &ast.BadExpr{}
	}
	var expr ast.Expr
	for i := 0; i < len(ops); i++ {
		cmp := &ast.BinaryExpr{
			X:  operands[i],
			Op: ops[i],
			Y:  operands[i+1],
		}
		if expr == nil {
			expr = cmp
		} else {
			expr = &ast.BinaryExpr{
				X:  expr,
				Op: token.LAND,
				Y:  cmp,
			}
		}
	}
	if expr == nil {
		return operands[0]
	}
	return expr
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

// VisitComparisonExpr handles comparison expressions (<, <=, >, >=)
func (v *ManuscriptAstVisitor) VisitComparisonExpr(ctx *parser.ComparisonExprContext) interface{} {
	operands, ops := v.flattenComparisonChain(ctx)
	if len(operands) == 0 {
		v.addError("Comparison expression has no operands", ctx.GetStart())
		return &ast.BadExpr{}
	}
	if len(ops) != len(operands)-1 {
		v.addError("Mismatch in operands and operators in comparison expr", ctx.GetStart())
		return &ast.BadExpr{}
	}
	var expr ast.Expr
	for i := 0; i < len(ops); i++ {
		cmp := &ast.BinaryExpr{
			X:  operands[i],
			Op: ops[i],
			Y:  operands[i+1],
		}
		if expr == nil {
			expr = cmp
		} else {
			expr = &ast.BinaryExpr{
				X:  expr,
				Op: token.LAND,
				Y:  cmp,
			}
		}
	}
	if expr == nil {
		return operands[0]
	}
	return expr
}

// VisitShiftExpr handles shift expressions (<<, >>)
func (v *ManuscriptAstVisitor) VisitShiftExpr(ctx *parser.ShiftExprContext) interface{} {
	return v.buildChainedBinaryExprMultiOp(ctx.GetChildren(), func(child antlr.Tree) (antlr.ParserRuleContext, bool) {
		prc, ok := child.(antlr.ParserRuleContext)
		if !ok {
			return nil, false
		}
		if c, ok := prc.(parser.IShiftExprContext); ok {
			return c, true
		}
		if c, ok := prc.(parser.IAdditiveExprContext); ok {
			return c, true
		}
		return nil, false
	}, map[int]token.Token{
		parser.ManuscriptLSHIFT: token.SHL,
		parser.ManuscriptRSHIFT: token.SHR,
	}, "shift", ctx.GetStart())
}

// VisitAdditiveExpr handles additive expressions (+, -)
func (v *ManuscriptAstVisitor) VisitAdditiveExpr(ctx *parser.AdditiveExprContext) interface{} {
	return v.buildChainedBinaryExprMultiOp(ctx.GetChildren(), func(child antlr.Tree) (antlr.ParserRuleContext, bool) {
		prc, ok := child.(antlr.ParserRuleContext)
		if !ok {
			return nil, false
		}
		if c, ok := prc.(parser.IAdditiveExprContext); ok {
			return c, true
		}
		if c, ok := prc.(parser.IMultiplicativeExprContext); ok {
			return c, true
		}
		return nil, false
	}, map[int]token.Token{
		parser.ManuscriptPLUS:  token.ADD,
		parser.ManuscriptMINUS: token.SUB,
	}, "additive", ctx.GetStart())
}

// VisitMultiplicativeExpr handles multiplicative expressions (*, /, %)
func (v *ManuscriptAstVisitor) VisitMultiplicativeExpr(ctx *parser.MultiplicativeExprContext) interface{} {
	return v.buildChainedBinaryExprMultiOp(ctx.GetChildren(), func(child antlr.Tree) (antlr.ParserRuleContext, bool) {
		prc, ok := child.(antlr.ParserRuleContext)
		if !ok {
			return nil, false
		}
		if c, ok := prc.(parser.IMultiplicativeExprContext); ok {
			return c, true
		}
		if c, ok := prc.(parser.IUnaryExprContext); ok {
			return c, true
		}
		return nil, false
	}, map[int]token.Token{
		parser.ManuscriptSTAR:  token.MUL,
		parser.ManuscriptSLASH: token.QUO,
		parser.ManuscriptMOD:   token.REM,
	}, "multiplicative", ctx.GetStart())
}

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
