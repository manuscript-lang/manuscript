package parser

import (
	"github.com/antlr4-go/antlr/v4"
)

// Package-level global variables for lexer state.
// This is a workaround for issues with ANTLR Go target's @members injection
// and accessing state in a wrapper struct from embedded struct actions.
// Use with caution: this makes the lexer non-reentrant if used concurrently.
var (
	lexerParenDepth   int
	lexerBracketDepth int
	lexerBraceDepth   int
)

// CustomManuscriptLexer wraps the ANTLR-generated ManuscriptLexer.
// In this setup, it doesn't hold the depth state itself but relies on global
// variables `lexerParenDepth`, etc., which are reset by its constructor.
type CustomManuscriptLexer struct {
	*ManuscriptLexer // Embed the ANTLR-generated lexer
}

// NewCustomManuscriptLexer creates a new instance of CustomManuscriptLexer.
// It initializes the embedded ANTLR lexer and resets the global depth tracking fields.
func NewCustomManuscriptLexer(input antlr.CharStream) *CustomManuscriptLexer {
	// Reset global state variables whenever a new lexer (effectively a new parsing session) starts.
	lexerParenDepth = 0
	lexerBracketDepth = 0
	lexerBraceDepth = 0

	antlrLexer := NewManuscriptLexer(input)

	customLexer := &CustomManuscriptLexer{
		ManuscriptLexer: antlrLexer,
	}

	return customLexer
}
