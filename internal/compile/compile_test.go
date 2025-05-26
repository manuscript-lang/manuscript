package compile

import (
	"strings"
	"testing"

	"manuscript-lang/manuscript/internal/config"
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

	// Test resolving another existing module
	content, err = resolver.ResolveModule("utils.ms")
	if err != nil {
		t.Fatalf("Expected no error, got: %v", err)
	}
	if content != "fn add(a, b) { a + b }" {
		t.Errorf("Expected 'fn add(a, b) { a + b }', got: %s", content)
	}

	// Test resolving non-existent module
	_, err = resolver.ResolveModule("missing.ms")
	if err == nil {
		t.Error("Expected error when resolving non-existent module")
	}
	if !strings.Contains(err.Error(), "module not found") {
		t.Errorf("Expected 'module not found' error, got: %v", err)
	}
}

func TestCompileManuscriptFromString(t *testing.T) {
	ctx := createTestContext(t)

	// Test basic compilation
	msCode := "let x = 42"
	goCode, err := CompileManuscriptFromString(msCode, ctx)
	if err != nil {
		t.Fatalf("Expected no error, got: %v", err)
	}

	if !strings.Contains(goCode, "package main") {
		t.Error("Expected Go code to contain 'package main'")
	}

	if !strings.Contains(goCode, "x := 42") {
		t.Error("Expected Go code to contain variable assignment")
	}
}

func TestCompileManuscriptFromStringSyntaxError(t *testing.T) {
	ctx := createTestContext(t)

	// Test syntax error handling
	msCode := "let x = " // Invalid syntax
	_, err := CompileManuscriptFromString(msCode, ctx)
	if err == nil {
		t.Error("Expected syntax error")
	}

	if err.Error() != SyntaxErrorCode {
		t.Errorf("Expected syntax error code '%s', got: %v", SyntaxErrorCode, err)
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

	result := CompileManuscript(ctx)
	if result.Error != nil {
		t.Fatalf("Expected no error, got: %v", result.Error)
	}

	if !strings.Contains(result.GoCode, "package main") {
		t.Error("Expected Go code to contain 'package main'")
	}

	if !strings.Contains(result.GoCode, "greeting := \"Hello, World!\"") {
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

	result := CompileManuscript(ctx)
	if result.Error == nil {
		t.Error("Expected error when file not found in resolver")
	}

	if !strings.Contains(result.Error.Error(), "module not found") {
		t.Errorf("Expected 'module not found' error, got: %v", result.Error)
	}
}

func TestManuscriptToGo(t *testing.T) {
	ctx := createTestContext(t)

	// Test function compilation
	msCode := `fn greet(name string) {
    "Hello, " + name
}`

	goCode, err := manuscriptToGo(msCode, ctx)
	if err != nil {
		t.Fatalf("Expected no error, got: %v", err)
	}

	if !strings.Contains(goCode, "func greet") {
		t.Error("Expected Go code to contain function definition")
	}

	if !strings.Contains(goCode, "return \"Hello, \" + name") {
		t.Error("Expected Go code to contain return statement")
	}
}

func createTestContext(t *testing.T) *config.CompilerContext {
	ctx, err := config.NewCompilerContextFromFile("test.ms", "", "")
	if err != nil {
		t.Fatalf("Failed to create test context: %v", err)
	}
	return ctx
}
