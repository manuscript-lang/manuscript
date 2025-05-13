package codegen

import (
	"go/ast"
	"go/token"
	"log"
	"manuscript-co/manuscript/internal/parser"
	"strconv"
)

// --- Expression Handling (Starting with Primary) ---

// VisitPrimaryExpr handles the base cases of expressions.
func (v *ManuscriptAstVisitor) VisitPrimaryExpr(ctx *parser.PrimaryExprContext) interface{} {
	if ctx.Literal() != nil {
		// Delegate to VisitLiteral for all literal types
		return v.Visit(ctx.Literal())
	}
	if ctx.ID() != nil {
		// Handle identifier: create an ast.Ident node
		identName := ctx.ID().GetText()
		return ast.NewIdent(identName)
	}
	if ctx.SELF() != nil {
		// Handle 'self': map to 'this' or a specific receiver name if applicable?
		// For now, let's represent it as an identifier named "self".
		// Go translation might require context (e.g., inside a method).
		return ast.NewIdent("self") // Placeholder, might need refinement
	}
	// Use the getter for the labeled element "parenExpr"
	if ctx.GetParenExpr() != nil {
		// Handle parenthesized expression: visit the inner expression
		return v.Visit(ctx.GetParenExpr())
	}
	if ctx.ArrayLiteral() != nil {
		return v.Visit(ctx.ArrayLiteral())
	}
	if ctx.ObjectLiteral() != nil {
		return v.Visit(ctx.ObjectLiteral())
	}
	if ctx.FnExpr() != nil {
		return v.Visit(ctx.FnExpr())
	}
	// TODO: Add cases for MapLiteral, SetLiteral, TupleLiteral, LambdaExpr, TryBlockExpr, MatchExpr
	// as their visitor methods are implemented.

	log.Printf("Warning: Unhandled primary expression type in VisitPrimaryExpr: %s", ctx.GetText())
	return &ast.BadExpr{} // Return BadExpr for unhandled cases
}

// VisitUnaryExpr handles prefix unary operators.
func (v *ManuscriptAstVisitor) VisitUnaryExpr(ctx *parser.UnaryExprContext) interface{} {
	// Check if a prefix operator is present
	if opToken := ctx.GetOp(); opToken != nil {
		// Recursively visit the operand expression
		visitedOperand := v.Visit(ctx.UnaryExpr()) // Visit the inner unaryExpr
		operandExpr, ok := visitedOperand.(ast.Expr)
		if !ok {
			log.Printf("Warning: Visiting operand for unary operator %s did not return ast.Expr. Got: %T", opToken.GetText(), visitedOperand)
			return &ast.BadExpr{}
		}

		var goOp token.Token
		switch opToken.GetTokenType() {
		case parser.ManuscriptPLUS:
			goOp = token.ADD // Unary plus
		case parser.ManuscriptMINUS:
			goOp = token.SUB // Unary minus
		case parser.ManuscriptEXCLAMATION:
			goOp = token.NOT // Logical not
		case parser.ManuscriptTRY:
			log.Printf("Warning: Unary 'try' operator translation not fully implemented. Returning operand for: %s", ctx.GetText())
			// TODO: Implement 'try' translation (e.g., IIFE with panic recovery or multi-value return)
			return operandExpr // For now, just pass through the operand
		case parser.ManuscriptCHECK:
			log.Printf("Warning: Unary 'check' operator translation not fully implemented. Returning operand for: %s", ctx.GetText())
			// TODO: Implement 'check' translation (likely involves statement-level transformation)
			return operandExpr // For now, just pass through the operand
		default:
			log.Printf("Warning: Unhandled unary operator token type: %d (%s)", opToken.GetTokenType(), opToken.GetText())
			return &ast.BadExpr{}
		}

		// Create and return the Go unary expression AST node
		return &ast.UnaryExpr{
			Op: goOp,
			X:  operandExpr,
		}
	} else if ctx.AwaitExpr() != nil {
		// If no operator, it must be the awaitExpr alternative
		return v.Visit(ctx.AwaitExpr()) // Delegate to VisitAwaitExpr (to be implemented)
	} else {
		log.Printf("Error: Invalid UnaryExprContext state: %s", ctx.GetText())
		return &ast.BadExpr{}
	}
}

// --- Pass-through expression visitors ---

// VisitExpr simply visits its child (assignmentExpr)
func (v *ManuscriptAstVisitor) VisitExpr(ctx *parser.ExprContext) interface{} {
	return v.Visit(ctx.AssignmentExpr())
}

// VisitAssignmentExpr handles assignment or passes through logicalOrExpr.
func (v *ManuscriptAstVisitor) VisitAssignmentExpr(ctx *parser.AssignmentExprContext) interface{} {
	log.Printf("VisitAssignmentExpr: Called for '%s'", ctx.GetText())

	if ctx.GetOp() != nil { // Assignment case
		leftExpr := v.Visit(ctx.GetLeft())
		rightExpr := v.Visit(ctx.GetRight())

		// Handle case where the lexer may have missed certain tokens
		if rightExpr == nil {
			// Check if there's a literal number in the text that wasn't lexed properly
			rightText := ctx.GetRight().GetText()
			log.Printf("VisitAssignmentExpr: Right expr is nil, checking text: '%s'", rightText)

			// Try to parse the right side as a number if it looks numeric
			if _, err := strconv.Atoi(rightText); err == nil {
				log.Printf("VisitAssignmentExpr: Treating '%s' as a numeric literal", rightText)
				rightExpr = &ast.BasicLit{
					Kind:  token.INT,
					Value: rightText,
				}
			}
		}

		// Create an assignment statement
		if leftExpr != nil && rightExpr != nil {
			if left, ok := leftExpr.(ast.Expr); ok {
				if right, ok := rightExpr.(ast.Expr); ok {
					return &ast.AssignStmt{
						Lhs: []ast.Expr{left},
						Tok: token.ASSIGN,
						Rhs: []ast.Expr{right},
					}
				}
			}
		}

		log.Printf("Warning: Assignment expression not fully handled: %s", ctx.GetText())
		return v.Visit(ctx.GetLeft()) // Fallback to just the left side
	}

	// Pass-through case (just a logicalOrExpr)
	return v.Visit(ctx.GetLeft()) // Visit the logicalOrExpr
}

// VisitLogicalOrExpr handles || or passes through logicalAndExpr.
func (v *ManuscriptAstVisitor) VisitLogicalOrExpr(ctx *parser.LogicalOrExprContext) interface{} {
	if ctx.GetOp() != nil { // OR case
		// TODO: Implement binary OR logic (return *ast.BinaryExpr)
		log.Printf("Warning: Logical OR expression not fully handled: %s", ctx.GetText())
		return v.Visit(ctx.GetLeft()) // Placeholder
	}
	// Pass-through case
	return v.Visit(ctx.GetLeft()) // Visit the logicalAndExpr
}

// VisitLogicalAndExpr handles && or passes through equalityExpr.
func (v *ManuscriptAstVisitor) VisitLogicalAndExpr(ctx *parser.LogicalAndExprContext) interface{} {
	if ctx.GetOp() != nil { // AND case
		// TODO: Implement binary AND logic
		log.Printf("Warning: Logical AND expression not fully handled: %s", ctx.GetText())
		return v.Visit(ctx.GetLeft()) // Placeholder
	}
	// Pass-through case
	return v.Visit(ctx.GetLeft()) // Visit the equalityExpr
}

// VisitEqualityExpr handles ==, != or passes through comparisonExpr.
func (v *ManuscriptAstVisitor) VisitEqualityExpr(ctx *parser.EqualityExprContext) interface{} {
	if ctx.GetOp() != nil { // Equality op case
		// TODO: Implement equality logic
		log.Printf("Warning: Equality expression not fully handled: %s", ctx.GetText())
		return v.Visit(ctx.GetLeft()) // Placeholder
	}
	// Pass-through case
	return v.Visit(ctx.GetLeft()) // Visit the comparisonExpr
}

// VisitComparisonExpr handles <, <=, >, >= or passes through additiveExpr.
func (v *ManuscriptAstVisitor) VisitComparisonExpr(ctx *parser.ComparisonExprContext) interface{} {
	if ctx.GetOp() != nil { // Comparison op case
		// TODO: Implement comparison logic
		log.Printf("Warning: Comparison expression not fully handled: %s", ctx.GetText())
		return v.Visit(ctx.GetLeft()) // Placeholder
	}
	// Pass-through case
	return v.Visit(ctx.GetLeft()) // Visit the additiveExpr
}

// VisitAdditiveExpr handles +, - or passes through multiplicativeExpr.
func (v *ManuscriptAstVisitor) VisitAdditiveExpr(ctx *parser.AdditiveExprContext) interface{} {
	if ctx.GetOp() != nil { // Add/Sub case
		// TODO: Implement add/sub logic
		log.Printf("Warning: Additive expression not fully handled: %s", ctx.GetText())
		return v.Visit(ctx.GetLeft()) // Placeholder
	}
	// Pass-through case
	return v.Visit(ctx.GetLeft()) // Visit the multiplicativeExpr
}

// VisitMultiplicativeExpr handles *, / or passes through unaryExpr.
func (v *ManuscriptAstVisitor) VisitMultiplicativeExpr(ctx *parser.MultiplicativeExprContext) interface{} {
	if ctx.GetOp() != nil { // Mul/Div case
		// TODO: Implement mul/div logic
		log.Printf("Warning: Multiplicative expression not fully handled: %s", ctx.GetText())
		return v.Visit(ctx.GetLeft()) // Placeholder
	}
	// Pass-through case
	return v.Visit(ctx.GetLeft()) // Visit the unaryExpr
}

// VisitAwaitExpr handles prefixes or passes through postfixExpr.
func (v *ManuscriptAstVisitor) VisitAwaitExpr(ctx *parser.AwaitExprContext) interface{} {
	if ctx.TRY() != nil || ctx.AWAIT() != nil || ctx.ASYNC() != nil {
		// TODO: Implement prefix handling (TRY?, AWAIT?, ASYNC?)
		log.Printf("Warning: TRY/AWAIT/ASYNC prefixes not fully handled: %s", ctx.GetText())
	}
	// Always visit the postfix expression part
	return v.Visit(ctx.PostfixExpr())
}

// VisitPostfixExpr handles calls, member access, index access or passes through primaryExpr.
func (v *ManuscriptAstVisitor) VisitPostfixExpr(ctx *parser.PostfixExprContext) interface{} {
	// Always visit the primary expression first.
	primaryResult := v.Visit(ctx.PrimaryExpr())

	// Check if there are postfix operations following the primary expression.
	// A simple heuristic: if the node has more than one child, postfix ops exist.
	// (Child 0 is primaryExpr, others are tokens like LPAREN, DOT, LSQBR or expr nodes for index/args)
	if ctx.GetChildCount() > 1 {
		// TODO: Properly handle the sequence of postfix operations (*ast.CallExpr, *ast.SelectorExpr, *ast.IndexExpr)
		log.Printf("Warning: Postfix operations (call/member/index) detected but not fully handled: %s. Returning primary expression result.", ctx.GetText())
		// For now, just return the result from the primary expression to allow propagation.
		return primaryResult
	}

	// If no postfix operations (only the primaryExpr child), return its result.
	return primaryResult
}
