package visitor

import (
	"fmt"
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
		c, ok := child.(parser.ILogicalAndExprContext)
		return c, ok
	}, parser.ManuscriptPIPE_PIPE, token.LOR, "logical OR", ctx.GetStart())
}

// VisitLogicalAndExpr handles binary AND expressions (&&)
func (v *ManuscriptAstVisitor) VisitLogicalAndExpr(ctx *parser.LogicalAndExprContext) interface{} {
	return v.buildChainedBinaryExpr(ctx.GetChildren(), func(child antlr.Tree) (antlr.ParserRuleContext, bool) {
		c, ok := child.(parser.IBitwiseOrExprContext)
		return c, ok
	}, parser.ManuscriptAMP_AMP, token.LAND, "logical AND", ctx.GetStart())
}

// VisitBitwiseOrExpr handles bitwise OR expressions (|)
func (v *ManuscriptAstVisitor) VisitBitwiseOrExpr(ctx *parser.BitwiseOrExprContext) interface{} {
	return v.buildChainedBinaryExpr(ctx.GetChildren(), func(child antlr.Tree) (antlr.ParserRuleContext, bool) {
		c, ok := child.(parser.IBitwiseXorExprContext)
		return c, ok
	}, parser.ManuscriptPIPE, token.OR, "bitwise OR", ctx.GetStart())
}

// VisitBitwiseXorExpr handles bitwise XOR expressions (^)
func (v *ManuscriptAstVisitor) VisitBitwiseXorExpr(ctx *parser.BitwiseXorExprContext) interface{} {
	return v.buildChainedBinaryExpr(ctx.GetChildren(), func(child antlr.Tree) (antlr.ParserRuleContext, bool) {
		c, ok := child.(parser.IBitwiseAndExprContext)
		return c, ok
	}, parser.ManuscriptCARET, token.XOR, "bitwise XOR", ctx.GetStart())
}

// VisitBitwiseAndExpr handles bitwise AND expressions (&)
func (v *ManuscriptAstVisitor) VisitBitwiseAndExpr(ctx *parser.BitwiseAndExprContext) interface{} {
	return v.buildChainedBinaryExpr(ctx.GetChildren(), func(child antlr.Tree) (antlr.ParserRuleContext, bool) {
		c, ok := child.(parser.IEqualityExprContext)
		return c, ok
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

// VisitEqualityExpr handles equality expressions (==, !=)
// For chained expressions like a == b == c, it compiles to (a == b) && (b == c)
func (v *ManuscriptAstVisitor) VisitEqualityExpr(ctx *parser.EqualityExprContext) interface{} {
	children := ctx.GetChildren()
	if len(children) == 0 {
		v.addError("Equality expression has no children", ctx.GetStart())
		return &ast.BadExpr{}
	}

	// Initial operand: this will be the X of the first comparison, or the entire expression if no operators.
	firstOperandAntlrCtx, ok := children[0].(parser.IComparisonExprContext)
	if !ok {
		errToken := ctx.GetStart()
		if len(children) > 0 {
			if prc, isPrc := children[0].(antlr.ParserRuleContext); isPrc {
				errToken = prc.GetStart()
			} else if tn, isTn := children[0].(antlr.TerminalNode); isTn {
				errToken = tn.GetSymbol()
			}
		}
		v.addError(fmt.Sprintf("First child of equality expression is not a comparison expression. Got: %s", v.safeGetNodeText(children[0])), errToken)
		return &ast.BadExpr{}
	}

	visitedFirstOperand := v.Visit(firstOperandAntlrCtx)
	if visitedFirstOperand == nil {
		return &ast.BadExpr{}
	} // Error added by Visit

	currentLHSExpr, ok := visitedFirstOperand.(ast.Expr)
	if !ok {
		v.addError(fmt.Sprintf("Visiting first operand of equality expr did not return ast.Expr. Operand: %s", v.safeGetNodeText(firstOperandAntlrCtx)), firstOperandAntlrCtx.GetStart())
		return &ast.BadExpr{}
	}

	if len(children) == 1 { // Only one operand, no operator
		return currentLHSExpr
	}

	var overallChainResult ast.Expr
	childIdx := 1 // Start with the first operator

	for childIdx < len(children) {
		// Expect an operator token
		opNode, ok := children[childIdx].(antlr.TerminalNode)
		if !ok {
			errToken := ctx.GetStart()
			if len(children) > childIdx {
				if prc, isPrc := children[childIdx].(antlr.ParserRuleContext); isPrc {
					errToken = prc.GetStart()
				} else if tn, isTn := children[childIdx].(antlr.TerminalNode); isTn {
					errToken = tn.GetSymbol()
				}
			}
			v.addError(fmt.Sprintf("Expected operator token in equality expression at child index %d, got %s", childIdx, v.safeGetNodeText(children[childIdx])), errToken)
			return &ast.BadExpr{}
		}
		opSymbol := opNode.GetSymbol()
		childIdx++

		goOp, knownOp := v.mapEqualityOpToken(opSymbol)
		if !knownOp {
			v.addError(fmt.Sprintf("Unknown equality operator '%s'", opSymbol.GetText()), opSymbol)
			return &ast.BadExpr{}
		}

		if childIdx >= len(children) {
			v.addError(fmt.Sprintf("Missing right operand in equality expression after operator '%s'", opSymbol.GetText()), opSymbol)
			return &ast.BadExpr{}
		}

		// Expect a right operand context
		rightOperandAntlrCtx, ok := children[childIdx].(parser.IComparisonExprContext)
		if !ok {
			errToken := opSymbol
			if len(children) > childIdx {
				if prc, isPrc := children[childIdx].(antlr.ParserRuleContext); isPrc {
					errToken = prc.GetStart()
				} else if tn, isTn := children[childIdx].(antlr.TerminalNode); isTn {
					errToken = tn.GetSymbol()
				}
			}
			v.addError(fmt.Sprintf("Expected right operand (comparison expression) in equality expression at child index %d, got %s", childIdx, v.safeGetNodeText(children[childIdx])), errToken)
			return &ast.BadExpr{}
		}
		childIdx++

		visitedRightOperand := v.Visit(rightOperandAntlrCtx)
		if visitedRightOperand == nil {
			return &ast.BadExpr{}
		}

		currentRHSExpr, ok := visitedRightOperand.(ast.Expr)
		if !ok {
			v.addError(fmt.Sprintf("Visiting right operand of equality expr did not return ast.Expr. Operand: %s", v.safeGetNodeText(rightOperandAntlrCtx)), rightOperandAntlrCtx.GetStart())
			return &ast.BadExpr{}
		}

		// Form the current comparison segment, e.g., (currentLHSExpr == currentRHSExpr)
		segmentComparison := &ast.BinaryExpr{
			X:  currentLHSExpr,
			Op: goOp,
			Y:  currentRHSExpr,
		}

		if overallChainResult == nil { // This is the first comparison in the chain
			overallChainResult = segmentComparison
		} else { // Subsequent comparison, combine with &&
			overallChainResult = &ast.BinaryExpr{
				X:  overallChainResult,
				Op: token.LAND, // &&
				Y:  segmentComparison,
			}
		}
		// The right operand of this segment becomes the left for the next segment.
		currentLHSExpr = currentRHSExpr
	}
	return overallChainResult
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
// For chained expressions like a < b > c, it compiles to (a < b) && (b > c)
func (v *ManuscriptAstVisitor) VisitComparisonExpr(ctx *parser.ComparisonExprContext) interface{} {
	children := ctx.GetChildren()
	if len(children) == 0 {
		v.addError("Comparison expression has no children", ctx.GetStart())
		return &ast.BadExpr{}
	}

	firstOperandAntlrCtx, ok := children[0].(parser.IShiftExprContext)
	if !ok {
		errToken := ctx.GetStart()
		if len(children) > 0 {
			if prc, isPrc := children[0].(antlr.ParserRuleContext); isPrc {
				errToken = prc.GetStart()
			} else if tn, isTn := children[0].(antlr.TerminalNode); isTn {
				errToken = tn.GetSymbol()
			}
		}
		v.addError(fmt.Sprintf("First child of comparison expression is not a shift expression. Got: %s", v.safeGetNodeText(children[0])), errToken)
		return &ast.BadExpr{}
	}

	visitedFirstOperand := v.Visit(firstOperandAntlrCtx)
	if visitedFirstOperand == nil {
		return &ast.BadExpr{}
	}

	currentLHSExpr, ok := visitedFirstOperand.(ast.Expr)
	if !ok {
		v.addError(fmt.Sprintf("Visiting first operand of comparison expr did not return ast.Expr. Operand: %s", v.safeGetNodeText(firstOperandAntlrCtx)), firstOperandAntlrCtx.GetStart())
		return &ast.BadExpr{}
	}

	if len(children) == 1 { // Only one operand, no operator
		return currentLHSExpr
	}

	var overallChainResult ast.Expr
	childIdx := 1 // Start with the first operator

	for childIdx < len(children) {
		opNode, ok := children[childIdx].(antlr.TerminalNode)
		if !ok {
			errToken := ctx.GetStart()
			if len(children) > childIdx {
				if prc, isPrc := children[childIdx].(antlr.ParserRuleContext); isPrc {
					errToken = prc.GetStart()
				} else if tn, isTn := children[childIdx].(antlr.TerminalNode); isTn {
					errToken = tn.GetSymbol()
				}
			}
			v.addError(fmt.Sprintf("Expected operator token in comparison expression at child index %d, got %s", childIdx, v.safeGetNodeText(children[childIdx])), errToken)
			return &ast.BadExpr{}
		}
		opSymbol := opNode.GetSymbol()
		childIdx++

		goOp, knownOp := v.mapComparisonOpToken(opSymbol)
		if !knownOp {
			v.addError(fmt.Sprintf("Unknown comparison operator '%s'", opSymbol.GetText()), opSymbol)
			return &ast.BadExpr{}
		}

		if childIdx >= len(children) {
			v.addError(fmt.Sprintf("Missing right operand in comparison expression after operator '%s'", opSymbol.GetText()), opSymbol)
			return &ast.BadExpr{}
		}

		rightOperandAntlrCtx, ok := children[childIdx].(parser.IShiftExprContext)
		if !ok {
			errToken := opSymbol
			if len(children) > childIdx {
				if prc, isPrc := children[childIdx].(antlr.ParserRuleContext); isPrc {
					errToken = prc.GetStart()
				} else if tn, isTn := children[childIdx].(antlr.TerminalNode); isTn {
					errToken = tn.GetSymbol()
				}
			}
			v.addError(fmt.Sprintf("Expected right operand (shift expression) in comparison expression at child index %d, got %s", childIdx, v.safeGetNodeText(children[childIdx])), errToken)
			return &ast.BadExpr{}
		}
		childIdx++

		visitedRightOperand := v.Visit(rightOperandAntlrCtx)
		if visitedRightOperand == nil {
			return &ast.BadExpr{}
		}

		currentRHSExpr, ok := visitedRightOperand.(ast.Expr)
		if !ok {
			v.addError(fmt.Sprintf("Visiting right operand of comparison expr did not return ast.Expr. Operand: %s", v.safeGetNodeText(rightOperandAntlrCtx)), rightOperandAntlrCtx.GetStart())
			return &ast.BadExpr{}
		}

		segmentComparison := &ast.BinaryExpr{
			X:  currentLHSExpr,
			Op: goOp,
			Y:  currentRHSExpr,
		}

		if overallChainResult == nil {
			overallChainResult = segmentComparison
		} else {
			overallChainResult = &ast.BinaryExpr{
				X:  overallChainResult,
				Op: token.LAND, // &&
				Y:  segmentComparison,
			}
		}
		currentLHSExpr = currentRHSExpr
	}
	return overallChainResult
}

// VisitShiftExpr handles shift expressions (<<, >>)
func (v *ManuscriptAstVisitor) VisitShiftExpr(ctx *parser.ShiftExprContext) interface{} {
	return v.buildChainedBinaryExprMultiOp(ctx.GetChildren(), func(child antlr.Tree) (antlr.ParserRuleContext, bool) {
		c, ok := child.(parser.IAdditiveExprContext)
		return c, ok
	}, map[int]token.Token{
		parser.ManuscriptLSHIFT: token.SHL,
		parser.ManuscriptRSHIFT: token.SHR,
	}, "shift", ctx.GetStart())
}

// VisitAdditiveExpr handles additive expressions (+, -)
func (v *ManuscriptAstVisitor) VisitAdditiveExpr(ctx *parser.AdditiveExprContext) interface{} {
	return v.buildChainedBinaryExprMultiOp(ctx.GetChildren(), func(child antlr.Tree) (antlr.ParserRuleContext, bool) {
		c, ok := child.(parser.IMultiplicativeExprContext)
		return c, ok
	}, map[int]token.Token{
		parser.ManuscriptPLUS:  token.ADD,
		parser.ManuscriptMINUS: token.SUB,
	}, "additive", ctx.GetStart())
}

// VisitMultiplicativeExpr handles multiplicative expressions (*, /, %)
func (v *ManuscriptAstVisitor) VisitMultiplicativeExpr(ctx *parser.MultiplicativeExprContext) interface{} {
	return v.buildChainedBinaryExprMultiOp(ctx.GetChildren(), func(child antlr.Tree) (antlr.ParserRuleContext, bool) {
		c, ok := child.(parser.IUnaryExprContext)
		return c, ok
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
