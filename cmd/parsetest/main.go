package main

import (
	"fmt"
	"os"

	"manuscript-co/manuscript/internal/parser"

	"github.com/antlr4-go/antlr/v4"
)

type errorListener struct {
	*antlr.DefaultErrorListener
	hasError bool
}

func (e *errorListener) SyntaxError(recognizer antlr.Recognizer, offendingSymbol interface{}, line, column int, msg string, ex antlr.RecognitionException) {
	e.hasError = true
	fmt.Fprintf(os.Stderr, "line %d:%d %s\n", line, column, msg)
}

func main() {
	input := `
fn main() {
  let x = 10
}
`
	inputStream := antlr.NewInputStream(input)
	lexer := parser.NewManuscriptLexer(inputStream)
	stream := antlr.NewCommonTokenStream(lexer, antlr.TokenDefaultChannel)
	p := parser.NewManuscript(stream) // Changed NewManuscriptParser to NewManuscript

	errorListener := &errorListener{}
	p.RemoveErrorListeners()
	p.AddErrorListener(errorListener)

	// Attempt to parse the program rule
	tree := p.Program()

	if errorListener.hasError {
		fmt.Println("Parsing failed with errors.")
		// Optionally, print the parse tree for debugging even if there are errors
		// fmt.Println(tree.ToStringTree(p.RuleNames, nil))
		os.Exit(1)
	} else {
		fmt.Println("Parsing successful!")
		fmt.Println("Parse tree (S-expression format):")
		fmt.Println(tree.ToStringTree(p.RuleNames, nil))
	}
}
