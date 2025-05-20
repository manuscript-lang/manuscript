package visitor

import (
	"go/ast"
	"go/token"
	"manuscript-co/manuscript/internal/parser"
	"strconv"
)

func (v *ManuscriptAstVisitor) VisitAssignmentExpr(ctx *parser.AssignmentExprContext) interface{} {
	leftAntlrExpr := ctx.TernaryExpr()
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

	if ctx.AssignmentOp() != nil {
		opNode := ctx.AssignmentOp()
		opText := opNode.GetText()
		rightAntlrExpr := ctx.AssignmentExpr()
		if rightAntlrExpr == nil {
			v.addError("Right-hand side of assignment is missing for operator "+opText, opNode.GetStart())
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
		if opNode.EQUALS() != nil {
			return &ast.AssignStmt{
				Lhs: []ast.Expr{leftExpr},
				Tok: token.ASSIGN,
				Rhs: []ast.Expr{rightExpr},
			}
		}
		var binaryOpToken token.Token
		switch {
		case opNode.PLUS_EQUALS() != nil:
			binaryOpToken = token.ADD
		case opNode.MINUS_EQUALS() != nil:
			binaryOpToken = token.SUB
		case opNode.STAR_EQUALS() != nil:
			binaryOpToken = token.MUL
		case opNode.SLASH_EQUALS() != nil:
			binaryOpToken = token.QUO
		case opNode.MOD_EQUALS() != nil:
			binaryOpToken = token.REM
		case opNode.CARET_EQUALS() != nil:
			binaryOpToken = token.XOR
		default:
			v.addError("Unhandled assignment operator: "+opText, opNode.GetStart())
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
