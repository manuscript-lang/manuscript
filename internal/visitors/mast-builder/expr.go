package mastb

import (
	"manuscript-co/manuscript/internal/ast"
	"manuscript-co/manuscript/internal/parser"

	"github.com/antlr4-go/antlr/v4"
)

// Expression visitors

func (v *ParseTreeToAST) VisitExpr(ctx *parser.ExprContext) interface{} {
	return ctx.AssignmentExpr().Accept(v)
}

func (v *ParseTreeToAST) VisitAssignmentExpr(ctx *parser.AssignmentExprContext) interface{} {
	if ctx == nil {
		return nil
	}

	if ctx.GetLeft() != nil && ctx.GetRight() != nil {
		assignExpr := &ast.AssignmentExpr{
			TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
		}

		assignExpr.Left = v.acceptAsExpr(ctx.GetLeft())
		assignExpr.Right = v.acceptAsExpr(ctx.GetRight())

		if ctx.AssignmentOp() != nil {
			if op := ctx.AssignmentOp().Accept(v); op != nil {
				assignExpr.Op = op.(ast.AssignmentOp)
			}
		}

		return assignExpr
	}

	return v.acceptIfNotNil(ctx.TernaryExpr())
}

func (v *ParseTreeToAST) VisitAssignmentOp(ctx *parser.AssignmentOpContext) interface{} {
	opMap := map[bool]ast.AssignmentOp{
		ctx.EQUALS() != nil:       ast.AssignEq,
		ctx.PLUS_EQUALS() != nil:  ast.AssignPlusEq,
		ctx.MINUS_EQUALS() != nil: ast.AssignMinusEq,
		ctx.STAR_EQUALS() != nil:  ast.AssignStarEq,
		ctx.SLASH_EQUALS() != nil: ast.AssignSlashEq,
		ctx.MOD_EQUALS() != nil:   ast.AssignModEq,
		ctx.CARET_EQUALS() != nil: ast.AssignCaretEq,
	}

	for condition, op := range opMap {
		if condition {
			return op
		}
	}
	return ast.AssignEq
}

func (v *ParseTreeToAST) VisitTernaryExpr(ctx *parser.TernaryExprContext) interface{} {
	if ctx.GetCond() != nil && ctx.GetThenBranch() != nil && ctx.GetElseExpr() != nil {
		return &ast.TernaryExpr{
			TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
			Cond:      v.acceptAsExpr(ctx.GetCond()),
			Then:      v.acceptAsExpr(ctx.GetThenBranch()),
			Else:      v.acceptAsExpr(ctx.GetElseExpr()),
		}
	}
	return ctx.LogicalOrExpr().Accept(v)
}

func (v *ParseTreeToAST) VisitLogicalOrExpr(ctx *parser.LogicalOrExprContext) interface{} {
	return v.visitBinaryOrFallback(ctx, ctx.GetLeft(), ctx.GetRight(), ast.LogicalOr, ctx.LogicalAndExpr())
}

func (v *ParseTreeToAST) VisitLogicalAndExpr(ctx *parser.LogicalAndExprContext) interface{} {
	return v.visitBinaryOrFallback(ctx, ctx.GetLeft(), ctx.GetRight(), ast.LogicalAnd, ctx.BitwiseXorExpr())
}

func (v *ParseTreeToAST) VisitBitwiseXorExpr(ctx *parser.BitwiseXorExprContext) interface{} {
	return v.visitBinaryOrFallback(ctx, ctx.GetLeft(), ctx.GetRight(), ast.BitwiseXor, ctx.BitwiseAndExpr())
}

func (v *ParseTreeToAST) VisitBitwiseAndExpr(ctx *parser.BitwiseAndExprContext) interface{} {
	return v.visitBinaryOrFallback(ctx, ctx.GetLeft(), ctx.GetRight(), ast.BitwiseAnd, ctx.EqualityExpr())
}

func (v *ParseTreeToAST) VisitEqualityExpr(ctx *parser.EqualityExprContext) interface{} {
	operands, ops := v.flattenEqualityChain(ctx)
	return v.buildChainedExpr(operands, ops, ctx)
}

func (v *ParseTreeToAST) VisitComparisonExpr(ctx *parser.ComparisonExprContext) interface{} {
	operands, ops := v.flattenComparisonChain(ctx)
	return v.buildChainedExpr(operands, ops, ctx)
}

func (v *ParseTreeToAST) VisitComparisonOp(ctx *parser.ComparisonOpContext) interface{} {
	opMap := map[bool]ast.BinaryOp{
		ctx.LT() != nil:        ast.Less,
		ctx.LT_EQUALS() != nil: ast.LessEqual,
		ctx.GT() != nil:        ast.Greater,
		ctx.GT_EQUALS() != nil: ast.GreaterEqual,
	}

	for condition, op := range opMap {
		if condition {
			return op
		}
	}
	return ast.Less
}

func (v *ParseTreeToAST) VisitAdditiveExpr(ctx *parser.AdditiveExprContext) interface{} {
	if ctx.GetLeft() != nil && ctx.GetRight() != nil {
		op := ast.Add
		if ctx.MINUS() != nil {
			op = ast.Subtract
		}
		return v.createBinaryExpr(ctx, ctx.GetLeft(), ctx.GetRight(), op)
	}
	return ctx.MultiplicativeExpr().Accept(v)
}

func (v *ParseTreeToAST) VisitMultiplicativeExpr(ctx *parser.MultiplicativeExprContext) interface{} {
	if ctx.GetLeft() != nil && ctx.GetRight() != nil {
		op := ast.Multiply
		if ctx.SLASH() != nil {
			op = ast.Divide
		} else if ctx.MOD() != nil {
			op = ast.Modulo
		}
		return v.createBinaryExpr(ctx, ctx.GetLeft(), ctx.GetRight(), op)
	}
	return ctx.UnaryExpr().Accept(v)
}

func (v *ParseTreeToAST) VisitUnaryExpr(ctx *parser.UnaryExprContext) interface{} {
	return v.delegateToFirstChild(ctx)
}

func (v *ParseTreeToAST) VisitLabelUnaryOpExpr(ctx *parser.LabelUnaryOpExprContext) interface{} {
	unaryExpr := &ast.UnaryExpr{
		TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
		Expr:      v.acceptAsExpr(ctx.GetUnary()),
	}

	opMap := map[bool]ast.UnaryOp{
		ctx.PLUS() != nil:        ast.UnaryPlus,
		ctx.MINUS() != nil:       ast.UnaryMinus,
		ctx.EXCLAMATION() != nil: ast.UnaryNot,
	}

	for condition, op := range opMap {
		if condition {
			unaryExpr.Op = op
			break
		}
	}

	return unaryExpr
}

func (v *ParseTreeToAST) VisitLabelUnaryPostfixExpr(ctx *parser.LabelUnaryPostfixExprContext) interface{} {
	return ctx.PostfixExpr().Accept(v)
}

func (v *ParseTreeToAST) VisitPostfixExpr(ctx *parser.PostfixExprContext) interface{} {
	if ctx.PrimaryExpr() != nil {
		return ctx.PrimaryExpr().Accept(v)
	} else if ctx.PostfixExpr() != nil && ctx.PostfixOp() != nil {
		baseExpr := ctx.PostfixExpr().Accept(v).(ast.Expression)
		return v.applyPostfixOp(ctx.PostfixOp(), baseExpr)
	}
	return nil
}

func (v *ParseTreeToAST) VisitPrimaryExpr(ctx *parser.PrimaryExprContext) interface{} {
	return v.delegateToFirstChild(ctx)
}

func (v *ParseTreeToAST) VisitPostfixOp(ctx *parser.PostfixOpContext) interface{} {
	return v.delegateToFirstChild(ctx)
}

func (v *ParseTreeToAST) applyPostfixOp(opCtx parser.IPostfixOpContext, baseExpr ast.Expression) ast.Expression {
	switch ctx := opCtx.(type) {
	case *parser.LabelPostfixCallContext:
		callExpr := &ast.CallExpr{
			TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
			Func:      baseExpr,
		}
		if ctx.ExprList() != nil {
			if args := ctx.ExprList().Accept(v); args != nil {
				callExpr.Args = args.([]ast.Expression)
			}
		}
		return callExpr

	case *parser.LabelPostfixDotContext:
		return &ast.DotExpr{
			TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
			Expr:      baseExpr,
			Field:     ctx.ID().GetText(),
		}

	case *parser.LabelPostfixIndexContext:
		return &ast.IndexExpr{
			TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
			Expr:      baseExpr,
			Index:     v.acceptAsExpr(ctx.Expr()),
		}
	}
	return baseExpr
}

func (v *ParseTreeToAST) VisitLabelPostfixCall(ctx *parser.LabelPostfixCallContext) interface{} {
	return nil
}

func (v *ParseTreeToAST) VisitLabelPostfixDot(ctx *parser.LabelPostfixDotContext) interface{} {
	return nil
}

func (v *ParseTreeToAST) VisitLabelPostfixIndex(ctx *parser.LabelPostfixIndexContext) interface{} {
	return nil
}

// Primary expressions

func (v *ParseTreeToAST) VisitLabelPrimaryLiteral(ctx *parser.LabelPrimaryLiteralContext) interface{} {
	return ctx.Literal().Accept(v)
}

func (v *ParseTreeToAST) VisitLabelPrimaryID(ctx *parser.LabelPrimaryIDContext) interface{} {
	return &ast.Identifier{
		NamedNode: ast.NamedNode{
			BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
			Name:     ctx.ID().GetText(),
		},
	}
}

func (v *ParseTreeToAST) VisitLabelPrimaryParen(ctx *parser.LabelPrimaryParenContext) interface{} {
	return &ast.ParenExpr{
		TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
		Expr:      v.acceptAsExpr(ctx.Expr()),
	}
}

func (v *ParseTreeToAST) VisitLabelPrimaryArray(ctx *parser.LabelPrimaryArrayContext) interface{} {
	return ctx.ArrayLiteral().Accept(v)
}

func (v *ParseTreeToAST) VisitLabelPrimaryObject(ctx *parser.LabelPrimaryObjectContext) interface{} {
	return ctx.ObjectLiteral().Accept(v)
}

func (v *ParseTreeToAST) VisitLabelPrimaryMap(ctx *parser.LabelPrimaryMapContext) interface{} {
	return ctx.MapLiteral().Accept(v)
}

func (v *ParseTreeToAST) VisitLabelPrimarySet(ctx *parser.LabelPrimarySetContext) interface{} {
	return ctx.SetLiteral().Accept(v)
}

func (v *ParseTreeToAST) VisitLabelPrimaryFn(ctx *parser.LabelPrimaryFnContext) interface{} {
	return ctx.FnExpr().Accept(v)
}

func (v *ParseTreeToAST) VisitLabelPrimaryMatch(ctx *parser.LabelPrimaryMatchContext) interface{} {
	return ctx.MatchExpr().Accept(v)
}

func (v *ParseTreeToAST) VisitLabelPrimaryVoid(ctx *parser.LabelPrimaryVoidContext) interface{} {
	return &ast.VoidExpr{
		TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
	}
}

func (v *ParseTreeToAST) VisitLabelPrimaryNull(ctx *parser.LabelPrimaryNullContext) interface{} {
	return &ast.NullExpr{
		TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
	}
}

func (v *ParseTreeToAST) VisitLabelPrimaryTaggedBlock(ctx *parser.LabelPrimaryTaggedBlockContext) interface{} {
	return ctx.TaggedBlockString().Accept(v)
}

func (v *ParseTreeToAST) VisitLabelPrimaryStructInit(ctx *parser.LabelPrimaryStructInitContext) interface{} {
	return ctx.StructInitExpr().Accept(v)
}

// Try expressions

func (v *ParseTreeToAST) VisitTryExpr(ctx *parser.TryExprContext) interface{} {
	return &ast.TryExpr{
		TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
		Expr:      v.acceptAsExpr(ctx.Expr()),
	}
}

// Function expressions

func (v *ParseTreeToAST) VisitFnExpr(ctx *parser.FnExprContext) interface{} {
	fnExpr := &ast.FnExpr{
		TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
	}

	if ctx.Parameters() != nil {
		if params := ctx.Parameters().Accept(v); params != nil {
			fnExpr.Parameters = params.([]ast.Parameter)
		}
	}

	if ctx.TypeAnnotation() != nil {
		if returnType := ctx.TypeAnnotation().Accept(v); returnType != nil {
			fnExpr.ReturnType = returnType.(ast.TypeAnnotation)
		}
	}

	if ctx.CodeBlock() != nil {
		if body := ctx.CodeBlock().Accept(v); body != nil {
			fnExpr.Body = body.(*ast.CodeBlock)
		}
	}

	return fnExpr
}

// Match expressions

func (v *ParseTreeToAST) VisitMatchExpr(ctx *parser.MatchExprContext) interface{} {
	matchExpr := &ast.MatchExpr{
		TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
		Expr:      v.acceptAsExpr(ctx.Expr()),
	}

	for _, caseCtx := range ctx.AllCaseClause() {
		if caseClause := caseCtx.Accept(v); caseClause != nil {
			matchExpr.Cases = append(matchExpr.Cases, caseClause.(ast.CaseClause))
		}
	}

	if ctx.DefaultClause() != nil {
		if defaultClause := ctx.DefaultClause().Accept(v); defaultClause != nil {
			defaultPtr := defaultClause.(ast.DefaultClause)
			matchExpr.Default = &defaultPtr
		}
	}

	return matchExpr
}

func (v *ParseTreeToAST) VisitCaseClause(ctx *parser.CaseClauseContext) interface{} {
	caseClause := ast.CaseClause{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if len(ctx.AllExpr()) > 0 {
		caseClause.Pattern = v.acceptAsExpr(ctx.Expr(0))
	}

	if len(ctx.AllExpr()) > 1 {
		caseClause.Body = &ast.CaseExpr{
			TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
			Expr:      v.acceptAsExpr(ctx.AllExpr()[1]),
		}
	} else if ctx.CodeBlock() != nil {
		if codeBlock := ctx.CodeBlock().Accept(v); codeBlock != nil {
			caseClause.Body = &ast.CaseBlock{
				BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
				Block:    codeBlock.(*ast.CodeBlock),
			}
		}
	}

	return caseClause
}

func (v *ParseTreeToAST) VisitDefaultClause(ctx *parser.DefaultClauseContext) interface{} {
	defaultClause := ast.DefaultClause{
		BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
	}

	if ctx.Expr() != nil {
		defaultClause.Body = &ast.CaseExpr{
			TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
			Expr:      v.acceptAsExpr(ctx.Expr()),
		}
	} else if ctx.CodeBlock() != nil {
		if codeBlock := ctx.CodeBlock().Accept(v); codeBlock != nil {
			defaultClause.Body = &ast.CaseBlock{
				BaseNode: ast.BaseNode{Position: v.getPosition(ctx)},
				Block:    codeBlock.(*ast.CodeBlock),
			}
		}
	}

	return defaultClause
}

// Helper functions

func (v *ParseTreeToAST) acceptAsExpr(ctx antlr.ParserRuleContext) ast.Expression {
	if ctx == nil {
		return nil
	}
	if expr := ctx.Accept(v); expr != nil {
		return expr.(ast.Expression)
	}
	return nil
}

func (v *ParseTreeToAST) acceptIfNotNil(ctx antlr.ParserRuleContext) interface{} {
	if ctx != nil {
		return ctx.Accept(v)
	}
	return nil
}

func (v *ParseTreeToAST) delegateToFirstChild(ctx antlr.ParserRuleContext) interface{} {
	for _, child := range ctx.GetChildren() {
		if child != nil {
			if ruleCtx, ok := child.(antlr.RuleContext); ok {
				return ruleCtx.Accept(v)
			}
		}
	}
	return nil
}

func (v *ParseTreeToAST) visitBinaryOrFallback(ctx antlr.ParserRuleContext, left, right antlr.ParserRuleContext, op ast.BinaryOp, fallback antlr.ParserRuleContext) interface{} {
	if left != nil && right != nil {
		return v.createBinaryExpr(ctx, left, right, op)
	}
	return fallback.Accept(v)
}

func (v *ParseTreeToAST) createBinaryExpr(ctx antlr.ParserRuleContext, leftCtx, rightCtx antlr.ParserRuleContext, op ast.BinaryOp) *ast.BinaryExpr {
	return &ast.BinaryExpr{
		TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
		Op:        op,
		Left:      v.acceptAsExpr(leftCtx),
		Right:     v.acceptAsExpr(rightCtx),
	}
}

func (v *ParseTreeToAST) buildChainedExpr(operands []ast.Expression, ops []ast.BinaryOp, ctx antlr.ParserRuleContext) interface{} {
	if len(operands) == 0 || len(ops) != len(operands)-1 {
		return nil
	}

	if len(operands) == 1 {
		return operands[0]
	}

	var expr ast.Expression
	for i := 0; i < len(ops); i++ {
		cmp := &ast.BinaryExpr{
			TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
			Left:      operands[i],
			Op:        ops[i],
			Right:     operands[i+1],
		}
		if expr == nil {
			expr = cmp
		} else {
			expr = &ast.BinaryExpr{
				TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
				Left:      expr,
				Op:        ast.LogicalAnd,
				Right:     cmp,
			}
		}
	}
	return expr
}

func (v *ParseTreeToAST) flattenEqualityChain(ctx *parser.EqualityExprContext) ([]ast.Expression, []ast.BinaryOp) {
	var operands []ast.Expression
	var ops []ast.BinaryOp

	var recur func(c *parser.EqualityExprContext)
	recur = func(c *parser.EqualityExprContext) {
		if c == nil {
			return
		}
		left := c.GetLeft()
		right := c.GetRight()

		if left != nil && right != nil {
			recur(left.(*parser.EqualityExprContext))

			if c.EQUALS_EQUALS() != nil {
				ops = append(ops, ast.Equal)
			} else if c.NEQ() != nil {
				ops = append(ops, ast.NotEqual)
			}

			if rightExpr := right.Accept(v); rightExpr != nil {
				operands = append(operands, rightExpr.(ast.Expression))
			}
		} else {
			if visited := c.ComparisonExpr().Accept(v); visited != nil {
				operands = append(operands, visited.(ast.Expression))
			}
		}
	}

	recur(ctx)
	return operands, ops
}

func (v *ParseTreeToAST) flattenComparisonChain(ctx *parser.ComparisonExprContext) ([]ast.Expression, []ast.BinaryOp) {
	var operands []ast.Expression
	var ops []ast.BinaryOp

	var recur func(c *parser.ComparisonExprContext)
	recur = func(c *parser.ComparisonExprContext) {
		if c == nil {
			return
		}
		left := c.GetLeft()
		right := c.GetRight()

		if left != nil && right != nil {
			recur(left.(*parser.ComparisonExprContext))

			if compOp := c.ComparisonOp().Accept(v); compOp != nil {
				ops = append(ops, compOp.(ast.BinaryOp))
			}

			if rightExpr := right.Accept(v); rightExpr != nil {
				operands = append(operands, rightExpr.(ast.Expression))
			}
		} else {
			if visited := c.AdditiveExpr().Accept(v); visited != nil {
				operands = append(operands, visited.(ast.Expression))
			}
		}
	}

	recur(ctx)
	return operands, ops
}
