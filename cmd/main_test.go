package main

import (
	"fmt"
	"log"
	codegen "manuscript-co/manuscript/internal/codegen"
	parser "manuscript-co/manuscript/internal/parser"
	"strings"
	"testing"

	"github.com/antlr4-go/antlr/v4"
)

func TestBasicCodegen(t *testing.T) {
	// Use a direct number for clarity in the test
	// We'll test string literals and numeric literals separately
	input := `
let x = 10;
let message = 'hello';
let multiLine = '''
This is a multi-line string.
It can contain multiple lines of text.
'''
let multiLine2 = 'This is another multi-line string. 
It can also contain multiple lines of text.
'
`

	inputStream := antlr.NewInputStream(input)
	lexer := parser.NewManuscriptLexer(inputStream)
	tokenStream := antlr.NewCommonTokenStream(lexer, antlr.TokenDefaultChannel)

	// --- Lexer Token Dump for Diagnostics ---
	log.Println("--- Lexer Token Dump Start ---")
	tokenStream.Fill() // Ensure all tokens are loaded
	for i, token := range tokenStream.GetAllTokens() {
		// Just print the raw token type without trying to map to symbolic names
		log.Printf("Token %d: Type=%d, Text='%s', Line=%d, Col=%d",
			i,
			token.GetTokenType(),
			token.GetText(),
			token.GetLine(),
			token.GetColumn())
	}
	log.Println("--- Lexer Token Dump End ---")
	tokenStream.Seek(0)
	// --- End Lexer Token Dump ---

	// Create parser the standard way (like in ExecuteProgram from main.go)
	p := parser.NewManuscript(tokenStream)
	tree := p.Program()

	codeGen := codegen.NewCodeGenerator()
	goCode, err := codeGen.Generate(tree)

	if err != nil {
		t.Fatalf("codeGen.Generate failed: %v", err)
	}

	fmt.Println("Reached print statement in TestBasicCodegen")
	fmt.Printf("--- Generated Go Code (TestBasicCodegen) ---\n%s\n--------------------------------------------\n", goCode)

	// Check for the package
	if !strings.Contains(goCode, "package main") {
		t.Fatalf("Generated code missing 'package main'")
	}

	// Check for the number literal handling
	if !strings.Contains(goCode, "x := 10") {
		t.Fatalf("Generated code missing or improperly formatted number literal '10'")
	}

	// Check for the string literal handling
	if !strings.Contains(goCode, `message := "hello"`) {
		t.Fatalf("Generated code missing or improperly formatted string literal declaration")
	}
}

// TODO: Add more test cases for other features as they are implemented
// in the codegen visitor (e.g., binary ops, function calls, declarations).
