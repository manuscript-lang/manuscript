package visitor

import (
	"fmt"
	"go/ast"
	"go/token"
	"manuscript-co/manuscript/internal/parser"
)

func (v *ManuscriptAstVisitor) VisitUnaryExpr(ctx *parser.UnaryExprContext) interface{} {
	if ctx.AwaitExpr() != nil {
		return v.Visit(ctx.AwaitExpr())
	}

	opToken := ctx.GetOp()
	if opToken == nil {
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
		assignValStmt := &ast.AssignStmt{
			Lhs: []ast.Expr{ast.NewIdent("val")},
			Tok: token.ASSIGN,
			Rhs: []ast.Expr{operandExpr},
		}
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
				Params: &ast.FieldList{},
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
