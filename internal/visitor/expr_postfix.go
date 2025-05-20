package visitor

import (
	"fmt"
	"go/ast"
	"go/token"
	"manuscript-co/manuscript/internal/parser"

	"github.com/antlr4-go/antlr/v4"
)

func (v *ManuscriptAstVisitor) VisitPostfixExpr(ctx *parser.PostfixExprContext) interface{} {
	if ctx.PrimaryExpr() == nil {
		v.addError(
			"Postfix expression is missing primary expression part",
			ctx.GetStart(),
		)
		return &ast.BadExpr{
			From: v.pos(ctx.GetStart()),
			To:   v.pos(ctx.GetStop()),
		}
	}

	currentAstNode := v.Visit(ctx.PrimaryExpr())
	if currentAstNode == nil {
		return &ast.BadExpr{
			From: v.pos(ctx.GetStart()),
			To:   v.pos(ctx.GetStop()),
		}
	}

	currentGoExpr, ok := currentAstNode.(ast.Expr)
	if !ok {
		v.addError(
			fmt.Sprintf(
				"Primary expression did not resolve to ast.Expr, got %T",
				currentAstNode,
			),
			ctx.PrimaryExpr().GetStart(),
		)
		return &ast.BadExpr{
			From: v.pos(ctx.PrimaryExpr().GetStart()),
			To:   v.pos(ctx.PrimaryExpr().GetStop()),
		}
	}

	children := ctx.GetChildren()

	var processPostfix func(expr ast.Expr, idx int) ast.Expr
	processPostfix = func(expr ast.Expr, idx int) ast.Expr {
		if idx >= len(children) {
			return expr
		}
		child := children[idx]
		termNode, isTerm := child.(antlr.TerminalNode)
		if !isTerm {
			return processPostfix(expr, idx+1)
		}
		tokenType := termNode.GetSymbol().GetTokenType()
		switch tokenType {
		case parser.ManuscriptDOT:
			if idx+1 >= len(children) {
				v.addError(
					"Missing identifier after DOT for member access",
					termNode.GetSymbol(),
				)
				return &ast.BadExpr{
					From: v.pos(termNode.GetSymbol()),
					To:   v.pos(ctx.GetStop()),
				}
			}
			idNode, ok := children[idx+1].(antlr.TerminalNode)
			if !ok || idNode.GetSymbol().GetTokenType() != parser.ManuscriptID {
				v.addError(
					"Expected identifier after DOT for member access",
					termNode.GetSymbol(),
				)
				return &ast.BadExpr{
					From: v.pos(termNode.GetSymbol()),
					To:   v.pos(ctx.GetStop()),
				}
			}
			return processPostfix(&ast.SelectorExpr{
				X:   expr,
				Sel: ast.NewIdent(idNode.GetText()),
			}, idx+2)
		case parser.ManuscriptLPAREN:
			lParenPos := v.pos(termNode.GetSymbol())
			args := []ast.Expr{}
			rParenPos := token.NoPos

			// Find closing parenthesis and process arguments
			for j := idx + 1; j < len(children); j++ {
				child := children[j]

				// Check for closing parenthesis
				if rParenNode, ok := child.(antlr.TerminalNode); ok && rParenNode.GetSymbol().GetTokenType() == parser.ManuscriptRPAREN {
					rParenPos = v.pos(rParenNode.GetSymbol())
					j++
					break
				}

				// Process argument list
				if exprListCtx, ok := child.(*parser.ExprListContext); ok {
					for _, exprCtx := range exprListCtx.AllExpr() {
						if argExpr, ok := v.Visit(exprCtx).(ast.Expr); ok {
							args = append(args, argExpr)
						} else {
							v.addError(
								"Invalid argument expression: "+exprCtx.GetText(),
								exprCtx.GetStart(),
							)
							args = append(args, &ast.BadExpr{
								From: v.pos(exprCtx.GetStart()),
								To:   v.pos(exprCtx.GetStop()),
							})
						}
					}
				}
			}

			// Handle missing closing parenthesis
			if rParenPos == token.NoPos {
				v.addError("Missing closing parenthesis", termNode.GetSymbol())
				rParenPos = v.pos(ctx.GetStop())
			}

			return processPostfix(&ast.CallExpr{
				Fun:    expr,
				Args:   args,
				Lparen: lParenPos,
				Rparen: rParenPos,
			}, idx+2)
		case parser.ManuscriptLSQBR:
			lSqbrPos := v.pos(termNode.GetSymbol())
			if idx+2 >= len(children) {
				v.addError("Malformed index access", termNode.GetSymbol())
				return &ast.BadExpr{
					From: lSqbrPos,
					To:   v.pos(ctx.GetStop()),
				}
			}
			indexExprCtx, ok := children[idx+1].(parser.IExprContext)
			if !ok {
				v.addError("Expected expression for index access", termNode.GetSymbol())
				return &ast.BadExpr{
					From: lSqbrPos,
					To:   v.pos(ctx.GetStop()),
				}
			}
			visitedIndex := v.Visit(indexExprCtx)
			indexAstExpr, astOk := visitedIndex.(ast.Expr)
			if !astOk {
				v.addError(
					"Index did not evaluate to a valid expression: "+indexExprCtx.GetText(),
					indexExprCtx.GetStart(),
				)
				return &ast.BadExpr{
					From: lSqbrPos,
					To:   v.pos(ctx.GetStop()),
				}
			}
			rSqbrNode, ok := children[idx+2].(antlr.TerminalNode)
			if !ok || rSqbrNode.GetSymbol().GetTokenType() != parser.ManuscriptRSQBR {
				v.addError("Expected closing square bracket for index access", termNode.GetSymbol())
				return &ast.BadExpr{
					From: lSqbrPos,
					To:   v.pos(ctx.GetStop()),
				}
			}
			rSqbrPos := v.pos(rSqbrNode.GetSymbol())
			return processPostfix(&ast.IndexExpr{
				X:      expr,
				Lbrack: lSqbrPos,
				Index:  indexAstExpr,
				Rbrack: rSqbrPos,
			}, idx+3)
		default:
			return processPostfix(expr, idx+1)
		}
	}

	return processPostfix(currentGoExpr, 1)
}
