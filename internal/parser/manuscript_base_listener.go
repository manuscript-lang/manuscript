// Code generated from Manuscript.g4 by ANTLR 4.13.1. DO NOT EDIT.

package parser // Manuscript
import "github.com/antlr4-go/antlr/v4"

// BaseManuscriptListener is a complete listener for a parse tree produced by ManuscriptParser.
type BaseManuscriptListener struct{}

var _ ManuscriptListener = &BaseManuscriptListener{}

// VisitTerminal is called when a terminal node is visited.
func (s *BaseManuscriptListener) VisitTerminal(node antlr.TerminalNode) {}

// VisitErrorNode is called when an error node is visited.
func (s *BaseManuscriptListener) VisitErrorNode(node antlr.ErrorNode) {}

// EnterEveryRule is called when any rule is entered.
func (s *BaseManuscriptListener) EnterEveryRule(ctx antlr.ParserRuleContext) {}

// ExitEveryRule is called when any rule is exited.
func (s *BaseManuscriptListener) ExitEveryRule(ctx antlr.ParserRuleContext) {}

// EnterProgram is called when production program is entered.
func (s *BaseManuscriptListener) EnterProgram(ctx *ProgramContext) {}

// ExitProgram is called when production program is exited.
func (s *BaseManuscriptListener) ExitProgram(ctx *ProgramContext) {}

// EnterStatement is called when production statement is entered.
func (s *BaseManuscriptListener) EnterStatement(ctx *StatementContext) {}

// ExitStatement is called when production statement is exited.
func (s *BaseManuscriptListener) ExitStatement(ctx *StatementContext) {}

// EnterMulDiv is called when production MulDiv is entered.
func (s *BaseManuscriptListener) EnterMulDiv(ctx *MulDivContext) {}

// ExitMulDiv is called when production MulDiv is exited.
func (s *BaseManuscriptListener) ExitMulDiv(ctx *MulDivContext) {}

// EnterAddSub is called when production AddSub is entered.
func (s *BaseManuscriptListener) EnterAddSub(ctx *AddSubContext) {}

// ExitAddSub is called when production AddSub is exited.
func (s *BaseManuscriptListener) ExitAddSub(ctx *AddSubContext) {}

// EnterParens is called when production Parens is entered.
func (s *BaseManuscriptListener) EnterParens(ctx *ParensContext) {}

// ExitParens is called when production Parens is exited.
func (s *BaseManuscriptListener) ExitParens(ctx *ParensContext) {}

// EnterInt is called when production Int is entered.
func (s *BaseManuscriptListener) EnterInt(ctx *IntContext) {}

// ExitInt is called when production Int is exited.
func (s *BaseManuscriptListener) ExitInt(ctx *IntContext) {}
