package main

import (
	"log"
	codegen "manuscript-co/manuscript/internal/codegen"
	parser "manuscript-co/manuscript/internal/parser"
	"testing"

	"github.com/antlr4-go/antlr/v4"
)

func manuscriptToGo(t *testing.T, input string) string {
	inputStream := antlr.NewInputStream(input)
	lexer := parser.NewManuscriptLexer(inputStream)
	tokenStream := antlr.NewCommonTokenStream(lexer, antlr.TokenDefaultChannel)

	// Create parser and generate code
	p := parser.NewManuscript(tokenStream)
	tree := p.Program()

	codeGen := codegen.NewCodeGenerator()
	goCode, err := codeGen.Generate(tree)

	if err != nil {
		t.Fatalf("codeGen.Generate failed: %v", err)
	}
	return goCode
}

// dumpTokens
func _(tokenStream *antlr.CommonTokenStream) {
	log.Println("--- Lexer Token Dump Start ---")
	tokenStream.Fill() // Ensure all tokens are loaded
	for i, token := range tokenStream.GetAllTokens() {
		log.Printf("Token %d: Type=%d, Text='%s', Line=%d, Col=%d",
			i,
			token.GetTokenType(),
			token.GetText(),
			token.GetLine(),
			token.GetColumn())
	}
	log.Println("--- Lexer Token Dump End ---")
	tokenStream.Seek(0)
}

func assertGoCode(t *testing.T, actual, expected string) {
	if actual != expected {
		t.Fatalf("Generated code does not match expected output.\nExpected:\n%s\n\nActual:\n%s", expected, actual)
	}
}

func TestBasicCodegen(t *testing.T) {
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
	expected := `package main

func main() {
	x := 10
	message := "hello"
	multiLine := "\nThis is a multi-line string.\nIt can contain multiple lines of text.\n"
	multiLine2 := "This is another multi-line string. \nIt can also contain multiple lines of text.\n"
}
`
	goCode := manuscriptToGo(t, input)
	assertGoCode(t, goCode, expected)
}

func TestMultipleVariableDeclaration(t *testing.T) {
	input := `
let a = 5, b = 10, c = 15;
let x, y, z = 20; // Only z gets a value, x and y are just declared
`
	expected := `package main

func main() {
	{
		a := 5
		b := 10
		c := 15
	}
	{
		var x
		var y
		z := 20
	}
}
`
	goCode := manuscriptToGo(t, input)
	assertGoCode(t, goCode, expected)
}
