package pipeline

import (
	"fmt"
	"time"

	"manuscript-co/manuscript/internal/ast"
)

// Stage name constants to avoid string comparisons
const (
	StageNameParseTree       = "parse-tree"
	StageNameManuscriptAST   = "manuscript-ast"
	StageNameASTGeneration   = "ast-generation"
	StageNameGoAST           = "go-ast"
	StageNameGoASTGeneration = "go-ast-generation"
)

// CompilationStage represents a single stage in the compilation pipeline
type CompilationStage interface {
	Name() string
	Process(input interface{}) (interface{}, error)
	Validate(input interface{}) error
}

// StageResult holds the result of a compilation stage
type StageResult struct {
	StageName  string
	Input      interface{}
	Output     interface{}
	Error      error
	Duration   time.Duration
	MemoryUsed int64 // Memory usage in bytes, if profiling is enabled
}

// Pipeline orchestrates the multi-stage compilation process
type Pipeline struct {
	stages         []CompilationStage
	options        *CompilerOptions
	errorCollector *ErrorCollector
	results        []StageResult
}

// NewPipeline creates a new compilation pipeline
func NewPipeline(options *CompilerOptions) *Pipeline {
	if options == nil {
		options = DefaultOptions()
	}

	return &Pipeline{
		stages:         make([]CompilationStage, 0),
		options:        options,
		errorCollector: NewErrorCollector(),
		results:        make([]StageResult, 0),
	}
}

// AddStage adds a compilation stage to the pipeline
func (p *Pipeline) AddStage(stage CompilationStage) {
	p.stages = append(p.stages, stage)
}

// GetOptions returns the compiler options
func (p *Pipeline) GetOptions() *CompilerOptions {
	return p.options
}

// GetErrorCollector returns the error collector
func (p *Pipeline) GetErrorCollector() *ErrorCollector {
	return p.errorCollector
}

// GetResults returns the results from all completed stages
func (p *Pipeline) GetResults() []StageResult {
	result := make([]StageResult, len(p.results))
	copy(result, p.results)
	return result
}

// Execute runs the entire compilation pipeline
func (p *Pipeline) Execute(input interface{}) (interface{}, error) {
	if err := p.options.Validate(); err != nil {
		return nil, fmt.Errorf("invalid compiler options: %w", err)
	}

	current := input
	p.results = p.results[:0] // Clear previous results

	for i, stage := range p.stages {
		var err error
		current, err = p.executeStage(stage, current, i, len(p.stages))
		if err != nil {
			return nil, err
		}

		// Check if this is the target output stage
		if p.shouldStopAtStage(stage) {
			break
		}
	}

	// Check for collected errors
	if p.errorCollector.HasErrors() {
		return current, fmt.Errorf("compilation completed with errors:\n%s",
			p.errorCollector.FormatErrors())
	}

	return current, nil
}

// ExecuteUntilStage runs the pipeline until a specific stage (inclusive)
func (p *Pipeline) ExecuteUntilStage(input interface{}, stageName string) (interface{}, error) {
	current := input
	p.results = p.results[:0]

	for i, stage := range p.stages {
		var err error
		current, err = p.executeStage(stage, current, i, len(p.stages))
		if err != nil {
			return nil, err
		}

		if stage.Name() == stageName {
			break
		}
	}

	return current, nil
}

// executeStage executes a single stage and handles common logic
func (p *Pipeline) executeStage(stage CompilationStage, input interface{}, currentStage, totalStages int) (interface{}, error) {
	stageResult := StageResult{
		StageName: stage.Name(),
		Input:     input,
	}

	startTime := time.Now()
	var startMemory int64
	if p.options.ProfileMemory {
		startMemory = getCurrentMemoryUsage()
	}

	// Validate input before processing
	if err := stage.Validate(input); err != nil {
		stageResult.Error = fmt.Errorf("validation failed for stage %s: %w", stage.Name(), err)
		stageResult.Duration = time.Since(startTime)
		p.results = append(p.results, stageResult)

		p.errorCollector.AddErrorWithCode(ErrorCodeStageValidation, stage.Name(), ast.Position{},
			fmt.Sprintf("Input validation failed: %v", err), SeverityError)
		return nil, stageResult.Error
	}

	// Process the stage
	output, err := stage.Process(input)
	stageResult.Duration = time.Since(startTime)
	stageResult.Output = output
	stageResult.Error = err

	if p.options.ProfileMemory {
		endMemory := getCurrentMemoryUsage()
		stageResult.MemoryUsed = endMemory - startMemory
	}

	p.results = append(p.results, stageResult)

	if err != nil {
		p.errorCollector.AddErrorWithCode(ErrorCodeStageProcessing, stage.Name(), ast.Position{},
			fmt.Sprintf("Processing failed: %v", err), SeverityError)
		return nil, fmt.Errorf("stage %s failed: %w", stage.Name(), err)
	}

	if p.options.Debug {
		p.logStageResult(stageResult, currentStage+1, totalStages)
	}

	return output, nil
}

// shouldStopAtStage determines if pipeline should stop at the current stage based on options
func (p *Pipeline) shouldStopAtStage(stage CompilationStage) bool {
	stageName := stage.Name()
	switch p.options.Target {
	case OutputParseTree:
		return stageName == StageNameParseTree
	case OutputManuscriptAST:
		return stageName == StageNameManuscriptAST || stageName == StageNameASTGeneration
	case OutputGoAST:
		return stageName == StageNameGoAST || stageName == StageNameGoASTGeneration
	case OutputGoSource:
		return false // Run all stages
	default:
		return false
	}
}

// logStageResult logs the result of a compilation stage for debugging
func (p *Pipeline) logStageResult(result StageResult, current, total int) {
	status := "✓"
	if result.Error != nil {
		status = "✗"
	}

	msg := fmt.Sprintf("[%d/%d] %s %s (%v)",
		current, total, status, result.StageName, result.Duration)

	if p.options.ProfileMemory && result.MemoryUsed > 0 {
		msg += fmt.Sprintf(" [%d KB]", result.MemoryUsed/1024)
	}

	if p.options.DebugOutput != nil {
		fmt.Fprintln(p.options.DebugOutput, msg)
	}
}

// Reset clears all pipeline state for reuse
func (p *Pipeline) Reset() {
	p.results = p.results[:0]
	p.errorCollector.Clear()
}

// getCurrentMemoryUsage returns current memory usage in bytes
// This is a placeholder - in a real implementation, you would use runtime.MemStats
func getCurrentMemoryUsage() int64 {
	return 0
}
