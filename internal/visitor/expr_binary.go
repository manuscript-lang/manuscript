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

// buildChainedBinaryExpressionAst is a helper to handle left-associative binary expressions.
func (v *ManuscriptAstVisitor) buildChainedBinaryExpressionAst(
	errorReportingCtx antlr.ParserRuleContext, // The specific context of the calling Visit method
	expressionTypeName string, // For error messages, e.g., "additive"
	children []antlr.Tree,
	assertAndGetOperand func(child antlr.Tree) (antlr.ParserRuleContext, bool), // Asserts and returns the operand context
	mapManuscriptOpToGoOp func(msOpToken antlr.Token) (goOp token.Token, knownOp bool),
) interface{} {
	if len(children) == 0 {
		v.addError(fmt.Sprintf("%s expression has no children", expressionTypeName), errorReportingCtx.GetStart())
		return &ast.BadExpr{}
	}

	// 1. Handle the first operand (left-most)
	firstOperandNode := children[0]
	firstOperandCtx, ok := assertAndGetOperand(firstOperandNode)
	if !ok {
		errMsg := fmt.Sprintf("First child of %s expression is not the expected operand type. Got: %s",
			expressionTypeName, v.safeGetNodeText(firstOperandNode))
		var errToken antlr.Token = errorReportingCtx.GetStart()
		if prc, isPrc := firstOperandNode.(antlr.ParserRuleContext); isPrc {
			errToken = prc.GetStart()
		} else if tn, isTn := firstOperandNode.(antlr.TerminalNode); isTn { // Should not be for an operand
			errToken = tn.GetSymbol()
		}
		v.addError(errMsg, errToken)
		return &ast.BadExpr{}
	}

	currentAstResult := v.Visit(firstOperandCtx)
	if currentAstResult == nil {
		return &ast.BadExpr{} // Error already added by v.Visit
	}
	leftExpr, ok := currentAstResult.(ast.Expr)
	if !ok {
		v.addError(fmt.Sprintf("Visiting left operand of %s expression did not return ast.Expr. Operand: %s",
			expressionTypeName, v.safeGetNodeText(firstOperandCtx)), firstOperandCtx.GetStart())
		return &ast.BadExpr{}
	}

	// 2. Process subsequent operator and operand pairs
	childIdx := 1
	for childIdx < len(children) {
		// Expect an operator token
		opNode := children[childIdx]
		terminalNode, ok := opNode.(antlr.TerminalNode)
		if !ok {
			errMsg := fmt.Sprintf("Expected operator token in %s expression, got %s",
				expressionTypeName, v.safeGetNodeText(opNode))
			var errToken antlr.Token = errorReportingCtx.GetStart()
			if prc, isPrc := opNode.(antlr.ParserRuleContext); isPrc { // Should not be for an operator
				errToken = prc.GetStart()
			}
			v.addError(errMsg, errToken)
			return &ast.BadExpr{}
		}
		opSymbol := terminalNode.GetSymbol()
		childIdx++

		goOp, knownOp := mapManuscriptOpToGoOp(opSymbol)
		if !knownOp {
			v.addError(fmt.Sprintf("Unknown operator '%s' in %s expression",
				opSymbol.GetText(), expressionTypeName), opSymbol)
			return &ast.BadExpr{}
		}

		if childIdx >= len(children) {
			v.addError(fmt.Sprintf("Missing right operand in %s expression after operator '%s'",
				expressionTypeName, opSymbol.GetText()), opSymbol)
			return &ast.BadExpr{}
		}
		rightOperandTreeNode := children[childIdx]
		rightOperandCtx, ok := assertAndGetOperand(rightOperandTreeNode)
		if !ok {
			errMsg := fmt.Sprintf("Expected right operand in %s expression, got %s",
				expressionTypeName, v.safeGetNodeText(rightOperandTreeNode))
			var errToken antlr.Token = opSymbol
			if prc, isPrc := rightOperandTreeNode.(antlr.ParserRuleContext); isPrc {
				errToken = prc.GetStart()
			} else if tn, isTn := rightOperandTreeNode.(antlr.TerminalNode); isTn { // Should not be for an operand
				errToken = tn.GetSymbol()
			}
			v.addError(errMsg, errToken)
			return &ast.BadExpr{}
		}
		childIdx++

		visitedRight := v.Visit(rightOperandCtx)
		if visitedRight == nil {
			return &ast.BadExpr{} // Error already added by v.Visit
		}
		rightExpr, ok := visitedRight.(ast.Expr)
		if !ok {
			v.addError(fmt.Sprintf("Visiting right operand of %s expression did not return ast.Expr. Operand: %s",
				expressionTypeName, v.safeGetNodeText(rightOperandCtx)), rightOperandCtx.GetStart())
			return &ast.BadExpr{}
		}

		leftExpr = &ast.BinaryExpr{
			X:  leftExpr,
			Op: goOp,
			Y:  rightExpr,
		}
	}
	return leftExpr
}

// VisitLogicalOrExpr handles binary OR expressions (||)
func (v *ManuscriptAstVisitor) VisitLogicalOrExpr(ctx *parser.LogicalOrExprContext) interface{} {
	assertAndGetOperand := func(child antlr.Tree) (antlr.ParserRuleContext, bool) {
		operand, ok := child.(parser.ILogicalAndExprContext)
		return operand, ok
	}
	mapOp := func(msOpToken antlr.Token) (token.Token, bool) {
		if msOpToken.GetTokenType() == parser.ManuscriptPIPE_PIPE {
			return token.LOR, true
		}
		return token.ILLEGAL, false
	}
	return v.buildChainedBinaryExpressionAst(ctx, "logical OR", ctx.GetChildren(), assertAndGetOperand, mapOp)
}

// VisitLogicalAndExpr handles binary AND expressions (&&)
func (v *ManuscriptAstVisitor) VisitLogicalAndExpr(ctx *parser.LogicalAndExprContext) interface{} {
	assertAndGetOperand := func(child antlr.Tree) (antlr.ParserRuleContext, bool) {
		operand, ok := child.(parser.IBitwiseOrExprContext)
		return operand, ok
	}
	mapOp := func(msOpToken antlr.Token) (token.Token, bool) {
		if msOpToken.GetTokenType() == parser.ManuscriptAMP_AMP {
			return token.LAND, true
		}
		return token.ILLEGAL, false
	}
	return v.buildChainedBinaryExpressionAst(ctx, "logical AND", ctx.GetChildren(), assertAndGetOperand, mapOp)
}

// VisitBitwiseOrExpr handles bitwise OR expressions (|)
func (v *ManuscriptAstVisitor) VisitBitwiseOrExpr(ctx *parser.BitwiseOrExprContext) interface{} {
	assertAndGetOperand := func(child antlr.Tree) (antlr.ParserRuleContext, bool) {
		operand, ok := child.(parser.IBitwiseXorExprContext)
		return operand, ok
	}
	mapOp := func(msOpToken antlr.Token) (token.Token, bool) {
		if msOpToken.GetTokenType() == parser.ManuscriptPIPE {
			return token.OR, true // Bitwise OR
		}
		return token.ILLEGAL, false
	}
	return v.buildChainedBinaryExpressionAst(ctx, "bitwise OR", ctx.GetChildren(), assertAndGetOperand, mapOp)
}

// VisitBitwiseXorExpr handles bitwise XOR expressions (^)
func (v *ManuscriptAstVisitor) VisitBitwiseXorExpr(ctx *parser.BitwiseXorExprContext) interface{} {
	assertAndGetOperand := func(child antlr.Tree) (antlr.ParserRuleContext, bool) {
		operand, ok := child.(parser.IBitwiseAndExprContext)
		return operand, ok
	}
	mapOp := func(msOpToken antlr.Token) (token.Token, bool) {
		if msOpToken.GetTokenType() == parser.ManuscriptCARET {
			return token.XOR, true // Bitwise XOR
		}
		return token.ILLEGAL, false
	}
	return v.buildChainedBinaryExpressionAst(ctx, "bitwise XOR", ctx.GetChildren(), assertAndGetOperand, mapOp)
}

// VisitBitwiseAndExpr handles bitwise AND expressions (&)
func (v *ManuscriptAstVisitor) VisitBitwiseAndExpr(ctx *parser.BitwiseAndExprContext) interface{} {
	assertAndGetOperand := func(child antlr.Tree) (antlr.ParserRuleContext, bool) {
		operand, ok := child.(parser.IEqualityExprContext)
		return operand, ok
	}
	mapOp := func(msOpToken antlr.Token) (token.Token, bool) {
		if msOpToken.GetTokenType() == parser.ManuscriptAMP {
			return token.AND, true // Bitwise AND
		}
		return token.ILLEGAL, false
	}
	return v.buildChainedBinaryExpressionAst(ctx, "bitwise AND", ctx.GetChildren(), assertAndGetOperand, mapOp)
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
	assertAndGetOperand := func(child antlr.Tree) (antlr.ParserRuleContext, bool) {
		operand, ok := child.(parser.IAdditiveExprContext)
		return operand, ok
	}
	mapOp := func(msOpToken antlr.Token) (token.Token, bool) {
		switch msOpToken.GetTokenType() {
		case parser.ManuscriptLSHIFT:
			return token.SHL, true // Shift Left
		case parser.ManuscriptRSHIFT:
			return token.SHR, true // Shift Right
		default:
			return token.ILLEGAL, false
		}
	}
	return v.buildChainedBinaryExpressionAst(ctx, "shift", ctx.GetChildren(), assertAndGetOperand, mapOp)
}

// VisitAdditiveExpr handles additive expressions (+, -)
func (v *ManuscriptAstVisitor) VisitAdditiveExpr(ctx *parser.AdditiveExprContext) interface{} {
	assertAndGetOperand := func(child antlr.Tree) (antlr.ParserRuleContext, bool) {
		operand, ok := child.(parser.IMultiplicativeExprContext)
		return operand, ok
	}
	mapOp := func(msOpToken antlr.Token) (token.Token, bool) {
		switch msOpToken.GetTokenType() {
		case parser.ManuscriptPLUS:
			return token.ADD, true
		case parser.ManuscriptMINUS:
			return token.SUB, true
		default:
			return token.ILLEGAL, false
		}
	}
	return v.buildChainedBinaryExpressionAst(ctx, "additive", ctx.GetChildren(), assertAndGetOperand, mapOp)
}

// VisitMultiplicativeExpr handles multiplicative expressions (*, /, %)
func (v *ManuscriptAstVisitor) VisitMultiplicativeExpr(ctx *parser.MultiplicativeExprContext) interface{} {
	assertAndGetOperand := func(child antlr.Tree) (antlr.ParserRuleContext, bool) {
		operand, ok := child.(parser.IUnaryExprContext)
		return operand, ok
	}
	mapOp := func(msOpToken antlr.Token) (token.Token, bool) {
		switch msOpToken.GetTokenType() {
		case parser.ManuscriptSTAR:
			return token.MUL, true
		case parser.ManuscriptSLASH:
			return token.QUO, true
		case parser.ManuscriptMOD:
			return token.REM, true
		default:
			return token.ILLEGAL, false
		}
	}
	return v.buildChainedBinaryExpressionAst(ctx, "multiplicative", ctx.GetChildren(), assertAndGetOperand, mapOp)
}
