// Code generated from Toy.g4 by ANTLR 4.13.1. DO NOT EDIT.

package parser // Toy

import "github.com/antlr4-go/antlr/v4"

// A complete Visitor for a parse tree produced by Toy.
type ToyVisitor interface {
	antlr.ParseTreeVisitor

	// Visit a parse tree produced by Toy#program.
	VisitProgram(ctx *ProgramContext) interface{}

	// Visit a parse tree produced by Toy#LetLabel.
	VisitLetLabel(ctx *LetLabelContext) interface{}

	// Visit a parse tree produced by Toy#FnLabel.
	VisitFnLabel(ctx *FnLabelContext) interface{}

	// Visit a parse tree produced by Toy#let.
	VisitLet(ctx *LetContext) interface{}

	// Visit a parse tree produced by Toy#fn.
	VisitFn(ctx *FnContext) interface{}

	// Visit a parse tree produced by Toy#expr.
	VisitExpr(ctx *ExprContext) interface{}
}
