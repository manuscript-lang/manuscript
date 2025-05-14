package visitor

import (
	"go/ast"
	"go/token"
	"log"
	"manuscript-co/manuscript/internal/parser"
)

// VisitLogicalOrExpr handles binary OR expressions (||)
func (v *ManuscriptAstVisitor) VisitLogicalOrExpr(ctx *parser.LogicalOrExprContext) interface{} {
	// Always visit the left operand
	leftResult := v.Visit(ctx.GetLeft())
	leftExpr, ok := leftResult.(ast.Expr)
	if !ok {
		log.Printf("Error: Left operand in logical OR expression is not an ast.Expr. Got: %T", leftResult)
		return &ast.BadExpr{}
	}

	// If there's no operator, just return the left expression (pass-through)
	if ctx.GetOp() == nil {
		return leftExpr
	}

	// Visit the right operand
	rightResult := v.Visit(ctx.GetRight())
	rightExpr, ok := rightResult.(ast.Expr)
	if !ok {
		log.Printf("Error: Right operand in logical OR expression is not an ast.Expr. Got: %T", rightResult)
		return &ast.BadExpr{}
	}

	// Create binary expression
	return &ast.BinaryExpr{
		X:  leftExpr,
		Op: token.LOR, // Logical OR in Go
		Y:  rightExpr,
	}
}

// VisitLogicalAndExpr handles binary AND expressions (&&)
func (v *ManuscriptAstVisitor) VisitLogicalAndExpr(ctx *parser.LogicalAndExprContext) interface{} {
	// Always visit the left operand
	leftResult := v.Visit(ctx.GetLeft())
	leftExpr, ok := leftResult.(ast.Expr)
	if !ok {
		log.Printf("Error: Left operand in logical AND expression is not an ast.Expr. Got: %T", leftResult)
		return &ast.BadExpr{}
	}

	// If there's no operator, just return the left expression (pass-through)
	if ctx.GetOp() == nil {
		return leftExpr
	}

	// Visit the right operand
	rightResult := v.Visit(ctx.GetRight())
	rightExpr, ok := rightResult.(ast.Expr)
	if !ok {
		log.Printf("Error: Right operand in logical AND expression is not an ast.Expr. Got: %T", rightResult)
		return &ast.BadExpr{}
	}

	// Create binary expression
	return &ast.BinaryExpr{
		X:  leftExpr,
		Op: token.LAND, // Logical AND in Go
		Y:  rightExpr,
	}
}

// VisitEqualityExpr handles equality expressions (==, !=)
func (v *ManuscriptAstVisitor) VisitEqualityExpr(ctx *parser.EqualityExprContext) interface{} {
	// Always visit the left operand
	leftResult := v.Visit(ctx.GetLeft())
	leftExpr, ok := leftResult.(ast.Expr)
	if !ok {
		log.Printf("Error: Left operand in equality expression is not an ast.Expr. Got: %T", leftResult)
		return &ast.BadExpr{}
	}

	// If there's no operator, just return the left expression (pass-through)
	if ctx.GetOp() == nil {
		return leftExpr
	}

	// Visit the right operand
	rightResult := v.Visit(ctx.GetRight())
	rightExpr, ok := rightResult.(ast.Expr)
	if !ok {
		log.Printf("Error: Right operand in equality expression is not an ast.Expr. Got: %T", rightResult)
		return &ast.BadExpr{}
	}

	// Create binary expression based on the operator
	var goOp token.Token
	switch ctx.GetOp().GetTokenType() {
	case parser.ManuscriptEQUALS_EQUALS:
		goOp = token.EQL // == in Go
	case parser.ManuscriptNEQ:
		goOp = token.NEQ // != in Go
	default:
		log.Printf("Error: Unknown equality operator: %s", ctx.GetOp().GetText())
		return &ast.BadExpr{}
	}

	return &ast.BinaryExpr{
		X:  leftExpr,
		Op: goOp,
		Y:  rightExpr,
	}
}

// VisitComparisonExpr handles comparison expressions (<, <=, >, >=)
func (v *ManuscriptAstVisitor) VisitComparisonExpr(ctx *parser.ComparisonExprContext) interface{} {
	// Always visit the left operand
	leftResult := v.Visit(ctx.GetLeft())
	leftExpr, ok := leftResult.(ast.Expr)
	if !ok {
		log.Printf("Error: Left operand in comparison expression is not an ast.Expr. Got: %T", leftResult)
		return &ast.BadExpr{}
	}

	// If there's no operator, just return the left expression (pass-through)
	if ctx.GetOp() == nil {
		return leftExpr
	}

	// Visit the right operand
	rightResult := v.Visit(ctx.GetRight())
	rightExpr, ok := rightResult.(ast.Expr)
	if !ok {
		log.Printf("Error: Right operand in comparison expression is not an ast.Expr. Got: %T", rightResult)
		return &ast.BadExpr{}
	}

	// Create binary expression based on the operator
	var goOp token.Token
	switch ctx.GetOp().GetTokenType() {
	case parser.ManuscriptLT:
		goOp = token.LSS // < in Go
	case parser.ManuscriptLT_EQUALS:
		goOp = token.LEQ // <= in Go
	case parser.ManuscriptGT:
		goOp = token.GTR // > in Go
	case parser.ManuscriptGT_EQUALS:
		goOp = token.GEQ // >= in Go
	default:
		log.Printf("Error: Unknown comparison operator: %s", ctx.GetOp().GetText())
		return &ast.BadExpr{}
	}

	return &ast.BinaryExpr{
		X:  leftExpr,
		Op: goOp,
		Y:  rightExpr,
	}
}

// VisitAdditiveExpr handles additive expressions (+, -)
func (v *ManuscriptAstVisitor) VisitAdditiveExpr(ctx *parser.AdditiveExprContext) interface{} {
	// Always visit the left operand
	leftResult := v.Visit(ctx.GetLeft())
	leftExpr, ok := leftResult.(ast.Expr)
	if !ok {
		log.Printf("Error: Left operand in additive expression is not an ast.Expr. Got: %T", leftResult)
		return &ast.BadExpr{}
	}

	// If there's no operator, just return the left expression (pass-through)
	if ctx.GetOp() == nil {
		return leftExpr
	}

	// Visit the right operand
	rightResult := v.Visit(ctx.GetRight())
	rightExpr, ok := rightResult.(ast.Expr)
	if !ok {
		log.Printf("Error: Right operand in additive expression is not an ast.Expr. Got: %T", rightResult)
		return &ast.BadExpr{}
	}

	// Create binary expression based on the operator
	var goOp token.Token
	switch ctx.GetOp().GetTokenType() {
	case parser.ManuscriptPLUS:
		goOp = token.ADD // + in Go
	case parser.ManuscriptMINUS:
		goOp = token.SUB // - in Go
	default:
		log.Printf("Error: Unknown additive operator: %s", ctx.GetOp().GetText())
		return &ast.BadExpr{}
	}

	return &ast.BinaryExpr{
		X:  leftExpr,
		Op: goOp,
		Y:  rightExpr,
	}
}

// VisitMultiplicativeExpr handles multiplicative expressions (*, /)
func (v *ManuscriptAstVisitor) VisitMultiplicativeExpr(ctx *parser.MultiplicativeExprContext) interface{} {
	// Always visit the left operand
	leftResult := v.Visit(ctx.GetLeft())
	leftExpr, ok := leftResult.(ast.Expr)
	if !ok {
		log.Printf("Error: Left operand in multiplicative expression is not an ast.Expr. Got: %T", leftResult)
		return &ast.BadExpr{}
	}

	// If there's no operator, just return the left expression (pass-through)
	if ctx.GetOp() == nil {
		return leftExpr
	}

	// Visit the right operand
	rightResult := v.Visit(ctx.GetRight())
	rightExpr, ok := rightResult.(ast.Expr)
	if !ok {
		log.Printf("Error: Right operand in multiplicative expression is not an ast.Expr. Got: %T", rightResult)
		return &ast.BadExpr{}
	}

	// Create binary expression based on the operator
	var goOp token.Token
	switch ctx.GetOp().GetTokenType() {
	case parser.ManuscriptSTAR:
		goOp = token.MUL // * in Go
	case parser.ManuscriptSLASH:
		goOp = token.QUO // / in Go
	case parser.ManuscriptMOD:
		goOp = token.REM // % in Go
	default:
		log.Printf("Error: Unknown multiplicative operator: %s", ctx.GetOp().GetText())
		return &ast.BadExpr{}
	}

	return &ast.BinaryExpr{
		X:  leftExpr,
		Op: goOp,
		Y:  rightExpr,
	}
}
