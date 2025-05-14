package main

import (
	"fmt"
	"manuscript-co/manuscript/internal/parser"
	"manuscript-co/manuscript/internal/visitor"

	"github.com/antlr4-go/antlr/v4"
)

func ExecuteProgram(program string) (string, error) {
	inputStream := antlr.NewInputStream(program)

	// Create lexer
	lexer := parser.NewManuscriptLexer(inputStream)
	tokenStream := antlr.NewCommonTokenStream(lexer, antlr.TokenDefaultChannel)

	// Create parser
	p := parser.NewManuscript(tokenStream)

	// Parse input
	tree := p.Program()

	// Generate Go code
	codeGen := visitor.NewCodeGenerator()
	goCode, err := codeGen.Generate(tree)
	if err != nil {
		return "", fmt.Errorf("code generation failed: %w", err)
	}
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
