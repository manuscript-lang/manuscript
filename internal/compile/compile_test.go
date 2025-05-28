package compile

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"manuscript-lang/manuscript/internal/config"
	"manuscript-lang/manuscript/internal/sourcemap"
)

func TestFileSystemResolver(t *testing.T) {
	resolver := &config.FileSystemResolver{}

	// Test reading a non-existent file
	_, err := resolver.ResolveModule("non-existent-file.ms")
	if err == nil {
		t.Error("Expected error when reading non-existent file")
	}
}

func TestStringResolver(t *testing.T) {
	modules := map[string]string{
		"main.ms":  "let x = 42",
		"utils.ms": "fn add(a, b) { a + b }",
	}

	resolver := config.NewStringResolver(modules)

	// Test resolving existing module
	content, err := resolver.ResolveModule("main.ms")
	if err != nil {
		t.Fatalf("Expected no error, got: %v", err)
	}
	if content != "let x = 42" {
		t.Errorf("Expected 'let x = 42', got: %s", content)
	}
}

func TestCompileManuscriptWithResolver(t *testing.T) {
	modules := map[string]string{
		"test.ms": "let greeting = \"Hello, World!\"",
	}
	resolver := config.NewStringResolver(modules)

	// Create a context with default config and set the resolver
	ctx := createTestContext(t)
	ctx.SourceFile = "test.ms"
	ctx.ModuleResolver = resolver

	// Get the manuscript code from the resolver
	msCode, err := resolver.ResolveModule("test.ms")
	if err != nil {
		t.Fatalf("Failed to resolve module: %v", err)
	}

	goCode, err := CompileManuscriptFromString(msCode, ctx)
	if err != nil {
		t.Fatalf("Expected no error, got: %v", err)
	}

	if !strings.Contains(goCode, "package main") {
		t.Error("Expected Go code to contain 'package main'")
	}

	if !strings.Contains(goCode, "greeting := \"Hello, World!\"") {
		t.Error("Expected Go code to contain greeting assignment")
	}
}

func TestCompileManuscriptWithResolverError(t *testing.T) {
	modules := map[string]string{
		"other.ms": "let x = 1",
	}
	resolver := config.NewStringResolver(modules)

	// Create a context with default config and set the resolver
	ctx := createTestContext(t)
	ctx.SourceFile = "missing.ms" // File not in resolver
	ctx.ModuleResolver = resolver

	// Try to get the manuscript code from the resolver - this should fail
	_, err := resolver.ResolveModule("missing.ms")
	if err == nil {
		t.Error("Expected error when file not found in resolver")
	}

	if !strings.Contains(err.Error(), "module not found") {
		t.Errorf("Expected 'module not found' error, got: %v", err)
	}
}

func createTestContext(t *testing.T) *config.CompilerContext {
	cfg := &config.MsConfig{
		CompilerOptions: config.CompilerOptions{
			OutputDir: "./build",
			EntryFile: "",
		},
	}

	ctx, err := config.NewCompilerContext(cfg, ".", "test.ms")
	if err != nil {
		t.Fatalf("Failed to create test context: %v", err)
	}

	return ctx
}

func TestCompileWithSourcemap(t *testing.T) {
	tests := []struct {
		name     string
		msCode   string
		expected struct {
			hasSourcemap bool
			sources      []string
			names        []string
		}
	}{
		{
			name: "simple function with variables",
			msCode: `fn main() {
  let x = 42
  let y = "hello"
  return x + 1
}`,
			expected: struct {
				hasSourcemap bool
				sources      []string
				names        []string
			}{
				hasSourcemap: true,
				sources:      []string{"test.ms"},
				names:        []string{"x", "y", "main"},
			},
		},
		{
			name: "function with parameters",
			msCode: `fn add(a int, b int) int {
  return a + b
}

fn main() {
  let result = add(5, 3)
  return result
}`,
			expected: struct {
				hasSourcemap bool
				sources      []string
				names        []string
			}{
				hasSourcemap: true,
				sources:      []string{"test.ms"},
				names:        []string{"a", "b", "add", "result", "main"},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Create config with sourcemap enabled
			cfg := &config.MsConfig{
				CompilerOptions: config.CompilerOptions{
					OutputDir: "./build",
					EntryFile: "test.ms",
					Sourcemap: true,
				},
			}

			ctx, err := config.NewCompilerContext(cfg, ".", "test.ms")
			if err != nil {
				t.Fatalf("Failed to create compiler context: %v", err)
			}

			// Compile the manuscript code
			goCode, sourceMap, err := manuscriptToGo(tt.msCode, ctx)
			if err != nil {
				t.Fatalf("Failed to compile manuscript code: %v", err)
			}

			// Verify Go code was generated
			if goCode == "" {
				t.Fatal("Expected Go code to be generated")
			}

			// Verify sourcemap was generated
			if tt.expected.hasSourcemap {
				if sourceMap == nil {
					t.Fatal("Expected sourcemap to be generated")
				}

				// Verify sourcemap structure
				if sourceMap.Version != 3 {
					t.Errorf("Expected sourcemap version 3, got %d", sourceMap.Version)
				}

				// Verify sources
				if len(sourceMap.Sources) != len(tt.expected.sources) {
					t.Errorf("Expected %d sources, got %d", len(tt.expected.sources), len(sourceMap.Sources))
				}

				for i, expectedSource := range tt.expected.sources {
					if i < len(sourceMap.Sources) && !strings.HasSuffix(sourceMap.Sources[i], expectedSource) {
						t.Errorf("Expected source to end with %s, got %s", expectedSource, sourceMap.Sources[i])
					}
				}

				// Verify names are present (order may vary)
				nameSet := make(map[string]bool)
				for _, name := range sourceMap.Names {
					nameSet[name] = true
				}

				for _, expectedName := range tt.expected.names {
					if !nameSet[expectedName] {
						t.Errorf("Expected name %s to be in sourcemap names", expectedName)
					}
				}

				// Verify mappings string is not empty
				if sourceMap.Mappings == "" {
					t.Error("Expected sourcemap mappings to be non-empty")
				}

				// Verify sourcemap comment is added to Go code
				if !strings.Contains(goCode, "//# sourceMappingURL=") {
					t.Error("Expected sourcemap comment in Go code")
				}
			}
		})
	}
}

func TestCompileWithoutSourcemap(t *testing.T) {
	msCode := `fn main() {
  let x = 42
  return x
}`

	// Create config with sourcemap disabled
	cfg := &config.MsConfig{
		CompilerOptions: config.CompilerOptions{
			OutputDir: "./build",
			EntryFile: "test.ms",
			Sourcemap: false,
		},
	}

	ctx, err := config.NewCompilerContext(cfg, ".", "test.ms")
	if err != nil {
		t.Fatalf("Failed to create compiler context: %v", err)
	}

	// Compile the manuscript code
	goCode, sourceMap, err := manuscriptToGo(msCode, ctx)
	if err != nil {
		t.Fatalf("Failed to compile manuscript code: %v", err)
	}

	// Verify Go code was generated
	if goCode == "" {
		t.Fatal("Expected Go code to be generated")
	}

	// Verify no sourcemap was generated
	if sourceMap != nil {
		t.Error("Expected no sourcemap to be generated when disabled")
	}

	// Verify no sourcemap comment in Go code
	if strings.Contains(goCode, "//# sourceMappingURL=") {
		t.Error("Expected no sourcemap comment in Go code when disabled")
	}
}

func TestSourcemapFileWriting(t *testing.T) {
	msCode := `fn main() {
  let x = 42
  return x
}`

	// Create temporary directory
	tempDir := t.TempDir()

	// Create config with sourcemap enabled
	cfg := &config.MsConfig{
		CompilerOptions: config.CompilerOptions{
			OutputDir: tempDir,
			EntryFile: "test.ms",
			Sourcemap: true,
		},
	}

	// Test BuildFile function
	testFile := filepath.Join(tempDir, "test.ms")
	if err := os.WriteFile(testFile, []byte(msCode), 0644); err != nil {
		t.Fatalf("Failed to write test file: %v", err)
	}

	BuildFile(testFile, cfg, false)

	// Verify output files exist
	outputFile := filepath.Join(tempDir, "test.go")
	sourcemapFile := outputFile + ".map"

	if _, err := os.Stat(outputFile); os.IsNotExist(err) {
		t.Errorf("Expected output file %s to exist", outputFile)
	}

	if _, err := os.Stat(sourcemapFile); os.IsNotExist(err) {
		t.Errorf("Expected sourcemap file %s to exist", sourcemapFile)
	}

	// Verify sourcemap file content
	sourcemapData, err := os.ReadFile(sourcemapFile)
	if err != nil {
		t.Fatalf("Failed to read sourcemap file: %v", err)
	}

	var sm sourcemap.SourceMap
	if err := json.Unmarshal(sourcemapData, &sm); err != nil {
		t.Fatalf("Failed to parse sourcemap JSON: %v", err)
	}

	if sm.Version != 3 {
		t.Errorf("Expected sourcemap version 3, got %d", sm.Version)
	}

	if len(sm.Sources) == 0 {
		t.Error("Expected sourcemap to have sources")
	}

	if sm.Mappings == "" {
		t.Error("Expected sourcemap to have mappings")
	}
}

func TestSourcemapErrorMapping(t *testing.T) {
	// Create a sourcemap with known mappings
	builder := sourcemap.NewBuilder("test.ms", "test.go")

	// Build a simple sourcemap
	sm := builder.Build()

	// Test error mapping (this tests the error mapping functionality)
	// Note: This is a basic test - in practice, the mappings would be populated during transpilation
	if sm == nil {
		t.Fatal("Expected sourcemap to be created")
	}

	// Test ParseGoError function
	errorStr := "test.go:5:10: undefined: someVar"
	filename, line, column, message, err := sourcemap.ParseGoError(errorStr)
	if err != nil {
		t.Fatalf("Failed to parse Go error: %v", err)
	}

	if filename != "test.go" {
		t.Errorf("Expected filename 'test.go', got '%s'", filename)
	}
	if line != 5 {
		t.Errorf("Expected line 5, got %d", line)
	}
	if column != 10 {
		t.Errorf("Expected column 10, got %d", column)
	}
	if message != "undefined: someVar" {
		t.Errorf("Expected message 'undefined: someVar', got '%s'", message)
	}
}

func TestCompileResultStructure(t *testing.T) {
	msCode := `fn main() {
  return 42
}`

	cfg := &config.MsConfig{
		CompilerOptions: config.CompilerOptions{
			OutputDir: "./build",
			EntryFile: "test.ms",
			Sourcemap: true,
		},
	}

	result := compileFile("", cfg, false)

	// Test that CompileResult has the expected structure
	if result.Error == nil {
		t.Error("Expected error for empty filename")
	}

	// Test with valid input
	ctx, err := config.NewCompilerContext(cfg, ".", "test.ms")
	if err != nil {
		t.Fatalf("Failed to create compiler context: %v", err)
	}

	goCode, err := CompileManuscriptFromString(msCode, ctx)
	if err != nil {
		t.Fatalf("Failed to compile manuscript string: %v", err)
	}

	if goCode == "" {
		t.Error("Expected Go code to be generated")
	}

	// Verify the Go code contains expected elements
	if !strings.Contains(goCode, "package main") {
		t.Error("Expected Go code to contain 'package main'")
	}

	if !strings.Contains(goCode, "func main()") {
		t.Error("Expected Go code to contain 'func main()'")
	}
}

func TestSyntaxErrorHandling(t *testing.T) {
	// Test with invalid manuscript code
	invalidCode := `fn main( {
  return 42
}`

	cfg := &config.MsConfig{
		CompilerOptions: config.CompilerOptions{
			OutputDir: "./build",
			EntryFile: "test.ms",
			Sourcemap: false,
		},
	}

	ctx, err := config.NewCompilerContext(cfg, ".", "test.ms")
	if err != nil {
		t.Fatalf("Failed to create compiler context: %v", err)
	}

	_, err = CompileManuscriptFromString(invalidCode, ctx)
	if err == nil {
		t.Error("Expected syntax error for invalid code")
	}

	if err.Error() != SyntaxErrorCode {
		t.Errorf("Expected syntax error code '%s', got '%s'", SyntaxErrorCode, err.Error())
	}
}
