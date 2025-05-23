package visitor

import (
	"go/ast"
	"go/token"
	"manuscript-co/manuscript/internal/parser"

	"github.com/antlr4-go/antlr/v4"
)

// VisitLogicalOrExpr handles binary OR expressions (||)
func (v *ManuscriptAstVisitor) VisitLogicalOrExpr(ctx *parser.LogicalOrExprContext) interface{} {
	return v.buildChainedBinaryExpr(ctx.GetChildren(), func(child antlr.Tree) (antlr.ParserRuleContext, bool) {
		prc, ok := child.(antlr.ParserRuleContext)
		if !ok {
			return nil, false
		}
		if c, ok := prc.(parser.ILogicalOrExprContext); ok {
			return c, true
		}
		if c, ok := prc.(parser.ILogicalAndExprContext); ok {
			return c, true
		}
		return nil, false
	}, parser.ManuscriptPIPE_PIPE, token.LOR, "logical OR", ctx.GetStart())
}

// VisitLogicalAndExpr handles binary AND expressions (&&)
func (v *ManuscriptAstVisitor) VisitLogicalAndExpr(ctx *parser.LogicalAndExprContext) interface{} {
	return v.buildChainedBinaryExpr(ctx.GetChildren(), func(child antlr.Tree) (antlr.ParserRuleContext, bool) {
		prc, ok := child.(antlr.ParserRuleContext)
		if !ok {
			return nil, false
		}
		if c, ok := prc.(parser.ILogicalAndExprContext); ok {
			return c, true
		}
		if c, ok := prc.(parser.IBitwiseOrExprContext); ok {
			return c, true
		}
		return nil, false
	}, parser.ManuscriptAMP_AMP, token.LAND, "logical AND", ctx.GetStart())
}

// VisitBitwiseOrExpr handles bitwise OR expressions (|)
func (v *ManuscriptAstVisitor) VisitBitwiseOrExpr(ctx *parser.BitwiseOrExprContext) interface{} {
	return v.buildChainedBinaryExpr(ctx.GetChildren(), func(child antlr.Tree) (antlr.ParserRuleContext, bool) {
		prc, ok := child.(antlr.ParserRuleContext)
		if !ok {
			return nil, false
		}
		if c, ok := prc.(parser.IBitwiseOrExprContext); ok {
			return c, true
		}
		if c, ok := prc.(parser.IBitwiseXorExprContext); ok {
			return c, true
		}
		return nil, false
	}, parser.ManuscriptPIPE, token.OR, "bitwise OR", ctx.GetStart())
}

// VisitBitwiseXorExpr handles bitwise XOR expressions (^)
func (v *ManuscriptAstVisitor) VisitBitwiseXorExpr(ctx *parser.BitwiseXorExprContext) interface{} {
	return v.buildChainedBinaryExpr(ctx.GetChildren(), func(child antlr.Tree) (antlr.ParserRuleContext, bool) {
		prc, ok := child.(antlr.ParserRuleContext)
		if !ok {
			return nil, false
		}
		if c, ok := prc.(parser.IBitwiseXorExprContext); ok {
			return c, true
		}
		if c, ok := prc.(parser.IBitwiseAndExprContext); ok {
			return c, true
		}
		return nil, false
	}, parser.ManuscriptCARET, token.XOR, "bitwise XOR", ctx.GetStart())
}

// VisitBitwiseAndExpr handles bitwise AND expressions (&)
func (v *ManuscriptAstVisitor) VisitBitwiseAndExpr(ctx *parser.BitwiseAndExprContext) interface{} {
	return v.buildChainedBinaryExpr(ctx.GetChildren(), func(child antlr.Tree) (antlr.ParserRuleContext, bool) {
		prc, ok := child.(antlr.ParserRuleContext)
		if !ok {
			return nil, false
		}
		if c, ok := prc.(parser.IBitwiseAndExprContext); ok {
			return c, true
		}
		if c, ok := prc.(parser.IEqualityExprContext); ok {
			return c, true
		}
		return nil, false
	}, parser.ManuscriptAMP, token.AND, "bitwise AND", ctx.GetStart())
}

// VisitEqualityExpr handles equality expressions (==, !=)
func (v *ManuscriptAstVisitor) VisitEqualityExpr(ctx *parser.EqualityExprContext) interface{} {
	operands, ops := v.flattenEqualityChain(ctx)
	if len(operands) == 0 {
		v.addError("Equality expression has no operands", ctx.GetStart())
		return &ast.BadExpr{}
	}
	if len(ops) != len(operands)-1 {
		v.addError("Mismatch in operands and operators in equality expr", ctx.GetStart())
		return &ast.BadExpr{}
	}
	var expr ast.Expr
	for i := 0; i < len(ops); i++ {
		cmp := &ast.BinaryExpr{
			X:  operands[i],
			Op: ops[i],
			Y:  operands[i+1],
		}
		if expr == nil {
			expr = cmp
		} else {
			expr = &ast.BinaryExpr{
				X:  expr,
				Op: token.LAND,
				Y:  cmp,
			}
		}
	}
	if expr == nil {
		return operands[0]
	}
	return expr
}

// VisitComparisonExpr handles comparison expressions (<, <=, >, >=)
func (v *ManuscriptAstVisitor) VisitComparisonExpr(ctx *parser.ComparisonExprContext) interface{} {
	operands, ops := v.flattenComparisonChain(ctx)
	if len(operands) == 0 {
		v.addError("Comparison expression has no operands", ctx.GetStart())
		return &ast.BadExpr{}
	}
	if len(ops) != len(operands)-1 {
		v.addError("Mismatch in operands and operators in comparison expr", ctx.GetStart())
		return &ast.BadExpr{}
	}
	var expr ast.Expr
	for i := 0; i < len(ops); i++ {
		cmp := &ast.BinaryExpr{
			X:  operands[i],
			Op: ops[i],
			Y:  operands[i+1],
		}
		if expr == nil {
			expr = cmp
		} else {
			expr = &ast.BinaryExpr{
				X:  expr,
				Op: token.LAND,
				Y:  cmp,
			}
		}
	}
	if expr == nil {
		return operands[0]
	}
	return expr
}

// VisitAdditiveExpr handles additive expressions (+, -)
func (v *ManuscriptAstVisitor) VisitAdditiveExpr(ctx *parser.AdditiveExprContext) interface{} {
	return v.buildChainedBinaryExprMultiOp(ctx.GetChildren(), func(child antlr.Tree) (antlr.ParserRuleContext, bool) {
		prc, ok := child.(antlr.ParserRuleContext)
		if !ok {
			return nil, false
		}
		if c, ok := prc.(parser.IAdditiveExprContext); ok {
			return c, true
		}
		if c, ok := prc.(parser.IMultiplicativeExprContext); ok {
			return c, true
		}
		return nil, false
	}, map[int]token.Token{
		parser.ManuscriptPLUS:  token.ADD,
		parser.ManuscriptMINUS: token.SUB,
	}, "additive", ctx.GetStart())
}

// VisitMultiplicativeExpr handles multiplicative expressions (*, /, %)
func (v *ManuscriptAstVisitor) VisitMultiplicativeExpr(ctx *parser.MultiplicativeExprContext) interface{} {
	return v.buildChainedBinaryExprMultiOp(ctx.GetChildren(), func(child antlr.Tree) (antlr.ParserRuleContext, bool) {
		prc, ok := child.(antlr.ParserRuleContext)
		if !ok {
			return nil, false
		}
		if c, ok := prc.(parser.IMultiplicativeExprContext); ok {
			return c, true
		}
		if c, ok := prc.(parser.IUnaryExprContext); ok {
			return c, true
		}
		return nil, false
	}, map[int]token.Token{
		parser.ManuscriptSTAR:  token.MUL,
		parser.ManuscriptSLASH: token.QUO,
		parser.ManuscriptMOD:   token.REM,
	}, "multiplicative", ctx.GetStart())
}
