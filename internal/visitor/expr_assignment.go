package visitor

import (
	"go/ast"
	"go/token"
	"manuscript-co/manuscript/internal/parser"
	"strconv"
)

func (v *ManuscriptAstVisitor) VisitAssignmentExpr(ctx *parser.AssignmentExprContext) interface{} {
	leftAntlrExpr := ctx.GetLeft()
	if leftAntlrExpr == nil {
		v.addError("Left-hand side of assignment is missing", ctx.GetStart())
		return &ast.BadStmt{}
	}
	visitedLeftExpr := v.Visit(leftAntlrExpr)
	leftExpr, ok := visitedLeftExpr.(ast.Expr)
	if !ok {
		v.addError("Left-hand side of assignment did not resolve to a valid expression: "+leftAntlrExpr.GetText(), leftAntlrExpr.GetStart())
		return &ast.BadStmt{}
	}

	if ctx.GetOp() != nil {
		opType := ctx.GetOp().GetTokenType()
		rightAntlrExpr := ctx.GetRight()
		if rightAntlrExpr == nil {
			v.addError("Right-hand side of assignment is missing for operator "+ctx.GetOp().GetText(), ctx.GetOp())
			return &ast.BadStmt{}
		}
		visitedRightExpr := v.Visit(rightAntlrExpr)
		rightExpr, ok := visitedRightExpr.(ast.Expr)
		if !ok {
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
			binaryOpToken = token.XOR
		default:
			v.addError("Unhandled assignment operator: "+ctx.GetOp().GetText(), ctx.GetOp())
			return &ast.BadStmt{}
		}
		rhsBinaryExpr := &ast.BinaryExpr{
			X:  leftExpr,
			Op: binaryOpToken,
			Y:  rightExpr,
		}
		return &ast.AssignStmt{
			Lhs: []ast.Expr{leftExpr},
			Tok: token.ASSIGN,
			Rhs: []ast.Expr{rhsBinaryExpr},
		}
	}
	return leftExpr
}
