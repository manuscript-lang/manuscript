// Code generated from ToyLexer.g4 by ANTLR 4.13.1. DO NOT EDIT.

package parser

import (
	"fmt"
	"github.com/antlr4-go/antlr/v4"
	"sync"
	"unicode"
)

// Suppress unused import error
var _ = fmt.Printf
var _ = sync.Once{}
var _ = unicode.IsLetter

type ToyLexer struct {
	*antlr.BaseLexer
	channelNames []string
	modeNames    []string
	// TODO: EOF string
}

var ToyLexerLexerStaticData struct {
	once                   sync.Once
	serializedATN          []int32
	ChannelNames           []string
	ModeNames              []string
	LiteralNames           []string
	SymbolicNames          []string
	RuleNames              []string
	PredictionContextCache *antlr.PredictionContextCache
	atn                    *antlr.ATN
	decisionToDFA          []*antlr.DFA
}

func toylexerLexerInit() {
	staticData := &ToyLexerLexerStaticData
	staticData.ChannelNames = []string{
		"DEFAULT_TOKEN_CHANNEL", "HIDDEN",
	}
	staticData.ModeNames = []string{
		"DEFAULT_MODE",
	}
	staticData.LiteralNames = []string{
		"", "'let'", "'fn'", "'='", "'('", "')'", "'{'", "'}'",
	}
	staticData.SymbolicNames = []string{
		"", "LET", "FN", "EQUALS", "LPAREN", "RPAREN", "LBRACE", "RBRACE", "ID",
		"WS",
	}
	staticData.RuleNames = []string{
		"LET", "FN", "EQUALS", "LPAREN", "RPAREN", "LBRACE", "RBRACE", "ID",
		"WS",
	}
	staticData.PredictionContextCache = antlr.NewPredictionContextCache()
	staticData.serializedATN = []int32{
		4, 0, 9, 48, 6, -1, 2, 0, 7, 0, 2, 1, 7, 1, 2, 2, 7, 2, 2, 3, 7, 3, 2,
		4, 7, 4, 2, 5, 7, 5, 2, 6, 7, 6, 2, 7, 7, 7, 2, 8, 7, 8, 1, 0, 1, 0, 1,
		0, 1, 0, 1, 1, 1, 1, 1, 1, 1, 2, 1, 2, 1, 3, 1, 3, 1, 4, 1, 4, 1, 5, 1,
		5, 1, 6, 1, 6, 1, 7, 4, 7, 38, 8, 7, 11, 7, 12, 7, 39, 1, 8, 4, 8, 43,
		8, 8, 11, 8, 12, 8, 44, 1, 8, 1, 8, 0, 0, 9, 1, 1, 3, 2, 5, 3, 7, 4, 9,
		5, 11, 6, 13, 7, 15, 8, 17, 9, 1, 0, 2, 2, 0, 65, 90, 97, 122, 3, 0, 9,
		10, 13, 13, 32, 32, 49, 0, 1, 1, 0, 0, 0, 0, 3, 1, 0, 0, 0, 0, 5, 1, 0,
		0, 0, 0, 7, 1, 0, 0, 0, 0, 9, 1, 0, 0, 0, 0, 11, 1, 0, 0, 0, 0, 13, 1,
		0, 0, 0, 0, 15, 1, 0, 0, 0, 0, 17, 1, 0, 0, 0, 1, 19, 1, 0, 0, 0, 3, 23,
		1, 0, 0, 0, 5, 26, 1, 0, 0, 0, 7, 28, 1, 0, 0, 0, 9, 30, 1, 0, 0, 0, 11,
		32, 1, 0, 0, 0, 13, 34, 1, 0, 0, 0, 15, 37, 1, 0, 0, 0, 17, 42, 1, 0, 0,
		0, 19, 20, 5, 108, 0, 0, 20, 21, 5, 101, 0, 0, 21, 22, 5, 116, 0, 0, 22,
		2, 1, 0, 0, 0, 23, 24, 5, 102, 0, 0, 24, 25, 5, 110, 0, 0, 25, 4, 1, 0,
		0, 0, 26, 27, 5, 61, 0, 0, 27, 6, 1, 0, 0, 0, 28, 29, 5, 40, 0, 0, 29,
		8, 1, 0, 0, 0, 30, 31, 5, 41, 0, 0, 31, 10, 1, 0, 0, 0, 32, 33, 5, 123,
		0, 0, 33, 12, 1, 0, 0, 0, 34, 35, 5, 125, 0, 0, 35, 14, 1, 0, 0, 0, 36,
		38, 7, 0, 0, 0, 37, 36, 1, 0, 0, 0, 38, 39, 1, 0, 0, 0, 39, 37, 1, 0, 0,
		0, 39, 40, 1, 0, 0, 0, 40, 16, 1, 0, 0, 0, 41, 43, 7, 1, 0, 0, 42, 41,
		1, 0, 0, 0, 43, 44, 1, 0, 0, 0, 44, 42, 1, 0, 0, 0, 44, 45, 1, 0, 0, 0,
		45, 46, 1, 0, 0, 0, 46, 47, 6, 8, 0, 0, 47, 18, 1, 0, 0, 0, 3, 0, 39, 44,
		1, 6, 0, 0,
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

// ToyLexerInit initializes any static state used to implement ToyLexer. By default the
// static state used to implement the lexer is lazily initialized during the first call to
// NewToyLexer(). You can call this function if you wish to initialize the static state ahead
// of time.
func ToyLexerInit() {
	staticData := &ToyLexerLexerStaticData
	staticData.once.Do(toylexerLexerInit)
}

// NewToyLexer produces a new lexer instance for the optional input antlr.CharStream.
func NewToyLexer(input antlr.CharStream) *ToyLexer {
	ToyLexerInit()
	l := new(ToyLexer)
	l.BaseLexer = antlr.NewBaseLexer(input)
	staticData := &ToyLexerLexerStaticData
	l.Interpreter = antlr.NewLexerATNSimulator(l, staticData.atn, staticData.decisionToDFA, staticData.PredictionContextCache)
	l.channelNames = staticData.ChannelNames
	l.modeNames = staticData.ModeNames
	l.RuleNames = staticData.RuleNames
	l.LiteralNames = staticData.LiteralNames
	l.SymbolicNames = staticData.SymbolicNames
	l.GrammarFileName = "ToyLexer.g4"
	// TODO: l.EOF = antlr.TokenEOF

	return l
}

// ToyLexer tokens.
const (
	ToyLexerLET    = 1
	ToyLexerFN     = 2
	ToyLexerEQUALS = 3
	ToyLexerLPAREN = 4
	ToyLexerRPAREN = 5
	ToyLexerLBRACE = 6
	ToyLexerRBRACE = 7
	ToyLexerID     = 8
	ToyLexerWS     = 9
)
