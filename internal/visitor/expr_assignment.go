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

	opNode := ctx.AssignmentOp()
	if opNode == nil {
		return leftExpr
	}

	rightAntlrExpr := ctx.AssignmentExpr()
	if rightAntlrExpr == nil {
		v.addError("Right-hand side of assignment is missing for operator "+opNode.GetText(), opNode.GetStart())
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

	binTok := mapAssignmentOpToGoToken(opNode)
	if binTok == token.ILLEGAL {
		return &ast.AssignStmt{
			Lhs: []ast.Expr{leftExpr},
			Tok: token.ASSIGN,
			Rhs: []ast.Expr{rightExpr},
		}
	}
	rhsBinaryExpr := &ast.BinaryExpr{
		X:  leftExpr,
		Op: binTok,
		Y:  rightExpr,
	}
	return &ast.AssignStmt{
		Lhs: []ast.Expr{leftExpr},
		Tok: token.ASSIGN,
		Rhs: []ast.Expr{rhsBinaryExpr},
	}
}

func mapAssignmentOpToGoToken(op parser.IAssignmentOpContext) token.Token {
	switch op.(type) {
	case *parser.LabelAssignEqContext:
		return token.ILLEGAL
	case *parser.LabelAssignPlusEqContext:
		return token.ADD
	case *parser.LabelAssignMinusEqContext:
		return token.SUB
	case *parser.LabelAssignStarEqContext:
		return token.MUL
	case *parser.LabelAssignSlashEqContext:
		return token.QUO
	case *parser.LabelAssignModEqContext:
		return token.REM
	case *parser.LabelAssignCaretEqContext:
		return token.XOR
	default:
		return token.ILLEGAL
	}
}
