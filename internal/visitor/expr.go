package visitor

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
	primaryResult := v.Visit(ctx.PrimaryExpr())

	// Check for function call by looking for the LPAREN token
	if lparenToken := ctx.GetToken(parser.ManuscriptLPAREN, 0); lparenToken != nil {
		ident, ok := primaryResult.(*ast.Ident)
		if !ok {
			log.Printf("Warning: Expected identifier for function call, got %T for %s", primaryResult, ctx.GetText())
			return &ast.BadExpr{From: token.NoPos, To: token.NoPos} // Return BadExpr for error
		}

		// Special handling for "print"
		if ident.Name == "print" {
			if v.ProgramImports == nil {
				log.Println("CRITICAL: ProgramImports map not initialized in ManuscriptAstVisitor during print call")
				// This should ideally not happen due to constructor initialization.
			}
			v.ProgramImports["fmt"] = true // Mark "fmt" for import

			var args []ast.Expr
			// Arguments are in ctx.AllExpr(). This assumes the grammar rule for arguments inside parentheses is `expr*` or `exprList`.
			// If GetText() of an expr is empty, it might indicate an empty arg list from grammar like `LPAREN RPAREN` vs `LPAREN exprList RPAREN`
			// We need to ensure AllExpr() doesn't give us a bogus entry for an empty list.
			rawArgs := ctx.AllExpr()
			if len(rawArgs) == 1 && rawArgs[0].GetText() == "" { // Heuristic for empty arg list if AllExpr behaves this way
				rawArgs = nil
			}

			for _, argCtx := range rawArgs {
				visitedArg := v.Visit(argCtx)
				if argExpr, ok := visitedArg.(ast.Expr); ok {
					args = append(args, argExpr)
				} else {
					log.Printf("Warning: Argument to print did not evaluate to ast.Expr: %s. Got %T", argCtx.GetText(), visitedArg)
					args = append(args, &ast.BadExpr{From: token.NoPos, To: token.NoPos})
				}
			}

			return &ast.CallExpr{
				Fun: &ast.SelectorExpr{
					X:   ast.NewIdent("fmt"),
					Sel: ast.NewIdent("Println"),
				},
				Args: args,
			}
		} else {
			// Generic function call
			var args []ast.Expr
			rawArgs := ctx.AllExpr()
			if len(rawArgs) == 1 && rawArgs[0].GetText() == "" {
				rawArgs = nil
			}
			for _, argCtx := range rawArgs {
				visitedArg := v.Visit(argCtx)
				if argExpr, ok := visitedArg.(ast.Expr); ok {
					args = append(args, argExpr)
				} else {
					log.Printf("Warning: Argument to generic function call did not evaluate to ast.Expr: %s. Got %T", argCtx.GetText(), visitedArg)
					args = append(args, &ast.BadExpr{From: token.NoPos, To: token.NoPos})
				}
			}
			return &ast.CallExpr{
				Fun:  ident, // The function identifier itself
				Args: args,
			}
		}
	} else if dotToken := ctx.GetToken(parser.ManuscriptDOT, 0); dotToken != nil {
		// TODO: Handle member access (e.g., obj.member) -> *ast.SelectorExpr
		// This will involve getting the member ID (ctx.ID() or ctx.GetToken(parser.ID, ...))
		// and creating an *ast.SelectorExpr { X: primaryResult, Sel: ast.NewIdent(memberName) }
		log.Printf("Warning: Member access (dot operator) not yet handled: %s. Returning primary expression.", ctx.GetText())
		return primaryResult
	} else if lsqbrToken := ctx.GetToken(parser.ManuscriptLSQBR, 0); lsqbrToken != nil {
		// TODO: Handle index access (e.g., arr[index]) -> *ast.IndexExpr
		// This will involve visiting the expression inside the brackets (ctx.Expr(0) or similar)
		// and creating an *ast.IndexExpr { X: primaryResult, Index: visitedIndexExpr }
		log.Printf("Warning: Index access (square brackets) not yet handled: %s. Returning primary expression.", ctx.GetText())
		return primaryResult
	}

	return primaryResult
}
