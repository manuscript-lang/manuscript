package pipeline

import (
	"manuscript-co/manuscript/internal/ast"
	"strings"
	"testing"
)

// MockStage implements CompilationStage for testing
type MockStage struct {
	name string
}

func (m *MockStage) Name() string {
	return m.name
}

func (m *MockStage) Process(input interface{}) (interface{}, error) {
	// Simple mock processing - just return the input with a suffix
	if str, ok := input.(string); ok {
		return str + "-processed", nil
	}
	return input, nil
}

func (m *MockStage) Validate(input interface{}) error {
	// Mock validation - always passes
	return nil
}

func TestPipelineBasicFunctionality(t *testing.T) {
	// Test pipeline creation with default options
	pipeline := NewPipeline(nil)

	if pipeline == nil {
		t.Fatal("NewPipeline returned nil")
	}

	if pipeline.GetOptions() == nil {
		t.Fatal("Pipeline options are nil")
	}

	if pipeline.GetErrorCollector() == nil {
		t.Fatal("Pipeline error collector is nil")
	}
}

func TestPipelineWithStages(t *testing.T) {
	// Create pipeline with custom options
	options := &CompilerOptions{
		Target:   OutputGoSource,
		OptLevel: OptBasic,
		Debug:    true,
	}

	pipeline := NewPipeline(options)

	// Add mock stages
	stage1 := &MockStage{name: "stage1"}
	stage2 := &MockStage{name: "stage2"}

	pipeline.AddStage(stage1)
	pipeline.AddStage(stage2)

	// Execute pipeline
	input := "test-input"
	output, err := pipeline.Execute(input)

	if err != nil {
		t.Fatalf("Pipeline execution failed: %v", err)
	}

	expected := "test-input-processed-processed"
	if output != expected {
		t.Fatalf("Expected output %q, got %q", expected, output)
	}

	// Check results
	results := pipeline.GetResults()
	if len(results) != 2 {
		t.Fatalf("Expected 2 stage results, got %d", len(results))
	}

	// Verify stage names
	if results[0].StageName != "stage1" {
		t.Errorf("Expected first stage name 'stage1', got %q", results[0].StageName)
	}

	if results[1].StageName != "stage2" {
		t.Errorf("Expected second stage name 'stage2', got %q", results[1].StageName)
	}

	// Verify timing information
	for i, result := range results {
		if result.Duration <= 0 {
			t.Errorf("Stage %d duration should be positive, got %v", i, result.Duration)
		}
	}
}

func TestPipelineExecuteUntilStage(t *testing.T) {
	pipeline := NewPipeline(DefaultOptions())

	stage1 := &MockStage{name: "stage1"}
	stage2 := &MockStage{name: "stage2"}
	stage3 := &MockStage{name: "stage3"}

	pipeline.AddStage(stage1)
	pipeline.AddStage(stage2)
	pipeline.AddStage(stage3)

	// Execute until stage2
	input := "test"
	output, err := pipeline.ExecuteUntilStage(input, "stage2")

	if err != nil {
		t.Fatalf("Pipeline execution failed: %v", err)
	}

	expected := "test-processed-processed"
	if output != expected {
		t.Fatalf("Expected output %q, got %q", expected, output)
	}

	// Should only have 2 results (stage1 and stage2)
	results := pipeline.GetResults()
	if len(results) != 2 {
		t.Fatalf("Expected 2 stage results, got %d", len(results))
	}
}

func TestErrorCollector(t *testing.T) {
	collector := NewErrorCollector()

	if collector.HasErrors() {
		t.Error("New collector should not have errors")
	}

	if collector.HasWarnings() {
		t.Error("New collector should not have warnings")
	}

	// Add an error
	collector.AddError("test-stage", ast.Position{Line: 1, Column: 5}, "test error", SeverityError)

	if !collector.HasErrors() {
		t.Error("Collector should have errors after adding one")
	}

	if collector.ErrorCount() != 1 {
		t.Errorf("Expected 1 error, got %d", collector.ErrorCount())
	}

	// Add a warning
	collector.AddWarning("test-stage", ast.Position{Line: 2, Column: 10}, "test warning")

	if !collector.HasWarnings() {
		t.Error("Collector should have warnings after adding one")
	}

	if collector.WarningCount() != 1 {
		t.Errorf("Expected 1 warning, got %d", collector.WarningCount())
	}

	// Test formatting
	errorStr := collector.FormatErrors()
	if errorStr == "" {
		t.Error("Error formatting should not be empty")
	}

	warningStr := collector.FormatWarnings()
	if warningStr == "" {
		t.Error("Warning formatting should not be empty")
	}

	allStr := collector.FormatAll()
	if allStr == "" {
		t.Error("All formatting should not be empty")
	}
}

func TestCompilerOptions(t *testing.T) {
	// Test default options
	opts := DefaultOptions()

	if opts.Target != OutputGoSource {
		t.Errorf("Expected default target %v, got %v", OutputGoSource, opts.Target)
	}

	if opts.OptLevel != OptBasic {
		t.Errorf("Expected default optimization level %v, got %v", OptBasic, opts.OptLevel)
	}

	if opts.Debug {
		t.Error("Expected debug to be disabled by default")
	}

	// Test validation
	err := opts.Validate()
	if err != nil {
		t.Errorf("Validation should not fail: %v", err)
	}
}

func TestErrorCodes(t *testing.T) {
	collector := NewErrorCollector()

	// Test adding error with specific code
	collector.AddErrorWithCode(ErrorCodeInvalidSyntax, "parser", ast.Position{Line: 1, Column: 5}, "syntax error", SeverityError)

	errors := collector.Errors()
	if len(errors) != 1 {
		t.Fatalf("Expected 1 error, got %d", len(errors))
	}

	err := errors[0]
	if err.Code != ErrorCodeInvalidSyntax {
		t.Errorf("Expected error code %s, got %s", ErrorCodeInvalidSyntax, err.Code)
	}

	// Test adding warning with specific code
	collector.AddWarningWithCode(WarningCodeUnusedVariable, "semantic", ast.Position{Line: 2, Column: 10}, "unused variable")

	warnings := collector.Warnings()
	if len(warnings) != 1 {
		t.Fatalf("Expected 1 warning, got %d", len(warnings))
	}

	warn := warnings[0]
	if warn.Code != WarningCodeUnusedVariable {
		t.Errorf("Expected warning code %s, got %s", WarningCodeUnusedVariable, warn.Code)
	}

	// Test error formatting includes codes
	errorStr := collector.FormatErrors()
	if !strings.Contains(errorStr, string(ErrorCodeInvalidSyntax)) {
		t.Errorf("Error formatting should include error code %s", ErrorCodeInvalidSyntax)
	}

	warningStr := collector.FormatWarnings()
	if !strings.Contains(warningStr, string(WarningCodeUnusedVariable)) {
		t.Errorf("Warning formatting should include warning code %s", WarningCodeUnusedVariable)
	}
}

func TestStageNameConstants(t *testing.T) {
	// Test that stage name constants are properly defined
	expectedNames := []string{
		StageNameParseTree,
		StageNameManuscriptAST,
		StageNameASTGeneration,
		StageNameGoAST,
		StageNameGoASTGeneration,
	}

	// Verify all constants are non-empty
	for _, name := range expectedNames {
		if name == "" {
			t.Error("Stage name constant should not be empty")
		}
	}

	// Test that shouldStopAtStage uses constants correctly
	pipeline := NewPipeline(&CompilerOptions{Target: OutputParseTree})

	// Create a mock stage with the parse tree name
	mockStage := &MockStage{name: StageNameParseTree}

	if !pipeline.shouldStopAtStage(mockStage) {
		t.Error("Pipeline should stop at parse tree stage when target is OutputParseTree")
	}
}
