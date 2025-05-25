package pipeline

import (
	"fmt"
	"strings"

	"manuscript-co/manuscript/internal/ast"
)

// ErrorCode represents specific error types for programmatic handling
type ErrorCode string

const (
	// Parse errors
	ErrorCodeInvalidSyntax     ErrorCode = "ERR_INVALID_SYNTAX"
	ErrorCodeUnexpectedToken   ErrorCode = "ERR_UNEXPECTED_TOKEN"
	ErrorCodeMissingToken      ErrorCode = "ERR_MISSING_TOKEN"
	ErrorCodeInvalidExpression ErrorCode = "ERR_INVALID_EXPRESSION"

	// Semantic errors
	ErrorCodeUndefinedVariable    ErrorCode = "ERR_UNDEFINED_VARIABLE"
	ErrorCodeTypeMismatch         ErrorCode = "ERR_TYPE_MISMATCH"
	ErrorCodeInvalidOperation     ErrorCode = "ERR_INVALID_OPERATION"
	ErrorCodeDuplicateDeclaration ErrorCode = "ERR_DUPLICATE_DECLARATION"

	// Stage errors
	ErrorCodeStageValidation ErrorCode = "ERR_STAGE_VALIDATION"
	ErrorCodeStageProcessing ErrorCode = "ERR_STAGE_PROCESSING"
	ErrorCodeStageTimeout    ErrorCode = "ERR_STAGE_TIMEOUT"
	ErrorCodeStageDependency ErrorCode = "ERR_STAGE_DEPENDENCY"

	// Generic errors
	ErrorCodeInternal ErrorCode = "ERR_INTERNAL"
	ErrorCodeGeneral  ErrorCode = "ERR_GENERAL"
)

// WarningCode represents specific warning types
type WarningCode string

const (
	WarningCodeUnusedVariable  WarningCode = "WARN_UNUSED_VARIABLE"
	WarningCodeDeprecatedUsage WarningCode = "WARN_DEPRECATED_USAGE"
	WarningCodePerformance     WarningCode = "WARN_PERFORMANCE"
	WarningCodeStyleViolation  WarningCode = "WARN_STYLE_VIOLATION"
	WarningCodeUnreachableCode WarningCode = "WARN_UNREACHABLE_CODE"
)

// ErrorSeverity represents the severity level of compilation issues
type ErrorSeverity int

const (
	SeverityInfo ErrorSeverity = iota
	SeverityWarning
	SeverityError
	SeverityFatal
)

func (s ErrorSeverity) String() string {
	switch s {
	case SeverityInfo:
		return "info"
	case SeverityWarning:
		return "warning"
	case SeverityError:
		return "error"
	case SeverityFatal:
		return "fatal"
	default:
		return "unknown"
	}
}

// CompilationError represents an error that occurred during compilation
type CompilationError struct {
	Code     ErrorCode
	Stage    string
	Position ast.Position
	Message  string
	Severity ErrorSeverity
	Source   string // Source code context if available
}

func (e CompilationError) String() string {
	if e.Position.Line > 0 {
		return fmt.Sprintf("%s: %s [%s] at %s: %s", e.Stage, e.Severity, e.Code, e.Position, e.Message)
	}
	return fmt.Sprintf("%s: %s [%s]: %s", e.Stage, e.Severity, e.Code, e.Message)
}

// CompilationWarning represents a warning that occurred during compilation
type CompilationWarning struct {
	Code     WarningCode
	Stage    string
	Position ast.Position
	Message  string
	Source   string // Source code context if available
}

func (w CompilationWarning) String() string {
	if w.Position.Line > 0 {
		return fmt.Sprintf("%s: warning [%s] at %s: %s", w.Stage, w.Code, w.Position, w.Message)
	}
	return fmt.Sprintf("%s: warning [%s]: %s", w.Stage, w.Code, w.Message)
}

// ErrorCollector accumulates errors and warnings throughout the compilation process
type ErrorCollector struct {
	errors   []CompilationError
	warnings []CompilationWarning
}

// NewErrorCollector creates a new error collector
func NewErrorCollector() *ErrorCollector {
	return &ErrorCollector{
		errors:   make([]CompilationError, 0),
		warnings: make([]CompilationWarning, 0),
	}
}

// AddError adds a new error to the collector
func (ec *ErrorCollector) AddError(stage string, pos ast.Position, message string, severity ErrorSeverity) {
	ec.AddErrorWithCode(ErrorCodeGeneral, stage, pos, message, severity)
}

// AddErrorWithCode adds a new error with a specific error code to the collector
func (ec *ErrorCollector) AddErrorWithCode(code ErrorCode, stage string, pos ast.Position, message string, severity ErrorSeverity) {
	ec.errors = append(ec.errors, CompilationError{
		Code:     code,
		Stage:    stage,
		Position: pos,
		Message:  message,
		Severity: severity,
	})
}

// AddErrorWithSource adds a new error with source context to the collector
func (ec *ErrorCollector) AddErrorWithSource(stage string, pos ast.Position, message string, severity ErrorSeverity, source string) {
	ec.AddErrorWithCodeAndSource(ErrorCodeGeneral, stage, pos, message, severity, source)
}

// AddErrorWithCodeAndSource adds a new error with code and source context to the collector
func (ec *ErrorCollector) AddErrorWithCodeAndSource(code ErrorCode, stage string, pos ast.Position, message string, severity ErrorSeverity, source string) {
	ec.errors = append(ec.errors, CompilationError{
		Code:     code,
		Stage:    stage,
		Position: pos,
		Message:  message,
		Severity: severity,
		Source:   source,
	})
}

// AddWarning adds a new warning to the collector
func (ec *ErrorCollector) AddWarning(stage string, pos ast.Position, message string) {
	ec.AddWarningWithCode(WarningCodeStyleViolation, stage, pos, message)
}

// AddWarningWithCode adds a new warning with a specific warning code to the collector
func (ec *ErrorCollector) AddWarningWithCode(code WarningCode, stage string, pos ast.Position, message string) {
	ec.warnings = append(ec.warnings, CompilationWarning{
		Code:     code,
		Stage:    stage,
		Position: pos,
		Message:  message,
	})
}

// AddWarningWithSource adds a new warning with source context to the collector
func (ec *ErrorCollector) AddWarningWithSource(stage string, pos ast.Position, message string, source string) {
	ec.AddWarningWithCodeAndSource(WarningCodeStyleViolation, stage, pos, message, source)
}

// AddWarningWithCodeAndSource adds a new warning with code and source context to the collector
func (ec *ErrorCollector) AddWarningWithCodeAndSource(code WarningCode, stage string, pos ast.Position, message string, source string) {
	ec.warnings = append(ec.warnings, CompilationWarning{
		Code:     code,
		Stage:    stage,
		Position: pos,
		Message:  message,
		Source:   source,
	})
}

// HasErrors returns true if any errors have been collected
func (ec *ErrorCollector) HasErrors() bool {
	return len(ec.errors) > 0
}

// HasWarnings returns true if any warnings have been collected
func (ec *ErrorCollector) HasWarnings() bool {
	return len(ec.warnings) > 0
}

// ErrorCount returns the total number of errors
func (ec *ErrorCollector) ErrorCount() int {
	return len(ec.errors)
}

// WarningCount returns the total number of warnings
func (ec *ErrorCollector) WarningCount() int {
	return len(ec.warnings)
}

// Errors returns a copy of all collected errors
func (ec *ErrorCollector) Errors() []CompilationError {
	result := make([]CompilationError, len(ec.errors))
	copy(result, ec.errors)
	return result
}

// Warnings returns a copy of all collected warnings
func (ec *ErrorCollector) Warnings() []CompilationWarning {
	result := make([]CompilationWarning, len(ec.warnings))
	copy(result, ec.warnings)
	return result
}

// Clear removes all errors and warnings
func (ec *ErrorCollector) Clear() {
	ec.errors = ec.errors[:0]
	ec.warnings = ec.warnings[:0]
}

// FormatErrors returns a formatted string containing all errors
func (ec *ErrorCollector) FormatErrors() string {
	if len(ec.errors) == 0 {
		return ""
	}

	var builder strings.Builder
	for i, err := range ec.errors {
		if i > 0 {
			builder.WriteString("\n")
		}
		builder.WriteString(err.String())
	}
	return builder.String()
}

// FormatWarnings returns a formatted string containing all warnings
func (ec *ErrorCollector) FormatWarnings() string {
	if len(ec.warnings) == 0 {
		return ""
	}

	var builder strings.Builder
	for i, warn := range ec.warnings {
		if i > 0 {
			builder.WriteString("\n")
		}
		builder.WriteString(warn.String())
	}
	return builder.String()
}

// FormatAll returns a formatted string containing all errors and warnings
func (ec *ErrorCollector) FormatAll() string {
	var parts []string

	if errorStr := ec.FormatErrors(); errorStr != "" {
		parts = append(parts, errorStr)
	}

	if warningStr := ec.FormatWarnings(); warningStr != "" {
		parts = append(parts, warningStr)
	}

	return strings.Join(parts, "\n")
}
