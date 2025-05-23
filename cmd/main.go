package main

import (
	"flag"
	"fmt"
	"log"
	parser "manuscript-co/manuscript/internal/parser"
	codegen "manuscript-co/manuscript/internal/visitor"
	"os"
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
	p.GetInterpreter().SetPredictionMode(antlr.PredictionModeSLL)
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
