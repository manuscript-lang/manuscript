package visitor

import (
	"fmt"
	"go/ast"
	"manuscript-co/manuscript/internal/parser"
)

// VisitPostfixExpr handles left-recursive postfix expressions using the ANTLR visitor pattern.
func (v *ManuscriptAstVisitor) VisitPostfixExpr(ctx *parser.PostfixExprContext) interface{} {
	// Base case: just a primary expression
	if ctx.PostfixExpr() == nil || ctx.PostfixOp() == nil {
		primary := ctx.PrimaryExpr()
		if primary == nil {
			v.addError("PostfixExpr missing primary expression", ctx.GetStart())
			return &ast.BadExpr{From: v.pos(ctx.GetStart()), To: v.pos(ctx.GetStop())}
		}
		res := v.Visit(primary)
		if expr, ok := res.(ast.Expr); ok {
			return expr
		}
		v.addError(fmt.Sprintf("PrimaryExpr did not resolve to ast.Expr, got %T", res), ctx.GetStart())
		return &ast.BadExpr{From: v.pos(ctx.GetStart()), To: v.pos(ctx.GetStop())}
	}

	// Recursive case: left is a postfixExpr, right is a postfixOp
	left := v.Visit(ctx.PostfixExpr())
	if left == nil {
		v.addError("Left side of PostfixExpr is nil", ctx.GetStart())
		return &ast.BadExpr{From: v.pos(ctx.GetStart()), To: v.pos(ctx.GetStop())}
	}
	leftExpr, ok := left.(ast.Expr)
	if !ok {
		v.addError(fmt.Sprintf("Left side of PostfixExpr did not resolve to ast.Expr, got %T", left), ctx.GetStart())
		return &ast.BadExpr{From: v.pos(ctx.GetStart()), To: v.pos(ctx.GetStop())}
	}

	right := ctx.PostfixOp()
	if right == nil {
		v.addError("PostfixExpr missing PostfixOp", ctx.GetStart())
		return &ast.BadExpr{From: v.pos(ctx.GetStart()), To: v.pos(ctx.GetStop())}
	}
	// Use the visitor pattern for the postfix operation
	return v.visitPostfixOp(right, leftExpr)
}

// visitPostfixOp dispatches to the correct postfix operation visitor.
func (v *ManuscriptAstVisitor) visitPostfixOp(op parser.IPostfixOpContext, x ast.Expr) ast.Expr {
	switch t := op.(type) {
	case *parser.PostfixCallContext:
		return v.VisitPostfixCallWithReceiver(t, x)
	case *parser.PostfixDotContext:
		return v.VisitPostfixDotWithReceiver(t, x)
	case *parser.PostfixIndexContext:
		return v.VisitPostfixIndexWithReceiver(t, x)
	default:
		v.addError("Unknown postfix operation type", op.GetStart())
		return &ast.BadExpr{From: v.pos(op.GetStart()), To: v.pos(op.GetStop())}
	}
}

// VisitPostfixCallWithReceiver handles function calls: x(args...)
func (v *ManuscriptAstVisitor) VisitPostfixCallWithReceiver(ctx *parser.PostfixCallContext, recv ast.Expr) ast.Expr {
	args := []ast.Expr{}
	if ctx.ExprList() != nil {
		if exprListCtx, ok := ctx.ExprList().(*parser.ExprListContext); ok {
			for _, exprNode := range exprListCtx.AllExpr() {
				if argAst, visitOk := v.Visit(exprNode).(ast.Expr); visitOk && argAst != nil {
					args = append(args, argAst)
				} else {
					v.addError("Invalid argument expression in call: "+exprNode.GetText(), exprNode.GetStart())
					args = append(args, &ast.BadExpr{From: v.pos(exprNode.GetStart()), To: v.pos(exprNode.GetStop())})
				}
			}
		}
	}
	return &ast.CallExpr{
		Fun:    recv,
		Lparen: v.pos(ctx.LPAREN().GetSymbol()),
		Args:   args,
		Rparen: v.pos(ctx.RPAREN().GetSymbol()),
	}
}

// VisitPostfixDotWithReceiver handles member access: x.y
func (v *ManuscriptAstVisitor) VisitPostfixDotWithReceiver(ctx *parser.PostfixDotContext, recv ast.Expr) ast.Expr {
	if ctx.DOT() == nil || ctx.ID() == nil {
		v.addError("Malformed member access (dot) operation", ctx.GetStart())
		return &ast.BadExpr{From: v.pos(ctx.GetStart()), To: v.pos(ctx.GetStop())}
	}
	return &ast.SelectorExpr{
		X:   recv,
		Sel: ast.NewIdent(ctx.ID().GetText()),
	}
}

// VisitPostfixIndexWithReceiver handles index access: x[y]
func (v *ManuscriptAstVisitor) VisitPostfixIndexWithReceiver(ctx *parser.PostfixIndexContext, recv ast.Expr) ast.Expr {
	if ctx.LSQBR() == nil || ctx.RSQBR() == nil || ctx.Expr() == nil {
		v.addError("Malformed index operation", ctx.GetStart())
		return &ast.BadExpr{From: v.pos(ctx.GetStart()), To: v.pos(ctx.GetStop())}
	}
	indexNode := ctx.Expr()
	indexAst := v.Visit(indexNode)
	indexExpr, ok := indexAst.(ast.Expr)
	if !ok || indexExpr == nil {
		v.addError("Invalid index expression: "+indexNode.GetText(), indexNode.GetStart())
		return &ast.BadExpr{From: v.pos(ctx.LSQBR().GetSymbol()), To: v.pos(ctx.RSQBR().GetSymbol())}
	}
	return &ast.IndexExpr{
		X:      recv,
		Lbrack: v.pos(ctx.LSQBR().GetSymbol()),
		Index:  indexExpr,
		Rbrack: v.pos(ctx.RSQBR().GetSymbol()),
	}
}
