// Code generated from Manuscript.g4 by ANTLR 4.13.1. DO NOT EDIT.

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

type ManuscriptLexer struct {
	*antlr.BaseLexer
	channelNames []string
	modeNames    []string
	// TODO: EOF string
}

var ManuscriptLexerLexerStaticData struct {
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

func manuscriptlexerLexerInit() {
	staticData := &ManuscriptLexerLexerStaticData
	staticData.ChannelNames = []string{
		"DEFAULT_TOKEN_CHANNEL", "HIDDEN",
	}
	staticData.ModeNames = []string{
		"DEFAULT_MODE",
	}
	staticData.LiteralNames = []string{
		"", "", "'*'", "'/'", "'+'", "'-'", "'('", "')'", "';'",
	}
	staticData.SymbolicNames = []string{
		"", "INT", "MUL", "DIV", "ADD", "SUB", "LPAREN", "RPAREN", "SEMI", "WS",
	}
	staticData.RuleNames = []string{
		"INT", "MUL", "DIV", "ADD", "SUB", "LPAREN", "RPAREN", "SEMI", "WS",
	}
	staticData.PredictionContextCache = antlr.NewPredictionContextCache()
	staticData.serializedATN = []int32{
		4, 0, 9, 45, 6, -1, 2, 0, 7, 0, 2, 1, 7, 1, 2, 2, 7, 2, 2, 3, 7, 3, 2,
		4, 7, 4, 2, 5, 7, 5, 2, 6, 7, 6, 2, 7, 7, 7, 2, 8, 7, 8, 1, 0, 4, 0, 21,
		8, 0, 11, 0, 12, 0, 22, 1, 1, 1, 1, 1, 2, 1, 2, 1, 3, 1, 3, 1, 4, 1, 4,
		1, 5, 1, 5, 1, 6, 1, 6, 1, 7, 1, 7, 1, 8, 4, 8, 40, 8, 8, 11, 8, 12, 8,
		41, 1, 8, 1, 8, 0, 0, 9, 1, 1, 3, 2, 5, 3, 7, 4, 9, 5, 11, 6, 13, 7, 15,
		8, 17, 9, 1, 0, 2, 1, 0, 48, 57, 3, 0, 9, 10, 13, 13, 32, 32, 46, 0, 1,
		1, 0, 0, 0, 0, 3, 1, 0, 0, 0, 0, 5, 1, 0, 0, 0, 0, 7, 1, 0, 0, 0, 0, 9,
		1, 0, 0, 0, 0, 11, 1, 0, 0, 0, 0, 13, 1, 0, 0, 0, 0, 15, 1, 0, 0, 0, 0,
		17, 1, 0, 0, 0, 1, 20, 1, 0, 0, 0, 3, 24, 1, 0, 0, 0, 5, 26, 1, 0, 0, 0,
		7, 28, 1, 0, 0, 0, 9, 30, 1, 0, 0, 0, 11, 32, 1, 0, 0, 0, 13, 34, 1, 0,
		0, 0, 15, 36, 1, 0, 0, 0, 17, 39, 1, 0, 0, 0, 19, 21, 7, 0, 0, 0, 20, 19,
		1, 0, 0, 0, 21, 22, 1, 0, 0, 0, 22, 20, 1, 0, 0, 0, 22, 23, 1, 0, 0, 0,
		23, 2, 1, 0, 0, 0, 24, 25, 5, 42, 0, 0, 25, 4, 1, 0, 0, 0, 26, 27, 5, 47,
		0, 0, 27, 6, 1, 0, 0, 0, 28, 29, 5, 43, 0, 0, 29, 8, 1, 0, 0, 0, 30, 31,
		5, 45, 0, 0, 31, 10, 1, 0, 0, 0, 32, 33, 5, 40, 0, 0, 33, 12, 1, 0, 0,
		0, 34, 35, 5, 41, 0, 0, 35, 14, 1, 0, 0, 0, 36, 37, 5, 59, 0, 0, 37, 16,
		1, 0, 0, 0, 38, 40, 7, 1, 0, 0, 39, 38, 1, 0, 0, 0, 40, 41, 1, 0, 0, 0,
		41, 39, 1, 0, 0, 0, 41, 42, 1, 0, 0, 0, 42, 43, 1, 0, 0, 0, 43, 44, 6,
		8, 0, 0, 44, 18, 1, 0, 0, 0, 3, 0, 22, 41, 1, 6, 0, 0,
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

// ManuscriptLexerInit initializes any static state used to implement ManuscriptLexer. By default the
// static state used to implement the lexer is lazily initialized during the first call to
// NewManuscriptLexer(). You can call this function if you wish to initialize the static state ahead
// of time.
func ManuscriptLexerInit() {
	staticData := &ManuscriptLexerLexerStaticData
	staticData.once.Do(manuscriptlexerLexerInit)
}

// NewManuscriptLexer produces a new lexer instance for the optional input antlr.CharStream.
func NewManuscriptLexer(input antlr.CharStream) *ManuscriptLexer {
	ManuscriptLexerInit()
	l := new(ManuscriptLexer)
	l.BaseLexer = antlr.NewBaseLexer(input)
	staticData := &ManuscriptLexerLexerStaticData
	l.Interpreter = antlr.NewLexerATNSimulator(l, staticData.atn, staticData.decisionToDFA, staticData.PredictionContextCache)
	l.channelNames = staticData.ChannelNames
	l.modeNames = staticData.ModeNames
	l.RuleNames = staticData.RuleNames
	l.LiteralNames = staticData.LiteralNames
	l.SymbolicNames = staticData.SymbolicNames
	l.GrammarFileName = "Manuscript.g4"
	// TODO: l.EOF = antlr.TokenEOF

	return l
}

// ManuscriptLexer tokens.
const (
	ManuscriptLexerINT    = 1
	ManuscriptLexerMUL    = 2
	ManuscriptLexerDIV    = 3
	ManuscriptLexerADD    = 4
	ManuscriptLexerSUB    = 5
	ManuscriptLexerLPAREN = 6
	ManuscriptLexerRPAREN = 7
	ManuscriptLexerSEMI   = 8
	ManuscriptLexerWS     = 9
)
