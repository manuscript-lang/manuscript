package visitor

import (
	"fmt"
	"go/ast"
	"go/token"
	"manuscript-co/manuscript/internal/parser"

	"github.com/antlr4-go/antlr/v4"
)

// TryMarkerExpr is a special ast.Expr node to indicate that an expression
// was originally a 'try' expression. This helps the visitor for 'let' statements
// generate the correct error handling code.
type TryMarkerExpr struct {
	ast.BadExpr  // Embed ast.BadExpr to satisfy ast.Expr interface (including unexported methods)
	OriginalExpr ast.Expr
	TryPos       token.Pos // Position of the 'try' keyword
}

func (t *TryMarkerExpr) Pos() token.Pos { return t.TryPos }
func (t *TryMarkerExpr) End() token.Pos {
	// End position should be the end of the original expression
	if t.OriginalExpr != nil {
		return t.OriginalExpr.End()
	}
	return t.TryPos // Fallback
}

// exprNode() makes it satisfy the ast.Expr interface.
// func (t *TryMarkerExpr) exprNode() {} // No longer needed if ast.BadExpr is embedded

// Ensure TryMarkerExpr implements ast.Expr (compile-time check)
var _ ast.Expr = (*TryMarkerExpr)(nil)

// buildTryLogic encapsulates the common AST generation for try-catch patterns.
// lhsValueExpr is the identifier for the value (e.g., 'a' in 'let a = try f()'), or underscore for standalone try.
// triedExpr is the actual expression that was wrapped by 'try'.
func (v *ManuscriptAstVisitor) buildTryLogic(lhsValueExpr ast.Expr, triedExpr ast.Expr) []ast.Stmt {
	errIdent := ast.NewIdent("err")

	assignLHS := []ast.Expr{lhsValueExpr, errIdent}
	// If lhsValueExpr is nil or explicitly underscore, it means we don't care about the value part.
	// However, Go's `:=` requires a new variable on the LHS. If triedExpr only returns an error,
	// this would be `err := triedExpr`. If it returns (val, err), it's `val, err` or `_, err`.
	// For simplicity, we assume triedExpr *might* return a value, so `lhsValueExpr, err` is the general form.
	// If lhsValueExpr is ast.NewIdent("_"), it correctly becomes `_, err`.

	assignStmt := &ast.AssignStmt{
		Lhs: assignLHS,
		Tok: token.DEFINE,
		Rhs: []ast.Expr{triedExpr},
	}

	ifStmt := &ast.IfStmt{
		Cond: &ast.BinaryExpr{
			X:  errIdent,
			Op: token.NEQ,
			Y:  ast.NewIdent("nil"),
		},
		Body: &ast.BlockStmt{
			List: []ast.Stmt{
				&ast.ReturnStmt{
					Results: []ast.Expr{ast.NewIdent("nil"), errIdent},
				},
			},
		},
	}
	return []ast.Stmt{assignStmt, ifStmt}
}

// VisitUnaryExpr is the main entry for unary expressions, dispatching to the correct sub-visitor.
func (v *ManuscriptAstVisitor) VisitUnaryExpr(ctx *parser.UnaryExprContext) interface{} {
	if ctx == nil {
		v.addError("VisitUnaryExpr called with nil context", nil)
		return &ast.BadExpr{}
	}
	return ctx.Accept(v)
}

// VisitUnaryOpExpr handles unary operator expressions: +, -, !, try
func (v *ManuscriptAstVisitor) VisitLabelUnaryOpExpr(ctx *parser.LabelUnaryOpExprContext) interface{} {
	opToken := ctx.GetOp()
	if opToken == nil {
		v.addError("Unary operator expression missing operator token", ctx.GetStart())
		return &ast.BadExpr{From: v.pos(ctx.GetStart()), To: v.pos(ctx.GetStop())}
	}
	operandCtx := ctx.UnaryExpr()
	if operandCtx == nil {
		v.addError(fmt.Sprintf("Unary operator '%s' found without an operand expression", opToken.GetText()), opToken)
		return &ast.BadExpr{From: v.pos(opToken), To: v.pos(opToken)}
	}
	operandResult := v.Visit(operandCtx)
	operandExpr, ok := operandResult.(ast.Expr)
	if !ok {
		v.addError(fmt.Sprintf("Operand for unary operator '%s' did not resolve to an ast.Expr. Got %T", opToken.GetText(), operandResult), opToken)
		return &ast.BadExpr{From: v.pos(opToken), To: v.pos(opToken)}
	}
	return v.buildUnaryOpExpr(opToken, operandExpr)
}

// VisitUnaryAwaitExpr handles await expressions (awaitExpr)
func (v *ManuscriptAstVisitor) VisitLabelUnaryAwaitExpr(ctx *parser.LabelUnaryAwaitExprContext) interface{} {
	awaitCtx := ctx.AwaitExpr()
	if awaitCtx == nil {
		v.addError("UnaryAwaitExpr missing AwaitExpr child", ctx.GetStart())
		return &ast.BadExpr{From: v.pos(ctx.GetStart()), To: v.pos(ctx.GetStop())}
	}
	return v.Visit(awaitCtx)
}

// buildUnaryOpExpr is a helper to construct Go AST for unary operators
func (v *ManuscriptAstVisitor) buildUnaryOpExpr(opToken antlr.Token, operandExpr ast.Expr) ast.Expr {
	opPos := v.pos(opToken)
	switch opToken.GetTokenType() {
	case parser.ManuscriptTRY:
		return &TryMarkerExpr{OriginalExpr: operandExpr, TryPos: opPos}
	case parser.ManuscriptPLUS:
		return &ast.UnaryExpr{OpPos: opPos, Op: token.ADD, X: operandExpr}
	case parser.ManuscriptMINUS:
		return &ast.UnaryExpr{OpPos: opPos, Op: token.SUB, X: operandExpr}
	case parser.ManuscriptEXCLAMATION:
		return &ast.UnaryExpr{OpPos: opPos, Op: token.NOT, X: operandExpr}
	default:
		v.addError(fmt.Sprintf("Unsupported unary operator: %s", opToken.GetText()), opToken)
		return &ast.BadExpr{From: opPos, To: opPos + token.Pos(len(opToken.GetText()))}
	}
}
