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

	v.addError("Unhandled primary expression type: "+ctx.GetText(), ctx.GetStart())
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
			errMsg := "Visiting operand for unary operator " + opToken.GetText() + " did not return a valid expression."
			v.addError(errMsg, opToken)
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
			v.addError("Unary 'try' operator translation not fully implemented for: "+ctx.GetText(), opToken)
			// TODO: Implement 'try' translation (e.g., IIFE with panic recovery or multi-value return)
			return operandExpr // For now, just pass through the operand
		case parser.ManuscriptCHECK:
			v.addError("Unary 'check' operator translation not fully implemented for: "+ctx.GetText(), opToken)
			// TODO: Implement 'check' translation (likely involves statement-level transformation)
			return operandExpr // For now, just pass through the operand
		default:
			errMsg := "Unhandled unary operator: " + opToken.GetText()
			v.addError(errMsg, opToken)
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
		v.addError("Invalid unary expression state: "+ctx.GetText(), ctx.GetStart())
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
	leftAntlrExpr := ctx.GetLeft()
	if leftAntlrExpr == nil {
		v.addError("Left-hand side of assignment is missing", ctx.GetStart())
		return &ast.BadStmt{} // Or some other error representation
	}
	visitedLeftExpr := v.Visit(leftAntlrExpr)
	leftExpr, ok := visitedLeftExpr.(ast.Expr)
	if !ok {
		v.addError("Left-hand side of assignment did not resolve to a valid expression: "+leftAntlrExpr.GetText(), leftAntlrExpr.GetStart())
		return &ast.BadStmt{}
	}

	if ctx.GetOp() != nil { // Assignment case
		opType := ctx.GetOp().GetTokenType()

		rightAntlrExpr := ctx.GetRight()
		if rightAntlrExpr == nil {
			v.addError("Right-hand side of assignment is missing for operator "+ctx.GetOp().GetText(), ctx.GetOp())
			return &ast.BadStmt{}
		}
		visitedRightExpr := v.Visit(rightAntlrExpr)
		rightExpr, ok := visitedRightExpr.(ast.Expr)
		if !ok {
			// Attempt to recover if lexer missed a literal number (existing logic)
			rightText := rightAntlrExpr.GetText()
			if _, err := strconv.Atoi(rightText); err == nil {
				rightExpr = &ast.BasicLit{
					Kind:  token.INT,
					Value: rightText,
				}
				ok = true
			} else {
				v.addError("Right-hand side of assignment did not resolve to a valid expression: "+rightAntlrExpr.GetText(), rightAntlrExpr.GetStart())
				return &ast.BadStmt{}
			}
		}

		if opType == parser.ManuscriptEQUALS {
			return &ast.AssignStmt{
				Lhs: []ast.Expr{leftExpr},
				Tok: token.ASSIGN,
				Rhs: []ast.Expr{rightExpr},
			}
		}

		// Handle compound assignments
		var binaryOpToken token.Token
		switch opType {
		case parser.ManuscriptPLUS_EQUALS:
			binaryOpToken = token.ADD
		case parser.ManuscriptMINUS_EQUALS:
			binaryOpToken = token.SUB
		case parser.ManuscriptSTAR_EQUALS:
			binaryOpToken = token.MUL
		case parser.ManuscriptSLASH_EQUALS:
			binaryOpToken = token.QUO
		case parser.ManuscriptMOD_EQUALS:
			binaryOpToken = token.REM
		case parser.ManuscriptCARET_EQUALS:
			binaryOpToken = token.XOR // Assuming ^ is XOR for integer types. Could be AND_NOT for sets or POW for numbers, needs clarification based on language spec.
		default:
			v.addError("Unhandled assignment operator: "+ctx.GetOp().GetText(), ctx.GetOp())
			return &ast.BadStmt{}
		}

		// Create a binary expression: leftExpr <op> rightExpr
		rhsBinaryExpr := &ast.BinaryExpr{
			X:  leftExpr, // Use the already visited left expression
			Op: binaryOpToken,
			Y:  rightExpr, // Use the already visited right expression
		}

		// Create an assignment statement: leftExpr = (leftExpr <op> rightExpr)
		return &ast.AssignStmt{
			Lhs: []ast.Expr{leftExpr},
			Tok: token.ASSIGN, // All compound assignments become a simple assign
			Rhs: []ast.Expr{rhsBinaryExpr},
		}
	}

	// Pass-through case (not an assignment, just a logicalOrExpr, which is the left part of assignmentExpr)
	return leftExpr
}

// VisitAwaitExpr handles prefixes or passes through postfixExpr.
func (v *ManuscriptAstVisitor) VisitAwaitExpr(ctx *parser.AwaitExprContext) interface{} {
	if ctx.TRY() != nil || ctx.AWAIT() != nil || ctx.ASYNC() != nil {
		// TODO: Implement prefix handling (TRY?, AWAIT?, ASYNC?)
		v.addError("TRY/AWAIT/ASYNC prefixes not fully handled: "+ctx.GetText(), ctx.GetStart())
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
			errMsg := "Expected identifier for function call, got non-identifier for " + ctx.GetText()
			v.addError(errMsg, ctx.GetStart())                      // Use ctx.GetStart() as primaryResult might not have token info
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
					errMsg := "Argument to print did not evaluate to a valid expression: " + argCtx.GetText()
					v.addError(errMsg, argCtx.GetStart())
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
					errMsg := "Argument to function call did not evaluate to a valid expression: " + argCtx.GetText()
					v.addError(errMsg, argCtx.GetStart())
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
		v.addError("Member access (dot operator) not yet handled: "+ctx.GetText(), dotToken.GetSymbol())
		return primaryResult
	} else if lsqbrToken := ctx.GetToken(parser.ManuscriptLSQBR, 0); lsqbrToken != nil {
		// TODO: Handle index access (e.g., arr[index]) -> *ast.IndexExpr
		// This will involve visiting the expression inside the brackets (ctx.Expr(0) or similar)
		// and creating an *ast.IndexExpr { X: primaryResult, Index: visitedIndexExpr }
		v.addError("Index access (square brackets) not yet handled: "+ctx.GetText(), lsqbrToken.GetSymbol())
		return primaryResult
	}

	return primaryResult
}
