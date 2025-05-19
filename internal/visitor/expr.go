package visitor

import (
	"fmt"
	"go/ast"
	"go/token"
	"manuscript-co/manuscript/internal/parser"
	"strconv"
	"strings"
	"unicode"

	"github.com/antlr4-go/antlr/v4"
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
	if ctx.MapLiteral() != nil {
		return v.Visit(ctx.MapLiteral())
	}
	if ctx.SetLiteral() != nil {
		return v.Visit(ctx.SetLiteral())
	}
	if ctx.TupleLiteral() != nil {
		return v.Visit(ctx.TupleLiteral())
	}
	if ctx.TaggedBlockString() != nil {
		return v.Visit(ctx.TaggedBlockString())
	}
	if ctx.StructInitExpr() != nil {
		return v.Visit(ctx.StructInitExpr())
	}
	// TODO: Add cases for LambdaExpr, TryBlockExpr, MatchExpr
	// as their visitor methods are implemented.

	v.addError("Unhandled primary expression type: "+ctx.GetText(), ctx.GetStart())
	return &ast.BadExpr{} // Return BadExpr for unhandled cases
}

// VisitUnaryExpr handles prefix unary operators.
func (v *ManuscriptAstVisitor) VisitUnaryExpr(ctx *parser.UnaryExprContext) interface{} {
	// The grammar is: unaryExpr: op=(PLUS | MINUS | EXCLAMATION | TRY) unaryExpr | awaitExpr;
	// So, either awaitExpr is present, or an operator (op) and a recursive unaryExpr are present.

	if ctx.AwaitExpr() != nil {
		// It's an await expression, delegate to its visitor.
		return v.Visit(ctx.AwaitExpr())
	}

	opToken := ctx.GetOp()
	if opToken == nil {
		// This should ideally not be reached if AwaitExpr() is also nil, implies grammar mismatch or parse error.
		v.addError(fmt.Sprintf("Unary expression without an operator or await expression near token %v", ctx.GetStart().GetText()), ctx.GetStart())
		return &ast.BadExpr{From: v.pos(ctx.GetStart()), To: v.pos(ctx.GetStop())}
	}

	if ctx.UnaryExpr() == nil {
		v.addError(fmt.Sprintf("Unary operator '%s' found without an operand expression near token %v", opToken.GetText(), opToken.GetText()), opToken)
		return &ast.BadExpr{From: v.pos(opToken), To: v.pos(opToken)}
	}

	operandVisitResult := v.Visit(ctx.UnaryExpr())
	operandExpr, ok := operandVisitResult.(ast.Expr)
	if !ok {
		errMsg := fmt.Sprintf("Operand for unary operator '%s' did not resolve to an ast.Expr. Got %T, near token %v", opToken.GetText(), operandVisitResult, opToken.GetText())
		v.addError(errMsg, opToken)
		return &ast.BadExpr{From: v.pos(opToken), To: v.pos(opToken)}
	}

	opPos := v.pos(opToken)

	switch opToken.GetTokenType() {
	case parser.ManuscriptLexerTRY:
		// Construct: defer func() { if r := recover(); r != nil { err = fmt.Errorf("panic: %v", r) } }()
		recoverFuncBody := &ast.BlockStmt{
			List: []ast.Stmt{
				&ast.IfStmt{
					Init: &ast.AssignStmt{
						Lhs: []ast.Expr{ast.NewIdent("r")},
						Tok: token.DEFINE,
						Rhs: []ast.Expr{&ast.CallExpr{Fun: ast.NewIdent("recover")}},
					},
					Cond: &ast.BinaryExpr{X: ast.NewIdent("r"), Op: token.NEQ, Y: ast.NewIdent("nil")},
					Body: &ast.BlockStmt{
						List: []ast.Stmt{
							&ast.AssignStmt{
								Lhs: []ast.Expr{ast.NewIdent("err")},
								Tok: token.ASSIGN,
								Rhs: []ast.Expr{&ast.CallExpr{
									Fun:  &ast.SelectorExpr{X: ast.NewIdent("fmt"), Sel: ast.NewIdent("Errorf")},
									Args: []ast.Expr{&ast.BasicLit{Kind: token.STRING, Value: `"panic: %v"`}, ast.NewIdent("r")},
								}},
							},
						},
					},
				},
			},
		}
		deferStmt := &ast.DeferStmt{
			Call: &ast.CallExpr{
				Fun: &ast.FuncLit{Type: &ast.FuncType{Params: &ast.FieldList{}}, Body: recoverFuncBody},
			},
		}

		// Construct: val = operandExpr
		assignValStmt := &ast.AssignStmt{
			Lhs: []ast.Expr{ast.NewIdent("val")},
			Tok: token.ASSIGN, // 'val' is defined in IIFE signature
			Rhs: []ast.Expr{operandExpr},
		}

		// Construct: return val, nil
		happyReturnStmt := &ast.ReturnStmt{
			Results: []ast.Expr{ast.NewIdent("val"), ast.NewIdent("nil")},
		}

		iifeBodyStmts := []ast.Stmt{
			deferStmt,
			assignValStmt,
			happyReturnStmt,
		}

		iifeFuncLit := &ast.FuncLit{
			Type: &ast.FuncType{
				Params: &ast.FieldList{}, // No params for this IIFE
				Results: &ast.FieldList{
					List: []*ast.Field{
						{Names: []*ast.Ident{ast.NewIdent("val")}, Type: ast.NewIdent("interface{}")},
						{Names: []*ast.Ident{ast.NewIdent("err")}, Type: ast.NewIdent("error")},
					},
				},
			},
			Body: &ast.BlockStmt{List: iifeBodyStmts, Lbrace: opPos},
		}

		return &ast.CallExpr{
			Fun:    iifeFuncLit,
			Lparen: opPos,
		}

	case parser.ManuscriptLexerPLUS:
		return &ast.UnaryExpr{OpPos: opPos, Op: token.ADD, X: operandExpr}
	case parser.ManuscriptLexerMINUS:
		return &ast.UnaryExpr{OpPos: opPos, Op: token.SUB, X: operandExpr}
	case parser.ManuscriptLexerEXCLAMATION:
		return &ast.UnaryExpr{OpPos: opPos, Op: token.NOT, X: operandExpr}
	default:
		v.addError(fmt.Sprintf("Unsupported unary operator: %s", opToken.GetText()), opToken)
		return &ast.BadExpr{From: opPos, To: opPos + token.Pos(len(opToken.GetText()))}
	}
}

// --- Pass-through expression visitors ---

// VisitExpr simply visits its child (assignmentExpr)
func (v *ManuscriptAstVisitor) VisitExpr(ctx *parser.ExprContext) interface{} {
	if ctx == nil {
		v.addError("VisitExpr called with nil context", nil)
		return &ast.BadExpr{}
	}
	if ctx.AssignmentExpr() == nil { // Check if child is nil
		v.addError("ExprContext has no AssignmentExpr child", ctx.GetStart())
		return &ast.BadExpr{}
	}
	return v.Visit(ctx.AssignmentExpr())
}

// VisitExprList handles comma-separated expressions.
// For contexts like for-loop post-updates, this often contains a single expression
// that should resolve to a statement (e.g., an assignment).
func (v *ManuscriptAstVisitor) VisitExprList(ctx *parser.ExprListContext) interface{} {
	if ctx == nil {
		v.addError("VisitExprList called with nil context", nil)
		return nil // Or BadStmt
	}

	allExprs := ctx.AllExpr() // This gets all IExprContext children
	if len(allExprs) == 0 {
		// This case implies an empty expression list, which might be valid in some contexts
		// but likely not directly as a for-loop post-statement.
		// For now, returning nil, which will lead to an empty Post field in ForStmt.
		return nil
	}

	// In Go's for loop, the Init and Post clauses can be a simple statement.
	// An ExprList with a single expression (like "i++" or "x = y") is common.
	// If Manuscript's exprList has multiple comma-separated top-level expressions,
	// e.g., "i++, j++", Go's AST expects a single Stmt.
	// This simple implementation processes only the first expression.
	// A more complex implementation might try to form a single AssignStmt for multi-assignments
	// or report errors for unsupported multi-statement forms in this context.
	if len(allExprs) > 1 {
		v.addError(
			fmt.Sprintf("ExprList with multiple (%d) expressions encountered in a context expecting a single statement; processing only the first: %s", len(allExprs), ctx.GetText()),
			ctx.GetStart(),
		)
		// Consider if this should be a hard error for for-loop contexts.
	}

	firstExprCtx := allExprs[0] // Process the first expression
	if firstExprCtx == nil {    // Defensive check
		v.addError("First expression in ExprList is nil", ctx.GetStart())
		return nil // Or BadStmt
	}

	visitedNode := v.Visit(firstExprCtx) // Visit the IExprContext

	if stmt, ok := visitedNode.(ast.Stmt); ok {
		return stmt // e.g., an *ast.AssignStmt from VisitAssignmentExpr
	}
	if expr, ok := visitedNode.(ast.Expr); ok {
		// Wrap a plain expression in an ExprStmt, e.g. for function calls
		return &ast.ExprStmt{X: expr}
	}

	if visitedNode == nil {
		v.addError(fmt.Sprintf("Visiting first expression in ExprList returned nil: %s", firstExprCtx.GetText()), firstExprCtx.GetStart())
	} else {
		v.addError(fmt.Sprintf("Expression in ExprList resolved to unexpected type %T: %s", visitedNode, firstExprCtx.GetText()), firstExprCtx.GetStart())
	}
	return &ast.BadStmt{From: v.pos(firstExprCtx.GetStart()), To: v.pos(firstExprCtx.GetStop())} // Return a BadStmt on failure
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
	// The prefixes TRY?, AWAIT?, ASYNC? are considered modifiers to the core postfixExpr.
	// The actual AST transformation for these (e.g., for await creating a goroutine + channel,
	// or for try creating an IIFE with panic recovery) would be complex and depend on
	// the target Go patterns.
	// For now, we'll note their presence and primarily visit the PostfixExpr.
	// A full implementation would likely wrap the result of Visit(ctx.PostfixExpr()).
	if ctx.TRY() != nil {
		v.addError("Semantic translation for 'try' prefix in awaitExpr not fully implemented: "+ctx.GetText(), ctx.GetStart())
	}
	if ctx.AWAIT() != nil {
		v.addError("Semantic translation for 'await' prefix in awaitExpr not fully implemented: "+ctx.GetText(), ctx.GetStart())
	}
	if ctx.ASYNC() != nil {
		v.addError("Semantic translation for 'async' prefix in awaitExpr not fully implemented: "+ctx.GetText(), ctx.GetStart())
	}
	return v.Visit(ctx.PostfixExpr())
}

// VisitPostfixExpr handles calls, member access, index access by iterating through operations.
func (v *ManuscriptAstVisitor) VisitPostfixExpr(ctx *parser.PostfixExprContext) interface{} {
	if ctx.PrimaryExpr() == nil {
		v.addError("Postfix expression is missing primary expression part", ctx.GetStart())
		return &ast.BadExpr{From: v.pos(ctx.GetStart()), To: v.pos(ctx.GetStop())}
	}

	currentAstNode := v.Visit(ctx.PrimaryExpr())
	if currentAstNode == nil {
		// Error already added by child visit
		return &ast.BadExpr{From: v.pos(ctx.GetStart()), To: v.pos(ctx.GetStop())}
	}

	currentGoExpr, ok := currentAstNode.(ast.Expr)
	if !ok {
		v.addError(fmt.Sprintf("Primary expression did not resolve to ast.Expr, got %T", currentAstNode), ctx.PrimaryExpr().GetStart())
		return &ast.BadExpr{From: v.pos(ctx.PrimaryExpr().GetStart()), To: v.pos(ctx.PrimaryExpr().GetStop())}
	}

	// Iterate through the postfix operations applied to the primaryExpr
	// Children list: [PrimaryExprContext, op1_token1, op1_token2/expr, op2_token1, ...]
	children := ctx.GetChildren()
	childIdx := 0
	// Find the PrimaryExpr child to start iterating after it
	for i, child := range children {
		if _, ok := child.(*parser.PrimaryExprContext); ok {
			childIdx = i + 1
			break
		}
	}

	for childIdx < len(children) {
		child := children[childIdx]
		termNode, isTerm := child.(antlr.TerminalNode)

		if !isTerm {
			// This case should ideally not be reached if grammar is correctly processed sequentially.
			// It might indicate an ExprContext for an argument that wasn't consumed by a call.
			var childText string
			var childStartToken antlr.Token
			if prc, ok := child.(antlr.ParserRuleContext); ok {
				childText = prc.GetText()
				childStartToken = prc.GetStart()
			} else if tn, ok := child.(antlr.TerminalNode); ok {
				childText = tn.GetText()
				childStartToken = tn.GetSymbol()
			} else {
				childText = "unknown_child_type"
			}

			if _, isExprCtx := child.(parser.IExprContext); isExprCtx {

				v.addError("Unexpected expression found in postfix operation chain: "+childText, childStartToken)
			} else {

				v.addError("Malformed postfix operation sequence: "+childText, childStartToken)
			}
			break // Safety break
		}

		tokenType := termNode.GetSymbol().GetTokenType()

		switch tokenType {
		case parser.ManuscriptLPAREN: // Function Call or Struct Init
			lParenPos := v.pos(termNode.GetSymbol())
			childIdx++ // Move past LPAREN
			var rParenPos token.Pos

			// Process function call arguments
			var args []ast.Expr

		argLoop:
			for childIdx < len(children) {
				argChild := children[childIdx]
				if argTerm, isArgTerm := argChild.(antlr.TerminalNode); isArgTerm {
					if argTerm.GetSymbol().GetTokenType() == parser.ManuscriptRPAREN {
						rParenPos = v.pos(argTerm.GetSymbol())
						childIdx++ // Consume RPAREN
						break argLoop
					} else if argTerm.GetSymbol().GetTokenType() == parser.ManuscriptCOMMA {
						childIdx++ // Consume COMMA
						continue
					} else {
						v.addError("Unexpected token in argument list: "+argTerm.GetText(), argTerm.GetSymbol())
						return &ast.BadExpr{From: lParenPos, To: v.pos(ctx.GetStop())}
					}
				} else if argListCtx, isArgList := argChild.(*parser.ExprListContext); isArgList {
					// This is the case where arguments are wrapped in an ExprListContext
					for _, exprCtx := range argListCtx.AllExpr() {
						exprText := exprCtx.GetText()

						// For struct initialization, we're looking for patterns like "field: value"
						if strings.Contains(exprText, ":") {
							colonPos := strings.Index(exprText, ":")
							if colonPos > 0 {
								fieldName := strings.TrimSpace(exprText[:colonPos])
								if isValidIdentifier(fieldName) {
									// Extract the value expression
									valueExpr := v.extractValueAfterColon(exprCtx)
									if valueExpr != nil {
										args = append(args, &ast.KeyValueExpr{
											Key:   ast.NewIdent(fieldName),
											Value: valueExpr,
										})
										continue
									}
								}
							}
						}

						visitedArg := v.Visit(exprCtx)
						if argExpr, exprOk := visitedArg.(ast.Expr); exprOk {
							args = append(args, argExpr)
						} else {
							v.addError(fmt.Sprintf("Argument did not evaluate to a valid expression: %s", exprText), exprCtx.GetStart())
							args = append(args, &ast.BadExpr{From: v.pos(exprCtx.GetStart()), To: v.pos(exprCtx.GetStop())})
						}
					}
					childIdx++ // Consume ExprListContext
				} else if argCtx, ok := argChild.(parser.IExprContext); ok {
					visitedArg := v.Visit(argCtx)
					if argExpr, exprOk := visitedArg.(ast.Expr); exprOk {
						args = append(args, argExpr)
					} else {
						v.addError("Argument did not evaluate to a valid expression: "+argCtx.GetText(), argCtx.GetStart())
						args = append(args, &ast.BadExpr{From: v.pos(argCtx.GetStart()), To: v.pos(argCtx.GetStop())})
					}
					childIdx++ // Consume ExprContext
				} else {
					v.addError(fmt.Sprintf("Unexpected item in argument list %T", argChild), termNode.GetSymbol()) // Use LPAREN for error pos
					return &ast.BadExpr{From: lParenPos, To: v.pos(ctx.GetStop())}
				}
			}

			if rParenPos == token.NoPos {
				v.addError("Missing closing parenthesis for function call", termNode.GetSymbol())
				// rParenPos will be end of context if not found
				rParenPos = v.pos(ctx.GetStop())
			}

			// Regular function call
			currentGoExpr = &ast.CallExpr{
				Fun:    currentGoExpr,
				Args:   args,
				Lparen: lParenPos,
				Rparen: rParenPos,
			}

		case parser.ManuscriptDOT: // Member Access
			childIdx++ // Move past DOT
			if childIdx >= len(children) {
				v.addError("Missing identifier after DOT for member access", termNode.GetSymbol())
				return &ast.BadExpr{From: v.pos(termNode.GetSymbol()), To: v.pos(ctx.GetStop())}
			}
			idNode, idOk := children[childIdx].(antlr.TerminalNode)
			if !idOk || idNode.GetSymbol().GetTokenType() != parser.ManuscriptID {
				var offendingText string
				if prc, ok := children[childIdx].(antlr.ParserRuleContext); ok {
					offendingText = prc.GetText()
				} else if tn, ok := children[childIdx].(antlr.TerminalNode); ok {
					offendingText = tn.GetText()
				} else {
					offendingText = "unknown_node_type"
				}
				v.addError("Expected identifier after DOT for member access, got: "+offendingText, termNode.GetSymbol())
				return &ast.BadExpr{From: v.pos(termNode.GetSymbol()), To: v.pos(ctx.GetStop())}
			}
			currentGoExpr = &ast.SelectorExpr{
				X:   currentGoExpr,
				Sel: ast.NewIdent(idNode.GetText()),
			}
			childIdx++ // Consume ID

		case parser.ManuscriptLSQBR: // Index Access
			lSqbrPos := v.pos(termNode.GetSymbol())
			childIdx++ // Move past LSQBR
			if childIdx >= len(children) {
				v.addError("Missing expression for index access", termNode.GetSymbol())
				return &ast.BadExpr{From: lSqbrPos, To: v.pos(ctx.GetStop())}
			}
			indexExprCtx, exprOk := children[childIdx].(parser.IExprContext)
			if !exprOk {
				var offendingText string
				if prc, ok := children[childIdx].(antlr.ParserRuleContext); ok {
					offendingText = prc.GetText()
				} else if tn, ok := children[childIdx].(antlr.TerminalNode); ok {
					offendingText = tn.GetText()
				} else {
					offendingText = "unknown_node_type"
				}
				v.addError("Expected expression for index access, got: "+offendingText, termNode.GetSymbol())
				return &ast.BadExpr{From: lSqbrPos, To: v.pos(ctx.GetStop())}
			}
			visitedIndex := v.Visit(indexExprCtx)
			indexAstExpr, astOk := visitedIndex.(ast.Expr)
			if !astOk {
				v.addError("Index did not evaluate to a valid expression: "+indexExprCtx.GetText(), indexExprCtx.GetStart())
				return &ast.BadExpr{From: lSqbrPos, To: v.pos(ctx.GetStop())}
			}
			childIdx++ // Consume ExprContext for index

			if childIdx >= len(children) {
				v.addError("Missing closing square bracket for index access", termNode.GetSymbol())
				return &ast.BadExpr{From: lSqbrPos, To: v.pos(ctx.GetStop())}
			}
			rSqbrNode, rSqbrOk := children[childIdx].(antlr.TerminalNode)
			if !rSqbrOk || rSqbrNode.GetSymbol().GetTokenType() != parser.ManuscriptRSQBR {
				v.addError("Expected closing square bracket for index access", termNode.GetSymbol())
				return &ast.BadExpr{From: lSqbrPos, To: v.pos(ctx.GetStop())}
			}
			rSqbrPos := v.pos(rSqbrNode.GetSymbol())
			currentGoExpr = &ast.IndexExpr{
				X:      currentGoExpr,
				Lbrack: lSqbrPos,
				Index:  indexAstExpr,
				Rbrack: rSqbrPos,
			}
			childIdx++ // Consume RSQBR

		default:
			// This token is not a recognized postfix operator starter.
			// It might be an error or end of postfix operations for this context.
			// For safety, we stop processing.
			v.addError(fmt.Sprintf("Unexpected token '%s' in postfix expression chain.", termNode.GetText()), termNode.GetSymbol())
			return currentGoExpr // return what has been processed so far
		}
	}
	return currentGoExpr
}

// isValidIdentifier checks if a string is a valid Go identifier
func isValidIdentifier(s string) bool {
	if len(s) == 0 {
		return false
	}

	// First character must be a letter or underscore
	firstChar := rune(s[0])
	if !unicode.IsLetter(firstChar) && firstChar != '_' {
		return false
	}

	// Remaining characters must be letters, digits, or underscores
	for _, c := range s[1:] {
		if !unicode.IsLetter(c) && !unicode.IsDigit(c) && c != '_' {
			return false
		}
	}

	return true
}

// extractValueAfterColon extracts the value expression after a colon in a struct field initialization
func (v *ManuscriptAstVisitor) extractValueAfterColon(exprCtx parser.IExprContext) ast.Expr {
	exprText := exprCtx.GetText()
	colonPos := strings.Index(exprText, ":")
	if colonPos < 0 {
		return nil
	}

	// Try to visit the expression as is
	visitedExpr := v.Visit(exprCtx)
	if expr, ok := visitedExpr.(ast.Expr); ok {
		return expr
	}

	// If direct visit doesn't work, try to extract and parse the right-hand side
	// Try to find the assignment expression and get the right side
	if ctx, ok := exprCtx.(*parser.ExprContext); ok {
		if assignExpr, ok := ctx.AssignmentExpr().(*parser.AssignmentExprContext); ok {
			if assignExpr.GetRight() != nil {
				valueResult := v.Visit(assignExpr.GetRight())
				if valueExpr, ok := valueResult.(ast.Expr); ok {
					return valueExpr
				}
			}
		}
	}

	// If we can't parse it as an expression, create a placeholder BadExpr
	return &ast.BadExpr{
		From: v.pos(exprCtx.GetStart()),
		To:   v.pos(exprCtx.GetStop()),
	}
}

// VisitStructInitExpr handles struct initialization expressions with named fields.
// Example: Point(x: 1, y: 2) -> Point{x: 1, y: 2}
func (v *ManuscriptAstVisitor) VisitStructInitExpr(ctx *parser.StructInitExprContext) interface{} {
	if ctx == nil {
		v.addError("VisitStructInitExpr called with nil context", nil)
		return &ast.BadExpr{}
	}

	// Get the struct type name
	if ctx.ID() == nil {
		v.addError("Struct initialization missing type name", ctx.GetStart())
		return &ast.BadExpr{}
	}
	structTypeName := ctx.ID().GetText()
	structTypeExpr := ast.NewIdent(structTypeName)

	// Process each field
	keyValueElts := make([]ast.Expr, 0)

	for _, fieldCtx := range ctx.AllStructField() {
		if fieldCtx.GetKey() == nil {
			v.addError("Struct field missing key", fieldCtx.GetStart())
			continue
		}
		fieldName := fieldCtx.GetKey().GetText()

		if fieldCtx.GetVal() == nil {
			v.addError("Struct field missing value", fieldCtx.GetStart())
			continue
		}
		valueResult := v.Visit(fieldCtx.GetVal())
		valueExpr, ok := valueResult.(ast.Expr)
		if !ok {
			v.addError("Struct field value did not resolve to a valid expression", fieldCtx.GetVal().GetStart())
			continue
		}

		keyValueElts = append(keyValueElts, &ast.KeyValueExpr{
			Key:   ast.NewIdent(fieldName),
			Value: valueExpr,
		})
	}

	// Create a composite literal representing the struct initialization
	return &ast.CompositeLit{
		Type: structTypeExpr,
		Elts: keyValueElts,
	}
}
