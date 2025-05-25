package main

import (
	"bytes"
	"errors"
	"flag"
	"fmt"
	"go/ast"
	"go/printer"
	"go/token"
	"log"
	mast "manuscript-co/manuscript/internal/ast"
	"manuscript-co/manuscript/internal/msparse"
	parser "manuscript-co/manuscript/internal/parser"
	"manuscript-co/manuscript/internal/transpiler"
	"os"
	"strings"

	"github.com/antlr4-go/antlr/v4"
)

const (
	syntaxErrorCode = "// SYNTAX ERROR"
)

// SyntaxErrorListener captures syntax errors from the ANTLR parser.
type SyntaxErrorListener struct {
	*antlr.DefaultErrorListener
	Errors []string
}

// NewSyntaxErrorListener creates a new instance of SyntaxErrorListener.
func NewSyntaxErrorListener() *SyntaxErrorListener {
	return &SyntaxErrorListener{Errors: make([]string, 0)}
}

// SyntaxError is called by ANTLR when a syntax error is encountered.
func (l *SyntaxErrorListener) SyntaxError(recognizer antlr.Recognizer, offendingSymbol interface{}, line, column int, msg string, e antlr.RecognitionException) {
	l.Errors = append(l.Errors, fmt.Sprintf("line %d:%d %s", line, column, msg))
}

func manuscriptToGo(input string, debug bool) (string, error) {
	tree, hasErrors := parseManuscriptCode(input, debug)
	if hasErrors {
		return "", errors.New(syntaxErrorCode)
	}

	return convertToGoCode(tree), nil
}

func parseManuscriptCode(msCode string, debug bool) (parser.IProgramContext, bool) {
	inputStream := antlr.NewInputStream(msCode)
	lexer := parser.NewManuscriptLexer(inputStream)
	stream := antlr.NewCommonTokenStream(lexer, antlr.TokenDefaultChannel)
	p := parser.NewManuscript(stream)
	if debug {
		dumpTokens(stream)
	}
	errorListener := NewSyntaxErrorListener()
	p.RemoveErrorListeners()
	p.AddErrorListener(errorListener)

	tree := p.Program()
	return tree, len(errorListener.Errors) > 0
}

func convertToGoCode(tree parser.IProgramContext) string {
	visitor := msparse.NewParseTreeToAST()
	result := tree.Accept(visitor)

	mnode, ok := result.(*mast.Program)
	if !ok {
		return ""
	}

	transpiler := transpiler.NewGoTranspiler("main")
	goNode := transpiler.Visit(mnode)
	if goNode == nil {
		return ""
	}

	return printGoAst(goNode)
}

func printGoAst(visitedNode ast.Node) string {
	goAST, ok := visitedNode.(*ast.File)
	if !ok || goAST == nil {
		return ""
	}

	fileSet := token.NewFileSet()
	var buf bytes.Buffer
	config := printer.Config{Mode: printer.UseSpaces, Tabwidth: 4}
	if err := config.Fprint(&buf, fileSet, goAST); err != nil {
		return ""
	}

	return strings.TrimSpace(buf.String())
}

func dumpTokens(stream *antlr.CommonTokenStream) {
	log.Println("--- Lexer Token Dump Start ---")
	stream.Fill()
	for i, token := range stream.GetAllTokens() {
		log.Printf("Token %d: Type=%d, Text='%s', Line=%d, Col=%d",
			i, token.GetTokenType(), token.GetText(), token.GetLine(), token.GetColumn())
	}
	log.Println("--- Lexer Token Dump End ---")
	stream.Seek(0) // Reset stream for parser
}

func main() {
	// Define command line flags
	debugFlag := flag.Bool("debug", false, "Enable token dumping for debugging")
	flag.BoolVar(debugFlag, "d", false, "Enable token dumping for debugging (shorthand)")
	flag.Parse()

	args := flag.Args()
	if len(args) < 1 {
		fmt.Println("Usage: msc [-debug] <filename>")
		return
	}

	filename := args[0]
	content, err := os.ReadFile(filename)
	if err != nil {
		fmt.Printf("failed to read file %s: %v\n", filename, err)
		return
	}

	program := string(content)
	goCode, err := manuscriptToGo(program, *debugFlag)
	if err != nil {
		fmt.Printf("failed to compile program: %v\n", err)
		return
	}
	fmt.Printf("%s", goCode)
}
