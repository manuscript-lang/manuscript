package compile

import (
	"fmt"
	"os"
	"strings"

	"github.com/antlr4-go/antlr/v4"
)

// Syntax error handling
type SyntaxErrorListener struct {
	*antlr.DefaultErrorListener
	Errors     []string
	SourceFile string
}

func NewSyntaxErrorListener(sourceFile string) *SyntaxErrorListener {
	return &SyntaxErrorListener{
		Errors:     make([]string, 0),
		SourceFile: sourceFile,
	}
}

func (l *SyntaxErrorListener) SyntaxError(
	recognizer antlr.Recognizer,
	offendingSymbol interface{},
	line, column int,
	msg string,
	e antlr.RecognitionException,
) {
	errorMsg := fmt.Sprintf("line %d:%d %s", line, column, msg)
	l.Errors = append(l.Errors, errorMsg)

	// Display the error with source code context like compilation errors
	if l.SourceFile != "" {
		l.printSyntaxError(line, column, msg)
	} else {
		fmt.Printf("Syntax error: %s\n", errorMsg)
	}
}

func (l *SyntaxErrorListener) printSyntaxError(line, column int, message string) {
	data, err := os.ReadFile(l.SourceFile)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Syntax error in %s at line %d, column %d: %s\n", l.SourceFile, line, column, message)
		return
	}

	lines := strings.Split(string(data), "\n")
	if line-1 < 0 || line-1 >= len(lines) {
		fmt.Fprintf(os.Stderr, "Syntax error in %s at line %d, column %d: %s\n", l.SourceFile, line, column, message)
		return
	}

	codeLine := lines[line-1]
	arrowColumn := column - 1
	if arrowColumn < 0 {
		arrowColumn = 0
	}
	arrow := strings.Repeat(" ", arrowColumn) + "^"

	fmt.Fprintf(os.Stderr, "\nSyntax error in %s at line %d, column %d:\n%s\n%s\n%s\n\n",
		l.SourceFile, line, column, codeLine, arrow, message)
}
