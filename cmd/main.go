package main

import (
	"fmt"
	"log"
	parser "manuscript-co/manuscript/internal/parser"
	codegen "manuscript-co/manuscript/internal/visitor"
	"strings"

	"github.com/antlr4-go/antlr/v4"
)

func manuscriptToGo(input string, debug bool) (string, error) {
	inputStream := antlr.NewInputStream(input)
	lexer := parser.NewManuscriptLexer(inputStream)
	tokenStream := antlr.NewCommonTokenStream(lexer, antlr.TokenDefaultChannel)

	if debug {
		dumpTokens(tokenStream, debug)
	}

	p := parser.NewManuscript(tokenStream)
	tree := p.Program()
	codeGen := codegen.NewCodeGenerator()
	goCode, err := codeGen.Generate(tree)
	if err != nil {
		return "", fmt.Errorf("codeGen.Generate failed: %w", err)
	}
	return strings.TrimSpace(goCode), nil
}

func dumpTokens(stream *antlr.CommonTokenStream, debug bool) {
	if !debug {
		return
	}
	log.Println("--- Lexer Token Dump Start ---")
	stream.Fill()
	for i, token := range stream.GetAllTokens() {
		log.Printf("Token %d: Type=%d, Text='%s', Line=%d, Col=%d",
			i, token.GetTokenType(), token.GetText(), token.GetLine(), token.GetColumn())
	}
	log.Println("--- Lexer Token Dump End ---")
	stream.Seek(0) // Reset stream for parser
}

func ExecuteProgram(program string) (string, error) {
	// Call manuscriptToGo for actual parsing and code generation.
	// Pass 'false' for the debug flag as ExecuteProgram doesn't have a debug mode currently.
	goCode, err := manuscriptToGo(program, false)
	if err != nil {
		// manuscriptToGo already provides a detailed error.
		return "", fmt.Errorf("failed to execute program: %w", err)
	}

	// ExecuteProgram's specific behavior: print the generated code.
	fmt.Printf("Generated Go code:\n%s\n", goCode)

	return goCode, nil
}

func main() {
	fmt.Println("Manuscript ANTLR parser demo")
	// Create input for parsing
	input := "2 * (3 + 4); 1 + 2; 3 - 4; 5 / 2"
	result, _ := ExecuteProgram(input)
	fmt.Printf("Expression '%s' evaluates to %s\n", input, result)
	fmt.Println("Expression parsed successfully")
}
