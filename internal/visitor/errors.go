package visitor

import "github.com/antlr4-go/antlr/v4"

// CompilationError represents an error found during the compilation process.
type CompilationError struct {
	Message string
	Token   antlr.Token
}

// NewCompilationError creates a new CompilationError.
func NewCompilationError(message string, token antlr.Token) CompilationError {
	return CompilationError{
		Message: message,
		Token:   token,
	}
}
