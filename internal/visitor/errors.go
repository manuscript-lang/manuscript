package visitor

import "github.com/antlr4-go/antlr/v4"

// CompilationError represents an error found during the compilation process.
type CompilationError struct {
	Message   string
	Token     antlr.Token
	ErrorCode string
}

// NewCompilationError creates a new CompilationError.
func NewCompilationError(message string, token antlr.Token, errorCode string) CompilationError {
	return CompilationError{
		Message:   message,
		Token:     token,
		ErrorCode: errorCode,
	}
}
