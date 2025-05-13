package codegen

import (
	"bytes"
	"fmt"
	"go/ast"
	"go/printer"
	"go/token"
	"log"
	"manuscript-co/manuscript/internal/parser"
	"strconv"

	"github.com/antlr4-go/antlr/v4"
)

// For logging errors/unhandled cases

// CodeGenerator is responsible for generating Go code from the parsed AST.
type CodeGenerator struct{} // No longer needs fileSet here

// NewCodeGenerator creates a new instance of CodeGenerator.
func NewCodeGenerator() *CodeGenerator {
	return &CodeGenerator{}
}

// GoAstVisitor implements the ANTLR visitor pattern to build a Go AST.
// It embeds the base visitor struct provided by ANTLR.
type GoAstVisitor struct {
	*parser.BaseManuscriptVisitor
	// Add any necessary state fields here if needed (e.g., symbol table)
}

// NewGoAstVisitor creates a new visitor instance.
func NewGoAstVisitor() *GoAstVisitor {
	// Initialize with the base visitor. It's important to initialize the embedded struct.
	return &GoAstVisitor{
		BaseManuscriptVisitor: &parser.BaseManuscriptVisitor{},
	}
}

// Generate takes the parsed Manuscript AST root and produces Go code using the visitor.
func (cg *CodeGenerator) Generate(astNode interface{}) (string, error) {
	root, ok := astNode.(antlr.ParseTree)
	if !ok {
		// Use fmt.Errorf for error creation
		return "", fmt.Errorf("error: Input to Generate is not an antlr.ParseTree")
	}

	visitor := NewGoAstVisitor()
	// The top-level visit should return the complete Go AST File node.
	// The Visit method starts the traversal. It will dispatch to VisitProgram.
	visitedNode := visitor.Visit(root)

	// Check if the result is the expected *ast.File
	goAST, ok := visitedNode.(*ast.File)
	if !ok || goAST == nil {
		// Log the type returned if it wasn't *ast.File
		log.Printf("Error: Visiting the root node did not return a valid *ast.File. Got type: %T", visitedNode)
		return "", fmt.Errorf("error: AST generation failed to produce a Go file node")
	}

	fileSet := token.NewFileSet() // Need fileset for printing
	var buf bytes.Buffer
	config := printer.Config{Mode: printer.TabIndent | printer.UseSpaces, Tabwidth: 4}
	// Print the generated Go AST to the buffer
	if err := config.Fprint(&buf, fileSet, goAST); err != nil {
		return "", fmt.Errorf("error printing Go AST: %w", err)
	}
	return buf.String(), nil
}

// --- Visitor Method Implementations (Starting Point) ---

// VisitProgram handles the root of the parse tree (program rule).
func (v *GoAstVisitor) VisitProgram(ctx *parser.ProgramContext) interface{} {
	file := &ast.File{
		Name:  ast.NewIdent("main"), // Default to main package
		Decls: []ast.Decl{},         // Declarations will be added here
	}
	mainFunc := &ast.FuncDecl{
		Name: ast.NewIdent("main"),
		Type: &ast.FuncType{Params: &ast.FieldList{}, Results: nil},
		Body: &ast.BlockStmt{List: []ast.Stmt{}},
	}
	file.Decls = append(file.Decls, mainFunc)
	mainBody := &mainFunc.Body.List

	for _, itemCtx := range ctx.AllProgramItem() {
		var visitedItem interface{}
		if stmtCtx := itemCtx.Stmt(); stmtCtx != nil {
			if concreteStmtCtx, ok := stmtCtx.(*parser.StmtContext); ok {
				visitedItem = v.VisitStmt(concreteStmtCtx)
			} else {
				log.Printf("Warning: Could not assert StmtContext type for %s", itemCtx.GetText())
			}
		} else if fnDeclCtx := itemCtx.FnDecl(); fnDeclCtx != nil {
			if concreteFnDeclCtx, ok := fnDeclCtx.(*parser.FnDeclContext); ok {
				visitedItem = v.Visit(concreteFnDeclCtx)
			} else {
				log.Printf("Warning: Could not assert FnDeclContext type for %s", itemCtx.GetText())
			}
		} else {
			// Log only if it's not one of the types we explicitly check for above
			if itemCtx.Stmt() == nil && itemCtx.FnDecl() == nil /* && other checked types == nil */ {
				log.Printf("Warning: Unhandled ProgramItem type in VisitProgram loop: %s", itemCtx.GetText())
			}
		}

		switch node := visitedItem.(type) {
		case ast.Stmt:
			*mainBody = append(*mainBody, node)
		case ast.Decl:
			if funcDecl, ok := node.(*ast.FuncDecl); !ok || funcDecl.Name.Name != "main" {
				file.Decls = append(file.Decls, node)
			}
		case nil:
			// Expected if an unhandled/unassertable ProgramItem type was encountered
		default:
			log.Printf("Warning: Unhandled node type (%T) returned from ProgramItem processing for item: %s", node, itemCtx.GetText())
			if expr, ok := node.(ast.Expr); ok {
				log.Printf("Treating returned expression as statement in main func.")
				*mainBody = append(*mainBody, &ast.ExprStmt{X: expr})
			}
		}
	}

	return file
}

// VisitChildren implements the default behavior of visiting children nodes.
// ANTLR's Go target requires this to be implemented manually for traversal.
func (v *GoAstVisitor) VisitChildren(node antlr.RuleNode) interface{} {
	var result interface{}
	for i := 0; i < node.GetChildCount(); i++ {
		child := node.GetChild(i)
		// Ensure the child is a ParseTree before calling Accept
		if pt, ok := child.(antlr.ParseTree); ok {
			result = pt.Accept(v)
			// TODO: Decide if we need to aggregate results or handle specific return values.
			// For now, just continue traversal. If a Visit* method returns something
			// specific (like an error or a specific AST node), we might need logic here.
		}
	}
	return result // Often nil in visitor patterns where side effects dominate.
}

// Visit implements parser.ManuscriptVisitor.
func (v *GoAstVisitor) Visit(tree antlr.ParseTree) interface{} {
	// The default Visit method provided by ANTLR often delegates to Accept.
	// We can keep the default or customize if needed. Usually, Accept is preferred.
	// For safety, let's ensure Accept is called.
	if tree == nil {
		return nil
	}
	return tree.Accept(v)
}

// VisitTerminal is called for leaf nodes (tokens). Usually ignored unless needed.
// func (v *GoAstVisitor) VisitTerminal(node antlr.TerminalNode) interface{} {
// 	return nil // Or return node.GetText() if needed
// }

// VisitErrorNode is called if the parser encounters an error.
// func (v *GoAstVisitor) VisitErrorNode(node antlr.ErrorNode) interface{} {
// 	log.Printf("Error node encountered: %s", node.GetText())
// 	return nil // Or an error representation
// }

// TODO: Implement other Visit methods based on the action plan (Phase 2 onwards)
// e.g., VisitProgramItem, VisitStmt, VisitExprStmt, VisitLetDecl, VisitAssignmentExpr, etc.

// VisitStmt handles different kinds of statements.
func (v *GoAstVisitor) VisitStmt(ctx *parser.StmtContext) interface{} {
	log.Printf("VisitStmt: Called for '%s'", ctx.GetText()) // Log entry

	if ctx.LetDecl() != nil {
		log.Printf("VisitStmt: Found LetDecl: %s", ctx.LetDecl().GetText())
		return v.VisitLetDecl(ctx.LetDecl().(*parser.LetDeclContext))
	}

	if exprStmtCtx := ctx.ExprStmt(); exprStmtCtx != nil {
		log.Printf("VisitStmt: Found ExprStmt: %s", exprStmtCtx.GetText())
		if concreteExprStmtCtx, ok := exprStmtCtx.(*parser.ExprStmtContext); ok {
			log.Printf("VisitStmt: Asserted ExprStmtContext, calling VisitExprStmt for '%s'", concreteExprStmtCtx.GetText())
			return v.VisitExprStmt(concreteExprStmtCtx)
		} else {
			log.Printf("VisitStmt: Failed to assert ExprStmtContext type for '%s'", exprStmtCtx.GetText())
			return nil
		}
	}

	if ctx.SEMICOLON() != nil {
		log.Printf("VisitStmt: Found SEMICOLON (empty statement): %s", ctx.GetText())
		return nil
	}

	log.Printf("VisitStmt: Unhandled statement type for '%s'", ctx.GetText())
	return nil // Return nil if unhandled
}

// VisitExprStmt processes an expression statement.
func (v *GoAstVisitor) VisitExprStmt(ctx *parser.ExprStmtContext) interface{} {
	// Explicitly visit only the expression part, ignore the semicolon child
	visitedExprRaw := v.Visit(ctx.Expr()) // Visit the core expression
	// Add detailed logging here:
	log.Printf("VisitExprStmt: Visited ctx.Expr() for '%s', got type %T, value: %+v", ctx.Expr().GetText(), visitedExprRaw, visitedExprRaw)

	if expr, ok := visitedExprRaw.(ast.Expr); ok {
		// Wrap the resulting expression in an ast.ExprStmt
		log.Printf("VisitExprStmt: Successfully asserted ast.Expr for '%s'", ctx.Expr().GetText()) // Log success
		return &ast.ExprStmt{X: expr}
	}

	// Log if the assertion failed
	log.Printf("VisitExprStmt: Failed to assert ast.Expr for '%s'. Got type %T instead.", ctx.Expr().GetText(), visitedExprRaw)
	return nil // Return nil if the expression visit failed
}

// --- Literal Handling ---

// VisitLiteral dispatches to specific literal type visitors or handles terminals directly.
func (v *GoAstVisitor) VisitLiteral(ctx *parser.LiteralContext) interface{} {
	if ctx.NumberLiteral() != nil {
		return v.Visit(ctx.NumberLiteral())
	}
	if ctx.StringLiteral() != nil {
		return v.Visit(ctx.StringLiteral())
	}
	if ctx.BooleanLiteral() != nil {
		return v.Visit(ctx.BooleanLiteral())
	}
	// VOID and NULL are likely terminals within LiteralContext
	if ctx.VOID() != nil {
		// Map Manuscript's `void` to Go's `nil`
		return ast.NewIdent("nil")
	}
	if ctx.NULL() != nil {
		// Map Manuscript's `null` to Go's `nil`
		return ast.NewIdent("nil")
	}
	// TODO: Handle ArrayLiteral and ObjectLiteral when implemented

	log.Printf("Warning: Unhandled literal type in VisitLiteral: %s", ctx.GetText())
	return nil
}

// VisitNumberLiteral converts a number literal context to an ast.BasicLit.
func (v *GoAstVisitor) VisitNumberLiteral(ctx *parser.NumberLiteralContext) interface{} {
	text := ctx.GetText()
	log.Printf("VisitNumberLiteral: Processing '%s'", text)

	// Check explicit token types first
	if ctx.INTEGER() != nil {
		intText := ctx.INTEGER().GetText()
		log.Printf("VisitNumberLiteral: Found INTEGER token with value '%s'", intText)
		return &ast.BasicLit{
			Kind:  token.INT,
			Value: intText,
		}
	}

	if ctx.FLOAT() != nil {
		floatText := ctx.FLOAT().GetText()
		log.Printf("VisitNumberLiteral: Found FLOAT token with value '%s'", floatText)
		return &ast.BasicLit{
			Kind:  token.FLOAT,
			Value: floatText,
		}
	}

	if ctx.HEX_LITERAL() != nil {
		hexText := ctx.HEX_LITERAL().GetText()
		log.Printf("VisitNumberLiteral: Found HEX_LITERAL token with value '%s'", hexText)
		return &ast.BasicLit{
			Kind:  token.INT,
			Value: hexText,
		}
	}

	if ctx.BINARY_LITERAL() != nil {
		binText := ctx.BINARY_LITERAL().GetText()
		log.Printf("VisitNumberLiteral: Found BINARY_LITERAL token with value '%s'", binText)
		return &ast.BasicLit{
			Kind:  token.INT,
			Value: binText,
		}
	}

	// If no specific token detected, try to infer the type from the text
	// This is a fallback mechanism in case the lexer doesn't properly tokenize
	if text != "" {
		log.Printf("VisitNumberLiteral: No specific token found, inferring type from text '%s'", text)
		if _, err := strconv.ParseInt(text, 10, 64); err == nil {
			return &ast.BasicLit{
				Kind:  token.INT,
				Value: text,
			}
		} else if _, err := strconv.ParseFloat(text, 64); err == nil {
			return &ast.BasicLit{
				Kind:  token.FLOAT,
				Value: text,
			}
		}
	}

	log.Printf("Error: Failed to parse number literal: %s", text)
	return &ast.BasicLit{
		Kind:  token.INT,
		Value: "0", // Default to 0 to avoid compiler errors
	}
}

// VisitStringLiteral converts a string literal context to an ast.BasicLit.
func (v *GoAstVisitor) VisitStringLiteral(ctx *parser.StringLiteralContext) interface{} {
	text := ctx.GetText()
	log.Printf("VisitStringLiteral: Processing '%s'", text)

	// Extract string content regardless of quote style
	if ctx.SingleQuotedString() != nil {
		// Handle single-quoted string - need to convert to double-quoted for Go
		content := ""

		// Extract content between the quotes
		if parts := ctx.SingleQuotedString().AllStringPart(); len(parts) > 0 {
			for _, part := range parts {
				if strContent := part.SINGLE_STR_CONTENT(); strContent != nil {
					content += strContent.GetText()
				}
			}
		}

		// Convert to Go string with double quotes
		goStr := strconv.Quote(content)
		log.Printf("VisitStringLiteral: Converted single-quoted '%s' to double-quoted %s", text, goStr)
		return &ast.BasicLit{
			Kind:  token.STRING,
			Value: goStr,
		}
	} else if ctx.MultiQuotedString() != nil {
		// Handle multi-quoted string (similar approach)
		content := ""

		// Extract content between triple quotes
		if parts := ctx.MultiQuotedString().AllStringPart(); len(parts) > 0 {
			for _, part := range parts {
				if strContent := part.MULTI_STR_CONTENT(); strContent != nil {
					content += strContent.GetText()
				}
			}
		}

		// Convert to Go string with double quotes
		goStr := strconv.Quote(content)
		log.Printf("VisitStringLiteral: Converted multi-quoted '%s' to double-quoted %s", text, goStr)
		return &ast.BasicLit{
			Kind:  token.STRING,
			Value: goStr,
		}
	}

	log.Printf("Warning: Malformed string literal detected: %s", text)
	return &ast.BadExpr{}
}

// VisitBooleanLiteral converts a boolean literal context to an ast.Ident (true/false).
func (v *GoAstVisitor) VisitBooleanLiteral(ctx *parser.BooleanLiteralContext) interface{} {
	text := ctx.GetText()
	if text == "true" {
		return ast.NewIdent("true")
	} else if text == "false" {
		return ast.NewIdent("false")
	} else {
		log.Printf("Warning: Unrecognized boolean literal: %s", text)
		// Go doesn't have a specific boolean literal node, `true` and `false` are identifiers.
		// Return BadExpr on error
		return &ast.BadExpr{}
	}
}

// --- Expression Handling (Starting with Primary) ---

// VisitPrimaryExpr handles the base cases of expressions.
func (v *GoAstVisitor) VisitPrimaryExpr(ctx *parser.PrimaryExprContext) interface{} {
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
func (v *GoAstVisitor) VisitUnaryExpr(ctx *parser.UnaryExprContext) interface{} {
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
func (v *GoAstVisitor) VisitExpr(ctx *parser.ExprContext) interface{} {
	return v.Visit(ctx.AssignmentExpr())
}

// VisitAssignmentExpr handles assignment or passes through logicalOrExpr.
func (v *GoAstVisitor) VisitAssignmentExpr(ctx *parser.AssignmentExprContext) interface{} {
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
func (v *GoAstVisitor) VisitLogicalOrExpr(ctx *parser.LogicalOrExprContext) interface{} {
	if ctx.GetOp() != nil { // OR case
		// TODO: Implement binary OR logic (return *ast.BinaryExpr)
		log.Printf("Warning: Logical OR expression not fully handled: %s", ctx.GetText())
		return v.Visit(ctx.GetLeft()) // Placeholder
	}
	// Pass-through case
	return v.Visit(ctx.GetLeft()) // Visit the logicalAndExpr
}

// VisitLogicalAndExpr handles && or passes through equalityExpr.
func (v *GoAstVisitor) VisitLogicalAndExpr(ctx *parser.LogicalAndExprContext) interface{} {
	if ctx.GetOp() != nil { // AND case
		// TODO: Implement binary AND logic
		log.Printf("Warning: Logical AND expression not fully handled: %s", ctx.GetText())
		return v.Visit(ctx.GetLeft()) // Placeholder
	}
	// Pass-through case
	return v.Visit(ctx.GetLeft()) // Visit the equalityExpr
}

// VisitEqualityExpr handles ==, != or passes through comparisonExpr.
func (v *GoAstVisitor) VisitEqualityExpr(ctx *parser.EqualityExprContext) interface{} {
	if ctx.GetOp() != nil { // Equality op case
		// TODO: Implement equality logic
		log.Printf("Warning: Equality expression not fully handled: %s", ctx.GetText())
		return v.Visit(ctx.GetLeft()) // Placeholder
	}
	// Pass-through case
	return v.Visit(ctx.GetLeft()) // Visit the comparisonExpr
}

// VisitComparisonExpr handles <, <=, >, >= or passes through additiveExpr.
func (v *GoAstVisitor) VisitComparisonExpr(ctx *parser.ComparisonExprContext) interface{} {
	if ctx.GetOp() != nil { // Comparison op case
		// TODO: Implement comparison logic
		log.Printf("Warning: Comparison expression not fully handled: %s", ctx.GetText())
		return v.Visit(ctx.GetLeft()) // Placeholder
	}
	// Pass-through case
	return v.Visit(ctx.GetLeft()) // Visit the additiveExpr
}

// VisitAdditiveExpr handles +, - or passes through multiplicativeExpr.
func (v *GoAstVisitor) VisitAdditiveExpr(ctx *parser.AdditiveExprContext) interface{} {
	if ctx.GetOp() != nil { // Add/Sub case
		// TODO: Implement add/sub logic
		log.Printf("Warning: Additive expression not fully handled: %s", ctx.GetText())
		return v.Visit(ctx.GetLeft()) // Placeholder
	}
	// Pass-through case
	return v.Visit(ctx.GetLeft()) // Visit the multiplicativeExpr
}

// VisitMultiplicativeExpr handles *, / or passes through unaryExpr.
func (v *GoAstVisitor) VisitMultiplicativeExpr(ctx *parser.MultiplicativeExprContext) interface{} {
	if ctx.GetOp() != nil { // Mul/Div case
		// TODO: Implement mul/div logic
		log.Printf("Warning: Multiplicative expression not fully handled: %s", ctx.GetText())
		return v.Visit(ctx.GetLeft()) // Placeholder
	}
	// Pass-through case
	return v.Visit(ctx.GetLeft()) // Visit the unaryExpr
}

// VisitAwaitExpr handles prefixes or passes through postfixExpr.
func (v *GoAstVisitor) VisitAwaitExpr(ctx *parser.AwaitExprContext) interface{} {
	if ctx.TRY() != nil || ctx.AWAIT() != nil || ctx.ASYNC() != nil {
		// TODO: Implement prefix handling (TRY?, AWAIT?, ASYNC?)
		log.Printf("Warning: TRY/AWAIT/ASYNC prefixes not fully handled: %s", ctx.GetText())
	}
	// Always visit the postfix expression part
	return v.Visit(ctx.PostfixExpr())
}

// VisitPostfixExpr handles calls, member access, index access or passes through primaryExpr.
func (v *GoAstVisitor) VisitPostfixExpr(ctx *parser.PostfixExprContext) interface{} {
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

// VisitLetDecl handles variable declarations like "let x = 10;"
func (v *GoAstVisitor) VisitLetDecl(ctx *parser.LetDeclContext) interface{} {
	log.Printf("VisitLetDecl: Called for '%s'", ctx.GetText())

	// Go statement to return eventually
	var declStmt ast.Stmt

	// For multiple assignments in a single let declaration, we'll create a block statement
	if len(ctx.GetAssignments()) > 1 {
		blockStmt := &ast.BlockStmt{List: []ast.Stmt{}}

		for _, assignment := range ctx.GetAssignments() {
			if assignmentResult := v.VisitLetAssignment(assignment.(*parser.LetAssignmentContext)); assignmentResult != nil {
				if assignStmt, ok := assignmentResult.(ast.Stmt); ok {
					blockStmt.List = append(blockStmt.List, assignStmt)
				} else {
					log.Printf("VisitLetDecl: Assignment result is not a statement: %T", assignmentResult)
				}
			}
		}

		declStmt = blockStmt
	} else if len(ctx.GetAssignments()) == 1 {
		// For a single assignment, just return the statement
		assignment := ctx.GetAssignments()[0]
		assignmentResult := v.VisitLetAssignment(assignment.(*parser.LetAssignmentContext))
		if stmt, ok := assignmentResult.(ast.Stmt); ok {
			declStmt = stmt
		} else {
			log.Printf("VisitLetDecl: Single assignment result is not a statement: %T", assignmentResult)
		}
	} else {
		log.Printf("VisitLetDecl: No assignments found in let declaration")
		return nil
	}

	return declStmt
}

// VisitLetAssignment handles the individual assignments in a let declaration
func (v *GoAstVisitor) VisitLetAssignment(ctx *parser.LetAssignmentContext) interface{} {
	log.Printf("VisitLetAssignment: Called for '%s'", ctx.GetText())

	// Visit the pattern (LHS of the assignment)
	patternRaw := v.Visit(ctx.LetPattern())
	if patternRaw == nil {
		log.Printf("VisitLetAssignment: Pattern visit returned nil")
		return nil
	}

	// For now, we'll only handle simple patterns (identifiers)
	var lhs []ast.Expr

	switch pattern := patternRaw.(type) {
	case ast.Expr:
		lhs = []ast.Expr{pattern}
	case []ast.Expr:
		lhs = pattern
	default:
		log.Printf("VisitLetAssignment: Unexpected pattern type: %T", pattern)
		return nil
	}

	// If there's a value, visit the expression (RHS of the assignment)
	var rhs []ast.Expr
	if ctx.GetValue() != nil {
		valueRaw := v.Visit(ctx.GetValue())

		if valueRaw == nil {
			log.Printf("VisitLetAssignment: Value visit returned nil")
			return nil
		}

		switch value := valueRaw.(type) {
		case ast.Expr:
			rhs = []ast.Expr{value}
		case []ast.Expr:
			rhs = value
		default:
			log.Printf("VisitLetAssignment: Unexpected value type: %T", value)
			return nil
		}
	} else {
		// If no value provided, the Go zero value will be used by default
		// For simple patterns, we can use nil as placeholder
		// This creates "var x" declaration
		return &ast.DeclStmt{
			Decl: &ast.GenDecl{
				Tok: token.VAR,
				Specs: []ast.Spec{
					&ast.ValueSpec{
						Names: []*ast.Ident{lhs[0].(*ast.Ident)},
					},
				},
			},
		}
	}

	// Create the Go-style ":=" statement (short variable declaration)
	return &ast.AssignStmt{
		Lhs: lhs,
		Tok: token.DEFINE, // ":=" operator
		Rhs: rhs,
	}
}

// VisitLetPattern handles the left side of a let declaration
func (v *GoAstVisitor) VisitLetPattern(ctx *parser.LetPatternContext) interface{} {
	log.Printf("VisitLetPattern: Called for '%s'", ctx.GetText())

	// Handle simple identifiers
	if ctx.ID() != nil {
		idToken := ctx.ID().GetSymbol()
		idName := idToken.GetText()
		log.Printf("VisitLetPattern: Found simple ID pattern: %s", idName)
		return ast.NewIdent(idName)
	}

	// Handle array patterns - convert to multiple variables
	if ctx.ArrayPattn() != nil {
		log.Printf("VisitLetPattern: Found array pattern, not fully implemented yet")
		// TODO: Full implementation for array destructuring
		return nil
	}

	// Handle object patterns - convert to multiple variables
	if ctx.ObjectPattn() != nil {
		log.Printf("VisitLetPattern: Found object pattern, not fully implemented yet")
		// TODO: Full implementation for object destructuring
		return nil
	}

	log.Printf("VisitLetPattern: Unhandled pattern type")
	return nil
}

// --- End of CodeGenerator methods ---
