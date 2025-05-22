// Code generated from Toy.g4 by ANTLR 4.13.1. DO NOT EDIT.

package parser // Toy

import (
	"fmt"
	"strconv"
	"sync"

	"github.com/antlr4-go/antlr/v4"
)

// Suppress unused import errors
var _ = fmt.Printf
var _ = strconv.Itoa
var _ = sync.Once{}

type Toy struct {
	*antlr.BaseParser
}

var ToyParserStaticData struct {
	once                   sync.Once
	serializedATN          []int32
	LiteralNames           []string
	SymbolicNames          []string
	RuleNames              []string
	PredictionContextCache *antlr.PredictionContextCache
	atn                    *antlr.ATN
	decisionToDFA          []*antlr.DFA
}

func toyParserInit() {
	staticData := &ToyParserStaticData
	staticData.LiteralNames = []string{
		"", "'let'", "'fn'", "'='", "'('", "')'", "'{'", "'}'",
	}
	staticData.SymbolicNames = []string{
		"", "LET", "FN", "EQUALS", "LPAREN", "RPAREN", "LBRACE", "RBRACE", "ID",
		"WS",
	}
	staticData.RuleNames = []string{
		"program", "programItem", "let", "fn", "expr",
	}
	staticData.PredictionContextCache = antlr.NewPredictionContextCache()
	staticData.serializedATN = []int32{
		4, 1, 9, 38, 2, 0, 7, 0, 2, 1, 7, 1, 2, 2, 7, 2, 2, 3, 7, 3, 2, 4, 7, 4,
		1, 0, 5, 0, 12, 8, 0, 10, 0, 12, 0, 15, 9, 0, 1, 0, 1, 0, 1, 1, 1, 1, 3,
		1, 21, 8, 1, 1, 2, 1, 2, 1, 2, 1, 2, 1, 2, 1, 3, 1, 3, 1, 3, 1, 3, 1, 3,
		1, 3, 1, 3, 1, 3, 1, 4, 1, 4, 1, 4, 0, 0, 5, 0, 2, 4, 6, 8, 0, 0, 34, 0,
		13, 1, 0, 0, 0, 2, 20, 1, 0, 0, 0, 4, 22, 1, 0, 0, 0, 6, 27, 1, 0, 0, 0,
		8, 35, 1, 0, 0, 0, 10, 12, 3, 2, 1, 0, 11, 10, 1, 0, 0, 0, 12, 15, 1, 0,
		0, 0, 13, 11, 1, 0, 0, 0, 13, 14, 1, 0, 0, 0, 14, 16, 1, 0, 0, 0, 15, 13,
		1, 0, 0, 0, 16, 17, 5, 0, 0, 1, 17, 1, 1, 0, 0, 0, 18, 21, 3, 4, 2, 0,
		19, 21, 3, 6, 3, 0, 20, 18, 1, 0, 0, 0, 20, 19, 1, 0, 0, 0, 21, 3, 1, 0,
		0, 0, 22, 23, 5, 1, 0, 0, 23, 24, 5, 8, 0, 0, 24, 25, 5, 3, 0, 0, 25, 26,
		3, 8, 4, 0, 26, 5, 1, 0, 0, 0, 27, 28, 5, 2, 0, 0, 28, 29, 5, 8, 0, 0,
		29, 30, 5, 4, 0, 0, 30, 31, 5, 5, 0, 0, 31, 32, 5, 6, 0, 0, 32, 33, 3,
		8, 4, 0, 33, 34, 5, 7, 0, 0, 34, 7, 1, 0, 0, 0, 35, 36, 5, 8, 0, 0, 36,
		9, 1, 0, 0, 0, 2, 13, 20,
	}
	deserializer := antlr.NewATNDeserializer(nil)
	staticData.atn = deserializer.Deserialize(staticData.serializedATN)
	atn := staticData.atn
	staticData.decisionToDFA = make([]*antlr.DFA, len(atn.DecisionToState))
	decisionToDFA := staticData.decisionToDFA
	for index, state := range atn.DecisionToState {
		decisionToDFA[index] = antlr.NewDFA(state, index)
	}
}

// ToyInit initializes any static state used to implement Toy. By default the
// static state used to implement the parser is lazily initialized during the first call to
// NewToy(). You can call this function if you wish to initialize the static state ahead
// of time.
func ToyInit() {
	staticData := &ToyParserStaticData
	staticData.once.Do(toyParserInit)
}

// NewToy produces a new parser instance for the optional input antlr.TokenStream.
func NewToy(input antlr.TokenStream) *Toy {
	ToyInit()
	this := new(Toy)
	this.BaseParser = antlr.NewBaseParser(input)
	staticData := &ToyParserStaticData
	this.Interpreter = antlr.NewParserATNSimulator(this, staticData.atn, staticData.decisionToDFA, staticData.PredictionContextCache)
	this.RuleNames = staticData.RuleNames
	this.LiteralNames = staticData.LiteralNames
	this.SymbolicNames = staticData.SymbolicNames
	this.GrammarFileName = "Toy.g4"

	return this
}

// Toy tokens.
const (
	ToyEOF    = antlr.TokenEOF
	ToyLET    = 1
	ToyFN     = 2
	ToyEQUALS = 3
	ToyLPAREN = 4
	ToyRPAREN = 5
	ToyLBRACE = 6
	ToyRBRACE = 7
	ToyID     = 8
	ToyWS     = 9
)

// Toy rules.
const (
	ToyRULE_program     = 0
	ToyRULE_programItem = 1
	ToyRULE_let         = 2
	ToyRULE_fn          = 3
	ToyRULE_expr        = 4
)

// IProgramContext is an interface to support dynamic dispatch.
type IProgramContext interface {
	antlr.ParserRuleContext

	// GetParser returns the parser.
	GetParser() antlr.Parser

	// Getter signatures
	EOF() antlr.TerminalNode
	AllProgramItem() []IProgramItemContext
	ProgramItem(i int) IProgramItemContext

	// IsProgramContext differentiates from other interfaces.
	IsProgramContext()
}

type ProgramContext struct {
	antlr.BaseParserRuleContext
	parser antlr.Parser
}

func NewEmptyProgramContext() *ProgramContext {
	var p = new(ProgramContext)
	antlr.InitBaseParserRuleContext(&p.BaseParserRuleContext, nil, -1)
	p.RuleIndex = ToyRULE_program
	return p
}

func InitEmptyProgramContext(p *ProgramContext) {
	antlr.InitBaseParserRuleContext(&p.BaseParserRuleContext, nil, -1)
	p.RuleIndex = ToyRULE_program
}

func (*ProgramContext) IsProgramContext() {}

func NewProgramContext(parser antlr.Parser, parent antlr.ParserRuleContext, invokingState int) *ProgramContext {
	var p = new(ProgramContext)

	antlr.InitBaseParserRuleContext(&p.BaseParserRuleContext, parent, invokingState)

	p.parser = parser
	p.RuleIndex = ToyRULE_program

	return p
}

func (s *ProgramContext) GetParser() antlr.Parser { return s.parser }

func (s *ProgramContext) EOF() antlr.TerminalNode {
	return s.GetToken(ToyEOF, 0)
}

func (s *ProgramContext) AllProgramItem() []IProgramItemContext {
	children := s.GetChildren()
	len := 0
	for _, ctx := range children {
		if _, ok := ctx.(IProgramItemContext); ok {
			len++
		}
	}

	tst := make([]IProgramItemContext, len)
	i := 0
	for _, ctx := range children {
		if t, ok := ctx.(IProgramItemContext); ok {
			tst[i] = t.(IProgramItemContext)
			i++
		}
	}

	return tst
}

func (s *ProgramContext) ProgramItem(i int) IProgramItemContext {
	var t antlr.RuleContext
	j := 0
	for _, ctx := range s.GetChildren() {
		if _, ok := ctx.(IProgramItemContext); ok {
			if j == i {
				t = ctx.(antlr.RuleContext)
				break
			}
			j++
		}
	}

	if t == nil {
		return nil
	}

	return t.(IProgramItemContext)
}

func (s *ProgramContext) GetRuleContext() antlr.RuleContext {
	return s
}

func (s *ProgramContext) ToStringTree(ruleNames []string, recog antlr.Recognizer) string {
	return antlr.TreesStringTree(s, ruleNames, recog)
}

func (s *ProgramContext) EnterRule(listener antlr.ParseTreeListener) {
	if listenerT, ok := listener.(ToyListener); ok {
		listenerT.EnterProgram(s)
	}
}

func (s *ProgramContext) ExitRule(listener antlr.ParseTreeListener) {
	if listenerT, ok := listener.(ToyListener); ok {
		listenerT.ExitProgram(s)
	}
}

func (s *ProgramContext) Accept(visitor antlr.ParseTreeVisitor) interface{} {
	switch t := visitor.(type) {
	case ToyVisitor:
		return t.VisitProgram(s)

	default:
		return t.VisitChildren(s)
	}
}

func (p *Toy) Program() (localctx IProgramContext) {
	localctx = NewProgramContext(p, p.GetParserRuleContext(), p.GetState())
	p.EnterRule(localctx, 0, ToyRULE_program)
	var _la int

	p.EnterOuterAlt(localctx, 1)
	p.SetState(13)
	p.GetErrorHandler().Sync(p)
	if p.HasError() {
		goto errorExit
	}
	_la = p.GetTokenStream().LA(1)

	for _la == ToyLET || _la == ToyFN {
		{
			p.SetState(10)
			p.ProgramItem()
		}

		p.SetState(15)
		p.GetErrorHandler().Sync(p)
		if p.HasError() {
			goto errorExit
		}
		_la = p.GetTokenStream().LA(1)
	}
	{
		p.SetState(16)
		p.Match(ToyEOF)
		if p.HasError() {
			// Recognition error - abort rule
			goto errorExit
		}
	}

errorExit:
	if p.HasError() {
		v := p.GetError()
		localctx.SetException(v)
		p.GetErrorHandler().ReportError(p, v)
		p.GetErrorHandler().Recover(p, v)
		p.SetError(nil)
	}
	p.ExitRule()
	return localctx
	goto errorExit // Trick to prevent compiler error if the label is not used
}

// IProgramItemContext is an interface to support dynamic dispatch.
type IProgramItemContext interface {
	antlr.ParserRuleContext

	// GetParser returns the parser.
	GetParser() antlr.Parser
	// IsProgramItemContext differentiates from other interfaces.
	IsProgramItemContext()
}

type ProgramItemContext struct {
	antlr.BaseParserRuleContext
	parser antlr.Parser
}

func NewEmptyProgramItemContext() *ProgramItemContext {
	var p = new(ProgramItemContext)
	antlr.InitBaseParserRuleContext(&p.BaseParserRuleContext, nil, -1)
	p.RuleIndex = ToyRULE_programItem
	return p
}

func InitEmptyProgramItemContext(p *ProgramItemContext) {
	antlr.InitBaseParserRuleContext(&p.BaseParserRuleContext, nil, -1)
	p.RuleIndex = ToyRULE_programItem
}

func (*ProgramItemContext) IsProgramItemContext() {}

func NewProgramItemContext(parser antlr.Parser, parent antlr.ParserRuleContext, invokingState int) *ProgramItemContext {
	var p = new(ProgramItemContext)

	antlr.InitBaseParserRuleContext(&p.BaseParserRuleContext, parent, invokingState)

	p.parser = parser
	p.RuleIndex = ToyRULE_programItem

	return p
}

func (s *ProgramItemContext) GetParser() antlr.Parser { return s.parser }

func (s *ProgramItemContext) CopyAll(ctx *ProgramItemContext) {
	s.CopyFrom(&ctx.BaseParserRuleContext)
}

func (s *ProgramItemContext) GetRuleContext() antlr.RuleContext {
	return s
}

func (s *ProgramItemContext) ToStringTree(ruleNames []string, recog antlr.Recognizer) string {
	return antlr.TreesStringTree(s, ruleNames, recog)
}

type LetLabelContext struct {
	ProgramItemContext
}

func NewLetLabelContext(parser antlr.Parser, ctx antlr.ParserRuleContext) *LetLabelContext {
	var p = new(LetLabelContext)

	InitEmptyProgramItemContext(&p.ProgramItemContext)
	p.parser = parser
	p.CopyAll(ctx.(*ProgramItemContext))

	return p
}

func (s *LetLabelContext) GetRuleContext() antlr.RuleContext {
	return s
}

func (s *LetLabelContext) Let() ILetContext {
	var t antlr.RuleContext
	for _, ctx := range s.GetChildren() {
		if _, ok := ctx.(ILetContext); ok {
			t = ctx.(antlr.RuleContext)
			break
		}
	}

	if t == nil {
		return nil
	}

	return t.(ILetContext)
}

func (s *LetLabelContext) EnterRule(listener antlr.ParseTreeListener) {
	if listenerT, ok := listener.(ToyListener); ok {
		listenerT.EnterLetLabel(s)
	}
}

func (s *LetLabelContext) ExitRule(listener antlr.ParseTreeListener) {
	if listenerT, ok := listener.(ToyListener); ok {
		listenerT.ExitLetLabel(s)
	}
}

func (s *LetLabelContext) Accept(visitor antlr.ParseTreeVisitor) interface{} {
	switch t := visitor.(type) {
	case ToyVisitor:
		return t.VisitLetLabel(s)

	default:
		return t.VisitChildren(s)
	}
}

type FnLabelContext struct {
	ProgramItemContext
}

func NewFnLabelContext(parser antlr.Parser, ctx antlr.ParserRuleContext) *FnLabelContext {
	var p = new(FnLabelContext)

	InitEmptyProgramItemContext(&p.ProgramItemContext)
	p.parser = parser
	p.CopyAll(ctx.(*ProgramItemContext))

	return p
}

func (s *FnLabelContext) GetRuleContext() antlr.RuleContext {
	return s
}

func (s *FnLabelContext) Fn() IFnContext {
	var t antlr.RuleContext
	for _, ctx := range s.GetChildren() {
		if _, ok := ctx.(IFnContext); ok {
			t = ctx.(antlr.RuleContext)
			break
		}
	}

	if t == nil {
		return nil
	}

	return t.(IFnContext)
}

func (s *FnLabelContext) EnterRule(listener antlr.ParseTreeListener) {
	if listenerT, ok := listener.(ToyListener); ok {
		listenerT.EnterFnLabel(s)
	}
}

func (s *FnLabelContext) ExitRule(listener antlr.ParseTreeListener) {
	if listenerT, ok := listener.(ToyListener); ok {
		listenerT.ExitFnLabel(s)
	}
}

func (s *FnLabelContext) Accept(visitor antlr.ParseTreeVisitor) interface{} {
	switch t := visitor.(type) {
	case ToyVisitor:
		return t.VisitFnLabel(s)

	default:
		return t.VisitChildren(s)
	}
}

func (p *Toy) ProgramItem() (localctx IProgramItemContext) {
	localctx = NewProgramItemContext(p, p.GetParserRuleContext(), p.GetState())
	p.EnterRule(localctx, 2, ToyRULE_programItem)
	p.SetState(20)
	p.GetErrorHandler().Sync(p)
	if p.HasError() {
		goto errorExit
	}

	switch p.GetTokenStream().LA(1) {
	case ToyLET:
		localctx = NewLetLabelContext(p, localctx)
		p.EnterOuterAlt(localctx, 1)
		{
			p.SetState(18)
			p.Let()
		}

	case ToyFN:
		localctx = NewFnLabelContext(p, localctx)
		p.EnterOuterAlt(localctx, 2)
		{
			p.SetState(19)
			p.Fn()
		}

	default:
		p.SetError(antlr.NewNoViableAltException(p, nil, nil, nil, nil, nil))
		goto errorExit
	}

errorExit:
	if p.HasError() {
		v := p.GetError()
		localctx.SetException(v)
		p.GetErrorHandler().ReportError(p, v)
		p.GetErrorHandler().Recover(p, v)
		p.SetError(nil)
	}
	p.ExitRule()
	return localctx
	goto errorExit // Trick to prevent compiler error if the label is not used
}

// ILetContext is an interface to support dynamic dispatch.
type ILetContext interface {
	antlr.ParserRuleContext

	// GetParser returns the parser.
	GetParser() antlr.Parser

	// Getter signatures
	LET() antlr.TerminalNode
	ID() antlr.TerminalNode
	EQUALS() antlr.TerminalNode
	Expr() IExprContext

	// IsLetContext differentiates from other interfaces.
	IsLetContext()
}

type LetContext struct {
	antlr.BaseParserRuleContext
	parser antlr.Parser
}

func NewEmptyLetContext() *LetContext {
	var p = new(LetContext)
	antlr.InitBaseParserRuleContext(&p.BaseParserRuleContext, nil, -1)
	p.RuleIndex = ToyRULE_let
	return p
}

func InitEmptyLetContext(p *LetContext) {
	antlr.InitBaseParserRuleContext(&p.BaseParserRuleContext, nil, -1)
	p.RuleIndex = ToyRULE_let
}

func (*LetContext) IsLetContext() {}

func NewLetContext(parser antlr.Parser, parent antlr.ParserRuleContext, invokingState int) *LetContext {
	var p = new(LetContext)

	antlr.InitBaseParserRuleContext(&p.BaseParserRuleContext, parent, invokingState)

	p.parser = parser
	p.RuleIndex = ToyRULE_let

	return p
}

func (s *LetContext) GetParser() antlr.Parser { return s.parser }

func (s *LetContext) LET() antlr.TerminalNode {
	return s.GetToken(ToyLET, 0)
}

func (s *LetContext) ID() antlr.TerminalNode {
	return s.GetToken(ToyID, 0)
}

func (s *LetContext) EQUALS() antlr.TerminalNode {
	return s.GetToken(ToyEQUALS, 0)
}

func (s *LetContext) Expr() IExprContext {
	var t antlr.RuleContext
	for _, ctx := range s.GetChildren() {
		if _, ok := ctx.(IExprContext); ok {
			t = ctx.(antlr.RuleContext)
			break
		}
	}

	if t == nil {
		return nil
	}

	return t.(IExprContext)
}

func (s *LetContext) GetRuleContext() antlr.RuleContext {
	return s
}

func (s *LetContext) ToStringTree(ruleNames []string, recog antlr.Recognizer) string {
	return antlr.TreesStringTree(s, ruleNames, recog)
}

func (s *LetContext) EnterRule(listener antlr.ParseTreeListener) {
	if listenerT, ok := listener.(ToyListener); ok {
		listenerT.EnterLet(s)
	}
}

func (s *LetContext) ExitRule(listener antlr.ParseTreeListener) {
	if listenerT, ok := listener.(ToyListener); ok {
		listenerT.ExitLet(s)
	}
}

func (s *LetContext) Accept(visitor antlr.ParseTreeVisitor) interface{} {
	switch t := visitor.(type) {
	case ToyVisitor:
		return t.VisitLet(s)

	default:
		return t.VisitChildren(s)
	}
}

func (p *Toy) Let() (localctx ILetContext) {
	localctx = NewLetContext(p, p.GetParserRuleContext(), p.GetState())
	p.EnterRule(localctx, 4, ToyRULE_let)
	p.EnterOuterAlt(localctx, 1)
	{
		p.SetState(22)
		p.Match(ToyLET)
		if p.HasError() {
			// Recognition error - abort rule
			goto errorExit
		}
	}
	{
		p.SetState(23)
		p.Match(ToyID)
		if p.HasError() {
			// Recognition error - abort rule
			goto errorExit
		}
	}
	{
		p.SetState(24)
		p.Match(ToyEQUALS)
		if p.HasError() {
			// Recognition error - abort rule
			goto errorExit
		}
	}
	{
		p.SetState(25)
		p.Expr()
	}

errorExit:
	if p.HasError() {
		v := p.GetError()
		localctx.SetException(v)
		p.GetErrorHandler().ReportError(p, v)
		p.GetErrorHandler().Recover(p, v)
		p.SetError(nil)
	}
	p.ExitRule()
	return localctx
	goto errorExit // Trick to prevent compiler error if the label is not used
}

// IFnContext is an interface to support dynamic dispatch.
type IFnContext interface {
	antlr.ParserRuleContext

	// GetParser returns the parser.
	GetParser() antlr.Parser

	// Getter signatures
	FN() antlr.TerminalNode
	ID() antlr.TerminalNode
	LPAREN() antlr.TerminalNode
	RPAREN() antlr.TerminalNode
	LBRACE() antlr.TerminalNode
	Expr() IExprContext
	RBRACE() antlr.TerminalNode

	// IsFnContext differentiates from other interfaces.
	IsFnContext()
}

type FnContext struct {
	antlr.BaseParserRuleContext
	parser antlr.Parser
}

func NewEmptyFnContext() *FnContext {
	var p = new(FnContext)
	antlr.InitBaseParserRuleContext(&p.BaseParserRuleContext, nil, -1)
	p.RuleIndex = ToyRULE_fn
	return p
}

func InitEmptyFnContext(p *FnContext) {
	antlr.InitBaseParserRuleContext(&p.BaseParserRuleContext, nil, -1)
	p.RuleIndex = ToyRULE_fn
}

func (*FnContext) IsFnContext() {}

func NewFnContext(parser antlr.Parser, parent antlr.ParserRuleContext, invokingState int) *FnContext {
	var p = new(FnContext)

	antlr.InitBaseParserRuleContext(&p.BaseParserRuleContext, parent, invokingState)

	p.parser = parser
	p.RuleIndex = ToyRULE_fn

	return p
}

func (s *FnContext) GetParser() antlr.Parser { return s.parser }

func (s *FnContext) FN() antlr.TerminalNode {
	return s.GetToken(ToyFN, 0)
}

func (s *FnContext) ID() antlr.TerminalNode {
	return s.GetToken(ToyID, 0)
}

func (s *FnContext) LPAREN() antlr.TerminalNode {
	return s.GetToken(ToyLPAREN, 0)
}

func (s *FnContext) RPAREN() antlr.TerminalNode {
	return s.GetToken(ToyRPAREN, 0)
}

func (s *FnContext) LBRACE() antlr.TerminalNode {
	return s.GetToken(ToyLBRACE, 0)
}

func (s *FnContext) Expr() IExprContext {
	var t antlr.RuleContext
	for _, ctx := range s.GetChildren() {
		if _, ok := ctx.(IExprContext); ok {
			t = ctx.(antlr.RuleContext)
			break
		}
	}

	if t == nil {
		return nil
	}

	return t.(IExprContext)
}

func (s *FnContext) RBRACE() antlr.TerminalNode {
	return s.GetToken(ToyRBRACE, 0)
}

func (s *FnContext) GetRuleContext() antlr.RuleContext {
	return s
}

func (s *FnContext) ToStringTree(ruleNames []string, recog antlr.Recognizer) string {
	return antlr.TreesStringTree(s, ruleNames, recog)
}

func (s *FnContext) EnterRule(listener antlr.ParseTreeListener) {
	if listenerT, ok := listener.(ToyListener); ok {
		listenerT.EnterFn(s)
	}
}

func (s *FnContext) ExitRule(listener antlr.ParseTreeListener) {
	if listenerT, ok := listener.(ToyListener); ok {
		listenerT.ExitFn(s)
	}
}

func (s *FnContext) Accept(visitor antlr.ParseTreeVisitor) interface{} {
	switch t := visitor.(type) {
	case ToyVisitor:
		return t.VisitFn(s)

	default:
		return t.VisitChildren(s)
	}
}

func (p *Toy) Fn() (localctx IFnContext) {
	localctx = NewFnContext(p, p.GetParserRuleContext(), p.GetState())
	p.EnterRule(localctx, 6, ToyRULE_fn)
	p.EnterOuterAlt(localctx, 1)
	{
		p.SetState(27)
		p.Match(ToyFN)
		if p.HasError() {
			// Recognition error - abort rule
			goto errorExit
		}
	}
	{
		p.SetState(28)
		p.Match(ToyID)
		if p.HasError() {
			// Recognition error - abort rule
			goto errorExit
		}
	}
	{
		p.SetState(29)
		p.Match(ToyLPAREN)
		if p.HasError() {
			// Recognition error - abort rule
			goto errorExit
		}
	}
	{
		p.SetState(30)
		p.Match(ToyRPAREN)
		if p.HasError() {
			// Recognition error - abort rule
			goto errorExit
		}
	}
	{
		p.SetState(31)
		p.Match(ToyLBRACE)
		if p.HasError() {
			// Recognition error - abort rule
			goto errorExit
		}
	}
	{
		p.SetState(32)
		p.Expr()
	}
	{
		p.SetState(33)
		p.Match(ToyRBRACE)
		if p.HasError() {
			// Recognition error - abort rule
			goto errorExit
		}
	}

errorExit:
	if p.HasError() {
		v := p.GetError()
		localctx.SetException(v)
		p.GetErrorHandler().ReportError(p, v)
		p.GetErrorHandler().Recover(p, v)
		p.SetError(nil)
	}
	p.ExitRule()
	return localctx
	goto errorExit // Trick to prevent compiler error if the label is not used
}

// IExprContext is an interface to support dynamic dispatch.
type IExprContext interface {
	antlr.ParserRuleContext

	// GetParser returns the parser.
	GetParser() antlr.Parser

	// Getter signatures
	ID() antlr.TerminalNode

	// IsExprContext differentiates from other interfaces.
	IsExprContext()
}

type ExprContext struct {
	antlr.BaseParserRuleContext
	parser antlr.Parser
}

func NewEmptyExprContext() *ExprContext {
	var p = new(ExprContext)
	antlr.InitBaseParserRuleContext(&p.BaseParserRuleContext, nil, -1)
	p.RuleIndex = ToyRULE_expr
	return p
}

func InitEmptyExprContext(p *ExprContext) {
	antlr.InitBaseParserRuleContext(&p.BaseParserRuleContext, nil, -1)
	p.RuleIndex = ToyRULE_expr
}

func (*ExprContext) IsExprContext() {}

func NewExprContext(parser antlr.Parser, parent antlr.ParserRuleContext, invokingState int) *ExprContext {
	var p = new(ExprContext)

	antlr.InitBaseParserRuleContext(&p.BaseParserRuleContext, parent, invokingState)

	p.parser = parser
	p.RuleIndex = ToyRULE_expr

	return p
}

func (s *ExprContext) GetParser() antlr.Parser { return s.parser }

func (s *ExprContext) ID() antlr.TerminalNode {
	return s.GetToken(ToyID, 0)
}

func (s *ExprContext) GetRuleContext() antlr.RuleContext {
	return s
}

func (s *ExprContext) ToStringTree(ruleNames []string, recog antlr.Recognizer) string {
	return antlr.TreesStringTree(s, ruleNames, recog)
}

func (s *ExprContext) EnterRule(listener antlr.ParseTreeListener) {
	if listenerT, ok := listener.(ToyListener); ok {
		listenerT.EnterExpr(s)
	}
}

func (s *ExprContext) ExitRule(listener antlr.ParseTreeListener) {
	if listenerT, ok := listener.(ToyListener); ok {
		listenerT.ExitExpr(s)
	}
}

func (s *ExprContext) Accept(visitor antlr.ParseTreeVisitor) interface{} {
	switch t := visitor.(type) {
	case ToyVisitor:
		return t.VisitExpr(s)

	default:
		return t.VisitChildren(s)
	}
}

func (p *Toy) Expr() (localctx IExprContext) {
	localctx = NewExprContext(p, p.GetParserRuleContext(), p.GetState())
	p.EnterRule(localctx, 8, ToyRULE_expr)
	p.EnterOuterAlt(localctx, 1)
	{
		p.SetState(35)
		p.Match(ToyID)
		if p.HasError() {
			// Recognition error - abort rule
			goto errorExit
		}
	}

errorExit:
	if p.HasError() {
		v := p.GetError()
		localctx.SetException(v)
		p.GetErrorHandler().ReportError(p, v)
		p.GetErrorHandler().Recover(p, v)
		p.SetError(nil)
	}
	p.ExitRule()
	return localctx
	goto errorExit // Trick to prevent compiler error if the label is not used
}
