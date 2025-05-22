// Code generated from Toy.g4 by ANTLR 4.13.1. DO NOT EDIT.

package parser // Toy

import "github.com/antlr4-go/antlr/v4"

type BaseToyVisitor struct {
	*antlr.BaseParseTreeVisitor
}

func (v *BaseToyVisitor) VisitProgram(ctx *ProgramContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseToyVisitor) VisitLetLabel(ctx *LetLabelContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseToyVisitor) VisitFnLabel(ctx *FnLabelContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseToyVisitor) VisitLet(ctx *LetContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseToyVisitor) VisitFn(ctx *FnContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseToyVisitor) VisitExpr(ctx *ExprContext) interface{} {
	return v.VisitChildren(ctx)
}
