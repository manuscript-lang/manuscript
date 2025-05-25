package msparse

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
		// This is an assignment expression
		assignExpr := &ast.AssignmentExpr{
			TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
		}

		if left := ctx.GetLeft().Accept(v); left != nil {
			if leftExpr, ok := left.(ast.Expression); ok {
				assignExpr.Left = leftExpr
			}
		}

		if right := ctx.GetRight().Accept(v); right != nil {
			if rightExpr, ok := right.(ast.Expression); ok {
				assignExpr.Right = rightExpr
			}
		}

		if ctx.AssignmentOp() != nil {
			if op := ctx.AssignmentOp().Accept(v); op != nil {
				if assignOp, ok := op.(ast.AssignmentOp); ok {
					assignExpr.Op = assignOp
				}
			}
		}

		return assignExpr
	}

	// This is just a ternary expression
	if ctx.TernaryExpr() != nil {
		return ctx.TernaryExpr().Accept(v)
	}

	return nil
}

func (v *ParseTreeToAST) VisitAssignmentOp(ctx *parser.AssignmentOpContext) interface{} {
	switch {
	case ctx.EQUALS() != nil:
		return ast.AssignEq
	case ctx.PLUS_EQUALS() != nil:
		return ast.AssignPlusEq
	case ctx.MINUS_EQUALS() != nil:
		return ast.AssignMinusEq
	case ctx.STAR_EQUALS() != nil:
		return ast.AssignStarEq
	case ctx.SLASH_EQUALS() != nil:
		return ast.AssignSlashEq
	case ctx.MOD_EQUALS() != nil:
		return ast.AssignModEq
	case ctx.CARET_EQUALS() != nil:
		return ast.AssignCaretEq
	default:
		return ast.AssignEq
	}
}

func (v *ParseTreeToAST) VisitTernaryExpr(ctx *parser.TernaryExprContext) interface{} {
	if ctx.GetCond() != nil && ctx.GetThenBranch() != nil && ctx.GetElseExpr() != nil {
		// This is a ternary expression
		ternaryExpr := &ast.TernaryExpr{
			TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
		}

		if cond := ctx.GetCond().Accept(v); cond != nil {
			ternaryExpr.Cond = cond.(ast.Expression)
		}

		if thenBranch := ctx.GetThenBranch().Accept(v); thenBranch != nil {
			ternaryExpr.Then = thenBranch.(ast.Expression)
		}

		if elseBranch := ctx.GetElseExpr().Accept(v); elseBranch != nil {
			ternaryExpr.Else = elseBranch.(ast.Expression)
		}

		return ternaryExpr
	}

	// This is just a logical OR expression
	return ctx.LogicalOrExpr().Accept(v)
}

func (v *ParseTreeToAST) VisitLogicalOrExpr(ctx *parser.LogicalOrExprContext) interface{} {
	if ctx.GetLeft() != nil && ctx.GetRight() != nil {
		return v.createBinaryExpr(ctx, ctx.GetLeft(), ctx.GetRight(), ast.LogicalOr)
	}
	return ctx.LogicalAndExpr().Accept(v)
}

func (v *ParseTreeToAST) VisitLogicalAndExpr(ctx *parser.LogicalAndExprContext) interface{} {
	if ctx.GetLeft() != nil && ctx.GetRight() != nil {
		return v.createBinaryExpr(ctx, ctx.GetLeft(), ctx.GetRight(), ast.LogicalAnd)
	}
	return ctx.BitwiseXorExpr().Accept(v)
}

func (v *ParseTreeToAST) VisitBitwiseXorExpr(ctx *parser.BitwiseXorExprContext) interface{} {
	if ctx.GetLeft() != nil && ctx.GetRight() != nil {
		return v.createBinaryExpr(ctx, ctx.GetLeft(), ctx.GetRight(), ast.BitwiseXor)
	}
	return ctx.BitwiseAndExpr().Accept(v)
}

func (v *ParseTreeToAST) VisitBitwiseAndExpr(ctx *parser.BitwiseAndExprContext) interface{} {
	if ctx.GetLeft() != nil && ctx.GetRight() != nil {
		return v.createBinaryExpr(ctx, ctx.GetLeft(), ctx.GetRight(), ast.BitwiseAnd)
	}
	return ctx.EqualityExpr().Accept(v)
}

func (v *ParseTreeToAST) VisitEqualityExpr(ctx *parser.EqualityExprContext) interface{} {
	// Handle chained equality expressions like a == b == c
	operands, ops := v.flattenEqualityChain(ctx)
	if len(operands) == 0 {
		return nil
	}
	if len(ops) != len(operands)-1 {
		return nil
	}

	// If only one operand, just return it
	if len(operands) == 1 {
		return operands[0]
	}

	// Build chained expression: (a == b) && (b == c) && ...
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

func (v *ParseTreeToAST) VisitComparisonExpr(ctx *parser.ComparisonExprContext) interface{} {
	// Handle chained comparison expressions like a < b < c
	operands, ops := v.flattenComparisonChain(ctx)
	if len(operands) == 0 {
		return nil
	}
	if len(ops) != len(operands)-1 {
		return nil
	}

	// If only one operand, just return it
	if len(operands) == 1 {
		return operands[0]
	}

	// Build chained expression: (a < b) && (b < c) && ...
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

func (v *ParseTreeToAST) VisitComparisonOp(ctx *parser.ComparisonOpContext) interface{} {
	switch {
	case ctx.LT() != nil:
		return ast.Less
	case ctx.LT_EQUALS() != nil:
		return ast.LessEqual
	case ctx.GT() != nil:
		return ast.Greater
	case ctx.GT_EQUALS() != nil:
		return ast.GreaterEqual
	default:
		return ast.Less
	}
}

func (v *ParseTreeToAST) VisitAdditiveExpr(ctx *parser.AdditiveExprContext) interface{} {
	if ctx.GetLeft() != nil && ctx.GetRight() != nil {
		var op ast.BinaryOp
		if ctx.PLUS() != nil {
			op = ast.Add
		} else if ctx.MINUS() != nil {
			op = ast.Subtract
		}
		return v.createBinaryExpr(ctx, ctx.GetLeft(), ctx.GetRight(), op)
	}
	return ctx.MultiplicativeExpr().Accept(v)
}

func (v *ParseTreeToAST) VisitMultiplicativeExpr(ctx *parser.MultiplicativeExprContext) interface{} {
	if ctx.GetLeft() != nil && ctx.GetRight() != nil {
		var op ast.BinaryOp
		if ctx.STAR() != nil {
			op = ast.Multiply
		} else if ctx.SLASH() != nil {
			op = ast.Divide
		} else if ctx.MOD() != nil {
			op = ast.Modulo
		}
		return v.createBinaryExpr(ctx, ctx.GetLeft(), ctx.GetRight(), op)
	}
	return ctx.UnaryExpr().Accept(v)
}

// UnaryExpr visitor - this was missing
func (v *ParseTreeToAST) VisitUnaryExpr(ctx *parser.UnaryExprContext) interface{} {
	// The UnaryExpr context is a base type that gets specialized into specific labeled contexts
	// We need to handle it by checking the specific derived type and delegating
	for _, child := range ctx.GetChildren() {
		if child != nil {
			if ruleCtx, ok := child.(antlr.RuleContext); ok {
				return ruleCtx.Accept(v)
			}
		}
	}
	return nil
}

// Helper function to create binary expressions
func (v *ParseTreeToAST) createBinaryExpr(ctx antlr.ParserRuleContext, leftCtx, rightCtx antlr.ParserRuleContext, op ast.BinaryOp) *ast.BinaryExpr {
	binaryExpr := &ast.BinaryExpr{
		TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
		Op:        op,
	}

	if left := leftCtx.Accept(v); left != nil {
		binaryExpr.Left = left.(ast.Expression)
	}

	if right := rightCtx.Accept(v); right != nil {
		binaryExpr.Right = right.(ast.Expression)
	}

	return binaryExpr
}

func (v *ParseTreeToAST) VisitLabelUnaryOpExpr(ctx *parser.LabelUnaryOpExprContext) interface{} {
	unaryExpr := &ast.UnaryExpr{
		TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
	}

	// Determine operator
	if ctx.PLUS() != nil {
		unaryExpr.Op = ast.UnaryPlus
	} else if ctx.MINUS() != nil {
		unaryExpr.Op = ast.UnaryMinus
	} else if ctx.EXCLAMATION() != nil {
		unaryExpr.Op = ast.UnaryNot
	}

	if ctx.GetUnary() != nil {
		if expr := ctx.GetUnary().Accept(v); expr != nil {
			unaryExpr.Expr = expr.(ast.Expression)
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
		// This is a postfix expression with an operator
		baseExpr := ctx.PostfixExpr().Accept(v).(ast.Expression)
		return v.applyPostfixOp(ctx.PostfixOp(), baseExpr)
	}
	return nil
}

// PrimaryExpr visitor - was missing
func (v *ParseTreeToAST) VisitPrimaryExpr(ctx *parser.PrimaryExprContext) interface{} {
	// The PrimaryExpr context is a base type that gets specialized into specific labeled contexts
	// We need to handle it by checking the children and delegating
	for _, child := range ctx.GetChildren() {
		if child != nil {
			if ruleCtx, ok := child.(antlr.RuleContext); ok {
				return ruleCtx.Accept(v)
			}
		}
	}
	return nil
}

// PostfixOp visitor - was missing
func (v *ParseTreeToAST) VisitPostfixOp(ctx *parser.PostfixOpContext) interface{} {
	// The PostfixOp context is a base type that gets specialized into specific labeled contexts
	// We need to handle it by checking the children and delegating
	for _, child := range ctx.GetChildren() {
		if child != nil {
			if ruleCtx, ok := child.(antlr.RuleContext); ok {
				return ruleCtx.Accept(v)
			}
		}
	}
	return nil
}

func (v *ParseTreeToAST) applyPostfixOp(opCtx parser.IPostfixOpContext, baseExpr ast.Expression) ast.Expression {
	if callCtx, ok := opCtx.(*parser.LabelPostfixCallContext); ok {
		callExpr := &ast.CallExpr{
			TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(callCtx)}},
			Func:      baseExpr,
		}

		if callCtx.ExprList() != nil {
			if args := callCtx.ExprList().Accept(v); args != nil {
				callExpr.Args = args.([]ast.Expression)
			}
		}

		return callExpr
	} else if dotCtx, ok := opCtx.(*parser.LabelPostfixDotContext); ok {
		dotExpr := &ast.DotExpr{
			TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(dotCtx)}},
			Expr:      baseExpr,
			Field:     dotCtx.ID().GetText(),
		}

		return dotExpr
	} else if indexCtx, ok := opCtx.(*parser.LabelPostfixIndexContext); ok {
		indexExpr := &ast.IndexExpr{
			TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(indexCtx)}},
			Expr:      baseExpr,
		}

		if indexCtx.Expr() != nil {
			if index := indexCtx.Expr().Accept(v); index != nil {
				indexExpr.Index = index.(ast.Expression)
			}
		}

		return indexExpr
	}

	return baseExpr
}

func (v *ParseTreeToAST) VisitLabelPostfixCall(ctx *parser.LabelPostfixCallContext) interface{} {
	// This is handled by applyPostfixOp
	return nil
}

func (v *ParseTreeToAST) VisitLabelPostfixDot(ctx *parser.LabelPostfixDotContext) interface{} {
	// This is handled by applyPostfixOp
	return nil
}

func (v *ParseTreeToAST) VisitLabelPostfixIndex(ctx *parser.LabelPostfixIndexContext) interface{} {
	// This is handled by applyPostfixOp
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
	parenExpr := &ast.ParenExpr{
		TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
	}

	if ctx.Expr() != nil {
		if expr := ctx.Expr().Accept(v); expr != nil {
			parenExpr.Expr = expr.(ast.Expression)
		}
	}

	return parenExpr
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
	tryExpr := &ast.TryExpr{
		TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
	}

	if ctx.Expr() != nil {
		if expr := ctx.Expr().Accept(v); expr != nil {
			tryExpr.Expr = expr.(ast.Expression)
		}
	}

	return tryExpr
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
	}

	if ctx.Expr() != nil {
		if expr := ctx.Expr().Accept(v); expr != nil {
			matchExpr.Expr = expr.(ast.Expression)
		}
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

	// Get the pattern expression (first expression)
	if len(ctx.AllExpr()) > 0 {
		if expr := ctx.Expr(0).Accept(v); expr != nil {
			caseClause.Pattern = expr.(ast.Expression)
		}
	}

	// Handle the body - can be either expression or code block
	if len(ctx.AllExpr()) > 1 {
		// Second expr is the body expression
		if bodyExpr := ctx.AllExpr()[1].Accept(v); bodyExpr != nil {
			caseClause.Body = &ast.CaseExpr{
				TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
				Expr:      bodyExpr.(ast.Expression),
			}
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

	// Handle the body - can be either expression or code block
	if ctx.Expr() != nil {
		if bodyExpr := ctx.Expr().Accept(v); bodyExpr != nil {
			defaultClause.Body = &ast.CaseExpr{
				TypedNode: ast.TypedNode{BaseNode: ast.BaseNode{Position: v.getPosition(ctx)}},
				Expr:      bodyExpr.(ast.Expression),
			}
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

// flattenEqualityChain recursively flattens a left-recursive equalityExpr tree into operands and operators.
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
			// This is a binary equality expression
			recur(left.(*parser.EqualityExprContext))

			// Add the operator
			if c.EQUALS_EQUALS() != nil {
				ops = append(ops, ast.Equal)
			} else if c.NEQ() != nil {
				ops = append(ops, ast.NotEqual)
			}

			// Add the right operand
			if rightExpr := right.Accept(v); rightExpr != nil {
				operands = append(operands, rightExpr.(ast.Expression))
			}
		} else {
			// Base case: just a comparisonExpr
			if visited := c.ComparisonExpr().Accept(v); visited != nil {
				operands = append(operands, visited.(ast.Expression))
			}
		}
	}

	recur(ctx)
	return operands, ops
}

// flattenComparisonChain recursively flattens a left-recursive comparisonExpr tree into operands and operators.
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
			// This is a binary comparison expression
			recur(left.(*parser.ComparisonExprContext))

			// Add the operator
			if compOp := c.ComparisonOp().Accept(v); compOp != nil {
				ops = append(ops, compOp.(ast.BinaryOp))
			}

			// Add the right operand
			if rightExpr := right.Accept(v); rightExpr != nil {
				operands = append(operands, rightExpr.(ast.Expression))
			}
		} else {
			// Base case: just an additiveExpr
			if visited := c.AdditiveExpr().Accept(v); visited != nil {
				operands = append(operands, visited.(ast.Expression))
			}
		}
	}

	recur(ctx)
	return operands, ops
}
