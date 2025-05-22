// Code generated from Toy.g4 by ANTLR 4.13.1. DO NOT EDIT.

package parser // Toy

import "github.com/antlr4-go/antlr/v4"

// BaseToyListener is a complete listener for a parse tree produced by Toy.
type BaseToyListener struct{}

var _ ToyListener = &BaseToyListener{}

// VisitTerminal is called when a terminal node is visited.
func (s *BaseToyListener) VisitTerminal(node antlr.TerminalNode) {}

// VisitErrorNode is called when an error node is visited.
func (s *BaseToyListener) VisitErrorNode(node antlr.ErrorNode) {}

// EnterEveryRule is called when any rule is entered.
func (s *BaseToyListener) EnterEveryRule(ctx antlr.ParserRuleContext) {}

// ExitEveryRule is called when any rule is exited.
func (s *BaseToyListener) ExitEveryRule(ctx antlr.ParserRuleContext) {}

// EnterProgram is called when production program is entered.
func (s *BaseToyListener) EnterProgram(ctx *ProgramContext) {}

// ExitProgram is called when production program is exited.
func (s *BaseToyListener) ExitProgram(ctx *ProgramContext) {}

// EnterLetLabel is called when production LetLabel is entered.
func (s *BaseToyListener) EnterLetLabel(ctx *LetLabelContext) {}

// ExitLetLabel is called when production LetLabel is exited.
func (s *BaseToyListener) ExitLetLabel(ctx *LetLabelContext) {}

// EnterFnLabel is called when production FnLabel is entered.
func (s *BaseToyListener) EnterFnLabel(ctx *FnLabelContext) {}

// ExitFnLabel is called when production FnLabel is exited.
func (s *BaseToyListener) ExitFnLabel(ctx *FnLabelContext) {}

// EnterLet is called when production let is entered.
func (s *BaseToyListener) EnterLet(ctx *LetContext) {}

// ExitLet is called when production let is exited.
func (s *BaseToyListener) ExitLet(ctx *LetContext) {}

// EnterFn is called when production fn is entered.
func (s *BaseToyListener) EnterFn(ctx *FnContext) {}

// ExitFn is called when production fn is exited.
func (s *BaseToyListener) ExitFn(ctx *FnContext) {}

// EnterExpr is called when production expr is entered.
func (s *BaseToyListener) EnterExpr(ctx *ExprContext) {}

// ExitExpr is called when production expr is exited.
func (s *BaseToyListener) ExitExpr(ctx *ExprContext) {}
