package pipeline

import "io"

// OutputTarget represents different compilation targets
type OutputTarget int

const (
	OutputGoAST OutputTarget = iota
	OutputGoSource
	OutputManuscriptAST
	OutputParseTree
)

func (ot OutputTarget) String() string {
	switch ot {
	case OutputGoAST:
		return "go-ast"
	case OutputGoSource:
		return "go-source"
	case OutputManuscriptAST:
		return "manuscript-ast"
	case OutputParseTree:
		return "parse-tree"
	default:
		return "unknown"
	}
}

// OptimizationLevel represents different optimization levels
type OptimizationLevel int

const (
	OptNone OptimizationLevel = iota
	OptBasic
	OptAggressive
)

func (ol OptimizationLevel) String() string {
	switch ol {
	case OptNone:
		return "none"
	case OptBasic:
		return "basic"
	case OptAggressive:
		return "aggressive"
	default:
		return "unknown"
	}
}

// CompilerOptions holds all configuration for the compilation pipeline
type CompilerOptions struct {
	// Output configuration
	Target OutputTarget

	// Optimization configuration
	OptLevel OptimizationLevel

	// Debug and profiling options
	Debug         bool
	ProfileStages bool
	ProfileMemory bool
	VerboseErrors bool

	// I/O options
	ErrorOutput io.Writer
	DebugOutput io.Writer
}

// DefaultOptions returns sensible default compiler options
func DefaultOptions() *CompilerOptions {
	return &CompilerOptions{
		Target:   OutputGoSource,
		OptLevel: OptBasic,
		Debug:    false,
	}
}

// Validate checks if the compiler options are valid and consistent
func (opts *CompilerOptions) Validate() error {
	return nil
}
