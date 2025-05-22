// Code generated from Toy.g4 by ANTLR 4.13.1. DO NOT EDIT.

package parser // Toy

import "github.com/antlr4-go/antlr/v4"

// ToyListener is a complete listener for a parse tree produced by Toy.
type ToyListener interface {
	antlr.ParseTreeListener

	// EnterProgram is called when entering the program production.
	EnterProgram(c *ProgramContext)

	// EnterLetLabel is called when entering the LetLabel production.
	EnterLetLabel(c *LetLabelContext)

	// EnterFnLabel is called when entering the FnLabel production.
	EnterFnLabel(c *FnLabelContext)

	// EnterLet is called when entering the let production.
	EnterLet(c *LetContext)

	// EnterFn is called when entering the fn production.
	EnterFn(c *FnContext)

	// EnterExpr is called when entering the expr production.
	EnterExpr(c *ExprContext)

	// ExitProgram is called when exiting the program production.
	ExitProgram(c *ProgramContext)

	// ExitLetLabel is called when exiting the LetLabel production.
	ExitLetLabel(c *LetLabelContext)

	// ExitFnLabel is called when exiting the FnLabel production.
	ExitFnLabel(c *FnLabelContext)

	// ExitLet is called when exiting the let production.
	ExitLet(c *LetContext)

	// ExitFn is called when exiting the fn production.
	ExitFn(c *FnContext)

	// ExitExpr is called when exiting the expr production.
	ExitExpr(c *ExprContext)
}
