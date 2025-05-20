package visitor

import (
	"fmt"
	"go/ast"
	"manuscript-co/manuscript/internal/parser"
)

func (v *ManuscriptAstVisitor) VisitPostfixExpr(ctx *parser.PostfixExprContext) interface{} {
	if ctx.PrimaryExpr() == nil {
		v.addError("Postfix expression is missing primary expression part", ctx.GetStart())
		return &ast.BadExpr{From: v.pos(ctx.GetStart()), To: v.pos(ctx.GetStop())}
	}

	currentAstNode := v.Visit(ctx.PrimaryExpr())
	if currentAstNode == nil {
		// Error should be added by the specific primary expression visitor
		return &ast.BadExpr{From: v.pos(ctx.PrimaryExpr().GetStart()), To: v.pos(ctx.PrimaryExpr().GetStop())}
	}

	goExpr, ok := currentAstNode.(ast.Expr)
	if !ok {
		v.addError(fmt.Sprintf("Primary expression did not resolve to ast.Expr, got %T", currentAstNode), ctx.PrimaryExpr().GetStart())
		return &ast.BadExpr{From: v.pos(ctx.PrimaryExpr().GetStart()), To: v.pos(ctx.PrimaryExpr().GetStop())}
	}

	for _, opCtx := range ctx.AllPostfixOp() { // Iterate through actual PostfixOpContexts
		// opCtx is parser.IPostfixOpContext
		concreteOpCtx, ok := opCtx.(*parser.PostfixOpContext)
		if !ok {
			v.addError("Internal error: PostfixOpContext has unexpected type", opCtx.GetStart())
			return &ast.BadExpr{From: v.pos(opCtx.GetStart()), To: v.pos(opCtx.GetStop())}
		}

		if concreteOpCtx.DOT() != nil && concreteOpCtx.ID() != nil { // Member access: .ID
			goExpr = &ast.SelectorExpr{
				X:   goExpr,
				Sel: ast.NewIdent(concreteOpCtx.ID().GetText()),
			}
		} else if concreteOpCtx.LPAREN() != nil && concreteOpCtx.RPAREN() != nil { // Function call: (exprList?)
			args := []ast.Expr{}
			lParenPos := v.pos(concreteOpCtx.LPAREN().GetSymbol())
			rParenPos := v.pos(concreteOpCtx.RPAREN().GetSymbol())

			if concreteOpCtx.ExprList() != nil {
				// The AllExpr() method is on the ExprListContext, not PostfixOpContext directly.
				// concreteOpCtx.ExprList() returns parser.IExprListContext.
				exprListInterface := concreteOpCtx.ExprList()
				if exprListInterface != nil {
					exprListCtx, castOk := exprListInterface.(*parser.ExprListContext)
					if castOk {
						for _, exprNode := range exprListCtx.AllExpr() { // exprNode is parser.IExprContext
							if argAst, visitOk := v.Visit(exprNode).(ast.Expr); visitOk && argAst != nil {
								args = append(args, argAst)
							} else {
								v.addError("Invalid argument expression in call: "+exprNode.GetText(), exprNode.GetStart())
								args = append(args, &ast.BadExpr{From: v.pos(exprNode.GetStart()), To: v.pos(exprNode.GetStop())})
							}
						}
					} else if !exprListInterface.IsEmpty() {
						v.addError("Internal error: ExprList context is not *parser.ExprListContext", exprListInterface.GetStart())
					}
				}
			}
			goExpr = &ast.CallExpr{
				Fun:    goExpr,
				Lparen: lParenPos,
				Args:   args,
				Rparen: rParenPos,
				// Ellipsis: token.NoPos, // For varargs, if needed
			}
		} else if concreteOpCtx.LSQBR() != nil && concreteOpCtx.Expr() != nil && concreteOpCtx.RSQBR() != nil { // Index access: [expr]
			// concreteOpCtx.Expr() returns parser.IExprContext
			indexNode := concreteOpCtx.Expr()
			indexAst := v.Visit(indexNode)
			if indexExpr, castOk := indexAst.(ast.Expr); castOk && indexExpr != nil {
				goExpr = &ast.IndexExpr{
					X:      goExpr,
					Lbrack: v.pos(concreteOpCtx.LSQBR().GetSymbol()),
					Index:  indexExpr,
					Rbrack: v.pos(concreteOpCtx.RSQBR().GetSymbol()),
				}
			} else {
				v.addError("Invalid index expression: "+indexNode.GetText(), indexNode.GetStart())
				goExpr = &ast.BadExpr{From: v.pos(concreteOpCtx.LSQBR().GetSymbol()), To: v.pos(concreteOpCtx.RSQBR().GetSymbol())}
			}
		} else {
			// This case should ideally not be reached if the grammar ensures PostfixOpContext is always one of the valid forms.
			v.addError("Unknown or malformed postfix operation: "+concreteOpCtx.GetText(), concreteOpCtx.GetStart())
			return &ast.BadExpr{From: v.pos(concreteOpCtx.GetStart()), To: v.pos(concreteOpCtx.GetStop())}
		}
	}
	return goExpr
}

// isTypeName checks if the given name is a type name
// This function might be needed if type conversions are handled via function-like calls to type names
// and that syntax is parsed as a regular PostfixExpr.
// For now, it is assumed that StructInitExpr handles explicit type constructions.
func (v *ManuscriptAstVisitor) isTypeName(name string) bool {
	// Check if it's a built-in type
	switch name {
	case "string", "int", "float", "bool": // Manuscript type names
		return true
	}
	// Check against known user-defined types (if symbol table/type info is available)
	// For example: if _, exists := v.typeInfo[name]; exists { return true }
	return false
}

// Ensure v.pos is defined in visitor.go or a common utility, e.g.:
// func (v *ManuscriptAstVisitor) pos(token antlr.Token) token.Pos {
//  if token == nil { return gotoken.NoPos }
//  // This is a placeholder. Actual mapping from ANTLR line/col to go/token.Pos
//  // requires a token.FileSet and adding files to it.
//  // For now, returning NoPos or a simplified offset if available.
//  // return token.GetTokenIndex() // This is not a token.Pos
//  return gotoken.NoPos // Fallback to NoPos if proper mapping isn't set up.
// }
